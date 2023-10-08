/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/memory>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>
#include <dhooks_gameconf_shim>

int g_nDamageStack[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	DynamicDetour dtGameRulesRadiusDamage = DynamicDetour.FromConf(hGameConf,
			"CTFGameRules::RadiusDamage()");
	if (!dtGameRulesRadiusDamage) {
		SetFailState("Failed to create detour " ... "CTFGameRules::RadiusDamage()");
	}
	dtGameRulesRadiusDamage.Enable(Hook_Pre, OnRadiusDamagePre);
	dtGameRulesRadiusDamage.Enable(Hook_Post, OnRadiusDamagePost);
	
	ClearDHooksDefinitions();
	delete hGameConf;
}

MRESReturn OnRadiusDamagePre(Address pGameRules, DHookParam hParams) {
	Address pDamageInfo = hParams.GetObjectVar(1, 0, ObjectValueType_Int);
	
	int weapon = LoadEntityHandleFromAddress(pDamageInfo + view_as<Address>(44));
	if (!IsValidEntity(weapon)) {
		return MRES_Ignored;
	}
	
	int owner = EntRefToEntIndex(LoadEntityHandleFromAddress(pDamageInfo + view_as<Address>(40)));
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "stack grenade damage custom", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	// grenade with custom damage stacking on direct hits
	float flDamageBonus = ReadFloatVar(attr, "add_dmg");
	float scale = 1.0 + (g_nDamageStack[owner] * flDamageBonus);
	
	float damage = LoadFromAddress(pDamageInfo + view_as<Address>(48), NumberType_Int32);
	StoreToAddress(pDamageInfo + view_as<Address>(48), damage * scale, NumberType_Int32);
	
	return MRES_Ignored;
}

MRESReturn OnRadiusDamagePost(Address pGameRules, DHookParam hParams) {
	Address pDamageInfo = hParams.GetObjectVar(1, 0, ObjectValueType_Int);
	
	int weapon = LoadEntityHandleFromAddress(pDamageInfo + view_as<Address>(44));
	if (!IsValidEntity(weapon)) {
		return MRES_Ignored;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "stack grenade damage custom", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	int inflictor = LoadEntityHandleFromAddress(pDamageInfo + view_as<Address>(36));
	if (!IsValidEntity(inflictor)) {
		// ???
		return MRES_Ignored;
	}
	
	int attacker = EntRefToEntIndex(LoadEntityHandleFromAddress(pDamageInfo + view_as<Address>(40)));
	if (attacker < 1 || attacker > MaxClients) {
		return MRES_Ignored;
	}
	
	int iDamagedOtherPlayers = LoadFromAddress(pDamageInfo + view_as<Address>(76), NumberType_Int32);
	
	// inflictor is implied to be a grenade since we assume the attribute is applied on a grenade launcher
	bool bDirectHit = GetEntProp(inflictor, Prop_Send, "m_bTouched") == 0;
	
	/**
	 * Update stack based on how many players we hit.  If no enemies were damaged (including
	 * invuln'd targets), the counter is reset.  The counter is only incremented if players
	 * were injured on a direct hit.
	 */
	int maxStack = ReadIntVar(attr, "max_stack", 10);
	if (iDamagedOtherPlayers == 0) {
		g_nDamageStack[attacker] = 0;
	} else if (bDirectHit) {
		if (++g_nDamageStack[attacker] > maxStack) {
			g_nDamageStack[attacker] = maxStack;
		}
	}
	
	return MRES_Ignored;
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
