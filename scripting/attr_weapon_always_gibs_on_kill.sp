/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <dhook_takedamageinfo>
#include <dhooks_gameconf_shim>

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Weapon Always Gibs On Kill",
	author = "Author!",
	description = "Description!",
	version = PLUGIN_VERSION,
	url = "localhost"
}

Handle g_DHookShouldGib;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	g_DHookShouldGib = GetDHooksDefinition(hGameConf, "CTFPlayer::ShouldGib()");
	
	ClearDHooksDefinitions();
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
	DHookEntity(g_DHookShouldGib, false, client, .callback = OnPlayerShouldGib);
}

MRESReturn OnPlayerShouldGib(int client, Handle hReturn, Handle hParams) {
	SetTakeDamageInfoContext(hParams, 1);
	
	int weapon = GetDamageInfoHandle(TakeDamageInfo_Weapon);
	if (IsValidEntity(weapon) && TF2CustAttr_GetInt(weapon, "weapon always gibs on kill")) {
		DHookSetReturn(hReturn, true);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}
