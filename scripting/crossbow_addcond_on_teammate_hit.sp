/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdktools>

#pragma newdecls required

#include <tf2utils>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

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

bool ReadTFCondVar(const char[] varstring, const char[] key, TFCond &value) {
	char condString[32];
	if (!ReadStringVar(varstring, key, condString, sizeof(condString))) {
		return false;
	}
	
	int result;
	if (StringToIntEx(condString, result)) {
		value = view_as<TFCond>(result);
		return true;
	}
	
	static StringMap s_Conditions;
	if (!s_Conditions) {
		char buffer[64];
		
		s_Conditions = new StringMap();
		for (TFCond cond; cond <= TF2Util_GetLastCondition(); cond++) {
			if (TF2Util_GetConditionName(cond, buffer, sizeof(buffer))) {
				s_Conditions.SetValue(buffer, cond);
			}
		}
	}
	
	if (s_Conditions.GetValue(condString, value)) {
		return true;
	}
	
	// log message if given string does not resolve to a condition
	static StringMap s_LoggedConditions;
	if (!s_LoggedConditions) {
		s_LoggedConditions = new StringMap();
	}
	any ignored;
	if (!s_LoggedConditions.GetValue(condString, ignored)) {
		LogError("Could not translate condition name %s to index.", condString);
		s_LoggedConditions.SetValue(condString, true);
	}
	return false;
}
