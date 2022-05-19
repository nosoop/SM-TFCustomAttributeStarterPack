/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <tf2attributes>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <stocksoup/entity_prefabs>
#include <stocksoup/entity_tools>
#include <stocksoup/tf/entity_prop_stocks>

#include <custom_status_hud>

Handle g_DHookPrimaryAttack;

bool g_bFriendlyBuff[MAXPLAYERS + 1];
float g_flBuffEndTime[MAXPLAYERS + 1];

int g_iConditionFx[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_flEffectExpiry[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookPrimaryAttack = DHookCreateFromConf(hGameConf, "CTFWeaponBase::PrimaryAttack()");
	
	delete hGameConf;
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
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
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_weapon_sniperrifle*")) != -1) {
		HookSniperRifle(entity);
	}
	
	PrecacheSound(")items/powerup_pickup_haste.wav");
	PrecacheSound(")weapons/discipline_device_power_down.wav");
}

public void OnEntityCreated(int entity, const char[] className) {
	if (!strncmp(className, "tf_weapon_sniperrifle", strlen("tf_weapon_sniperrifle"))) {
		HookSniperRifle(entity);
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

void HookSniperRifle(int sniperrifle) {
	DHookEntity(g_DHookPrimaryAttack, true, sniperrifle, .callback = OnSniperRifleAttackPost);
}

public void OnClientPutInServer(int client) {
	g_flBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

void OnClientPostThinkPost(int client) {
	if (IsValidEntity(g_iConditionFx[client]) && GetGameTime() > g_flEffectExpiry[client]) {
		RemoveEntity(g_iConditionFx[client]);
	}
	
	if (!g_flBuffEndTime[client] || g_flBuffEndTime[client] >= GetGameTime()) {
		return;
	}
	
	ClearAttributeCache(client);
	
	g_flBuffEndTime[client] = 0.0;
	
	EmitGameSoundToClient(client, "DisciplineDevice.PowerDown");
}

MRESReturn OnSniperRifleAttackPost(int sniperrifle) {
	if (GetEntPropFloat(sniperrifle, Prop_Send, "m_flChargedDamage") < 150.0) {
		return MRES_Ignored;
	}
	
	int owner = TF2_GetEntityOwner(sniperrifle);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	int target = GetClientAimTarget(owner);
	if (target == -1 || TF2_GetClientTeam(owner) != TF2_GetClientTeam(target)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(sniperrifle, "sniper weapon rate mod on hit ally",
			attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	float scale = ReadFloatVar(attr, "scale", 1.0);
	float duration = ReadFloatVar(attr, "duration", 0.0);
	
	g_bFriendlyBuff[target] = true;
	ModWeaponRate(target, scale, duration);
	ApplyEffect(target, 1.0);
	
	return MRES_Ignored;
}

void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (!weapon || !IsValidEntity(weapon)) {
		return; 
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "sniper weapon rate mod on hit",
			attr, sizeof(attr))) {
		return;
	}
	
	if (GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage") < 150.0) {
		return;
	}
	
	float scale = ReadFloatVar(attr, "scale", 1.0);
	float duration = ReadFloatVar(attr, "duration", 0.0);
	
	g_bFriendlyBuff[victim] = false;
	ModWeaponRate(victim, scale, duration);
}

void ModWeaponRate(int client, float scale, float duration) {
	if (scale == 1.0 || duration == 0.0) {
		return;
	}
	
	TF2Attrib_AddCustomPlayerAttribute(client, "Reload time decreased", scale, duration);
	TF2Attrib_AddCustomPlayerAttribute(client, "fire rate bonus HIDDEN", scale, duration);
	
	if (GetGameTime() > g_flBuffEndTime[client]) {
		EmitGameSoundToAll("Powerup.PickUpHaste", .entity = client);
	}
	
	/**
	 * mult_postfiredelay is cached, so we have to clear the entire cache for that attribute
	 * when the duration is over -- attribute expiry during that tick still counts here
	 */
	g_flBuffEndTime[client] = GetGameTime() + duration + GetTickInterval();
	
	ClearAttributeCache(client);
}

void ClearAttributeCache(int client) {
	TF2Attrib_ClearCache(client);
	for (int i; i < 3; i++) {
		int weapon = GetPlayerWeaponSlot(client, i);
		if (IsValidEntity(weapon)) {
			TF2Attrib_ClearCache(weapon);
			UpdateWeaponResetParity(weapon); // fixes minigun
		}
	}
}

void UpdateWeaponResetParity(int weapon) {
	SetEntProp(weapon, Prop_Send, "m_bResetParity",
			!GetEntProp(weapon, Prop_Send, "m_bResetParity"));
}

void ApplyEffect(int client, float duration) {
	g_flEffectExpiry[client] = GetGameTime() + duration;
	if (IsValidEntity(g_iConditionFx[client])) {
		return;
	}
	
	// show at feet
	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);
	vecOrigin[2] += 0.2;
	
	int particle = CreateParticle(TF2_GetClientTeam(client) == TFTeam_Red?
			"soldierbuff_red_buffed" : "soldierbuff_blue_buffed");
	TeleportEntity(particle, vecOrigin, NULL_VECTOR, NULL_VECTOR);
	ParentEntity(client, particle);
	
	g_iConditionFx[client] = EntIndexToEntRef(particle);
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	if (GetGameTime() > g_flBuffEndTime[client] || !g_bFriendlyBuff[client]) {
		return Plugin_Continue;
	}
	
	char buffer[64];
	FormatEx(buffer, sizeof(buffer), "Moonbeam Boost: %ds",
			RoundToCeil(g_flBuffEndTime[client] - GetGameTime()));
	entries.SetString("moonbeam_cond", buffer);
	return Plugin_Changed;
}
