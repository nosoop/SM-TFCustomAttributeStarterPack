/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#pragma newdecls required

#include <tf2utils>
#include <stocksoup/var_strings>
#include <tf_calcmaxspeed>
#include <tf_custom_attributes>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] TF2 Classic Nailgun Slow",
	author = "nosoop",
	description = "Custom slowdown behavior for the Nailgun.",
	version = PLUGIN_VERSION,
	url = "localhost"
}

float g_flNailgunStunTime[MAXPLAYERS + 1];
float g_flNailgunSpeedRatio[MAXPLAYERS + 1];

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flNailgunStunTime[client] = 0.0;
	g_flNailgunSpeedRatio[client] = 1.0;
	
	SDKHook(client, SDKHook_PreThinkPost, OnClientPreThinkPost);
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnClientTakeDamageAlivePost);
}

public void OnClientPreThinkPost(int client) {
	if (g_flNailgunStunTime[client] <= 0.0) {
		return;
	}
	
	g_flNailgunStunTime[client] -= GetGameFrameTime();
	if (g_flNailgunStunTime[client] <= 0.0) {
		g_flNailgunStunTime[client] = 0.0;
		g_flNailgunSpeedRatio[client] = 1.0;
		TF2Util_UpdatePlayerSpeed(client);
	}
}

public void OnClientTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3],
		int damagecustom) {
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	char nailgunProps[512];
	if (!TF2CustAttr_GetString(weapon, "nailgun custom slow",
			nailgunProps, sizeof(nailgunProps))) {
		return;
	}
	
	float flSlowRatio = ReadFloatVar(nailgunProps, "move_ratio", 0.5);
	float flSlowAdditive = ReadFloatVar(nailgunProps, "slow_add_time", 1.0);
	float flSlowMaxTime = ReadFloatVar(nailgunProps, "slow_max_time", 5.0);
	
	if (flSlowRatio < g_flNailgunSpeedRatio[victim]) {
		g_flNailgunSpeedRatio[victim] = flSlowRatio;
	}
	
	float flNewSlowDuration = g_flNailgunStunTime[victim] + flSlowAdditive;
	g_flNailgunStunTime[victim] = (flNewSlowDuration > flSlowMaxTime)?
			flSlowMaxTime : flNewSlowDuration;
	TF2Util_UpdatePlayerSpeed(victim);
}

public Action TF2_OnCalculateMaxSpeed(int client, float &flMaxSpeed) {
	if (g_flNailgunStunTime[client] <= 0.0) {
		return Plugin_Continue;
	}
	
	flMaxSpeed *= g_flNailgunSpeedRatio[client];
	return Plugin_Changed;
}
