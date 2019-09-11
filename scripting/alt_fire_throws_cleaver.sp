/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>
#include <custom_status_hud>

Handle g_SDKCallInitGrenade;
Handle g_SDKCallIsEntityWeapon;
Handle g_SDKCallGetWeaponSlot;
Handle g_DHookSecondaryAttack;
Handle g_SDKCallWeaponSwitch;

float g_flGunThrowRegenerateTime[MAXPLAYERS + 1][3];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::IsBaseCombatWeapon()");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_SDKCallIsEntityWeapon = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::GetSlot()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallGetWeaponSlot = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CTFWeaponBaseGrenadeProj::InitGrenade(int float)");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallInitGrenade = EndPrepSDKCall();
	
	g_DHookSecondaryAttack = DHookCreateFromConf(hGameConf,
			"CBaseCombatWeapon::SecondaryAttack()");
	
	delete hGameConf;
	
	hGameConf = LoadGameConfigFile("sdkhooks.games");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (sdkhooks.games).");
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Weapon_Switch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallWeaponSwitch = EndPrepSDKCall();
	
	delete hGameConf;
}

public void OnMapStart() {
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "*")) != -1) {
		if (entity && IsEntityWeapon(entity)) {
			DHookEntity(g_DHookSecondaryAttack, false, entity, .callback = OnSecondaryAttackPre);
		}
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnClientWeaponCanSwitchTo);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
	
	for (int i; i < sizeof(g_flGunThrowRegenerateTime[]); i++) {
		g_flGunThrowRegenerateTime[client][i] = 0.0;
	}
}

public void OnEntityCreated(int entity, const char[] className) {
	if (entity && IsEntityWeapon(entity)) {
		DHookEntity(g_DHookSecondaryAttack, false, entity, .callback = OnSecondaryAttackPre);
	}
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (!IsValidEntity(inflictor) || !IsValidEntity(weapon)) {
		return;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "alt fire throws cleaver", attr, sizeof(attr))) {
		return;
	}
	
	TF2_RemoveCondition(victim, TFCond_Bleeding);
}

public MRESReturn OnSecondaryAttackPre(int weapon) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	if (GetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack") > GetGameTime()) {
		return MRES_Ignored;
	}
	
	int slot = GetWeaponSlot(weapon);
	if (g_flGunThrowRegenerateTime[owner][slot] > GetGameTime()) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "alt fire throws cleaver", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	float speed = ReadFloatVar(attr, "velocity", 3000.0);
	float regenTime = ReadFloatVar(attr, "regen", 10.0);
	ThrowCleaver(owner, speed, weapon);
	
	if (slot >= 0 && slot < sizeof(g_flGunThrowRegenerateTime[])) {
		g_flGunThrowRegenerateTime[owner][slot] = GetGameTime() + regenTime;
	}
	
	SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack", GetGameTime() + 5.0);
	
	int replacementWeapon = GetSwitchWeaponSlot(owner, slot);
	if (IsValidEntity(replacementWeapon)) {
		SetActiveWeapon(owner, replacementWeapon);
	}
	return MRES_Ignored;
}

// mostly gleaned from CTFJar::TossJarThink()
// 
void ThrowCleaver(int client, float flSpeed = 3000.0, int weapon) {
	float angEyes[3], vecEyePosition[3];
	GetClientEyeAngles(client, angEyes);
	GetClientEyePosition(client, vecEyePosition);
	
	float vecAimForward[3], vecAimUp[3], vecAimRight[3];
	GetAngleVectors(angEyes, vecAimForward, vecAimRight, vecAimUp);
	
	float vecVelocity[3], vecAngImpulse[3];
	GetCleaverVelocityVector(vecVelocity, vecAimForward, vecAimRight, vecAimUp);
	GetCleaverAngularImpulse(vecAngImpulse);
	
	NormalizeVector(vecVelocity, vecVelocity);
	ScaleVector(vecVelocity, flSpeed);
	
	int cleaver = CreateEntityByName("tf_projectile_cleaver");
	
	// it is important that teleporting happens before dispatch otherwise spawn angles are wrong
	TeleportEntity(cleaver, vecEyePosition, angEyes, NULL_VECTOR);
	DispatchSpawn(cleaver);
	
	// use for physics logic
	SDKCall(g_SDKCallInitGrenade, cleaver, vecVelocity, vecAngImpulse, client, 0, 5.0);
	
	SetEntPropEnt(cleaver, Prop_Send, "m_hThrower", client);
	SetEntPropEnt(cleaver, Prop_Send, "m_hLauncher", weapon);
	SetEntPropEnt(cleaver, Prop_Send, "m_hOriginalLauncher", weapon);
}

// CTFCleaver::GetVelocityVector()
void GetCleaverVelocityVector(float velocity[3], const float vecForward[3],
		const float vecRight[3], const float vecUp[3]) {
	float vecResult[3];
	vecResult = vecForward;
	ScaleVector(vecResult, 10.0);
	AddVectors(vecResult, vecUp, vecResult);
	NormalizeVector(vecResult, velocity);
	ScaleVector(velocity, 3000.0);
	#pragma unused vecRight
}

// CTFCleaver::GetAngularImpulse()
void GetCleaverAngularImpulse(float vecAngImpulse[3]) {
	vecAngImpulse[0] = 0.0;
	vecAngImpulse[1] = 500.0;
	vecAngImpulse[2] = 0.0;
}

bool IsEntityWeapon(int entity) {
	return SDKCall(g_SDKCallIsEntityWeapon, entity);
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	bool changed;
	for (int i; i < sizeof(g_flGunThrowRegenerateTime[]); i++) {
		float flNextRefillTime = g_flGunThrowRegenerateTime[client][i];
		if (!flNextRefillTime || GetGameTime() > flNextRefillTime) {
			continue;
		}
		
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		char attr[64];
		if (!TF2CustAttr_GetString(weapon, "alt fire throws cleaver", attr, sizeof(attr))) {
			continue;
		}
		
		changed = true;
		
		float flRemainingTime = flNextRefillTime - GetGameTime();
		float flMaxRefillTime = ReadFloatVar(attr, "regen", 10.0);
		
		char keyBuffer[16], buffer[64];
		Format(keyBuffer, sizeof(keyBuffer), "clip_slot_%d", i);
		Format(buffer, sizeof(buffer), "Gun: %.0f%%",
				FloatAbs(1.0 - flRemainingTime / flMaxRefillTime) * 100.0);
		
		entries.SetString(keyBuffer, buffer);
	}
	return changed? Plugin_Changed : Plugin_Continue;
}

public Action OnClientWeaponCanSwitchTo(int client, int weapon) {
	int slot = GetWeaponSlot(weapon);
	if (slot < 0 || slot > sizeof(g_flGunThrowRegenerateTime[])) {
		return Plugin_Continue;
	}
	
	if (g_flGunThrowRegenerateTime[client][slot] < GetGameTime()) {
		return Plugin_Continue;
	}
	
	EmitGameSoundToClient(client, "Player.DenyWeaponSelection");
	return Plugin_Handled;
}

int GetWeaponSlot(int weapon) {
	return SDKCall(g_SDKCallGetWeaponSlot, weapon);
}

void SetActiveWeapon(int client, int weapon) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(hActiveWeapon)) {
		bool bResetParity = !!GetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity");
		SetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity", !bResetParity);
	}
	
	SDKCall(g_SDKCallWeaponSwitch, client, weapon, 0);
}

/**
 * Iterate over weapon slots to find a weapon that isn't currently disabled
 */
int GetSwitchWeaponSlot(int client, int currentSlot) {
	for (int i; i < sizeof(g_flGunThrowRegenerateTime[]); i++) {
		if (i == currentSlot) {
			continue;
		}
		
		int desiredWeapon = GetPlayerWeaponSlot(client, i);
		if (IsValidEntity(desiredWeapon)
				&& g_flGunThrowRegenerateTime[client][i] < GetGameTime()) {
			return desiredWeapon;
		}
	}
	return INVALID_ENT_REFERENCE;
}
