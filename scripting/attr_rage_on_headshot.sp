/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>

#pragma newdecls required

#include <stocksoup/log_server>
#include <stocksoup/var_strings>
#include <tf_custom_attributes>

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Rage on Headshot",
	author = "nosoop",
	description = "Adds to the player's rage meter on headshots.",
	version = PLUGIN_VERSION,
	url = "localhost"
}

public void OnPluginStart() {
	HookEvent("player_hurt", OnPlayerHurt, EventHookMode_Post);
}

public void OnPlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || victim > MaxClients) {
		return;
	}
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker < 1 || attacker > MaxClients) {
		return;
	}
	
	int customKill = event.GetInt("custom");
	if (customKill != TF_CUSTOM_HEADSHOT && customKill != TF_CUSTOM_HEADSHOT_DECAPITATION) {
		return;
	}
	
	int hPrimary = GetPlayerWeaponSlot(attacker, 0);
	if (!IsValidEntity(hPrimary)) {
		return;
	}
	
	float flRageOnHeadshot = GetHeadshotRageIncrase(hPrimary);
	if (!flRageOnHeadshot) {
		return;
	}
	
	float flRageMeter = GetEntPropFloat(attacker, Prop_Send, "m_flRageMeter");
	flRageMeter += flRageOnHeadshot;
	
	if (flRageMeter > 100.0) {
		flRageMeter = 100.0;
	}
	SetEntPropFloat(attacker, Prop_Send, "m_flRageMeter", flRageMeter);
}

float GetHeadshotRageIncrase(int weapon) {
	// custom varstring has keys `amount` and `add_while_draining`
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "rage on headshot", attr, sizeof(attr))) {
		return 0.0;
	}
	
	bool bAddWhileDraining = !!ReadIntVar(attr, "add_while_draining", 0);
	if (!bAddWhileDraining) {
		int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
		if (!IsValidEntity(owner) || GetEntProp(owner, Prop_Send, "m_bRageDraining")) {
			return 0.0;
		}
	}
	
	return ReadFloatVar(attr, "amount");
}
