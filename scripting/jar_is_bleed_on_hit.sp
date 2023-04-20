#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <stocksoup/entity_prefabs>
#include <stocksoup/entity_tools>
#include <stocksoup/tf/econ>
#include <stocksoup/tf/tempents_stocks>

#include <dhooks>
#include <tf2_stocks>
#include <tf_custom_attributes>
#include <tf2utils>

#include <dhooks_gameconf_shim>

#pragma newdecls required

float g_flConditionEnd[MAXPLAYERS + 1];
float g_flBleedEffectDuration[MAXPLAYERS + 1];
int g_iConditionFx[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	Handle dtJarExplode = GetDHooksDefinition(hGameConf, "JarExplode()");
	DHookEnableDetour(dtJarExplode, false, OnJarExplodePre);
	DHookEnableDetour(dtJarExplode, true, OnJarExplodePost);
	
	ClearDHooksDefinitions();
	delete hGameConf;
	
	HookUserMessage(GetUserMessageId("PlayerJarated"), OnPlayerJarated);
}

public void OnPluginEnd() {
	for (int i = 1; i < MaxClients; i++) {
		if (IsValidEntity(g_iConditionFx[i])) {
			RemoveEntity(g_iConditionFx[i]);
		}
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

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flConditionEnd[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
}

static int s_iTomatoWeapon;
static float s_flJarDuration;
MRESReturn OnJarExplodePre(Handle hParams) {
	s_iTomatoWeapon = INVALID_ENT_REFERENCE;
	
	int originalLauncher = DHookGetParam(hParams, 3);
	if (TF2CustAttr_GetFloat(originalLauncher, "jar is bleed on hit") == 0.0) {
		return MRES_Ignored;
	}
	
	s_iTomatoWeapon = EntIndexToEntRef(originalLauncher);
	s_flJarDuration = DHookGetParam(hParams, 9);
	
	// zero out duration so we don't have to remove the condition ourselves
	// (removing the condition for TF_COND_URINE starts a new usermessage)
	DHookSetParam(hParams, 9, 0.0);
	
	return MRES_ChangedHandled;
}

MRESReturn OnJarExplodePost(Handle hParams) {
	s_iTomatoWeapon = INVALID_ENT_REFERENCE;
	return MRES_Ignored;
}

// this handles mad milk
Action OnPlayerJarated(UserMsg msg_id, BfRead msg, const int[] players, int playersNum,
		bool reliable, bool init) {
	if (!IsValidEntity(s_iTomatoWeapon)) {
		return Plugin_Continue;
	}
	
	int client = msg.ReadByte();
	int victim = msg.ReadByte();
	
	ApplyEffect(victim, s_flJarDuration,
			TF2CustAttr_GetFloat(s_iTomatoWeapon, "jar is bleed on hit"));
	
	return Plugin_Continue;
	#pragma unused client
}

void OnClientPostThinkPost(int client) {
	if (!IsValidEntity(g_iConditionFx[client])) {
		return;
	}
	
	if (g_flConditionEnd[client] > GetGameTime()) {
		return;
	}
	
	RemoveEntity(g_iConditionFx[client]);
	g_iConditionFx[client] = INVALID_ENT_REFERENCE;
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3],
		int damagecustom) {
	if (GetGameTime() > g_flConditionEnd[victim]) {
		return;
	}
	
	g_flConditionEnd[victim] = 0.0;
	TF2_MakeBleed(victim, attacker, g_flBleedEffectDuration[victim]);
}

Action ApplySelfEffect(int client, int argc) {
	ApplyEffect(client, 5.0, 5.0);
	return Plugin_Handled;
}

void ApplyEffect(int client, float duration, float bleedDuration) {
	if (IsValidEntity(g_iConditionFx[client])) {
		RemoveEntity(g_iConditionFx[client]);
	}
	
	int effect = TF2_SpawnWearable();
	
	char model[PLATFORM_MAX_PATH];
	GetEntityModelPath(client, model, sizeof(model));
	SetEntityModel(effect, model);
	
	TF2Util_EquipPlayerWearable(client, effect);
	
	g_iConditionFx[client] = EntIndexToEntRef(effect);
	
	TE_SetupTFParticleEffect("peejar_drips_milk", NULL_VECTOR, .entity = effect);
	TE_SendToAll();
	
	g_flConditionEnd[client] = GetGameTime() + duration;
	g_flBleedEffectDuration[client] = bleedDuration;
}
