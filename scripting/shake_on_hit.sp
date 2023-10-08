/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <smlib/clients>

#include <tf2utils>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <dhooks_gameconf_shim>

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	DynamicDetour dtOnMeleeDoDamage = GetDHooksDetourDefinition(hGameConf,
			"CTFWeaponBaseMelee::DoMeleeDamage()");
	if (!dtOnMeleeDoDamage) {
		SetFailState("Failed to create detour " ... "CTFWeaponBaseMelee::DoMeleeDamage()");
	}
	dtOnMeleeDoDamage.Enable(Hook_Post, OnMeleeDoDamagePost);
	
	ClearDHooksDefinitions();
	delete hGameConf;
}

MRESReturn OnMeleeDoDamagePost(int weapon, Handle hParams) {
	int target = DHookGetParam(hParams, 1);
	int attacker = TF2_GetEntityOwner(weapon);
	
	if (attacker < 1 || attacker > MaxClients) {
		return MRES_Ignored;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(weapon, "shake on hit", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	float amplitude = ReadFloatVar(attr, "amplitude", 20.0);
	float frequency = ReadFloatVar(attr, "frequency", 10.0);
	float duration = ReadFloatVar(attr, "duration", 1.0);
	
	Client_Shake(attacker, .amplitude = amplitude, .frequency = frequency,
			.duration = duration);
	if (target > 0 && target <= MaxClients) {
		Client_Shake(target, .amplitude = amplitude, .frequency = frequency,
				.duration = duration);
	}
	
	return MRES_Ignored;
}
