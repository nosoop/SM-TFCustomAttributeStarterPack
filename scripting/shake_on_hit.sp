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

Handle g_DHookMeleeOnEntityHit;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookMeleeOnEntityHit = DHookCreateFromConf(hGameConf,
			"CTFWeaponBaseMelee::OnEntityHit()");
	
	delete hGameConf;
	
}

public void OnMapStart() {
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "*")) != -1) {
		if (TF2Util_IsEntityWeapon(ent) && TF2Util_GetWeaponSlot(ent) == TFWeaponSlot_Melee) {
			OnMeleeWeaponCreated(ent);
		}
	}
	
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (TF2Util_IsEntityWeapon(entity)) {
		SDKHook(entity, SDKHook_SpawnPost, OnWeaponSpawnPost);
	}
}

void OnWeaponSpawnPost(int weapon) {
	if (TF2Util_GetWeaponSlot(weapon) == TFWeaponSlot_Melee) {
		OnMeleeWeaponCreated(weapon);
	}
}

void OnMeleeWeaponCreated(int weapon) {
	DHookEntity(g_DHookMeleeOnEntityHit, true, weapon, .callback = MeleeOnEntityHit);
}

MRESReturn MeleeOnEntityHit(int weapon, Handle hParams) {
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
