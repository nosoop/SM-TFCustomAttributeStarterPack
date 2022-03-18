/**
 * [TF2] Custom Attribute: addcond while active
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdkhooks>
#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>

#define PLUGIN_VERSION "1.0.1"
public Plugin myinfo = {
	name = "[TF2] Custom Attribute: addcond while active",
	author = "nosoop",
	description = "Condition is added when weapon is active, then removed when switched.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomAttributeStarterPack"
}

#define TFCond_Invalid (view_as<TFCond>(-1))

TFCond g_iLastActiveCondition[MAXPLAYERS + 1] = { TFCond_Invalid, ... };

public void OnPluginStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_iLastActiveCondition[client] = TFCond_Invalid;
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
	SDKHook(client, SDKHook_SpawnPost, OnClientSpawnPost);
}

void OnClientSpawnPost(int client) {
	if (!client) {
		return;
	}
	
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (!IsValidEntity(activeWeapon)) {
		return;
	}
	
	OnClientWeaponSwitchPost(client, activeWeapon);
}

void OnClientWeaponSwitchPost(int client, int weapon) {
	// the weapon switch may have been superceded; check actually active weapon
	int activeWeapon = TF2_GetClientActiveWeapon(client);
	TFCond currentCondition = TFCond_Invalid;
	
	char buffer[64];
	if (IsValidEntity(activeWeapon)
			&& TF2CustAttr_GetString(activeWeapon, "addcond while active", buffer, sizeof(buffer))) {
		currentCondition = ParseConditionString(buffer);
	}
	
	if (g_iLastActiveCondition[client] != TFCond_Invalid) {
		TF2_RemoveCondition(client, g_iLastActiveCondition[client]);
	}
	if (currentCondition != TFCond_Invalid) {
		TF2_AddCondition(client, currentCondition);
	}
	g_iLastActiveCondition[client] = currentCondition;
}

TFCond ParseConditionString(const char[] name) {
	static StringMap s_Conditions;
	if (!s_Conditions) {
		char buffer[64];
		
		s_Conditions = new StringMap();
		for (TFCond cond; cond <= TF2Util_GetLastCondition(); cond++) {
			if (TF2Util_GetConditionName(cond, buffer, sizeof(buffer))) {
				s_Conditions.SetValue(buffer, cond);
			}
		}
	}
	
	TFCond value = TFCond_Invalid;
	s_Conditions.GetValue(name, value);
	return value;
}
