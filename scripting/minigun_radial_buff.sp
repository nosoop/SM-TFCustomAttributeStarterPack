#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdkhooks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <stocksoup/entity_prop_stocks>
#include <stocksoup/tf/econ>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/entity_prefabs>
#include <stocksoup/entity_tools>
#include <stocksoup/tf/weapon>
#include <stocksoup/tf/tempents_stocks>

#include "shared/tf_var_strings.sp"

enum {
	AC_STATE_IDLE = 0,
	AC_STATE_STARTFIRING,
	AC_STATE_FIRING,
	AC_STATE_SPINNING,
	AC_STATE_DRYFIRE
};

Handle g_DHookItemPostFrame;
Handle g_SDKCallFindEntityInSphere;

float g_flNextBuffTime[MAXPLAYERS + 1];

int g_iConditionFx[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_flEffectExpiry[MAXPLAYERS + 1];

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
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
	int minigun = -1;
	while ((minigun = FindEntityByClassname(minigun, "tf_weapon_minigun")) != -1) {
		HookMinigun(minigun);
	}
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidEntity(g_iConditionFx[i])) {
			RemoveEntity(g_iConditionFx[i]);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flNextBuffTime[client] = 0.0;
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

public void OnEntityCreated(int entity, const char[] className) {
	if (TF2Util_IsEntityWeapon(entity) && TF2Util_GetWeaponID(entity) == TF_WEAPON_MINIGUN) {
		HookMinigun(entity);
	}
}

void OnClientPostThinkPost(int client) {
	if (IsValidEntity(g_iConditionFx[client]) && GetGameTime() > g_flEffectExpiry[client]) {
		RemoveEntity(g_iConditionFx[client]);
	}
}

static void HookMinigun(int minigun) {
	DHookEntity(g_DHookItemPostFrame, false, minigun, .callback = OnMinigunPostFramePre);
}

MRESReturn OnMinigunPostFramePre(int minigun) {
	int owner = TF2_GetEntityOwner(minigun);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	int iWeaponState = GetEntProp(minigun, Prop_Send, "m_iWeaponState");
	
	if (iWeaponState <= AC_STATE_STARTFIRING || g_flNextBuffTime[owner] > GetGameTime()) {
		return MRES_Ignored;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(minigun, "minigun has custom radial buff", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	TFCond condition;
	if (!ReadTFCondVar(attr, "condition", condition)) {
		return MRES_Ignored;
	}
	
	float radius = ReadFloatVar(attr, "radius");
	float duration = ReadFloatVar(attr, "duration");
	if (radius <= 0.0 || duration <= 0.0) {
		return MRES_Ignored;
	}
	
	if (RadialBuff(minigun, radius, condition, duration, false)) {
		// don't check on every tick
		g_flNextBuffTime[owner] = GetGameTime() + 0.25;
	}
	
	return MRES_Ignored;
}

bool RadialBuff(int minigun, float radius, TFCond condition, float flDuration, bool self) {
	int owner = TF2_GetEntityOwner(minigun);
	if (owner < 1 || owner > MaxClients) {
		return false;
	}
	
	if (!TF2_GetWeaponAmmo(minigun)) {
		return false;
	}
	
	float vecClientPos[3];
	GetClientAbsOrigin(owner, vecClientPos);
	
	int ent = -1;
	while ((ent = FindEntityInSphere(ent, vecClientPos, radius)) != -1) {
		if (ent < 1 || ent > MaxClients) {
			continue;
		}
		
		if (ent == owner && !self) {
			continue;
		}
		
		if (TF2_GetClientTeam(ent) != TF2_GetClientTeam(owner)) {
			continue;
		}
		
		TF2_AddCondition(ent, condition, flDuration, owner);
		ApplyEffect(ent, 1.0);
	}
	return true;
}

static int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius);
}

void ApplyEffect(int client, float duration) {
	g_flEffectExpiry[client] = GetGameTime() + duration;
	if (IsValidEntity(g_iConditionFx[client])) {
		return;
	}
	
	// show at feet
	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);
	vecOrigin[2] += 0.4;
	
	int particle = CreateParticle("soldierbuff_mvm");
	TeleportEntity(particle, vecOrigin, NULL_VECTOR, NULL_VECTOR);
	ParentEntity(client, particle);
	
	g_iConditionFx[client] = EntIndexToEntRef(particle);
}
