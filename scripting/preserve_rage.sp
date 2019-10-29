#pragma semicolon 1
#include <sourcemod>

#include <sdktools>

#pragma newdecls required

#include <tf_custom_attributes>

float g_flRageAmount[MAXPLAYERS + 1];

public void OnPluginStart() {
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_changeclass", OnPlayerChangeClass);
}

public void OnPlayerChangeClass(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	g_flRageAmount[client] = 0.0;
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	// no rage kept if it was being drained
	g_flRageAmount[client] = GetEntProp(client, Prop_Send, "m_bRageDraining")?
			0.0 : GetEntPropFloat(client, Prop_Send, "m_flRageMeter");
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	
	// TODO handle attribute here
	// TODO do we need to also handle it during post_inventory_application?
	for (int i; i < 3; i++) {
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		float flRageLimit = TF2CustAttr_GetFloat(weapon, "preserve rage", 0.0);
		if (flRageLimit > 0.0 && g_flRageAmount[client] > flRageLimit) {
			g_flRageAmount[client] = flRageLimit;
		}
	}
	
	SetEntPropFloat(client, Prop_Send, "m_flRageMeter", g_flRageAmount[client]);
}
