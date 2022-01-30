#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>
#include <tf2utils>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>

Handle g_DHookFlamethrowerDeflect;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookFlamethrowerDeflect = DHookCreateFromConf(hGameConf,
			"CTFWeaponBase::DeflectEntity()");
	
	delete hGameConf;
}

public void OnMapStart() {
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_weapon_flamethrower")) != -1) {
		HookFlamethrower(entity);
	}
	while ((entity = FindEntityByClassname(entity, "tf_weapon_rocketlauncher_fireball")) != -1) {
		HookFlamethrower(entity);
	}
}

public void OnEntityCreated(int entity, const char[] className) {
	if (!TF2Util_IsEntityWeapon(entity)) {
		return;
	}
	
	int weaponid = TF2Util_GetWeaponID(entity);
	if (weaponid == TF_WEAPON_FLAMETHROWER || weaponid == TF_WEAPON_FLAME_BALL) {
		HookFlamethrower(entity);
	}
}

void HookFlamethrower(int flamethrower) {
	DHookEntity(g_DHookFlamethrowerDeflect, true, flamethrower,
			.callback = OnFlamethrowerDeflectPost);
}

public MRESReturn OnFlamethrowerDeflectPost(int flamethrower, Handle hParams) {
	int target = DHookGetParam(hParams, 1);
	int owner = DHookGetParam(hParams, 2);
	
	// check for projectile
	if (!IsValidEntity(target)
			|| !HasEntProp(target, Prop_Send, "m_hLauncher")) {
		return;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(flamethrower, "airblast projectiles adds self condition",
			attr, sizeof(attr))) {
		return;
	}
	
	TFCond condition;
	if (!ReadTFCondVar(attr, "condition", condition)) {
		return;
	}
	
	float duration = ReadFloatVar(attr, "duration");
	
	TF2_AddCondition(owner, condition, duration);
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
