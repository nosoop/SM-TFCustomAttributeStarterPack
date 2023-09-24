/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <dhooks>
#include <sdktools>

#pragma newdecls required

#include <tf2utils>
#include <tf_econ_data>
#include <tf_custom_attributes>
#include <stocksoup/tf/econ>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/sdkports/util>
#include <stocksoup/var_strings>
#include <dhooks_gameconf_shim>

float g_flPoisonBuffEndTime[MAXPLAYERS + 1];

int g_iPoisonDmgRemaining[MAXPLAYERS + 1];
float g_flNextPoisonTime[MAXPLAYERS + 1];
float g_flConditionEnd[MAXPLAYERS + 1];

int g_iPoisonAttackerSerial[MAXPLAYERS + 1];
int g_iPoisonDmgPerTick[MAXPLAYERS + 1];
float g_flPoisonDmgInterval[MAXPLAYERS + 1];

Handle g_DHookWeaponSecondaryAttack;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	g_DHookWeaponSecondaryAttack = 
			GetDHooksDefinition(hGameConf, "CBaseCombatWeapon::SecondaryAttack()");
	
	ClearDHooksDefinitions();
	delete hGameConf;
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "*")) != -1) {
		if (IsMedicWeapon(entity)) {
			OnMedicWeaponCreated(entity);
		}
	}
}

public void OnEntityCreated(int entity, const char[] name) {
	if (IsMedicWeapon(entity)) {
		OnMedicWeaponCreated(entity);
	}
}

public void OnGameFrame() {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		OnClientPostThinkPost(i);
	}
}

void OnMedicWeaponCreated(int weapon) {
	DHookEntity(g_DHookWeaponSecondaryAttack, true, weapon,
			.callback = OnWeaponSecondaryAttack);
}

public void OnClientPutInServer(int client) {
	g_iPoisonDmgRemaining[client] = 0;
	g_flPoisonBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

MRESReturn OnWeaponSecondaryAttack(int weapon) {
	char attr[256];
	if (!TF2CustAttr_GetString(weapon, "syringegun poison on hit", attr, sizeof(attr))) {
		return;
	}
	
	int client = TF2_GetEntityOwner(weapon);
	if (client < 1 || client > MaxClients || g_flPoisonBuffEndTime[client] > GetGameTime()) {
		return;
	}
	
	int secondary = GetPlayerWeaponSlot(client, 1);
	if (!IsValidEntity(secondary) || TF2Util_GetWeaponID(secondary) != TF_WEAPON_MEDIGUN) {
		return;
	}
	
	float minCharge = ReadFloatVar(attr, "min_charge");
	float charge = GetEntPropFloat(secondary, Prop_Send, "m_flChargeLevel");
	if (charge < minCharge) {
		return;
	}
	SetEntPropFloat(secondary, Prop_Send, "m_flChargeLevel", charge - minCharge);
	
	g_flPoisonBuffEndTime[client] = GetGameTime() + ReadFloatVar(attr, "buff_duration");
}

void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (attacker < 1 || attacker > MaxClients || !IsValidEntity(weapon)
			|| GetGameTime() > g_flPoisonBuffEndTime[attacker]) {
		return;
	}
	
	char attr[256];
	if (!TF2CustAttr_GetString(weapon, "syringegun poison on hit", attr, sizeof(attr))) {
		return;
	}
	
	float duration = ReadFloatVar(attr, "duration");
	int damagePerTick = ReadIntVar(attr, "dmg_per_tick");
	float tickInterval = ReadFloatVar(attr, "dmg_tick_interval");
	float maxDuration = ReadFloatVar(attr, "max_duration", 60.0);
	
	if (g_iPoisonDmgRemaining[victim] <= 0) {
		ApplyPoisonEffect(victim, damagePerTick, tickInterval, duration, attacker);
	} else {
		// compute and manually add more poison
		// TODO this should be merged into ApplyPoisonEffect (check for existing poison dmg)
		int addPoisonDamage = RoundToFloor(duration / tickInterval) * damagePerTick;
		int maxPoisonDamage = RoundToFloor(maxDuration / tickInterval) * damagePerTick;
		
		g_iPoisonDmgRemaining[victim] += addPoisonDamage;
		if (g_iPoisonDmgRemaining[victim] > maxPoisonDamage) {
			g_iPoisonDmgRemaining[victim] = maxPoisonDamage;
		}
	}
}

void OnClientPostThinkPost(int client) {
	if (g_iPoisonDmgRemaining[client] <= 0 || g_flNextPoisonTime[client] > GetGameTime()) {
		// no poison damage or next poison time isn't reached yet
		return;
	}
	
	int nPoisonDamage = g_iPoisonDmgPerTick[client];
	float damageInterval = g_flPoisonDmgInterval[client];
	int attacker = GetClientFromSerial(g_iPoisonAttackerSerial[client]);
	
	SDKHooks_TakeDamage(client, attacker, attacker, float(nPoisonDamage),
			DMG_SLASH | DMG_PREVENT_PHYSICS_FORCE);
	g_iPoisonDmgRemaining[client] -= nPoisonDamage;
	
	if (g_iPoisonDmgRemaining[client] > 0) {
		UTIL_ScreenFade(client, { 192, 32, 192, 64 }, 0.5, 0.5, FFADE_PURGE | FFADE_OUT);
		g_flNextPoisonTime[client] += damageInterval;
		return;
	}
	
	UTIL_ScreenFade(client, { 0, 0, 0, 0 }, 1.5, 1.5, FFADE_PURGE | FFADE_OUT);
	TF2Util_UpdatePlayerSpeed(client);
}

void ApplyPoisonEffect(int client, int damagePerTick, float damageTickInterval, float duration,
		int attacker = 0) {
	g_flConditionEnd[client] = GetGameTime() + duration;
	
	g_flNextPoisonTime[client] = GetGameTime() + damageTickInterval;
	g_iPoisonDmgRemaining[client] = RoundToFloor(duration / damageTickInterval) * damagePerTick;
	
	g_iPoisonAttackerSerial[client] = attacker > 0 && attacker <= MaxClients?
			GetClientSerial(attacker) : 0;
	g_iPoisonDmgPerTick[client] = damagePerTick;
	g_flPoisonDmgInterval[client] = damageTickInterval;
	
	EmitGameSoundToAll("Player.DrownStart", client);
	
	TF2Util_UpdatePlayerSpeed(client);
}

public Action TF2_OnCalculateMaxSpeed(int client, float &speed) {
	if (g_iPoisonDmgRemaining[client] > 0) {
		speed *= 0.85;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

bool IsMedicWeapon(int entity) {
	if (!TF2Util_IsEntityWeapon(entity)) {
		return false;
	}
	
	int weaponid = TF2Util_GetWeaponID(entity);
	return weaponid == TF_WEAPON_SYRINGEGUN_MEDIC || weaponid == TF_WEAPON_CROSSBOW;
}
