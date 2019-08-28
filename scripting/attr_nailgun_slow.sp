/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#pragma newdecls required

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

// TODO maybe have an arraylist with stun amounts, 
Handle g_SDKCallUpdatePlayerSpeed;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayer::TeamFortress_SetSpeed()");
	g_SDKCallUpdatePlayerSpeed = EndPrepSDKCall();
	
	delete hGameConf;
}

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
		TF2_UpdatePlayerSpeed(client);
	}
}

public void OnClientTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3],
		int damagecustom) {
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(weapon);
	if (!attr) {
		return;
	}
	
	/**
	 * we really should have a native for the attribute getters so we don't need to do all these
	 * checks every single time
	 */
	char nailgunProps[512];
	attr.GetString("nailgun custom slow", nailgunProps, sizeof(nailgunProps));
	delete attr;
	
	if (!nailgunProps[0]) {
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
	TF2_UpdatePlayerSpeed(victim);
}

public Action TF2_OnCalculateMaxSpeed(int client, float &flMaxSpeed) {
	if (g_flNailgunStunTime[client] <= 0.0) {
		return Plugin_Continue;
	}
	
	flMaxSpeed *= g_flNailgunSpeedRatio[client];
	return Plugin_Changed;
}

static void TF2_UpdatePlayerSpeed(int client) {
	SDKCall(g_SDKCallUpdatePlayerSpeed, client);
}
