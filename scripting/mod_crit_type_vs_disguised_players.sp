/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <tf_ontakedamage>

public Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType) {
	if (victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients
			|| !IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	if (!TF2_IsPlayerInCondition(victim, TFCond_Disguised)) {
		return Plugin_Continue;
	}
	
	// set to 1 for mini-crits, 2 for full crits
	CritType modifiedCritType =
			view_as<CritType>(TF2CustAttr_GetInt(weapon, "mod crit type vs disguised players"));
	
	if (modifiedCritType > critType) {
		critType = modifiedCritType;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
