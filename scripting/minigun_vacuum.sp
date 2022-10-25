/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

#include <tf2attributes>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/weapon>
#include <stocksoup/math>
// #include <stocksoup/datapack>
#include <stocksoup/sdkports/vector>

#if defined KARMACHARGER_SOUNDS_ENABLED
#define SOUND_VACUUM_KILL "weapons/enemy_sweeper/vacuum_suck.wav"
#endif // KARMACHARGER_SOUNDS_ENABLED

enum eMinigunState {
	AC_STATE_IDLE = 0,
	AC_STATE_STARTFIRING,
	AC_STATE_FIRING,
	AC_STATE_SPINNING,
	AC_STATE_DRYFIRE
};

Handle g_DHookItemPostFrame;
Handle g_SDKCallFindEntityInSphere;

float g_flNextVacuumAttack[MAXPLAYERS + 1];
float g_flAmmoDrainFrac[MAXPLAYERS + 1];

// float g_flVacuumFOVMult[MAXPLAYERS + 1]; // unused fov multiplier for vacuum victims

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookItemPostFrame = DHookCreateFromConf(hGameConf, "CBaseCombatWeapon::ItemPostFrame()");
	
	StartPrepSDKCall(SDKCall_EntityList);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CGlobalEntityList::FindEntityInSphere()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer,
			VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();
	
	delete hGameConf;
}

public void OnMapStart() {
#if defined KARMACHARGER_SOUNDS_ENABLED
	AddFileToDownloadsTable("sound/" ... SOUND_VACUUM_KILL);
	PrecacheSound(SOUND_VACUUM_KILL);
#endif
	
	int minigun = -1;
	while ((minigun = FindEntityByClassname(minigun, "tf_weapon_minigun")) != -1) {
		HookMinigun(minigun);
	}
}

public void OnEntityCreated(int entity, const char[] className) {
	if (StrEqual(className, "tf_weapon_minigun")) {
		HookMinigun(entity);
	}
}

static void HookMinigun(int minigun) {
	DHookEntity(g_DHookItemPostFrame, false, minigun, .callback = OnMinigunPostFramePre);
}


public MRESReturn OnMinigunPostFramePre(int minigun) {
	int owner = TF2_GetEntityOwner(minigun);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	
	char attr[128];
	int iWeaponState = GetEntProp(minigun, Prop_Send, "m_iWeaponState");
	
	if (GetEntPropFloat(minigun, Prop_Data, "m_flNextSecondaryAttack") > GetGameTime()) {
		// don't treat state as firing if secondary attack isn't toggleable
		iWeaponState = AC_STATE_IDLE;
	}
	
	TF2CustAttr_GetString(minigun, "minigun vacuum", attr, sizeof(attr));
	if (!attr[0]) {
		return MRES_Ignored;
	}
	
	switch (iWeaponState) {
		case AC_STATE_IDLE: {
			// EmitGameSoundToAll("BaseCombatCharacter.StopWeaponSounds", minigun);
		}
		// case AC_STATE_STARTFIRING, AC_STATE_SPINNING, AC_STATE_FIRING, AC_STATE_DRYFIRE: {
		case AC_STATE_FIRING: {
			if (GetGameTime() > g_flNextVacuumAttack[owner] && VacuumAttack(minigun, attr)) {
				g_flNextVacuumAttack[owner] = GetGameTime()
						+ ReadFloatVar(attr, "interval", GetGameFrameTime());
			}
			
			int nAmmoAvailable = TF2_GetWeaponAmmo(minigun);
			if (nAmmoAvailable) {
				// drain amoo while aiming
				g_flAmmoDrainFrac[owner] += TF2Attrib_HookValueFloat(0.0,
						"uses_ammo_while_aiming", owner) * GetGameFrameTime();
				
				if (g_flAmmoDrainFrac[owner] >= 1.0) {
					int nAmmoRemoved = RoundToFloor(g_flAmmoDrainFrac[owner]);
					
					// remove non-fractional portion before capping the amount
					g_flAmmoDrainFrac[owner] -= float(nAmmoRemoved);
					if (nAmmoRemoved > nAmmoAvailable) {
						nAmmoRemoved = nAmmoAvailable;
					}
					TF2_SetWeaponAmmo(minigun, nAmmoAvailable - nAmmoRemoved);
				}
			}
			// vacuum noises
			// EmitGameSoundToAll("Weapon_ManMelter.altfire_lp", minigun);
		}
	}
	
	// disable primary fire if vacuum attribute is present
	// SetEntPropFloat(minigun, Prop_Data, "m_flNextPrimaryAttack", GetGameTime() + 2.0);
	
	return MRES_Ignored;
}

bool VacuumAttack(int minigun, const char[] attributeValue) {
	int owner = TF2_GetEntityOwner(minigun);
	if (owner < 1 || owner > MaxClients) {
		return false;
	}
	
	if (!TF2_GetWeaponAmmo(minigun)) {
		return false;
	}
	
	float flPullInterval = ReadFloatVar(attributeValue, "interval", GetGameFrameTime());
	float flLength = ReadFloatVar(attributeValue, "vacuum_range");
	float flPullStrength = ReadFloatVar(attributeValue, "vacuum_pull_factor"); // HU/s
	float flDamageDistance = ReadFloatVar(attributeValue, "damage_range");
	float flDamagePerAttack = ReadFloatVar(attributeValue, "damage");
	float flEffectCone = ReadFloatVar(attributeValue, "effect_cone_deg", 60.0);
	if (!flLength) {
		return false;
	}
	
	float vecClientPos[3], angEyes[3], vecEyeForward[3];
	GetClientAbsOrigin(owner, vecClientPos);
	GetClientEyeAngles(owner, angEyes);
	
	GetAngleVectors(angEyes, vecEyeForward, NULL_VECTOR, NULL_VECTOR);
	
	// TODO iterate over sphere
	int ent = -1;
	while ((ent = FindEntityInSphere(ent, vecClientPos, flLength)) != -1) {
		float vecTargetPos[3];
		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", vecTargetPos);
		
		if (ent < 1 || ent > MaxClients || !IsPlayerAlive(ent)) {
			continue;
		}
		
		if (ent == owner || TF2_GetClientTeam(owner) == TF2_GetClientTeam(ent)) {
			continue;
		}
		
		if (!PointWithinViewAngle(vecClientPos, vecTargetPos, vecEyeForward,
				Cosine(0.5 * DegToRad(flEffectCone)))) {
			continue;
		}
		
		float vecResultPos[3];
		SubtractVectors(vecClientPos, vecTargetPos, vecResultPos);
		vecResultPos[2] = 0.0; // drop the vertical component
		
		NormalizeVector(vecResultPos, vecResultPos);
		ScaleVector(vecResultPos, flPullStrength * flPullInterval);
		
		float vecTargetVelocity[3];
		GetEntPropVector(ent, Prop_Data, "m_vecAbsVelocity", vecTargetVelocity);
		
		AddVectors(vecResultPos, vecTargetVelocity, vecTargetVelocity);
		TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, vecTargetVelocity);
		
		if (GetVectorDistance(vecClientPos, vecTargetPos) < flDamageDistance) {
			SDKHooks_TakeDamage(ent, minigun, owner, flDamagePerAttack * flPullInterval,
					DMG_CLUB, minigun, NULL_VECTOR, vecClientPos);
			
			if (!IsPlayerAlive(ent)) {
				int ragdoll = GetEntPropEnt(ent, Prop_Send, "m_hRagdoll");
				if (IsValidEntity(ragdoll)) {
					RemoveEntity(ragdoll);
				}
#if defined KARMACHARGER_SOUNDS_ENABLED
				EmitSoundToAll(SOUND_VACUUM_KILL, minigun, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
#else
				EmitGameSoundToAll("Weapon_DumpsterRocket.Reload", minigun);
#endif
			}
		}
		TF2_AddCondition(ent, TFCond_AirCurrent, flPullInterval * 2.0, owner);
	}
	
	return true;
}

static int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius);
}
