/**
 * Custom Flare Modifiers
 * 
 * I'd like to put this stuff into Attribute Extended Support Fixes, but I don't want to have to
 * repurpose some other attribute classnames for this.  There isn't anything for self-blast
 * radius, and I guess I could use `blast_dmg_to_self` for the self flare damage multiplier.
 * 
 * Maybe I'll port this to use custom attribute classes in the future.
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>
#include <tf_custom_attributes>

#define FLARE_SELF_BLAST_RADIUS 100.0

Address g_pflFlareSelfDamageRadius;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_pflFlareSelfDamageRadius = GameConfGetAddress(hGameConf,
			"CTFProjectile_Flare::Explode_Air()::SelfDamageRadius");
	if (!g_pflFlareSelfDamageRadius) {
		LogError("Could not determine address for "
				... "CTFProjectile_Flare::Explode_Air()::SelfDamageRadius");
	} else if (view_as<float>(LoadFromAddress(g_pflFlareSelfDamageRadius, NumberType_Int32)) != FLARE_SELF_BLAST_RADIUS) {
		any rawValue = LoadFromAddress(g_pflFlareSelfDamageRadius, NumberType_Int32);
		LogError("Address for CTFProjectile_Flare::Explode_Air()::SelfDamageRadius "
				... "contains unexpected value %08x (%f)", rawValue, rawValue);
		g_pflFlareSelfDamageRadius = Address_Null;
	} else {
		// we have a valid pointer to *something*, we can go ahead and patch
		Handle dtFlareExplodeAir = DHookCreateFromConf(hGameConf,
				"CTFProjectile_Flare::Explode_Air()");
		if (!dtFlareExplodeAir) {
			SetFailState("Failed to create detour %s", "CTFProjectile_Flare::Explode_Air()");
		}
		DHookEnableDetour(dtFlareExplodeAir, false, OnProjectileFlareExplodeAir);
	}
	
	delete hGameConf;
}

public void OnPluginEnd() {
	if (g_pflFlareSelfDamageRadius) {
		StoreToAddress(g_pflFlareSelfDamageRadius, view_as<any>(FLARE_SELF_BLAST_RADIUS),
				NumberType_Int32);
	}
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage,
		int& damagetype, int& weapon, float damageForce[3], float damagePosition[3],
		int damagecustom) {
	if (damagecustom != TF_CUSTOM_FLARE_EXPLOSION) {
		return Plugin_Continue;
	}
	
	if (attacker != victim) {
		return Plugin_Continue;
	}
	damage *= TF2CustAttr_GetFloat(weapon, "mult self flare damage", 1.0);
	
	// can't modify damage forces...
	
	return Plugin_Changed;
}

/**
 * Inject a modified blast jump radius for flare-like projectiles right before the code runs.
 * This is confirmed working on the Detonator and Scorch Shot.
 */
MRESReturn OnProjectileFlareExplodeAir(int projectile, Handle hParams) {
	int launcher = GetEntPropEnt(projectile, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(launcher)) {
		return MRES_Ignored;
	}
	
	if (g_pflFlareSelfDamageRadius) {
		float flRadius = TF2CustAttr_GetFloat(launcher, "mult self flare radius", 1.0)
				* FLARE_SELF_BLAST_RADIUS;
		StoreToAddress(g_pflFlareSelfDamageRadius, view_as<any>(flRadius), NumberType_Int32);
	}
	return MRES_Ignored;
}
