/**
 * "pull target on hit"
 * 
 * Pulls target towards the attacking player.
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <sdkhooks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3],
		int damagecustom) {
	/**
	 * don't trigger on condition-based damage
	 * someday I'll look into what game function to hook for this case
	 */
	if (!IsValidEntity(weapon) || TF2Util_IsCustomDamageTypeDOT(damagecustom)) {
		return;
	}
	
	float flPull = TF2CustAttr_GetFloat(weapon, "pull target on hit");
	if (flPull <= 0.0) {
		return;
	}
	
	float vecOrigin[3], vecAttackerOrigin[3];
	GetClientAbsOrigin(victim, vecOrigin);
	GetClientAbsOrigin(attacker, vecAttackerOrigin);
	
	float vecPullForce[3];
	MakeVectorFromPoints(vecOrigin, vecAttackerOrigin, vecPullForce);
	vecPullForce[2] = 0.0;
	
	NormalizeVector(vecPullForce, vecPullForce);
	ScaleVector(vecPullForce, flPull);
	
	// force victims to slide towards their target for a bit
	TF2_AddCondition(victim, TFCond_LostFooting, 0.5);
	
	// don't bother making this an impulse force
	TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vecPullForce);
	
	return;
}
