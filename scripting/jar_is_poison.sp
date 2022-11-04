#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#include <stocksoup/sdkports/util>
// #include <stocksoup/entity_prefabs>
// #include <stocksoup/entity_tools>
// #include <stocksoup/tf/econ>
// #include <stocksoup/tf/tempents_stocks>

#include <dhooks>
#include <tf2_stocks>
#include <tf_custom_attributes>

#pragma newdecls required

#include <stocksoup/var_strings>

// #include <tf2wearables>

int g_iPoisonDmgRemaining[MAXPLAYERS + 1];
float g_flNextPoisonTime[MAXPLAYERS + 1];
float g_flConditionEnd[MAXPLAYERS + 1];

int g_iPoisonAttackerSerial[MAXPLAYERS + 1];
int g_iPoisonDmgPerTick[MAXPLAYERS + 1];
float g_flPoisonDmgInterval[MAXPLAYERS + 1];

// visual effect of jar
int g_iConditionFx[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtJarExplode = DHookCreateFromConf(hGameConf, "JarExplode()");
	DHookEnableDetour(dtJarExplode, false, OnJarExplodePre);
	DHookEnableDetour(dtJarExplode, true, OnJarExplodePost);
	
	delete hGameConf;
	
	HookUserMessage(GetUserMessageId("PlayerJarated"), OnPlayerJarated);
	
	RegAdminCmd("sm_poisonjar", ApplySelfEffect, ADMFLAG_ROOT);
}

public void OnPluginEnd() {
	for (int i = 1; i < MaxClients; i++) {
		if (IsValidEntity(g_iConditionFx[i])) {
			RemoveEntity(g_iConditionFx[i]);
		}
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
	g_flConditionEnd[client] = 0.0;
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

static int s_iJarWeapon;

MRESReturn OnJarExplodePre(Handle hParams) {
	s_iJarWeapon = INVALID_ENT_REFERENCE;
	
	int originalLauncher = DHookGetParam(hParams, 3);
	
	char buffer[4];
	if (!TF2CustAttr_GetString(originalLauncher, "jar is poison", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	s_iJarWeapon = EntIndexToEntRef(originalLauncher);
	// s_JarCondition = view_as<TFCond>(DHookGetParam(hParams, 8));
	// s_flJarDuration = DHookGetParam(hParams, 9);
	
	// zero out duration so we don't have to remove the condition ourselves
	DHookSetParam(hParams, 9, 0.0);
	
	return MRES_ChangedHandled;
}

MRESReturn OnJarExplodePost(Handle hParams) {
	s_iJarWeapon = INVALID_ENT_REFERENCE;
	return MRES_Ignored;
}

// this handles mad milk
Action OnPlayerJarated(UserMsg msg_id, BfRead msg, const int[] players, int playersNum,
		bool reliable, bool init) {
	if (!IsValidEntity(s_iJarWeapon)) {
		return Plugin_Continue;
	}
	
	int client = msg.ReadByte();
	int victim = msg.ReadByte();
	
	// this *crashes* on jarate
	// TF2_RemoveCondition(victim, s_JarCondition);
	
	char buffer[64];
	if (!TF2CustAttr_GetString(s_iJarWeapon, "jar is poison", buffer, sizeof(buffer))) {
		return Plugin_Continue;
	}
	
	int posionDamage = ReadIntVar(buffer, "dmg_per_tick");
	float flInterval = ReadFloatVar(buffer, "interval");
	float flDuration = ReadFloatVar(buffer, "duration");
	
	ApplyPoisonEffect(victim, posionDamage, flInterval, flDuration, client);
	
	return Plugin_Continue;
	#pragma unused client
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
	
	if (IsValidEntity(g_iConditionFx[client])) {
		RemoveEntity(g_iConditionFx[client]);
	}
	g_iConditionFx[client] = INVALID_ENT_REFERENCE;
}

Action ApplySelfEffect(int client, int argc) {
	ApplyPoisonEffect(client, 3, 0.5, 10.0);
	return Plugin_Handled;
}

void ApplyPoisonEffect(int client, int damagePerTick, float damageTickInterval, float duration,
		int attacker = 0) {
	if (IsValidEntity(g_iConditionFx[client])) {
		RemoveEntity(g_iConditionFx[client]);
	}
	
	/*int effect = TF2_SpawnWearable();
	
	char model[PLATFORM_MAX_PATH];
	GetEntityModelPath(client, model, sizeof(model));
	SetEntityModel(effect, model);
	
	TF2_EquipPlayerWearable(client, effect);
	
	g_iConditionFx[client] = EntIndexToEntRef(effect);
	
	TE_SetupTFParticleEffect("peejar_drips_milk", NULL_VECTOR, .entity = effect);
	TE_SendToAll();*/
	
	g_flConditionEnd[client] = GetGameTime() + duration;
	
	g_flNextPoisonTime[client] = GetGameTime();
	g_iPoisonDmgRemaining[client] = RoundToFloor(duration / damageTickInterval) * damagePerTick;
	
	g_iPoisonAttackerSerial[client] = attacker > 0 && attacker <= MaxClients?
			GetClientSerial(attacker) : 0;
	g_iPoisonDmgPerTick[client] = damagePerTick;
	g_flPoisonDmgInterval[client] = damageTickInterval;
}
