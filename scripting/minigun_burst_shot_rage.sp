#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdkhooks>
#include <tf2attributes>

#pragma newdecls required

#include <stocksoup/math>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>
#include <custom_status_hud>

#include <tf_custom_attributes>

enum BoostState {
	Boost_None,
	Boost_Prestart,
	Boost_Starting,
	Boost_Active,
	Boost_ResetState
}

#define TALOS_BOOST_ACTIVATE_DELAY 1.5

#if defined KARMACHARGER_SOUNDS_ENABLED
#define TALOS_BOOST_SOUND_LOOP "weapons/talos/talos_boost_loop.wav"
#define TALOS_BOOST_SOUND_OVER "weapons/talos/talos_boost_over.wav"
#define TALOS_BOOST_SOUND_START "weapons/talos/talos_boost_start.wav"
#endif // KARMACHARGER_SOUNDS_ENABLED

BoostState g_BoostState[MAXPLAYERS + 1];
float g_flStateTransitionTime[MAXPLAYERS + 1];
float g_flNextAllowedBoostTime[MAXPLAYERS + 1];

float g_flBoostActivateTime[MAXPLAYERS + 1];
float g_flBoostPenaltyExpired[MAXPLAYERS + 1];
float g_flBoostPenaltyDecayRate[MAXPLAYERS + 1];

// minigun weapon states
enum {
	AC_STATE_IDLE = 0,
	AC_STATE_STARTFIRING,
	AC_STATE_FIRING,
	AC_STATE_SPINNING,
	AC_STATE_DRYFIRE
};

Handle g_DHookRemoveAmmo;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookRemoveAmmo = DHookCreateFromConf(hGameConf, "CTFPlayer::RemoveAmmo()");
	
	Handle dtMinigunActivatePushBack = DHookCreateFromConf(hGameConf,
			"CTFMinigun::ActivatePushBackAttackMode()");
	DHookEnableDetour(dtMinigunActivatePushBack, false, OnMinigunActivatePushBackPre);
	
	delete hGameConf;
	
	HookEvent("player_spawn", OnPlayerSpawn);
}


public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
#if defined KARMACHARGER_SOUNDS_ENABLED
	AddFileToDownloadsTable("sound/" ... TALOS_BOOST_SOUND_LOOP);
	AddFileToDownloadsTable("sound/" ... TALOS_BOOST_SOUND_OVER);
	AddFileToDownloadsTable("sound/" ... TALOS_BOOST_SOUND_START);
	
	PrecacheSound(")" ... TALOS_BOOST_SOUND_LOOP);
	PrecacheSound(")" ... TALOS_BOOST_SOUND_OVER);
	PrecacheSound(")" ... TALOS_BOOST_SOUND_START);
#endif // KARMACHARGER_SOUNDS_ENABLED
}

void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_flBoostPenaltyDecayRate[client] = 0.0;
}

public void OnClientPutInServer(int client) {
	g_flNextAllowedBoostTime[client] = 0.0;
	g_flStateTransitionTime[client] = 0.0;
	
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
	DHookEntity(g_DHookRemoveAmmo, false, client, .callback = OnPlayerRemoveAmmo);
}

MRESReturn OnMinigunActivatePushBackPre(int minigun) {
	int owner = TF2_GetEntityOwner(minigun);
	if (!IsValidEntity(owner)) {
		return MRES_Ignored;
	}
	
	char buffer[128];
	if (!TF2CustAttr_GetString(minigun, "minigun burst shot rage", buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	ActivateBurstMode(owner);
	return MRES_Supercede;
}

public void OnPlayerRunCmdPost(int client, int buttons) {
	if (buttons & IN_RELOAD == 0) {
		return;
	}
	
	int weapon = TF2_GetClientActiveWeapon(client);
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	char buffer[16];
	if (!TF2CustAttr_GetString(weapon, "minigun burst shot rage", buffer, sizeof(buffer))) {
		return;
	}
	
	ActivateBurstMode(client);
}

void ActivateBurstMode(int client) {
	float flRageMeter = GetEntPropFloat(client, Prop_Send, "m_flRageMeter");
	if (flRageMeter < 100.0 || g_BoostState[client]) {
		return;
	}
	
	g_BoostState[client] = Boost_Prestart;
}

void OnClientPostThinkPost(int client) {
	int primaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	
	char attr[128];
	if (g_BoostState[client] != Boost_None) {
		TF2CustAttr_GetString(primaryWeapon, "minigun burst shot rage", attr, sizeof(attr));
	}
	
	bool bRageDraining = !!GetEntProp(client, Prop_Send, "m_bRageDraining");
	
	// I don't even know
	// trying to maintain boost states is awkward
	
	switch (g_BoostState[client]) {
		case Boost_None: {
			// not in boosted state
			// TODO properly deal with fire rate penalties
			if (g_flBoostPenaltyDecayRate[client]) {
				// we have a penalty being applied
				Address pAttr = TF2Attrib_GetByName(primaryWeapon, "fire rate bonus HIDDEN");
				if (pAttr) {
					float flNewRate = TF2Attrib_GetValue(pAttr)
						- (g_flBoostPenaltyDecayRate[client] * GetGameFrameTime());
					TF2Attrib_SetValue(pAttr, flNewRate);
					TF2Attrib_ClearCache(primaryWeapon);
					
					if (GetGameTime() > g_flBoostPenaltyExpired[client]) {
						TF2Attrib_RemoveByName(primaryWeapon, "fire rate bonus HIDDEN");
						UpdateWeaponResetParity(primaryWeapon);
						g_flBoostPenaltyDecayRate[client] = 0.0;
					}
				}
			}
		}
		case Boost_Prestart: {
			// player activated boost, begin charging, transition to starting state
#if defined KARMACHARGER_SOUNDS_ENABLED
			EmitSoundToClient(client, ")" ... TALOS_BOOST_SOUND_START);
#endif // KARMACHARGER_SOUNDS_ENABLED
			
			g_flBoostActivateTime[client] = GetGameTime() + TALOS_BOOST_ACTIVATE_DELAY;
			
			// disable next attack if it's sooner than our activation time
			float flNextAttack =
					GetEntPropFloat(primaryWeapon, Prop_Data, "m_flNextPrimaryAttack");
			if (g_flBoostActivateTime[client] > flNextAttack) {
				SetEntPropFloat(primaryWeapon, Prop_Data, "m_flNextPrimaryAttack",
						g_flBoostActivateTime[client]);
			}
			
			// roll it back to startfiring to disable the weapon temporarily while "charging"
			if (GetEntProp(primaryWeapon, Prop_Send, "m_iWeaponState") > AC_STATE_STARTFIRING) {
				SetEntProp(primaryWeapon, Prop_Send, "m_iWeaponState", AC_STATE_STARTFIRING);
			}
			g_BoostState[client]++;
		}
		case Boost_Starting: {
			// disable next attack if it's sooner than our activation time
			float flNextAttack =
					GetEntPropFloat(primaryWeapon, Prop_Data, "m_flNextPrimaryAttack");
			if (g_flBoostActivateTime[client] > flNextAttack) {
				SetEntPropFloat(primaryWeapon, Prop_Data, "m_flNextPrimaryAttack",
						g_flBoostActivateTime[client]);
			}
			
			// transition to active boost if we're activated
			if (g_flBoostActivateTime[client] && GetGameTime() > g_flBoostActivateTime[client]
					&& !bRageDraining) {
#if defined KARMACHARGER_SOUNDS_ENABLED
				EmitSoundToClient(client, ")" ... TALOS_BOOST_SOUND_LOOP);
#endif // KARMACHARGER_SOUNDS_ENABLED
				SetEntProp(client, Prop_Send, "m_bRageDraining", true);
				
				UpdateWeaponResetParity(primaryWeapon);
				
				float flFireBonus = ReadFloatVar(attr, "mult_postfiredelay", 1.0);
				TF2Attrib_SetByName(primaryWeapon, "fire rate bonus HIDDEN", flFireBonus);
				
				float flSpreadScale = ReadFloatVar(attr, "mult_spread", 1.0);
				TF2Attrib_SetByName(primaryWeapon, "weapon spread bonus", flSpreadScale);
				
				g_BoostState[client]++;
			}
		}
		case Boost_Active: {
			// transition to boost disabled if rage isn't draining
			if (!bRageDraining) {
#if defined KARMACHARGER_SOUNDS_ENABLED
				StopSound(client, SNDCHAN_AUTO, ")" ... TALOS_BOOST_SOUND_LOOP);
				EmitSoundToClient(client, ")" ... TALOS_BOOST_SOUND_OVER);
#endif // KARMACHARGER_SOUNDS_ENABLED
				TF2Attrib_RemoveByName(primaryWeapon, "fire rate bonus HIDDEN");
				TF2Attrib_RemoveByName(primaryWeapon, "weapon spread bonus");
				
				// fix sound breakage after fire rate bonus attribute is cleared
				UpdateWeaponResetParity(primaryWeapon);
				
				g_flBoostActivateTime[client] = 0.0;
				
				float flRechargeTime = ReadFloatVar(attr, "recharge_period", 0.0);
				if (flRechargeTime > 0.0) {
					// 
					float flFirePenalty = ReadFloatVar(attr, "fire_delay_recharge", 1.0);
					TF2Attrib_SetByName(primaryWeapon, "fire rate bonus HIDDEN", flFirePenalty);
					
					float flDecayAmount = (flFirePenalty - 1.0); // 0.25 -> 1.0 = -0.75
					// subtract -0.75 * GetGameFrameTime() until expired ??
					
					g_flBoostPenaltyDecayRate[client] = flDecayAmount / flRechargeTime;
					g_flBoostPenaltyExpired[client] = GetGameTime() + flRechargeTime;
				}
				
				g_BoostState[client] = Boost_None;
			}
		}
	}
}

MRESReturn OnPlayerRemoveAmmo(int client, Handle hReturn, Handle hParams) {
	if (g_BoostState[client] != Boost_Active) {
		return MRES_Ignored;
	}
	
	int primaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (!IsValidEntity(primaryWeapon)) {
		return MRES_Ignored;
	}
	
	int ammoType = DHookGetParam(hParams, 2);
	if (ammoType != GetEntProp(primaryWeapon, Prop_Send, "m_iPrimaryAmmoType")) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(primaryWeapon, "minigun burst shot rage", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	int ammoPerShot = ReadIntVar(attr, "ammo_per_shot", 1);
	DHookSetParam(hParams, 1, ammoPerShot);
	return MRES_ChangedHandled;
}

void UpdateWeaponResetParity(int weapon) {
	SetEntProp(weapon, Prop_Send, "m_bResetParity",
			!GetEntProp(weapon, Prop_Send, "m_bResetParity"));
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	int primaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (!IsValidEntity(primaryWeapon) || TF2_GetClientActiveWeapon(client) != primaryWeapon) {
		return Plugin_Continue;
	}
	
	char attr[128];
	if (!TF2CustAttr_GetString(primaryWeapon, "minigun burst shot rage", attr, sizeof(attr))) {
		return Plugin_Continue;
	}
	
	char buffer[64];
	Address pAttr = TF2Attrib_GetByName(primaryWeapon, "fire rate bonus HIDDEN");
	
	float flValue = pAttr? TF2Attrib_GetValue(pAttr) : 1.0;
	Format(buffer, sizeof(buffer), "Fire Rate: %.0f%%", 100.0 / flValue);
	entries.SetString("talos_fire_rate", buffer);
	
	return Plugin_Changed;
}
