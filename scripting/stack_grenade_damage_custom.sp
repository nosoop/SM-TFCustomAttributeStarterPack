/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

Handle g_DHookGrenadeExplode;
int g_nDamageStack[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookGrenadeExplode = DHookCreateFromConf(hGameConf, "CBaseGrenade::Explode()");
	
	delete hGameConf;
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnEntityCreated(int entity, const char[] className) {
	if (IsValidEdict(entity) && HasEntProp(entity, Prop_Send, "m_bDefensiveBomb")) {
		HookGrenadeEntity(entity);
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

static void HookGrenadeEntity(int grenade) {
	DHookEntity(g_DHookGrenadeExplode, false, grenade, .callback = OnGrendeExplodePre);
	DHookEntity(g_DHookGrenadeExplode, true, grenade, .callback = OnGrendeExplodePost);
}

static int s_InflictingGrenade;
static bool s_bDirectHit;
static int s_nPlayersDamaged;

public MRESReturn OnGrendeExplodePre(int grenade, Handle hParams) {
	// reset counters
	s_bDirectHit = !GetEntProp(grenade, Prop_Send, "m_bTouched");
	s_nPlayersDamaged = 0;
	
	int weapon = GetEntPropEnt(grenade, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(weapon)) {
		return MRES_Ignored;
	}
	
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return MRES_Ignored;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "stack grenade damage custom", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	// grenade with custom damage stacking on direct hits
	float flDamageBonus = ReadFloatVar(attr, "add_dmg");
	float scale = 1.0 + (g_nDamageStack[owner] * flDamageBonus);
	
	s_InflictingGrenade = EntIndexToEntRef(grenade);
	
	float damage = GetEntPropFloat(grenade, Prop_Send, "m_flDamage");
	SetEntPropFloat(grenade, Prop_Send, "m_flDamage", damage * scale);
	
	return MRES_Ignored;
}

public void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (!IsValidEntity(inflictor) || !IsValidEntity(weapon) || victim == attacker) {
		return;
	}
	
	if (!IsValidEntity(s_InflictingGrenade)
			|| EntIndexToEntRef(inflictor) != s_InflictingGrenade) {
		return;
	}
	
	// players were hurt (shouldn't be ubered?)
	s_nPlayersDamaged++;
}

public MRESReturn OnGrendeExplodePost(int grenade, Handle hParams) {
	// there shouldn't be any nested grenade calls... right?
	s_InflictingGrenade = INVALID_ENT_REFERENCE;
	
	int weapon = GetEntPropEnt(grenade, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "stack grenade damage custom", attr, sizeof(attr))) {
		return;
	}
	
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return;
	}
	
	// update stack based on how many players we hit
	int maxStack = ReadIntVar(attr, "max_stack", 10);
	
	if (s_nPlayersDamaged == 0) {
		g_nDamageStack[owner] = 0;
	} else if (s_bDirectHit) {
		if (++g_nDamageStack[owner] > maxStack) {
			g_nDamageStack[owner] = maxStack;
		}
	}
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	int weapon = TF2_GetClientActiveWeapon(client);
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "stack grenade damage custom", attr, sizeof(attr))) {
		return Plugin_Continue;
	}
	
	float flDamageBonus = ReadFloatVar(attr, "add_dmg");
	float scale = g_nDamageStack[client] * flDamageBonus;
	
	char buffer[64];
	Format(buffer, sizeof(buffer), "Damage: +%d%", RoundFloat(scale * 100));
	entries.SetString("grenade_stack", buffer);
	
	return Plugin_Changed;
}
