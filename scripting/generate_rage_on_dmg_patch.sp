/**
 * "generate rage on damage" patch
 * 
 * Optionally disables a bunch of side effects that "generate rage on damage" provides
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <sourcescramble>
#include <stocksoup/memory>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>

MemoryPatch g_PatchHandleRageGain;
MemoryPatch g_PatchDisableHeavyRageKnockback;
MemoryPatch g_PatchDisableHeavyRageDamagePenalty;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_PatchHandleRageGain = MemoryPatch.CreateFromConf(hGameConf,
			"HandleRageGain()::NoHeavyRageGain");
	if (!g_PatchHandleRageGain.Validate()) {
		SetFailState("Could not verify patch for HandleRageGain()::NoHeavyRageGain");
	}
	
	g_PatchDisableHeavyRageKnockback = MemoryPatch.CreateFromConf(hGameConf,
			"CTFPlayer::ApplyPushFromDamage()::NoHeavyKnockbackRage");
	if (!g_PatchDisableHeavyRageKnockback.Validate()) {
		SetFailState("Could not verify patch for "
				... "CTFPlayer::ApplyPushFromDamage()::NoHeavyKnockbackRage");
	}
	
	g_PatchDisableHeavyRageDamagePenalty = MemoryPatch.CreateFromConf(hGameConf,
			"CTFGameRules::ApplyOnDamageAliveModifyRules()::DisableHeavyRageDamagePenalty");
	if (!g_PatchDisableHeavyRageDamagePenalty.Validate()) {
		SetFailState("Could not verify patch for CTFGameRules::ApplyOnDamageAliveModifyRules()"
				... "::DisableHeavyRageDamagePenalty");
	}
	
	Handle dtApplyOnDamageAliveModifyRules = DHookCreateFromConf(hGameConf,
			"CTFGameRules::ApplyOnDamageAliveModifyRules()");
	DHookEnableDetour(dtApplyOnDamageAliveModifyRules, false, OnApplyOnDamageModifyRulesPre);
	
	Handle dtApplyPushFromDamage = DHookCreateFromConf(hGameConf,
			"CTFPlayer::ApplyPushFromDamage()");
	DHookEnableDetour(dtApplyPushFromDamage, false, OnApplyPushFromDamagePre);
	
	Handle dtHandleRageGain = DHookCreateFromConf(hGameConf, "HandleRageGain()");
	DHookEnableDetour(dtHandleRageGain, false, OnHandleRageGainPre);
	
	delete hGameConf;
	
}

public MRESReturn OnApplyOnDamageModifyRulesPre(Address pGameRules, Handle hReturn,
		Handle hParams) {
	g_PatchDisableHeavyRageDamagePenalty.Disable();
	
	Address pTakeDamageInfo = DHookGetParam(hParams, 1);
	int weapon = LoadEntityHandleFromAddress(pTakeDamageInfo + view_as<Address>(0x44));
	
	if (!HasGenerateRageOnDamage(weapon)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "generate rage on damage patch", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	if (ReadIntVar(attr, "disable_rage_damage_penalty")) {
		g_PatchDisableHeavyRageDamagePenalty.Enable();
	}
	return MRES_Ignored;
}

public MRESReturn OnApplyPushFromDamagePre(int client, Handle hParams) {
	g_PatchDisableHeavyRageKnockback.Disable();
	
	Address pTakeDamageInfo = DHookGetParam(hParams, 1);
	int weapon = LoadEntityHandleFromAddress(pTakeDamageInfo + view_as<Address>(0x44));
	
	if (!HasGenerateRageOnDamage(weapon)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "generate rage on damage patch", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	if (ReadIntVar(attr, "disable_knockback")) {
		g_PatchDisableHeavyRageKnockback.Enable();
	}
	return MRES_Ignored;
}

public MRESReturn OnHandleRageGainPre(Handle hParams) {
	g_PatchHandleRageGain.Disable();
	if (DHookIsNullParam(hParams, 1)) {
		return MRES_Ignored;
	}
	
	int client = DHookGetParam(hParams, 1);
	
	int activeWeapon = TF2_GetClientActiveWeapon(client);
	if (!HasGenerateRageOnDamage(activeWeapon)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(activeWeapon, "generate rage on damage patch",
			attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	if (ReadIntVar(attr, "disable_rage_on_damage")) {
		g_PatchHandleRageGain.Enable();
	}
	return MRES_Ignored;
}

bool HasGenerateRageOnDamage(int weapon) {
	// going to assume this is applied on runtime
	return IsValidEntity(weapon) && !!TF2Attrib_GetByName(weapon, "generate rage on damage");
}
