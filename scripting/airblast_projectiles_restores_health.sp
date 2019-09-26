#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/player>

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
	if (StrEqual(className, "tf_weapon_flamethrower")
			|| StrEqual(className, "tf_weapon_rocketlauncher_fireball")) {
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
	
	int healAmount = TF2CustAttr_GetInt(flamethrower, "airblast projectiles restores health");
	
	// TODO use CTFPlayer::TakeHealth()
	TF2_HealPlayer(owner, healAmount, .notify = true);
}
