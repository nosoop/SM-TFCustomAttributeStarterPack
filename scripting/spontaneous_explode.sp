/**
 * "spontaneous explode at aim"
 * 
 * Generates a massive explosion where the cursor is located.  Gibs players and forces their
 * crit death sound.
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <dhooks>
#include <sdkhooks>

#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prefabs>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/tempents_stocks>
#include <stocksoup/var_strings>
#include <stocksoup/value_remap>

#include <smlib/clients>

Handle g_SDKCallFindEntityInSphere;
Handle g_SDKCallGetCombatCharacterPtr;

// read from CTFPlayer::DeathSound() disasm
int offs_CTFPlayer_LastDamageType = 0x215C;

static char g_ExplosionSounds[][] = {
	"misc/doomsday_missile_explosion.wav",
	"weapons/explode1.wav",
	"items/cart_explode.wav",
	"mvm/mvm_tank_explode.wav",
	"weapons/rocket_blackbox_explode1.wav",
	"misc/halloween/spell_mirv_explode_primary.wav"
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
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CBaseEntity::MyCombatCharacterPointer()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallGetCombatCharacterPtr = EndPrepSDKCall();
	
	Handle dtBaseGunFireProjectile = DHookCreateFromConf(hGameConf,
			"CTFWeaponBaseGun::FireProjectile()");
	DHookEnableDetour(dtBaseGunFireProjectile, false, OnBaseGunFireProjectilePre);
	
	Handle dtCreateRagdoll = DHookCreateFromConf(hGameConf, "CTFPlayer::CreateRagdollEntity()");
	DHookEnableDetour(dtCreateRagdoll, false, OnCreateRagdollPre);
	
	int offslastDamage = FindSendPropInfo("CTFPlayer", "m_flMvMLastDamageTime");
	if (offslastDamage < 0) {
		SetFailState("Could not get offset for CTFPlayer::m_flMvMLastDamageTime");
	}
	
	offs_CTFPlayer_LastDamageType = offslastDamage + 0x14;
	
	delete hGameConf;
}

public void OnMapStart() {
	for (int i; i < sizeof(g_ExplosionSounds); i++) {
		PrecacheSound(g_ExplosionSounds[i]);
	}
}

MRESReturn OnBaseGunFireProjectilePre(int weapon, Handle hParams) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	char buffer[128];
	if (!TF2CustAttr_GetString(weapon, "spontaneous explode at aim", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	int clip = GetEntProp(weapon, Prop_Data, "m_iClip1");
	if (!clip) {
		return MRES_Supercede;
	}
	
	CauseSpontaneousExplosion(owner, weapon);
	return MRES_Supercede;
}

static bool s_ForceGibRagdoll;
MRESReturn OnCreateRagdollPre(int client, Handle hParams) {
	if (!s_ForceGibRagdoll) {
		return MRES_Ignored;
	}
	DHookSetParam(hParams, 1, true);
	return MRES_ChangedHandled;
}

static bool s_ForceCritDeathSound;
void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage, int damagetype) {
	if (!s_ForceCritDeathSound) {
		return;
	}
	
	// forces crit damagetype so we get the crit death sound
	SetEntData(victim, offs_CTFPlayer_LastDamageType, DMG_CRIT);
}

void CauseSpontaneousExplosion(int client, int weapon) {
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "spontaneous explode at aim", attr, sizeof(attr))) {
		return;
	}
	
	float angEye[3], vecStartPosition[3];
	GetClientEyePosition(client, vecStartPosition);
	GetClientEyeAngles(client, angEye);
	
	Handle trace = TR_TraceRayFilterEx(vecStartPosition, angEye, MASK_SHOT | MASK_PLAYERSOLID,
			RayType_Infinite, TraceEntityFilterSelf, client);
	if (!TR_DidHit(trace)) {
		delete trace;
		return;
	}
	
	float vecAimPoint[3], vecNormal[3];
	TR_GetEndPosition(vecAimPoint, trace);
	TR_GetPlaneNormal(trace, vecNormal);
	delete trace;
	
	AddVectors(vecAimPoint, vecNormal, vecAimPoint);
	TE_SetupTFParticleEffect("fluidSmokeExpl_ring_mvm", vecAimPoint);
	TE_SendToAll();
	
	EmitSoundToAll(g_ExplosionSounds[GetRandomInt(0, sizeof(g_ExplosionSounds) - 1)],
			.level = SNDLEVEL_GUNFIRE, .origin = vecAimPoint);
	
	float radius = ReadFloatVar(attr, "radius");
	
	int entity = -1;
	while ((entity = FindEntityInSphere(entity, vecAimPoint, radius)) != -1) {
		// damage combat characters (buildings, players, tanks...)
		if (IsEntityCombatCharacter(entity) && entity != client) {
			s_ForceCritDeathSound = true;
			s_ForceGibRagdoll = true;
			SDKHooks_TakeDamage(entity, weapon, client, ReadFloatVar(attr, "damage"),
					DMG_PREVENT_PHYSICS_FORCE | DMG_ALWAYSGIB);
			s_ForceCritDeathSound = false;
			s_ForceGibRagdoll = false;
			continue;
		}
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		// TODO improve logic with observer modes
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) {
			continue;
		}
		
		float vecPosition[3];
		GetClientEyePosition(i, vecPosition);
		
		float distance = GetVectorDistance(vecAimPoint, vecPosition);
		
		float amplitude = RemapValueFloat({ 32.0, 2048.0 }, { 50.0, 10.0 }, distance, true);
		Client_Shake(i, .amplitude = amplitude);
	}
}

/**
 * Internal callback function that ignores itself.
 */
static stock bool TraceEntityFilterSelf(int entity, int contentsMask, int client) {
	// dumb hack to prevent hitting respawn room visualizers
	if (client == entity || HasEntProp(entity, Prop_Data, "m_iszRespawnRoomName")) {
		return false;
	}
	return true;
}

static int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius, Address_Null);
}

static bool IsEntityCombatCharacter(int entity) {
	return SDKCall(g_SDKCallGetCombatCharacterPtr, entity) != Address_Null;
}
