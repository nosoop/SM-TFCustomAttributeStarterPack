/**
 * [TF2CA] Attribute: Banner Buff Override
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <dhooks>

#pragma newdecls required
#include <stocksoup/memory>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>
#include <tf2attributes>

#define PLUGIN_VERSION "1.1.1"
public Plugin myinfo = {
	name = "[TF2CA] Banner Buff Override",
	author = "nosoop",
	description = "Overrides the behavior of the Soldier's buff items.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop"
}

// taken from game code
#define SOLDIER_BUFF_RADIUS 450.0

#define CUSTOM_SOLDIER_BUFF_MAX_NAME_LENGTH 64

Handle g_DHookOnModifyRage;

static Address g_offset_CTFPlayerShared_pOuter;

int g_iActiveBuffWeapon[MAXPLAYERS + 1];
StringMap g_BuffForwards; // <callback>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("cattr-buff-override");
	
	CreateNative("TF2CustomAttrRageBuff_Register", RegisterCustomBuff);
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	
	Handle dtActivateRageBuff = DHookCreateFromConf(hGameConf, "CTFPlayerShared::ActivateRageBuff()");
	DHookEnableDetour(dtActivateRageBuff, false, OnActivateRageBuffPre);
	
	g_DHookOnModifyRage = DHookCreateFromConf(hGameConf, "CTFPlayerShared::PulseRageBuff()");
	DHookEnableDetour(g_DHookOnModifyRage, false, OnPulseRageBuffPre);
	
	g_offset_CTFPlayerShared_pOuter =
			view_as<Address>(GameConfGetOffset(hGameConf, "CTFPlayerShared::m_pOuter"));
	
	delete hGameConf;
	
	g_BuffForwards = new StringMap();
}

public int RegisterCustomBuff(Handle plugin, int argc) {
	char buffName[CUSTOM_SOLDIER_BUFF_MAX_NAME_LENGTH];
	GetNativeString(1, buffName, sizeof(buffName));
	if (!buffName[0]) {
		ThrowNativeError(1, "Cannot have an empty buff name.");
	}
	
	Handle hFwd;
	if (!g_BuffForwards.GetValue(buffName, hFwd)) {
		hFwd = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);
		g_BuffForwards.SetValue(buffName, hFwd);
	}
	AddToForward(hFwd, plugin, GetNativeFunction(2));
}

public MRESReturn OnActivateRageBuffPre(Address pPlayerShared, Handle hParams) {
	int client = GetClientFromPlayerShared(pPlayerShared);
	g_iActiveBuffWeapon[client] = INVALID_ENT_REFERENCE;
	
	int inflictor = DHookGetParam(hParams, 1);
	if (!IsValidEntity(inflictor)) {
		return MRES_Ignored;
	}
	
	if (inflictor == client) {
		// Heatmaker treats the client as the inflictor instead of the weapon
		// hack around this by pulling down the active weapon instead
		inflictor = TF2_GetClientActiveWeapon(inflictor);
	}
	if (!IsValidEntity(inflictor)) {
		return MRES_Ignored;
	}
	
	g_iActiveBuffWeapon[client] = EntIndexToEntRef(inflictor);
	return MRES_Ignored;
}

public MRESReturn OnPulseRageBuffPre(Address pPlayerShared, Handle hParams) {
	int client = GetClientFromPlayerShared(pPlayerShared);
	
	int buffItem = EntRefToEntIndex(g_iActiveBuffWeapon[client]);
	if (!IsValidEntity(buffItem)) {
		return MRES_Ignored;
	}
	
	char buffName[CUSTOM_SOLDIER_BUFF_MAX_NAME_LENGTH];
	if (!TF2CustAttr_GetString(buffItem, "custom soldier buff type", buffName, sizeof(buffName))
			&& !TF2CustAttr_GetString(buffItem, "custom buff type", buffName, sizeof(buffName))) {
		return MRES_Ignored;
	}
	
	Handle hFwd;
	if (!g_BuffForwards.GetValue(buffName, hFwd) || !GetForwardFunctionCount(hFwd)) {
		LogError("Buff type '%s' is not associated with a plugin", buffName);
		return MRES_Supercede;
	}
	
	// there is a mod_soldier_buff_range attribute class but it's not present in items_game
	// regardless, implement it here
	float flRadius = TF2Attrib_HookValueFloat(SOLDIER_BUFF_RADIUS, "mod_soldier_buff_range",
			buffItem);
	flRadius *= TF2CustAttr_GetFloat(buffItem, "mult soldier custom buff range", 1.0);
	
	float flRadiusSq = Pow(flRadius, 2.0);
	
	float vecBuffOrigin[3];
	GetClientAbsOrigin(client, vecBuffOrigin);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) {
			continue;
		}
		
		float vecTargetOrigin[3];
		GetClientAbsOrigin(i, vecTargetOrigin);
		if (GetVectorDistance(vecBuffOrigin, vecTargetOrigin, true) > flRadiusSq) {
			continue;
		}
		
		Call_StartForward(hFwd);
		Call_PushCell(client);
		Call_PushCell(i);
		Call_PushString(buffName);
		Call_PushCell(buffItem);
		Call_Finish();
		
		// there is a player_buff event we could implement but it shouldn't really matter
	}
	
	return MRES_Supercede;
}

static int GetClientFromPlayerShared(Address pPlayerShared) {
	Address pOuter = DereferencePointer(pPlayerShared + g_offset_CTFPlayerShared_pOuter);
	return GetEntityFromAddress(pOuter);
}
