/**
 * Modifies damage against sappers.
 * Note that this stacks on top of "mult_dmg_vs_buildings".
 * This also requires "damage applies to sappers" being set on the weapon.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>

public void OnPluginStart() {
	HookEvent("player_sapped_object", OnObjectSapped);
}

public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int sapperobj = event.GetInt("sapperid");
	SDKHook(sapperobj, SDKHook_OnTakeDamage, OnSapperTakeDamage);
}

public Action OnSapperTakeDamage(int victim, int& attacker, int& inflictor, float& damage,
		int& damagetype, int& weapon, float damageForce[3], float damagePosition[3],
		int damagecustom) {
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return Plugin_Continue;
	}
	
	int cost = TF2CustAttr_GetInt(weapon, "weapon unsap metal cost");
	int metal = GetMetalCount(owner);
	if (cost > metal) {
		return Plugin_Stop;
	} else if (cost) {
		SetMetalCount(owner, metal - cost);
	}
	return Plugin_Continue;
}

static int GetMetalCount(int client) {
	return GetEntProp(client, Prop_Send, "m_iAmmo", .element = 3);
}

static void SetMetalCount(int client, int metal) {
	SetEntProp(client, Prop_Send, "m_iAmmo", metal, .element = 3);
}
