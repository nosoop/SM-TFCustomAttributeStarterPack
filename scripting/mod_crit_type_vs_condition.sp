#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <tf_ontakedamage>
#include <stocksoup/var_strings>

public Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType) {
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "mod crit type on target condition",
			attr, sizeof(attr))) {
		return Plugin_Continue;
	}
	
	TFCond cond = view_as<TFCond>(ReadIntVar(attr, "condition"));
	if (!TF2_IsPlayerInCondition(victim, cond)) {
		return Plugin_Continue;
	}
	
	CritType newCritType = view_as<CritType>(ReadIntVar(attr, "crit_type"));
	if (newCritType > critType) {
		critType = newCritType;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
