/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdktools>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

#include "shared/tf_var_strings.sp"

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtHealingBoltImpactTeamPlayer = DHookCreateFromConf(hGameConf,
			"CTFProjectile_HealingBolt::ImpactTeamPlayer()");
	DHookEnableDetour(dtHealingBoltImpactTeamPlayer, false, OnHealingBoltImpactTeamPlayer);
	
	delete hGameConf;
}

public MRESReturn OnHealingBoltImpactTeamPlayer(int healingBolt, Handle hParams) {
	int originalLauncher = GetEntPropEnt(healingBolt, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(originalLauncher)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(originalLauncher, "crossbow addcond on teammate hit",
			attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	RemoveEntity(healingBolt);
	
	// past this point we always supercede;
	// the attribute being present overrides any other behavior
	
	int owner = TF2_GetEntityOwner(originalLauncher);
	if (!IsValidEntity(owner)) {
		return MRES_Supercede;
	}
	
	TFCond condition;
	if (!ReadTFCondVar(attr, "condition", condition)) {
		return MRES_Supercede;
	}
	
	float flChargeRequired = ReadFloatVar(attr, "charge_required");
	float flChargeLevel = GetMedigunChargeLevel(owner);
	if (flChargeRequired > flChargeLevel) {
		return MRES_Supercede;
	}
	
	SetMedigunChargeLevel(owner, flChargeLevel - flChargeRequired);
	
	float duration = ReadFloatVar(attr, "duration");
	
	int target = DHookGetParam(hParams, 1);
	TF2_AddCondition(target, condition, duration, owner);
	
	EmitGameSoundToAll("Medigun.DrainCharge", .entity = owner);
	EmitGameSoundToAll("Halloween.spell_overheal", .entity = target);
	
	return MRES_Supercede;
}

float GetMedigunChargeLevel(int client) {
	int secondaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if (!IsValidEntity(secondaryWeapon)
			|| !HasEntProp(secondaryWeapon, Prop_Send, "m_flChargeLevel")) {
		return 0.0;
	}
	
	return GetEntPropFloat(secondaryWeapon, Prop_Send, "m_flChargeLevel");
}

void SetMedigunChargeLevel(int client, float flChargeLevel) {
	int secondaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if (!IsValidEntity(secondaryWeapon)
			|| !HasEntProp(secondaryWeapon, Prop_Send, "m_flChargeLevel")) {
		return;
	}
	SetEntPropFloat(secondaryWeapon, Prop_Send, "m_flChargeLevel", flChargeLevel);
}
