#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>

#pragma newdecls required

#include <dhooks>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>

Handle g_SDKCallIsWeapon;
Handle g_SDKCallGetWeaponSlot;

Handle g_DHookOnMeleeEntityHit;

float g_flBuffEndTime[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookOnMeleeEntityHit = DHookCreateFromConf(hGameConf,
			"CTFWeaponBaseMelee::OnEntityHit()");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::IsBaseCombatWeapon()");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_SDKCallIsWeapon = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::GetSlot()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallGetWeaponSlot = EndPrepSDKCall();
	
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
		if (!IsEntityMeleeWeapon(entity)) {
			continue;
		}
		OnMeleeCreated(entity);
	}
	
	PrecacheSound(")items/powerup_pickup_haste.wav");
}

public void OnEntityCreated(int entity, const char[] name) {
	SDKHook(entity, SDKHook_SpawnPost, OnEntitySpawnPost);
}

public void OnEntitySpawnPost(int entity) {
	if (IsEntityMeleeWeapon(entity)) {
		OnMeleeCreated(entity);
	}
}

void OnMeleeCreated(int meleeWeapon) {
	DHookEntity(g_DHookOnMeleeEntityHit, true, meleeWeapon, .callback = OnMeleeEntityHitPost);
}

public void OnClientPutInServer(int client) {
	g_flBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

public void OnClientPostThinkPost(int client) {
	if (!g_flBuffEndTime[client] || g_flBuffEndTime[client] >= GetGameTime()) {
		return;
	}
	
	ClearAttributeCache(client);
	
	g_flBuffEndTime[client] = 0.0;
}

public MRESReturn OnMeleeEntityHitPost(int weapon, Handle hParams) {
	int entity = DHookGetParam(hParams, 1);
	if (entity < 1 || entity > MaxClients) {
		return MRES_Ignored;
	}
	
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients
			|| TF2_GetClientTeam(entity) != TF2_GetClientTeam(owner)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "weapon rate buff ally", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	float scale = ReadFloatVar(attr, "scale", 1.0);
	float duration = ReadFloatVar(attr, "duration", 0.0);
	
	if (scale == 1.0 || duration == 0.0) {
		return MRES_Ignored;
	}
	
	ModWeaponRate(entity, scale, duration);
	
	return MRES_Ignored;
}

void ModWeaponRate(int client, float scale, float duration) {
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

bool IsEntityMeleeWeapon(int entity) {
	return SDKCall(g_SDKCallIsWeapon, entity)
			&& SDKCall(g_SDKCallGetWeaponSlot, entity) == TFWeaponSlot_Melee;
}
