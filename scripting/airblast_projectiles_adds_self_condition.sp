#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>
#include <tf2utils>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>

#include "shared/tf_var_strings.sp"

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
