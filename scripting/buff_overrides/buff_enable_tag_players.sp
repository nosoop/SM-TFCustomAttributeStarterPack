#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <sdkhooks>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prefabs>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>
#include <tf_cattr_buff_override>

int g_iGlowEnt[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_flTagEndTime[MAXPLAYERS + 1];

float g_flGlowOnHitEndTime[MAXPLAYERS + 1];
float g_flGlowOnHitDuration[MAXPLAYERS + 1];

public void OnPluginStart() {
	HookEvent("post_inventory_application", OnInventoryAppliedPost);
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
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

public void OnCustomBuffHandlerAvailable() {
	TF2CustomAttrRageBuff_Register("tag enemies on hit", OnCritBannerPulse);
}

void OnCritBannerPulse(int owner, int target, const char[] name, int buffItem) {
	TFTeam buffTeam = TF2_GetClientTeam(owner);
	
	// disallow enemies, allow disguised players, disallow cloaked
	if (TF2_GetClientTeamFromClient(target, owner) != buffTeam
			|| TF2_IsPlayerInCondition(target, TFCond_Cloaked)
			|| TF2_IsPlayerInCondition(target, TFCond_Stealthed)) {
		return;
	}
	
	char attr[64];
	TF2CustAttr_GetString(buffItem, "buff tag enemies on hit", attr, sizeof(attr));
	
	g_flGlowOnHitDuration[target] = ReadFloatVar(attr, "duration", 5.0);
	
	g_flGlowOnHitEndTime[target] = GetGameTime() + BUFF_PULSE_CONDITION_DURATION;
	
	TF2_AddCondition(target, TFCond_SpeedBuffAlly, BUFF_PULSE_CONDITION_DURATION, owner);
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-buff-override")) {
		OnCustomBuffHandlerAvailable();
	}
}

public void OnClientPutInServer(int client) {
	g_flTagEndTime[client] = 0.0;
	g_flGlowOnHitEndTime[client] = 0.0;
	g_flGlowOnHitDuration[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientDisconnect(int client) {
	if (IsValidEntity(g_iGlowEnt[client])) {
		RemoveEntity(g_iGlowEnt[client]);
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
	if (g_flTagEndTime[client] > GetGameTime() && GlowValidOnVictim(glowTarget)) {
		return;
	}
	
	RemoveEntity(g_iGlowEnt[client]);
	g_iGlowEnt[client] = INVALID_ENT_REFERENCE;
}

bool GlowValidOnVictim(int client) {
	return IsPlayerAlive(client);
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (victim == attacker || attacker < 1 || attacker > MaxClients
			|| GetGameTime() > g_flGlowOnHitEndTime[attacker]) {
		return;
	}
	
	if (IsValidEntity(g_iGlowEnt[victim])) {
		RemoveEntity(g_iGlowEnt[victim]);
	}
	g_iGlowEnt[victim] = EntIndexToEntRef(TF2_AttachBasicGlow(victim));
	g_flTagEndTime[victim] = GetGameTime() + g_flGlowOnHitDuration[attacker];
	
	SDKHook(g_iGlowEnt[victim], SDKHook_SetTransmit, OnGlowShouldTransmit);
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
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}
