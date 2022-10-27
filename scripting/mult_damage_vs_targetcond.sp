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
	if (!ReadTFCondVar(attr, "condition", cond)) {
		return Plugin_Continue;
	}
	
	damage *= ReadFloatVar(attr, "scale", 1.0);
	
	return Plugin_Continue;
}

bool ReadTFCondVar(const char[] varstring, const char[] key, TFCond &value) {
	char condString[32];
	if (!ReadStringVar(varstring, key, condString, sizeof(condString))) {
		return false;
	}
	
	int result;
	if (StringToIntEx(condString, result)) {
		value = view_as<TFCond>(result);
		return true;
	}
	
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
	
	if (s_Conditions.GetValue(condString, value)) {
		return true;
	}
	
	// log message if given string does not resolve to a condition
	static StringMap s_LoggedConditions;
	if (!s_LoggedConditions) {
		s_LoggedConditions = new StringMap();
	}
	any ignored;
	if (!s_LoggedConditions.GetValue(condString, ignored)) {
		LogError("Could not translate condition name %s to index.", condString);
		s_LoggedConditions.SetValue(condString, true);
	}
	return false;
}
