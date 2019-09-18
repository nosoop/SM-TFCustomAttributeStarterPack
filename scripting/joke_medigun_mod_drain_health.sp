/**
 * Monolith plugin.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>
#include <sdkhooks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/client>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/tempents_stocks>

Handle g_DHookWeaponPostFrame;
Handle g_SDKCallFindEntityInSphere;

// read from CTFPlayer::DeathSound() disasm
int offs_CTFPlayer_LastDamageType = 0x215C;

char g_MedicScripts[][] = {
	"medic_sf13_influx_big03",
	"medic_sf13_magic_reac07",
	"Medic.CritDeath",
};

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	StartPrepSDKCall(SDKCall_EntityList);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CGlobalEntityList::FindEntityInSphere()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer,
			VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();
	
	Handle dtMedigunAllowedToHealTarget = DHookCreateFromConf(hGameConf,
			"CWeaponMedigun::AllowedToHealTarget()");
	DHookEnableDetour(dtMedigunAllowedToHealTarget, false, OnAllowedToHealTargetPre);
	
	Handle dtMedigunSecondaryAttack = DHookCreateFromConf(hGameConf,
			"CWeaponMedigun::SecondaryAttack()");
	DHookEnableDetour(dtMedigunSecondaryAttack, false, OnMedigunSecondaryAttackPre);
	
	g_DHookWeaponPostFrame = DHookCreateFromConf(hGameConf,
			"CBaseCombatWeapon::ItemPostFrame()");
	
	Handle dtCreateRagdoll = DHookCreateFromConf(hGameConf, "CTFPlayer::CreateRagdollEntity()");
	DHookEnableDetour(dtCreateRagdoll, false, OnCreateRagdollPre);
	
	int offslastDamage = FindSendPropInfo("CTFPlayer", "m_flMvMLastDamageTime");
	if (offslastDamage < 0) {
		SetFailState("Could not get offset for CTFPlayer::m_flMvMLastDamageTime");
	}
	
	offs_CTFPlayer_LastDamageType = offslastDamage + 0x14;
	
	delete hGameConf;
	
	HookEvent("player_death", OnPlayerDeath);
}

public void OnMapStart() {
	PrecacheScriptSound("MVM.BombExplodes");
	PrecacheSound("mvm/mvm_bomb_explode.wav");
	for (int i; i < sizeof(g_MedicScripts); i++) {
		PrecacheScriptSound(g_MedicScripts[i]);
	}
	
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_weapon_medigun")) != -1) {
		DHookEntity(g_DHookWeaponPostFrame, true, entity, .callback = OnMedigunPostFramePost);
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

static bool s_ForceCritDeathSound;
public void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype) {
	if (!s_ForceCritDeathSound) {
		return;
	}
	
	// forces crit damagetype so we get the crit death sound
	SetEntData(victim, offs_CTFPlayer_LastDamageType, DMG_CRIT);
}

public void OnEntityCreated(int entity, const char[] className) {
	if (StrEqual(className, "tf_weapon_medigun")) {
		DHookEntity(g_DHookWeaponPostFrame, true, entity, .callback = OnMedigunPostFramePost);
	}
}

static bool s_ForceGibRagdoll;
public MRESReturn OnCreateRagdollPre(int client, Handle hParams) {
	if (!s_ForceGibRagdoll) {
		return MRES_Ignored;
	}
	DHookSetParam(hParams, 1, true);
	return MRES_ChangedHandled;
}

// setting this up as a post hook causes windows srcds to crash
public MRESReturn OnAllowedToHealTargetPre(int medigun, Handle hReturn, Handle hParams) {
	if (TF2CustAttr_GetFloat(medigun, "medigun drains health") == 0.0) {
		return MRES_Ignored;
	}
	int target = DHookGetParam(hParams, 1);
	if (target > 0 && target <= MaxClients) {
		DHookSetReturn(hReturn, true);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

public MRESReturn OnMedigunPostFramePost(int medigun) {
	int healTarget = GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget");
	if (!IsValidEntity(healTarget) || healTarget < 1 || healTarget > MaxClients) {
		// don't process non-client targets
		return MRES_Ignored;
	}
	
	float flDrainRate = TF2CustAttr_GetFloat(medigun, "medigun drains health");
	if (flDrainRate == 0.0) {
		return MRES_Ignored;
	}
	
	int owner = TF2_GetEntityOwner(medigun);
	
	// TODO fix not being able to damage friendly players with owner set without friendlyfire??
	
	s_ForceGibRagdoll = true;
	s_ForceCritDeathSound = true;
	SDKHooks_TakeDamage(healTarget, medigun, owner, flDrainRate * GetGameFrameTime(),
			DMG_PREVENT_PHYSICS_FORCE | DMG_ALWAYSGIB);
	s_ForceCritDeathSound = false;
	s_ForceGibRagdoll = false;
	
	if (!IsPlayerAlive(healTarget)) {
		float flChargeLevel = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
		flChargeLevel += 0.1;
		if (flChargeLevel > 1.0) {
			flChargeLevel = 1.0;
		}
		SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", flChargeLevel);
	}
	
	return MRES_Ignored;
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!s_ForceGibRagdoll) {
		return;
	}
	
	float vecOrigin[3], vecMins[3], vecMaxs[3];
	GetClientAbsOrigin(client, vecOrigin);
	GetClientMins(client, vecMins);
	GetClientMaxs(client, vecMaxs);
	
	vecOrigin[2] += (vecMaxs[2] - vecMins[2]) / 2.0;
	
	TE_SetupTFExplosion_stub(vecOrigin, view_as<float>({ 0.0, 1.0, 0.0 }), TF_WEAPON_ROCKETLAUNCHER, 0, 0, 0xFFFF, 0xFFFF);
	TE_SendToAll();
}

// this is going to be rolled up into stocksoup once it's better documented
stock void TE_SetupTFExplosion_stub(const float vecOrigin[3],
		const float vecNormal[3] = { 0.0, 1.0, 0.0 }, int weaponid = TF_WEAPON_NONE,
		int entindex = 0, int def_id, int sound, int particleIndex = 0xFFFF) {
	TE_Start("TFExplosion");
	TE_WriteFloat("m_vecOrigin[0]", vecOrigin[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecOrigin[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecOrigin[2]);
	TE_WriteVector("m_vecNormal", vecNormal);
	TE_WriteNum("m_iWeaponID", weaponid);
	TE_WriteNum("entindex", entindex);
	TE_WriteNum("m_nDefID", def_id);
	TE_WriteNum("m_nSound", sound & 0xFFFF);
	
	// written as a short, -1 == 0xFFFF
	TE_WriteNum("m_iCustomParticleIndex", particleIndex & 0xFFFF);
}

public MRESReturn OnMedigunSecondaryAttackPre(int medigun) {
	// TODO handle medigun
	if (TF2CustAttr_GetFloat(medigun, "ubercharge nukes everything in radius") == 0.0) {
		return MRES_Ignored;
	}
	
	float flChargeMeter = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
	if (flChargeMeter < 1.0) {
		return MRES_Supercede;
	}
	
	int owner = TF2_GetEntityOwner(medigun);
	
	EmitGameSoundToAll(g_MedicScripts[GetRandomInt(0, sizeof(g_MedicScripts) - 1)], owner);
	EmitGameSoundToAll("MVM.BombExplodes", owner);
	
	MedicDetonate(medigun);
	
	return MRES_Supercede;
}

void MedicDetonate(int medigun) {
	float radius = TF2CustAttr_GetFloat(medigun, "ubercharge nukes everything in radius");
	if (radius == 0.0) {
		return;
	}
	
	int owner = TF2_GetEntityOwner(medigun);
	if (!IsValidEntity(owner) || !IsPlayerAlive(owner)) {
		return;
	}
	
	// ForcePlayerSuicide(owner);
	SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", 0.0);
	
	float vecOrigin[3];
	GetClientAbsOrigin(owner, vecOrigin);
	
	Client_Shake(owner);
	
	TE_SetupTFParticleEffect("fluidSmokeExpl_ring_mvm", vecOrigin);
	TE_SendToAll();
	
	int entity = -1;
	while ((entity = FindEntityInSphere(entity, vecOrigin, radius)) != -1) {
		// damage players
		if (entity > 0 && entity <= MaxClients && entity != owner) {
			s_ForceCritDeathSound = true;
			s_ForceGibRagdoll = true;
			SDKHooks_TakeDamage(entity, medigun, owner, 69420.0,
					DMG_PREVENT_PHYSICS_FORCE | DMG_ALWAYSGIB);
			s_ForceCritDeathSound = false;
			s_ForceGibRagdoll = false;
			continue;
		}
		
		// destroy nearby buildings??
	}
}

static int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius);
}

// pulled from smlib

#define	SHAKE_START					0			// Starts the screen shake for all players within the radius.
#define	SHAKE_STOP					1			// Stops the screen shake for all players within the radius.
#define	SHAKE_AMPLITUDE				2			// Modifies the amplitude of an active screen shake for all players within the radius.
#define	SHAKE_FREQUENCY				3			// Modifies the frequency of an active screen shake for all players within the radius.
#define	SHAKE_START_RUMBLEONLY		4			// Starts a shake effect that only rumbles the controller, no screen effect.
#define	SHAKE_START_NORUMBLE		5			// Starts a shake that does NOT rumble the controller.

/**
 * Shakes a client's screen with the specified amptitude,
 * frequency & duration.
 * 
 * @param client		Client Index.
 * @param command		Shake Mode, use one of the SHAKE_ definitions.
 * @param amplitude		Shake magnitude/amplitude.
 * @param frequency		Shake noise frequency.
 * @param duration		Shake lasts this long.
 * @return				True on success, false otherwise.
 */
stock bool Client_Shake(int client, int command = SHAKE_START, float amplitude = 50.0,
		float frequency = 150.0, float duration = 3.0) {
	if (command == SHAKE_STOP) {
		amplitude = 0.0;
	} else if (amplitude <= 0.0) {
		return false;
	}
	
	Handle userMessage = StartMessageOne("Shake", client);
	
	if (userMessage == INVALID_HANDLE) {
		return false;
	}
	
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available
			&& GetUserMessageType() == UM_Protobuf) {
		PbSetInt(userMessage, "command", command);
		PbSetFloat(userMessage, "local_amplitude", amplitude);
		PbSetFloat(userMessage, "frequency", frequency);
		PbSetFloat(userMessage, "duration", duration);
	} else {
		BfWriteByte(userMessage, command);
		BfWriteFloat(userMessage, amplitude);
		BfWriteFloat(userMessage, frequency);
		BfWriteFloat(userMessage, duration);
	}
	EndMessage();
	return true;
}
