#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <tf2_stocks>
#include <sdkhooks>

#pragma newdecls required

#include <stocksoup/tf/weapon>
#include <tf_custom_attributes>

Handle g_DHookItemPostFrame;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookItemPostFrame = DHookCreateFromConf(hGameConf, "CBaseCombatWeapon::ItemPostFrame()");
	
	delete hGameConf;
}

public void OnMapStart() {
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_weapon_sniperrifle")) != -1) {
		HookSniperRifle(entity);
	}
}

public void OnEntityCreated(int entity, const char[] className) {
	if (!StrEqual(className, "tf_weapon_sniperrifle")) {
		return;
	}
	HookSniperRifle(entity);
}

void HookSniperRifle(int weapon) {
	DHookEntity(g_DHookItemPostFrame, true, weapon, .callback = OnSniperPrimaryAttackPost);
}

public MRESReturn OnSniperPrimaryAttackPost(int entity) {
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients || !TF2_IsPlayerInCondition(owner, TFCond_Slowed)) {
		return MRES_Ignored;
	}
	
	// don't stay zoomed if we're out of ammo, otherwise sniper will switch weapon
	// and jump will be disabled
	if (TF2_GetWeaponAmmo(entity) && TF2CustAttr_GetInt(entity, "sniper rifle zoomed reload")) {
		SetEntPropFloat(entity, Prop_Data, "m_flUnzoomTime", -1.0);
		SetEntProp(entity, Prop_Data, "m_bRezoomAfterShot", false);
	}
	return MRES_Ignored;
}
