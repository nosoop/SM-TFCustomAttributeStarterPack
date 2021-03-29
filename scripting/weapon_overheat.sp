/**
 * "weapon overheat" attribute
 * 
 * Disables a weapon for a time if it was used extensively.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <dhooks>
#include <sdktools>

#pragma newdecls required

#include <tf2utils>
#include <tf2attributes>
#include <tf_custom_attributes>

#include <stocksoup/math>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>

#define NUM_WEAPON_SLOTS 5

Handle g_DHookPrimaryAttack;
Handle g_DHookSecondaryAttack;

Handle g_SDKCallMinigunWindDown;

float g_flOverheatAmount[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];
float g_flOverheatClearTime[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];
float g_flOverheatDecayTime[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];
float g_flOverheatDecayRate[MAXPLAYERS + 1][NUM_WEAPON_SLOTS];

// minigun weapon states
enum {
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
	g_DHookSecondaryAttack = DHookCreateFromConf(hGameConf,
			"CBaseCombatWeapon::SecondaryAttack()");
	
	Handle dtMinigunSharedAttack = DHookCreateFromConf(hGameConf, "CTFMinigun::SharedAttack()");
	DHookEnableDetour(dtMinigunSharedAttack, false, OnMinigunAttackPre);
	DHookEnableDetour(dtMinigunSharedAttack, true, OnMinigunAttackPost);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFMinigun::WindDown()");
	g_SDKCallMinigunWindDown = EndPrepSDKCall();
	
	Handle dtMechanicalArmShockAttack = DHookCreateFromConf(hGameConf, "CTFMechanicalArm::ShockAttack()");
	if (!dtMechanicalArmShockAttack) {
		SetFailState("Failed to create detour %s", "CTFMechanicalArm::ShockAttack()");
	}
	DHookEnableDetour(dtMechanicalArmShockAttack, true, OnMechanicalArmShockAttackPost);
	
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
		if (TF2Util_IsEntityWeapon(entity)) {
			HookWeaponEntity(entity);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnEntityCreated(int entity, const char[] name) {
	if (TF2Util_IsEntityWeapon(entity)) {
		HookWeaponEntity(entity);
	}
}

static void HookWeaponEntity(int weapon) {
	// miniguns are handled on the CTFMinigun::SharedAttack() detour
	if (TF2Util_GetWeaponID(weapon) != TF_WEAPON_MINIGUN) {
		DHookEntity(g_DHookPrimaryAttack, true, weapon, .callback = OnPrimaryAttackPost);
		DHookEntity(g_DHookPrimaryAttack, false, weapon, .callback = OnPrimaryAttackPre);
		
		DHookEntity(g_DHookSecondaryAttack, false, weapon, .callback = OnSecondaryAttackPre);
		DHookEntity(g_DHookSecondaryAttack, true, weapon, .callback = OnSecondaryAttackPost);
	}
}

/**
 * Reset cooldown.
 */
public void OnInventoryAppliedPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	for (int i; i < NUM_WEAPON_SLOTS; i++) {
		g_flOverheatAmount[client][i] = 0.0;
		g_flOverheatClearTime[client][i] = 0.0;
		g_flOverheatDecayTime[client][i] = 0.0;
	}
}

/**
 * Process overheat amount for a player.
 */
public void OnClientPostThinkPost(int client) {
	// TODO would OnGameFrame be better suited for this?
	
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

static bool s_bPrimaryAttackAvailableInPre;
public MRESReturn OnPrimaryAttackPre(int weapon) {
	float flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	s_bPrimaryAttackAvailableInPre = flNextPrimaryAttack <= GetGameTime();
}

public MRESReturn OnPrimaryAttackPost(int weapon) {
	if (!s_bPrimaryAttackAvailableInPre) {
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
		ForceWeaponCooldown(weapon, flCooldown);
	}
	return MRES_Ignored;
}

// check if we can attack in the pre-hook
static bool s_bSecondaryAttackAvailableInPre;

static bool s_bShockAttackActivated;
public MRESReturn OnSecondaryAttackPre(int weapon) {
	float flNextSecondaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack");
	s_bSecondaryAttackAvailableInPre = flNextSecondaryAttack <= GetGameTime();
	s_bShockAttackActivated = false;
}

public MRESReturn OnMechanicalArmShockAttackPost(int weapon, Handle hReturn) {
	bool success = DHookGetReturn(hReturn);
	s_bShockAttackActivated = success;
}

public MRESReturn OnSecondaryAttackPost(int weapon) {
	if (!s_bSecondaryAttackAvailableInPre) {
		return MRES_Ignored;
	}
	
	if (TF2Util_GetWeaponID(weapon) == TF_WEAPON_MECHANICAL_ARM && !s_bShockAttackActivated) {
		// special case for the Short Circuit
		// we check for shock attack activation since we get a delay even with insufficent ammo
		
		// we don't perform cooldown logic post ShockAttack() because the attack timers are
		// updated at the end of SecondaryAttack()
		return MRES_Ignored;
	}
	
	char buffer[512];
	if (!TF2CustAttr_GetString(weapon, "weapon overheat", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	float flOverheat = ReadFloatVar(buffer, "heat_rate_alt", 0.0);
	if (flOverheat <= 0.0) {
		return MRES_Ignored;
	}
	
	float flCooldown = ReadFloatVar(buffer, "cooldown", 0.0);
	float flDecayTime = ReadFloatVar(buffer, "decay_time", 0.0);
	float flDecayRate = ReadFloatVar(buffer, "decay_rate", 0.0);
	
	float overheat = ApplyOverheat(weapon, flOverheat, flDecayTime, flDecayRate);
	
	float flSpreadMod = ReadFloatVar(buffer, "overheat_spread_scale", 1.0);
	if (flSpreadMod != 1.0) {
		// we want client prediction to show mostly-correct bullet spread so we set this
		float spread = LerpFloat(GetOverheatAmount(weapon), 1.0, flSpreadMod);
		TF2Attrib_SetByName(weapon, "weapon spread bonus", spread);
	}
	
	if (overheat >= 1.0) {
		ForceWeaponCooldown(weapon, flCooldown);
	}
	return MRES_Ignored;
}

public MRESReturn OnMinigunAttackPre(int weapon) {
	float flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	s_bPrimaryAttackAvailableInPre = flNextPrimaryAttack <= GetGameTime();
}

public MRESReturn OnMinigunAttackPost(int weapon) {
	int state = GetEntProp(weapon, Prop_Send, "m_iWeaponState");
	if (!s_bPrimaryAttackAvailableInPre
			|| (state != AC_STATE_FIRING && state != AC_STATE_SPINNING)) {
		return MRES_Ignored;
	}
	
	char buffer[512];
	if (!TF2CustAttr_GetString(weapon, "weapon overheat", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	float flCooldown = ReadFloatVar(buffer, "cooldown", 0.0);
	float flDecayTime = ReadFloatVar(buffer, "decay_time", 0.0);
	float flDecayRate = ReadFloatVar(buffer, "decay_rate", 0.0);
	
	float overheat;
	if (state != AC_STATE_SPINNING) {
		float flOverheatRate = ReadFloatVar(buffer, "heat_rate", 0.0);
		overheat = ApplyOverheat(weapon, flOverheatRate, flDecayTime, flDecayRate);
	} else {
		// use heat_rate_alt if in spinup state but not firing
		float flPassiveOverheatRate = ReadFloatVar(buffer, "heat_rate_alt", 0.0);
		overheat = ApplyOverheat(weapon, flPassiveOverheatRate * GetGameFrameTime(),
				flDecayTime, flDecayRate, true);
	}
	
	float flSpreadMod = ReadFloatVar(buffer, "overheat_spread_scale", 1.0);
	if (flSpreadMod != 1.0) {
		// we want client prediction to show mostly-correct bullet spread so we set this
		float spread = LerpFloat(GetOverheatAmount(weapon), 1.0, flSpreadMod);
		TF2Attrib_SetByName(weapon, "weapon spread bonus", spread);
	}
	
	if (overheat >= 1.0) {
		ForceWeaponCooldown(weapon, flCooldown);
	}
	
	return MRES_Ignored;
}

/**
 * Prevents a weapon from firing for the specified amount of time, and updates the overheat
 * clearing timer so it resets overheat when the weapon can be used again.
 */
void ForceWeaponCooldown(int weapon, float flCooldown) {
	float flCooldownEnd = GetGameTime() + flCooldown;
	
	SetOverheatClearTime(weapon, flCooldownEnd);
	SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", flCooldownEnd);
	SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack", flCooldownEnd);
	
	if (!PlayCustomOverheatSound(weapon)) {
		EmitGameSoundToAll("TFPlayer.FlameOut", .entity = weapon);
	}
	
	if (TF2Util_GetWeaponID(weapon) == TF_WEAPON_MINIGUN) {
		SDKCall(g_SDKCallMinigunWindDown, weapon);
	} else {
		UpdateWeaponResetParity(weapon);
	}
}

/**
 * Checks if the weapon has a custom overheat sound that overrides the builtin.
 * 
 * @return True if a valid sound was provided and played.
 */
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

/**
 * Adds overheat to the given weapon, updating the decay time / rate.
 * 
 * @return New overheat amount, or 0.0 if no overheat was added.
 */
float ApplyOverheat(int weapon, float amount, float decayTime, float decayRate,
		bool bIgnoreNextPrimaryAttack = false) {
	float flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	if (amount <= 0.0 || (!bIgnoreNextPrimaryAttack && flNextPrimaryAttack <= GetGameTime())) {
		return 0.0;
	}
	
	int owner = TF2_GetEntityOwner(weapon);
	if (!IsValidEntity(owner)) {
		return 0.0;
	}
	
	int slot;
	if (!HasWeaponSlot(weapon, slot)) {
		return 0.0;
	}
	
	// clear overheat to be safe
	if (g_flOverheatAmount[owner][slot] >= 1.0
			&& GetGameTime() >= g_flOverheatClearTime[owner][slot]) {
		g_flOverheatAmount[owner][slot] = 0.0;
	}
	
	g_flOverheatAmount[owner][slot] += amount;
	
	// we just used our weapon, so push back the time we can start decaying overheat
	g_flOverheatDecayTime[owner][slot] = GetGameTime() + decayTime;
	g_flOverheatDecayRate[owner][slot] = decayRate;
	
	if (g_flOverheatAmount[owner][slot] > 1.0) {
		g_flOverheatAmount[owner][slot] = 1.0;
	}
	return g_flOverheatAmount[owner][slot];
}

void SetOverheatClearTime(int weapon, float time) {
	int owner = TF2_GetEntityOwner(weapon);
	int slot;
	if (!IsValidEntity(owner) || !HasWeaponSlot(weapon, slot)) {
		return;
	}
	
	g_flOverheatClearTime[owner][slot] = time;
	g_flOverheatDecayRate[owner][slot] = 0.0; // disable decay
}

float GetOverheatAmount(int weapon) {
	int owner = TF2_GetEntityOwner(weapon);
	int slot;
	if (!IsValidEntity(owner) || !HasWeaponSlot(weapon, slot)) {
		return 0.0;
	}
	return g_flOverheatAmount[owner][slot];
}

/**
 * Hook that applies a damage modifier based on how heated the attacker's weapon is.
 */
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
	
	int slot;
	if (!HasWeaponSlot(activeWeapon, slot)) {
		return Plugin_Continue;
	}
	
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

bool HasWeaponSlot(int weapon, int &slot) {
	if (TF2Util_IsEntityWearable(weapon)) {
		return false;
	}
	slot = TF2Util_GetWeaponSlot(weapon);
	return slot < NUM_WEAPON_SLOTS;
}

void UpdateWeaponResetParity(int weapon) {
	SetEntProp(weapon, Prop_Send, "m_bResetParity",
			!GetEntProp(weapon, Prop_Send, "m_bResetParity"));
}
