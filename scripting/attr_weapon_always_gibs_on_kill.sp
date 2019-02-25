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
	Handle hGameConf = LoadGameConfigFile("tf2.ca_weapon_always_gibs_on_kill");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.ca_weapon_always_gibs_on_kill).");
	}
	
	g_DHookShouldGib = DHookCreateFromConf(hGameConf, "CTFPlayer::ShouldGib()");
	
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

public MRESReturn OnPlayerShouldGib(int client, Handle hReturn, Handle hParams) {
	SetTakeDamageInfoContext(hParams, 1);
	
	int weapon = GetDamageInfoHandle(TakeDamageInfo_Weapon);
	if (IsAlwaysGibWeapon(weapon)) {
		DHookSetReturn(hReturn, true);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

static bool IsAlwaysGibWeapon(int weapon) {
	if (!IsValidEntity(weapon)) {
		return false;
	}
	
	KeyValues attributes = TF2CustAttr_GetAttributeKeyValues(weapon);
	if (!attributes) {
		return false;
	}
	
	bool alwaysGib = !!attributes.GetNum("weapon always gibs on kill", false);
	delete attributes;
	return alwaysGib;
}
