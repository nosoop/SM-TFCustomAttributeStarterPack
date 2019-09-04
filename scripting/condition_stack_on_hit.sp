#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>

#pragma newdecls required

#include <tf_cond_info>
#include <tf_custom_attributes>
#include <stocksoup/value_remap>
#include <stocksoup/var_strings>

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	char attr[256];
	if (!TF2CustAttr_GetString(weapon, "condition stack on hit", attr, sizeof(attr))) {
		return;
	}
	
	TFCond condition = view_as<TFCond>(ReadIntVar(attr, "condition"));
	
	float falloffRange[2], falloffDuration[2];
	
	falloffRange[0] = ReadFloatVar(attr, "falloff_range_min", 32.0);
	falloffRange[1] = ReadFloatVar(attr, "falloff_range_max", falloffRange[0]);
	
	falloffDuration[0] = ReadFloatVar(attr, "duration_at_min");
	falloffDuration[1] = ReadFloatVar(attr, "duration_at_max", 0.0);
	
	float flMaxDuration = ReadFloatVar(attr, "max_duration", 10.0);
	bool additive = !!ReadIntVar(attr, "additive");
	
	if (!condition) {
		return;
	}
	
	float flDistance = GetDistanceBetweenClients(attacker, victim);
	float flDuration = RemapValueFloat(falloffRange, falloffDuration, flDistance, true);
	if (!TF2_IsPlayerInCondition(victim, condition) || !additive) {
		TF2_AddCondition(victim, condition, flDuration, attacker);
	} else {
		float flNewDuration = TF2_GetConditionData(victim, condition,
				ConditionInfo_Duration);
		flNewDuration += flDuration;
		
		if (flNewDuration > flMaxDuration) {
			flNewDuration = flMaxDuration;
		}
		
		TF2_SetConditionData(victim, condition, ConditionInfo_Duration, flNewDuration);
	}
}

float GetDistanceBetweenClients(int client, int otherClient, bool ignoreHeight = false) {
	float vecClientOrigin[3], vecOtherClientOrigin[3];
	GetClientAbsOrigin(client, vecClientOrigin);
	GetClientAbsOrigin(otherClient, vecOtherClientOrigin);
	
	if (ignoreHeight) {
		vecClientOrigin[2] = 0.0;
		vecOtherClientOrigin[2] = 0.0;
	}
	
	return GetVectorDistance(vecClientOrigin, vecOtherClientOrigin);
}