/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>

#pragma newdecls required

#include <tf2_stocks>
#include <tf2attributes>
#include <tf_cattr_drink_effect>
#include <tf_custom_attributes>

#include <stocksoup/var_strings>

Handle g_SDKCallUpdatePlayerSpeed;

float g_flBuffEndTime[MAXPLAYERS + 1];

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
	g_flBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

public void OnCustomDrinkHandlerAvailable() {
	TF2CustomAttrDrink_Register("sugar frenzy", SugarFrenzyEffect);
}

public void OnClientPostThinkPost(int client) {
	if (!g_flBuffEndTime[client] || g_flBuffEndTime[client] >= GetGameTime()) {
		return;
	}
	
	TF2Attrib_RemoveCustomPlayerAttribute(client, "CARD: move speed bonus");
	
	ClearAttributeCache(client);
	
	TF2_UpdatePlayerSpeed(client);
	EmitGameSoundToAll("Scout.DodgeTired", client);
	
	g_flBuffEndTime[client] = 0.0;
}

public void SugarFrenzyEffect(int owner, int weapon, const char[] effectName) {
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	char attr[256];
	TF2CustAttr_GetString(weapon, "sugar frenzy drink properties", attr, sizeof(attr));
	
	float flDuration = ReadFloatVar(attr, "duration", 0.0);
	
	float flPostFireMult = ReadFloatVar(attr, "mult_postfiredelay", 1.0);
	float flMultReload = ReadFloatVar(attr, "mult_reload_time", 1.0);
	float flMoveSpeed = ReadFloatVar(attr, "mult_movespeed", 1.0);
	
	TF2Attrib_AddCustomPlayerAttribute(owner, "Reload time decreased", flMultReload, flDuration);
	TF2Attrib_AddCustomPlayerAttribute(owner, "fire rate bonus HIDDEN",
			flPostFireMult, flDuration);
	TF2Attrib_AddCustomPlayerAttribute(owner, "CARD: move speed bonus",
			flMoveSpeed, flDuration);
	
	/**
	 * mult_postfiredelay is cached, so we have to clear the entire cache for that attribute
	 * when the duration is over -- attribute expiry during that tick still counts here
	 */
	g_flBuffEndTime[owner] = GetGameTime() + flDuration + GetTickInterval();
	
	ClearAttributeCache(owner);
}

public Action ClearAttributeCacheTimer(Handle timer, int clientserial) {
	int client = GetClientFromSerial(clientserial);
	if (!client) {
		return Plugin_Handled;
	}
	
	ClearAttributeCache(client);
	TF2_UpdatePlayerSpeed(client);
	return Plugin_Handled;
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-custom-drink")) {
		OnCustomDrinkHandlerAvailable();
	}
}

void ClearAttributeCache(int client) {
	TF2Attrib_ClearCache(client);
	for (int i; i < 3; i++) {
		int weapon = GetPlayerWeaponSlot(client, i);
		if (IsValidEntity(weapon)) {
			TF2Attrib_ClearCache(weapon);
		}
	}
}

static void TF2_UpdatePlayerSpeed(int client) {
	SDKCall(g_SDKCallUpdatePlayerSpeed, client);
}
