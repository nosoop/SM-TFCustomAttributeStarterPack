/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdkhooks>
#include <tf2utils>
#include <tf_custom_attributes>

#include <stocksoup/var_strings>
#include "shared/tf_var_strings.sp"

public void OnPluginStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnPlayerTakeDamageAlive);
}

Action OnPlayerTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage,
		int& damagetype, int& weapon, float damageForce[3], float damagePosition[3],
		int damagecustom) {
	if (TF2Util_IsCustomDamageTypeDOT(damagecustom)) {
		return Plugin_Continue;
	}
	
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "mult damage vs targetcond", attr, sizeof(attr))) {
		return Plugin_Continue;
	}
	
	TFCond cond;
	if (!ReadTFCondVar(attr, "condition", cond) || !TF2_IsPlayerInCondition(victim, cond)) {
		return Plugin_Continue;
	}
	
	damage *= ReadFloatVar(attr, "scale", 1.0);
	
	return Plugin_Changed;
}
