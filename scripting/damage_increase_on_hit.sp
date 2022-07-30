#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <tf_econ_data>
#include <stocksoup/var_strings>
#include <stocksoup/tf/econ>
#include <stocksoup/tf/entity_prop_stocks>

#include <custom_status_hud>

#define NUM_ATTR_SLOTS 3

float g_flBonusDamageDecayStartTime[MAXPLAYERS + 1][NUM_ATTR_SLOTS];
float g_flBonusDamage[MAXPLAYERS + 1][NUM_ATTR_SLOTS];

public void OnPluginStart() {
	HookEvent("player_spawn", OnPlayerSpawn);
	// TODO should we hook post_inventory_application and reset bonus damage there too?
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	
	for (int i; i < sizeof(g_flBonusDamageDecayStartTime[]); i++) {
		g_flBonusDamageDecayStartTime[client][i] = 0.0;
		g_flBonusDamage[client][i] = 0.0;
	}
}

Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage,
		int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if (attacker > MaxClients || attacker < 1 || !IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	int slot = GetWeaponLoadoutSlot(weapon);
	if (slot < 0 || slot > sizeof(g_flBonusDamage[])) {
		return Plugin_Continue;
	}
	
	// validate bonus damage attribute on weapon
	// slight perf hit since we need to check the attrib twice for paired call correctness
	char buffer[4];
	if (!TF2CustAttr_GetString(weapon, "damage increase mult on hit", buffer, sizeof(buffer))) {
		return Plugin_Continue;
	}
	
	float flBonusDamage = g_flBonusDamage[attacker][slot];
	if (!flBonusDamage) {
		return Plugin_Continue;
	}
	damage *= 1.0 + flBonusDamage;
	return Plugin_Changed;
}

void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (attacker > MaxClients || attacker < 1 || !IsValidEntity(weapon)) {
		return;
	}
	
	int slot = GetWeaponLoadoutSlot(weapon);
	if (slot < 0 || slot > sizeof(g_flBonusDamage[])) {
		return;
	}
	
	char buffer[256];
	if (!TF2CustAttr_GetString(weapon, "damage increase mult on hit", buffer, sizeof(buffer))) {
		return;
	}
	
	float flDamageChange = ReadFloatVar(buffer, "amount", 0.0);
	float flDamageBonusMax = ReadFloatVar(buffer, "max", 0.0);
	float flDecayStartTime = ReadFloatVar(buffer, "decay_start", 0.0);
	bool bResetOnKill = !!ReadIntVar(buffer, "reset_on_kill", false);
	bool bIgnoreSelfDamage = ReadIntVar(buffer, "ignore_self_dmg", false) != 0;
	
	if (bIgnoreSelfDamage && attacker == victim) {
		return;
	}
	
	if (!flDamageChange) {
		return;
	}
	
	if (bResetOnKill && GetClientHealth(victim) <= 0) {
		g_flBonusDamage[attacker][slot] = 0.0;
		return;
	}
	
	if (flDecayStartTime > 0.0) {
		g_flBonusDamageDecayStartTime[attacker][slot] = GetGameTime() + flDecayStartTime;
	}
	
	g_flBonusDamage[attacker][slot] += flDamageChange;
	if (g_flBonusDamage[attacker][slot] > flDamageBonusMax) {
		g_flBonusDamage[attacker][slot] = flDamageBonusMax;
	}
	
	return;
}

void OnClientPostThinkPost(int client) {
	for (int i; i < sizeof(g_flBonusDamage[]); i++) {
		if (!g_flBonusDamage[client][i]) {
			continue;
		}
		
		float flDecayStartTime = g_flBonusDamageDecayStartTime[client][i];
		if (!flDecayStartTime || flDecayStartTime > GetGameTime()) {
			continue;
		}
		
		int weapon = TF2Util_GetPlayerLoadoutEntity(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		char buffer[256];
		if (!TF2CustAttr_GetString(weapon, "damage increase mult on hit", buffer, sizeof(buffer))) {
			g_flBonusDamageDecayStartTime[client][i] = 0.0;
			g_flBonusDamage[client][i] = 0.0;
			continue;
		}
		
		float flDecayPerSecond = ReadFloatVar(buffer, "decay_per_second", 0.0);
		g_flBonusDamage[client][i] -= GetGameFrameTime() * flDecayPerSecond;
		if (g_flBonusDamage[client][i] < 0.0) {
			g_flBonusDamage[client][i] = 0.0;
		}
	}
}

int GetWeaponLoadoutSlot(int weapon) {
	int client = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(client)) {
		return -1;
	}
	
	return TF2Econ_GetItemSlot(TF2_GetItemDefinitionIndexSafe(weapon),
			TF2_GetPlayerClass(client));
}

float GetBonusDamage(int weapon) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return 0.0;
	}
	
	int slot = GetWeaponLoadoutSlot(weapon);
	if (slot < 0 || slot > sizeof(g_flBonusDamage[])) {
		return 0.0;
	}
	
	return g_flBonusDamage[owner][slot];
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	int activeWeapon = TF2_GetClientActiveWeapon(client);
	if (!IsValidEntity(activeWeapon)) {
		return Plugin_Continue;
	}
	
	char attrBuffer[256];
	if (!TF2CustAttr_GetString(activeWeapon, "damage increase mult on hit",
			attrBuffer, sizeof(attrBuffer)) || !ReadIntVar(attrBuffer, "show_on_hud", true)) {
		return Plugin_Continue;
	}
	
	char buffer[64];
	Format(buffer, sizeof(buffer), "Damage: %.0f%%", GetBonusDamage(activeWeapon) * 100);
	entries.SetString("damage_on_hit_buff", buffer);
	return Plugin_Changed;
}
