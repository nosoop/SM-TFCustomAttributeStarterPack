#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>

#pragma newdecls required

#include <tf2_stocks>
#include <tf2attributes>
#include <tf_cattr_lunch_effect>
#include <tf_custom_attributes>

#include <stocksoup/var_strings>
#include <custom_status_hud>

float g_flBuffEndTime[MAXPLAYERS + 1];

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flBuffEndTime[client] = 0.0;
}

void OnCustomLunchboxHandlerAvailable() {
	TF2CustomAttrLunchbox_Register("mod crit chance", ApplyModCritChance);
}

void ApplyModCritChance(int owner, int weapon, const char[] effectName) {
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	char attr[256];
	TF2CustAttr_GetString(weapon, "mod crit chance lunch properties", attr, sizeof(attr));
	
	float flDuration = ReadFloatVar(attr, "duration", 0.0);
	float flCritScale = ReadFloatVar(attr, "scale", 1.0);
	
	TF2Attrib_AddCustomPlayerAttribute(owner, "crit mod disabled hidden", flCritScale,
			flDuration);
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-custom-lunchbox")) {
		OnCustomLunchboxHandlerAvailable();
	}
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	if (g_flBuffEndTime[client] > GetGameTime()) {
		char buffer[64];
		Format(buffer, sizeof(buffer), "Crit Bonus: %.0fs",
				g_flBuffEndTime[client] - GetGameTime());
		
		entries.SetString("mod_crit_bonus", buffer);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
