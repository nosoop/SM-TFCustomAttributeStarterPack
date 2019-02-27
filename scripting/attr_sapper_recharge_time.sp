/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <tf2_morestocks>

#include <tf_custom_attributes>

#pragma newdecls required

#include <stocksoup/tf/hud_notify>
#include <stocksoup/datapack>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Sapper Recharge Time",
	author = "nosoop",
	description = "Forces a switch away from the sapper and prevents use for the specified "
			... "duration",
	version = PLUGIN_VERSION,
	url = "localhost"
}

float g_flClientSapLockTime[MAXPLAYERS + 1];

Handle g_SDKCallWeaponSwitch;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("sdkhooks.games");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (sdkhooks.games).");
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Weapon_Switch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallWeaponSwitch = EndPrepSDKCall();
	if (!g_SDKCallWeaponSwitch) {
		SetFailState("Could not initialize call for CTFPlayer::Weapon_Switch");
	}
	
	delete hGameConf;
	
	HookEvent("player_sapped_object", OnObjectSapped);
	HookEvent("post_inventory_application", OnPlayerLoadoutRefresh);
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flClientSapLockTime[client] = 0.0;
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnClientWeaponCanSwitchTo);
}

public void OnPlayerLoadoutRefresh(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_flClientSapLockTime[client] = 0.0;
}

/**
 * Called when an object is sapped; checks if we should be setting up the reprogrammer.
 */
public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int sapperattach = event.GetInt("sapperid");
	
	if (!IsValidEntity(sapperattach)) {
		return;
	}
	
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(sapper);
	if (!attr) {
		// no custom attributes
		return;
	}
	
	float flRechargeTime = attr.GetFloat("sapper recharge time", 0.0);
	delete attr;
	
	if (flRechargeTime <= 0.0) {
		return;
	}
	
	ForceSwitchFromSecondaryWeapon(attacker);
	SetSapperCooldownTimer(attacker, flRechargeTime);
}

/**
 * Sets the cooldown timer.
 */
void SetSapperCooldownTimer(int client, float cooldown) {
	float regenTime = GetGameTime() + cooldown;
	
	int sapper = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper));
	SetEntPropFloat(sapper, Prop_Send, "m_flEffectBarRegenTime", regenTime);
	g_flClientSapLockTime[client] = regenTime;
	
	DataPack pack;
	CreateDataTimer(cooldown, OnSapperCooldownEnd, pack, TIMER_FLAG_NO_MAPCHANGE);
	WritePackClient(pack, client);
	pack.WriteFloat(regenTime);
}

void ForceSwitchFromSecondaryWeapon(int client) {
	int weapon = INVALID_ENT_REFERENCE;
	if (IsValidEntity((weapon = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Melee))))
			|| IsValidEntity((weapon = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Primary))))) {
		SetActiveWeapon(client, weapon);
	}
}

/**
 * Called when the cooldown has finished and sends an audible notification to the client.
 */
public Action OnSapperCooldownEnd(Handle timer, DataPack pack) {
	pack.Reset();
	int client = ReadPackClient(pack);
	float regenTime = pack.ReadFloat();
	
	if (g_flClientSapLockTime[client] == regenTime && IsPlayerAlive(client)) {
		EmitGameSoundToClient(client, "TFPlayer.ReCharged");
	}
	return Plugin_Handled;
}

/**
 * Called when attempting to switch weapons.  Deny switching to sapper if not allowed.
 */
public Action OnClientWeaponCanSwitchTo(int client, int weapon) {
	if (weapon != GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper))
			|| g_flClientSapLockTime[client] < GetGameTime()) {
		return Plugin_Continue;
	}
	
	EmitGameSoundToClient(client, "Player.DenyWeaponSelection");
	
	TF_HudNotifyCustom(client, "obj_status_sapper", TF2_GetClientTeam(client),
			"Sapper is disabled for another %d seconds.",
			RoundToCeil(g_flClientSapLockTime[client] - GetGameTime()));
	
	// Alternatively we can just allow the weapon switch but also prevent attack 
	SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", g_flClientSapLockTime[client]);
	return Plugin_Handled;
}

void SetActiveWeapon(int client, int weapon) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(hActiveWeapon)) {
		bool bResetParity = !!GetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity");
		SetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity", !bResetParity);
	}
	
	SDKCall(g_SDKCallWeaponSwitch, client, weapon, 0);
}
