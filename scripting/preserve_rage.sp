#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

#include <tf_custom_attributes>

float g_flRageAmount[MAXPLAYERS + 1];

public void OnPluginStart() {
	// HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_changeclass", OnPlayerChangeClass);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_SpawnPost, OnPlayerSpawnPost);
}

void OnPlayerChangeClass(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	g_flRageAmount[client] = 0.0;
}

void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	// no rage kept if it was being drained
	g_flRageAmount[client] = GetEntProp(client, Prop_Send, "m_bRageDraining")?
			0.0 : GetEntPropFloat(client, Prop_Send, "m_flRageMeter");
}

void OnPlayerSpawnPost(int client) {
	// TODO handle attribute here
	// TODO do we need to also handle it during post_inventory_application?
	bool process;
	for (int i; i < 3; i++) {
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		char preserveAttr[24];
		if (!TF2CustAttr_GetString(weapon, "preserve rage", preserveAttr,
				sizeof(preserveAttr))) {
			continue;
		}
		
		process = true;
		float flRageLimit = StringToFloat(preserveAttr);
		if (flRageLimit > 0.0 && g_flRageAmount[client] > flRageLimit) {
			g_flRageAmount[client] = flRageLimit;
		}
	}
	
	if (process) {
		SetEntPropFloat(client, Prop_Send, "m_flRageMeter", g_flRageAmount[client]);
	}
}
