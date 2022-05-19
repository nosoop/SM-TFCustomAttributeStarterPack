/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prefabs>
#include <stocksoup/tf/teams>

// associated with attackers
int g_iGlowEnt[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_flTagEndTime[MAXPLAYERS + 1];

public void OnPluginStart() {
	HookEvent("post_inventory_application", OnInventoryAppliedPost);
	HookEvent("player_death", OnInventoryAppliedPost);
}

public void OnPluginEnd() {
	for (int i; i < sizeof(g_iGlowEnt); i++) {
		if (IsValidEntity(g_iGlowEnt[i])) {
			RemoveEntity(g_iGlowEnt[i]);
		}
	}
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientDisconnect(int client) {
	if (IsValidEntity(g_iGlowEnt[client])) {
		RemoveEntity(g_iGlowEnt[client]);
	}
}

public void OnGameFrame() {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		OnClientPostThinkPost(i);
	}
}

void OnInventoryAppliedPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	for (int i = MaxClients; i --> 1;) {
		if (IsValidEntity(g_iGlowEnt[i])
				&& GetEntPropEnt(g_iGlowEnt[i], Prop_Data, "m_hParent") == client) {
			RemoveEntity(g_iGlowEnt[i]);
		}
	}
}

void OnClientPostThinkPost(int client) {
	if (!IsValidEntity(g_iGlowEnt[client])) {
		return;
	}
	
	int glowTarget = GetEntPropEnt(g_iGlowEnt[client], Prop_Data, "m_hParent");
	if (g_flTagEndTime[client] > GetGameTime()
			&& GlowValidOnAttacker(client) && GlowValidOnVictim(glowTarget)) {
		return;
	}
	
	RemoveEntity(g_iGlowEnt[client]);
	g_iGlowEnt[client] = INVALID_ENT_REFERENCE;
}

// invalidate if owner isn't carrying the weapon
bool GlowValidOnAttacker(int client) {
	if (!IsPlayerAlive(client)) {
		return false;
	}
	
	// client has at least one weapon with the attribute
	for (int i; i < 3; i++) {
		int loadoutItem = TF2Util_GetPlayerLoadoutEntity(client, i);
		if (IsValidEntity(loadoutItem)
				&& TF2CustAttr_GetFloat(loadoutItem, "tag last enemy hit") > 0.0) {
			return true;
		}
	}
	return false;
}

bool GlowValidOnVictim(int client) {
	return IsPlayerAlive(client);
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (!IsValidEntity(weapon) || victim == attacker) {
		return;
	}
	
	float flDuration = TF2CustAttr_GetFloat(weapon, "tag last enemy hit");
	if (!flDuration) {
		return;
	}
	
	if (IsValidEntity(g_iGlowEnt[attacker])) {
		RemoveEntity(g_iGlowEnt[attacker]);
	}
	g_iGlowEnt[attacker] = EntIndexToEntRef(TF2_AttachBasicGlow(victim));
	g_flTagEndTime[attacker] = GetGameTime() + flDuration;
	
	SDKHook(g_iGlowEnt[attacker], SDKHook_SetTransmit, OnGlowShouldTransmit);
}

Action OnGlowShouldTransmit(int glow, int client) {
	int glowTarget = GetEntPropEnt(glow, Prop_Data, "m_hParent");
	if (!IsValidEntity(glowTarget)) {
		return Plugin_Stop;
	}
	
	if (TF2_IsPlayerInCondition(glowTarget, TFCond_Cloaked)
			|| TF2_IsPlayerInCondition(glowTarget, TFCond_Disguised)) {
		return Plugin_Stop;
	}
	
	if (!TF2_IsEnemyTeam(TF2_GetClientTeam(glowTarget), TF2_GetClientTeam(client))) {
		// prevent showing outline on teammates
		// TODO make this more robust for teamcounts larger than 2 --
		// we'd need to track the attacker
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}
