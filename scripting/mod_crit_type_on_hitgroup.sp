#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <tf_custom_attributes>
#include <tf_ontakedamage>

// hit group standards, taken from
// https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/shareddefs.h
#define	HITGROUP_GENERIC	0
#define	HITGROUP_HEAD		1
#define	HITGROUP_CHEST		2
#define	HITGROUP_STOMACH	3
#define HITGROUP_LEFTARM	4
#define HITGROUP_RIGHTARM	5
#define HITGROUP_LEFTLEG	6
#define HITGROUP_RIGHTLEG	7
#define HITGROUP_GEAR		10

public Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType) {
	if (victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients
			|| !IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "mod crit type on hitgroup", attr, sizeof(attr))) {
		return Plugin_Continue;
	}
	
	int hitgroup = GetEntProp(victim, Prop_Data, "m_LastHitGroup");
	
	// don't activate this on HITGROUP_GENERIC
	if (hitgroup && hitgroup == ReadIntVar(attr, "hitgroup", HITGROUP_GENERIC)) {
		CritType newCritType = view_as<CritType>(ReadIntVar(attr, "crit_type"));
		if (newCritType > critType) {
			critType = newCritType;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}
