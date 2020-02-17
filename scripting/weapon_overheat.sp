/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <dhooks>
#include <sdktools>

#pragma newdecls required

#include <tf2attributes>
#include <tf_custom_attributes>

#include <stocksoup/math>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>

#define NUM_WEAPON_SLOTS 5

Handle g_DHookPrimaryAttack;

Handle g_SDKCallWeaponGetSlot;
Handle g_SDKCallMinigunWindDown;

float g_flOverheatAmount[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];
float g_flOverheatClearTime[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];
float g_flOverheatDecayTime[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];
float g_flOverheatDecayRate[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];

// minigun weapon states
enum eMinigunState {
	AC_STATE_IDLE = 0,
	AC_STATE_STARTFIRING,
	AC_STATE_FIRING,
	AC_STATE_SPINNING,
	AC_STATE_DRYFIRE
};

ConVar g_ConVarMeterRender;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookPrimaryAttack = DHookCreateFromConf(hGameConf, "CTFWeaponBase::PrimaryAttack()");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::GetSlot()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallWeaponGetSlot = EndPrepSDKCall();
	
	Handle dtMinigunSharedAttack = DHookCreateFromConf(hGameConf, "CTFMinigun::SharedAttack()");
	DHookEnableDetour(dtMinigunSharedAttack, false, OnMinigunAttackPre);
	DHookEnableDetour(dtMinigunSharedAttack, true, OnMinigunAttackPost);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFMinigun::WindDown()");
	g_SDKCallMinigunWindDown = EndPrepSDKCall();
	
	delete hGameConf;
	
	HookEvent("post_inventory_application", OnInventoryAppliedPost);
	
	g_ConVarMeterRender = CreateConVar("cattr_overheat_meter_mode", "0",
			"Meter display mode.  0 for text, 1 for bars.");
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "*")) != -1) {
		if (HasEntProp(entity, Prop_Data, "m_flNextPrimaryAttack")) {
			HookWeaponEntity(entity);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnEntityCreated(int entity, const char[] name) {
	if (HasEntProp(entity, Prop_Data, "m_flNextPrimaryAttack")) {
		HookWeaponEntity(entity);
	}
}

static void HookWeaponEntity(int weapon) {
	char cname[64];
	GetEntityClassname(weapon, cname, sizeof(cname));
	
	// miniguns are handled on CTFMinigun::SharedAttack
	if (!StrEqual(cname, "tf_weapon_minigun")) {
		DHookEntity(g_DHookPrimaryAttack, true, weapon, .callback = OnPrimaryAttackPost);
		DHookEntity(g_DHookPrimaryAttack, false, weapon, .callback = OnPrimaryAttackPre);
	}
	
	if (HasEntProp(weapon, Prop_Data, "CTFWeaponBaseGunZoomOutIn")) {
	}
}

public void OnInventoryAppliedPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	for (int i; i < NUM_WEAPON_SLOTS; i++) {
		g_flOverheatAmount[client][i] = 0.0;
		g_flOverheatClearTime[client][i] = 0.0;
		g_flOverheatDecayTime[client][i] = 0.0;
	}
}

public void OnClientPostThinkPost(int client) {
	for (int i; i < NUM_WEAPON_SLOTS; i++) {
		// no overheat to deal with
		if (g_flOverheatAmount[client][i] <= 0.0) {
			continue;
		}
		
		// overheated -- don't do anything until it's cleared
		if (g_flOverheatAmount[client][i] >= 1.0
				&& GetGameTime() > g_flOverheatClearTime[client][i]) {
			g_flOverheatAmount[client][i] = 0.0;
			continue;
		}
		
		// attempt to decay if we have some amount and we can start decreasing it
		if (g_flOverheatDecayRate[client][i] > 0.0
				&& GetGameTime() > g_flOverheatDecayTime[client][i]) {
			g_flOverheatAmount[client][i] -=
					g_flOverheatDecayRate[client][i] * GetGameFrameTime();
			if (g_flOverheatAmount[client][i] < 0.0) {
				g_flOverheatAmount[client][i] = 0.0;
			}
		}
	}
}

// check when weapon is fired
// determine overheat amount, add to float

static bool s_bPrimaryAttackAvailable;
public MRESReturn OnPrimaryAttackPre(int weapon) {
	float flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	s_bPrimaryAttackAvailable = flNextPrimaryAttack <= GetGameTime();
}

public MRESReturn OnPrimaryAttackPost(int weapon) {
	if (!s_bPrimaryAttackAvailable) {
		return MRES_Ignored;
	}
	
	char buffer[512];
	if (!TF2CustAttr_GetString(weapon, "weapon overheat", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	float flOverheat = ReadFloatVar(buffer, "heat_rate", 0.0);
	float flCooldown = ReadFloatVar(buffer, "cooldown", 0.0);
	float flDecayTime = ReadFloatVar(buffer, "decay_time", 0.0);
	float flDecayRate = ReadFloatVar(buffer, "decay_rate", 0.0);
	
	float overheat = ApplyOverheat(weapon, flOverheat, flDecayTime, flDecayRate);
	
	float flSpreadMod = ReadFloatVar(buffer, "overheat_spread_scale", 1.0);
	if (flSpreadMod != 1.0) {
		// this needs to be lag compensated so we do need to apply this modifier
		float spread = LerpFloat(GetOverheatAmount(weapon), 1.0, flSpreadMod);
		TF2Attrib_SetByName(weapon, "weapon spread bonus", spread);
	}
	
	if (overheat >= 1.0) {
		float flCooldownEnd = GetGameTime() + flCooldown;
		
		SetOverheatClearTime(weapon, flCooldownEnd);
		SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", flCooldownEnd);
		SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack", flCooldownEnd);
		
		if (!PlayCustomOverheatSound(weapon)) {
			EmitGameSoundToAll("TFPlayer.FlameOut", .entity = weapon);
		}
		
		UpdateWeaponResetParity(weapon);
	}
	return MRES_Ignored;
}

public MRESReturn OnMinigunAttackPre(int weapon) {
	float flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	s_bPrimaryAttackAvailable = flNextPrimaryAttack <= GetGameTime();
}

public MRESReturn OnMinigunAttackPost(int weapon) {
	if (!s_bPrimaryAttackAvailable
			|| GetEntProp(weapon, Prop_Send, "m_iWeaponState") != AC_STATE_FIRING) {
		return MRES_Ignored;
	}
	
	char buffer[512];
	if (!TF2CustAttr_GetString(weapon, "weapon overheat", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	float flOverheat = ReadFloatVar(buffer, "heat_rate", 0.0);
	float flCooldown = ReadFloatVar(buffer, "cooldown", 0.0);
	float flDecayTime = ReadFloatVar(buffer, "decay_time", 0.0);
	float flDecayRate = ReadFloatVar(buffer, "decay_rate", 0.0);
	
	float overheat = ApplyOverheat(weapon, flOverheat, flDecayTime, flDecayRate);
	
	float flSpreadMod = ReadFloatVar(buffer, "overheat_spread_scale", 1.0);
	if (flSpreadMod != 1.0) {
		// this needs to be lag compensated so we do need to apply this modifier
		float spread = LerpFloat(GetOverheatAmount(weapon), 1.0, flSpreadMod);
		TF2Attrib_SetByName(weapon, "weapon spread bonus", spread);
	}
	
	if (overheat >= 1.0) {
		float flCooldownEnd = GetGameTime() + flCooldown;
		
		SetOverheatClearTime(weapon, flCooldownEnd);
		SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", flCooldownEnd);
		SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack", flCooldownEnd);
		
		if (!PlayCustomOverheatSound(weapon)) {
			EmitGameSoundToAll("TFPlayer.FlameOut", .entity = weapon);
		}
		
		SDKCall(g_SDKCallMinigunWindDown, weapon);
	}
	
	return MRES_Ignored;
}

bool PlayCustomOverheatSound(int weapon) {
	char overheatSound[PLATFORM_MAX_PATH];
	if (!TF2CustAttr_GetString(weapon, "weapon overheat sound", overheatSound,
			sizeof(overheatSound))) {
		return false;
	}
	
	char overheatSoundFile[PLATFORM_MAX_PATH];
	FormatEx(overheatSoundFile, sizeof(overheatSoundFile), "sound/%s", overheatSound);
	if (!FileExists(overheatSoundFile, true)) {
		return false;
	}
	
	PrecacheSound(overheatSound);
	EmitSoundToAll(overheatSound, .entity = weapon);
	return true;
}

float ApplyOverheat(int weapon, float amount, float decayTime, float decayRate) {
	float flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	if (amount <= 0.0 || flNextPrimaryAttack <= GetGameTime()) {
		return 0.0;
	}
	
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return 0.0;
	}
	
	int slot = GetWeaponSlot(weapon);
	
	// clear overheat to be safe
	if (g_flOverheatAmount[owner][slot] >= 1.0
			&& GetGameTime() >= g_flOverheatClearTime[owner][slot]) {
		g_flOverheatAmount[owner][slot] = 0.0;
	}
	
	g_flOverheatAmount[owner][slot] += amount;
	
	g_flOverheatDecayTime[owner][slot] = GetGameTime() + decayTime;
	g_flOverheatDecayRate[owner][slot] = decayRate;
	
	if (g_flOverheatAmount[owner][slot] > 1.0) {
		g_flOverheatAmount[owner][slot] = 1.0;
	}
	return g_flOverheatAmount[owner][slot];
}

void SetOverheatClearTime(int weapon, float time) {
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return;
	}
	
	int slot = GetWeaponSlot(weapon);
	g_flOverheatClearTime[owner][slot] = time;
	g_flOverheatDecayRate[owner][slot] = 0.0; // disable decay
}

float GetOverheatAmount(int weapon) {
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return 0.0;
	}
	
	int slot = GetWeaponSlot(weapon);
	return g_flOverheatAmount[owner][slot];
}

public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	float overheat = GetOverheatAmount(weapon);
	if (overheat <= 0.0) {
		return Plugin_Continue;
	}
	
	char buffer[512];
	if (!TF2CustAttr_GetString(weapon, "weapon overheat", buffer, sizeof(buffer))) {
		return Plugin_Continue;
	}
	
	float flDamageMod = ReadFloatVar(buffer, "overheat_dmg_scale", 1.0);
	if (flDamageMod == 1.0) {
		return Plugin_Continue;
	}
	
	damage *= LerpFloat(overheat, 1.0, flDamageMod);
	return Plugin_Changed;
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	int activeWeapon = TF2_GetClientActiveWeapon(client);
	
	if (!IsValidEntity(activeWeapon)) {
		return Plugin_Continue;
	}
	
	char buffer[512];
	if (!TF2CustAttr_GetString(activeWeapon, "weapon overheat", buffer, sizeof(buffer))) {
		return Plugin_Continue;
	}
	
	int slot = GetWeaponSlot(activeWeapon);
	
	char entry[64];
	switch (g_ConVarMeterRender.IntValue) {
		case 0: {
			Format(entry, sizeof(entry), "Overheat: %d%%",
					RoundFloat(g_flOverheatAmount[client][slot] * 100.0));
		}
		case 1: {
			char progress[21] = "                    ";
			for (int i; i < RoundFloat(g_flOverheatAmount[client][slot] * 10.0); i++) {
				progress[i] = '|';
				progress[sizeof(progress) - 1 - i] = '\0';
			}
			Format(entry, sizeof(entry), "Overheat: [%s]", progress);
		}
	}
	entries.SetString("active_overheat", entry);
	return Plugin_Changed;
}

int GetWeaponSlot(int weapon) {
	return SDKCall(g_SDKCallWeaponGetSlot, weapon);
}

void UpdateWeaponResetParity(int weapon) {
	SetEntProp(weapon, Prop_Send, "m_bResetParity",
			!GetEntProp(weapon, Prop_Send, "m_bResetParity"));
}
