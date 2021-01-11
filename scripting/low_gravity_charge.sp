/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2>
#include <sdkhooks>

#pragma newdecls required

#include <tf2utils>
#include <tf2wearables>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>

bool g_bAppliedGravityCharge[MAXPLAYERS + 1];
bool g_bShouldCritWhileAirborne[MAXPLAYERS + 1];

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void TF2_OnConditionAdded(int client, TFCond condition) {
	if (condition != TFCond_Charging) {
		return;
	}
	
	int weapon = TF2_GetPlayerLoadoutSlot(client, TF2LoadoutSlot_Secondary);
	
	char attr[64];
	if (!IsValidEntity(weapon)
			|| !TF2CustAttr_GetString(weapon, "demo charge low gravity", attr, sizeof(attr))) {
		return;
	}
	
	SetEntityGravity(client, ReadFloatVar(attr, "gravity", 1.0));
	g_bAppliedGravityCharge[client] = true;
	g_bShouldCritWhileAirborne[client] = !!ReadIntVar(attr, "low_grav_crits", false);
	UpdateChargingWeaponCritState(client, TF2_GetClientActiveWeapon(client));
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
}

public void OnClientPostThinkPost(int client) {
	if (!g_bAppliedGravityCharge[client] || GetEntityFlags(client) & FL_ONGROUND == 0) {
		return;
	}
	
	SetEntityGravity(client, 1.0);
	g_bAppliedGravityCharge[client] = false;
	
	TF2_RemoveCondition(client, TFCond_CritRuneTemp);
	return;
}

public void OnClientWeaponSwitchPost(int client, int weapon) {
	UpdateChargingWeaponCritState(client, weapon);
}

void UpdateChargingWeaponCritState(int client, int weapon) {
	if (!g_bAppliedGravityCharge[client] || !g_bShouldCritWhileAirborne[client]) {
		return;
	}
	
	if (IsValidEntity(weapon) && TF2Util_GetWeaponSlot(weapon) == TFWeaponSlot_Melee) {
		TF2_AddCondition(client, TFCond_CritRuneTemp);
	} else {
		TF2_RemoveCondition(client, TFCond_CritRuneTemp);
	}
}
