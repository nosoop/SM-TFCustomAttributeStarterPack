/**
 * code pretty much kept from https://forums.alliedmods.net/showthread.php?t=316648 with some
 * modification to support configuration and custom attributes
 */
#pragma semicolon 1
#include <sourcemod>

// we need a couple of important functions from these built-in extensions
#include <sdkhooks>
#include <sdktools>

#include <tf_custom_attributes>
#include <stocksoup/tf/player>
#include <stocksoup/var_strings>

#include <tf2utils>

/**
 * we need this to hook the projectile "touch" event
 * you may recall the other day that I mentioned `SDKHook`'s `Touch` event should be fine
 * 
 * that was a lie
 */
#include <dhooks>

// enforces new syntax (1.7 onward)
#pragma newdecls required

// declares a variable that is available across all functions
Handle g_DHookProjectileTouch;

public void OnPluginStart() {
	// declares a game configuration file (from `gamedata/`)
	// this is used for certain values that may change across game or game updates instead of
	// hardcoding the values in the plugin
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	// prepares a hook on a virtual function CTFBaseProjectile::ProjectileTouch()
	// the game calls this when a projectile is hitting something
	int offs = GameConfGetOffset(hGameConf, "CTFBaseProjectile::ProjectileTouch()");
	g_DHookProjectileTouch = DHookCreate(offs, HookType_Entity, ReturnType_Void,
			ThisPointer_CBaseEntity, OnProjectileTouch);
	DHookAddParam(g_DHookProjectileTouch, HookParamType_CBaseEntity);
	
	delete hGameConf;
}

/**
 * Called when an entity has been created.
 */
public void OnEntityCreated(int entity, const char[] className) {
	// you'll need to identify any other entity names if you want to add 
	if (StrEqual(className, "tf_projectile_syringe")) {
		// hooks the entity with the information given in OnPluginStart()
		// https://bitbucket.org/Peace_Maker/dhooks2/src/e7363b9d67935f70d1269b449e9fc6d5d6b43bd8/sourcemod/scripting/include/dhooks.inc?at=dynhooks
		DHookEntity(g_DHookProjectileTouch, false, entity);
	}
}

/**
 * Called when the syringe hits another entity.
 */
public MRESReturn OnProjectileTouch(int entity, Handle hParams) {
	// retrieves the entity from the parameter list
	int other = DHookGetParam(hParams, 1);
	
	// use default behavior when the entity hit isn't a player
	if (other < 1 || other > MaxClients) {
		return MRES_Ignored;
	}
	
	// use default behavior when the entity hit is on a different team
	int teamNum = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	if (teamNum != GetClientTeam(other)) {
		return MRES_Ignored;
	}
	
	int originalLauncher = GetEntPropEnt(entity, Prop_Send, "m_hOriginalLauncher");
	char buffer[64];
	if (!TF2CustAttr_GetString(originalLauncher, "mod syringes heal teammates",
			buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	float flHealAmount = ReadFloatVar(buffer, "amount", 0.0);
	
	if (flHealAmount == 0.0) {
		return MRES_Ignored;
	}
	
	float flOverhealMax = ReadFloatVar(buffer, "overheal_max", 0.0);
	float flMaxHealAmount = (TF2Util_GetPlayerMaxHealth(other) * (1.0 + flOverhealMax))
			- GetClientHealth(other);
	
	if (flMaxHealAmount <= 0) {
		flHealAmount = 0.0;
	} else if (flHealAmount > flMaxHealAmount) {
		flHealAmount = flMaxHealAmount;
	}
	
	/**
	 * do the heal, remove the syringe, and prevent the default behavior
	 * 
	 * note that if you were looking for better integration it'd be better to call
	 * CTFPlayer::TakeHealth() and adjust for heal modifiers (which is done inline for the
	 * crossbow bolt).
	 */
	TF2_HealPlayer(other, RoundFloat(flHealAmount), true, true);
	RemoveEntity(entity);
	return MRES_Supercede;
}
