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

void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int sapperobj = event.GetInt("sapperid");
	SDKHook(sapperobj, SDKHook_OnTakeDamage, OnSapperTakeDamage);
}

Action OnSapperTakeDamage(int victim, int& attacker, int& inflictor, float& damage,
		int& damagetype, int& weapon, float damageForce[3], float damagePosition[3],
		int damagecustom) {
	float flSapperDamage = TF2CustAttr_GetFloat(weapon, "mult damage vs sappers", 1.0);
	
	if (flSapperDamage != 1.0) {
		damage *= flSapperDamage;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
