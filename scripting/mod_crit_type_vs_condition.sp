#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <tf_ontakedamage>
#include <stocksoup/var_strings>
#include <tf2utils>

public Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType) {
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	// we use a bitwise or here because we don't want to short-circuit the check
	// attacker condition crit mod might be higher than the target's
	if (ApplyTargetConditionCritMod(victim, weapon, damagecustom, critType)
			| ApplyAttackerConditionCritMod(attacker, weapon, damagecustom, critType)) {
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

bool ApplyTargetConditionCritMod(int victim, int weapon, int damagecustom, CritType &critType) {
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "mod crit type on target condition",
			attr, sizeof(attr))) {
		return false;
	}
	
	if (ReadIntVar(attr, "no_dot") && TF2Util_IsCustomDamageTypeDOT(damagecustom)) {
		return false;
	}
	
	TFCond cond;
	if (!ReadTFCondVar(attr, "condition", cond) || !TF2_IsPlayerInCondition(victim, cond)) {
		return false;
	}
	
	CritType newCritType = view_as<CritType>(ReadIntVar(attr, "crit_type"));
	if (newCritType > critType) {
		critType = newCritType;
		return true;
	}
	return false;
}

bool ApplyAttackerConditionCritMod(int attacker, int weapon, int damagecustom,
		CritType &critType) {
	if (attacker < 1 || attacker > MaxClients) {
		return false;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "mod crit type on attacker condition",
			attr, sizeof(attr))) {
		return false;
	}
	
	if (ReadIntVar(attr, "no_dot") && TF2Util_IsCustomDamageTypeDOT(damagecustom)) {
		return false;
	}
	
	TFCond cond;
	if (!ReadTFCondVar(attr, "condition", cond) || !TF2_IsPlayerInCondition(attacker, cond)) {
		return false;
	}
	
	CritType newCritType = view_as<CritType>(ReadIntVar(attr, "crit_type"));
	if (newCritType > critType) {
		critType = newCritType;
		return true;
	}
	return false;
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
