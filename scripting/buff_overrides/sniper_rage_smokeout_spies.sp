/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2attributes>
#include <tf2_stocks>
#include <dhooks>
#include <sdkhooks>

#pragma newdecls required
#include <stocksoup/tf/tempents_stocks>
#include <tf_cattr_buff_override>
#include <tf_custom_attributes>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Sniper Rage: Smoke Out Spies",
	author = "nosoop",
	description = "Sniper rage effect that adds a smoke effect on disguised spies.",
	version = PLUGIN_VERSION,
	url = "localhost"
}

#define SOUND_HUNT_ACTIVATE "weapons/medi_shield_deploy.wav"

float g_flHuntModeEndTime[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle detourActivateRageBuff = DHookCreateFromConf(hGameConf,
			"CTFPlayerShared::ActivateRageBuff()");
	DHookEnableDetour(detourActivateRageBuff, false, OnActivateRageBuffPre);
	
	delete hGameConf;
}

public void OnClientPutInServer(int client) {
	g_flHuntModeEndTime[client] = 0.0;
}

public void OnCustomBuffHandlerAvailable() {
	TF2CustomAttrRageBuff_Register("spy smokeout", OnHuntModeUpdate);
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-buff-override")) {
		OnCustomBuffHandlerAvailable();
	}
}

public void OnMapStart() {
	PrecacheSound(SOUND_HUNT_ACTIVATE);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public MRESReturn OnActivateRageBuffPre(Address pPlayerShared, Handle hParams) {
	int client = DHookGetParam(hParams, 1);
	int hPrimary = GetPlayerWeaponSlot(client, 0);
	
	// check if weapon contains rage effect, skip if not
	// TODO avoid requiring specific weapon slot
	char attr[64];
	if (!IsValidEntity(hPrimary)
			|| !TF2CustAttr_GetString(hPrimary, "custom buff type", attr, sizeof(attr))
			|| !StrEqual(attr, "spy smokeout")
			|| GetEntProp(client, Prop_Send, "m_bRageDraining")) {
		return MRES_Ignored;
	}
	
	ActivateHuntMode(client);
	return MRES_Ignored;
}

public void OnHuntModeUpdate(int owner, int target, const char[] name, int buffItem) {
	// only apply to self
	if (target != owner) {
		return;
	}
	
	g_flHuntModeEndTime[owner] = GetGameTime() + BUFF_PULSE_CONDITION_DURATION;
	TF2_AddCondition(owner, TFCond_MarkedForDeath, BUFF_PULSE_CONDITION_DURATION);
}

void ActivateHuntMode(int client) {
	g_flHuntModeEndTime[client] = GetGameTime() + BUFF_PULSE_CONDITION_DURATION;
	SDKHook(client, SDKHook_PostThinkPost, OnHuntThinkPost);
	
	EmitSoundToAll(SOUND_HUNT_ACTIVATE, client);
}

public void OnHuntThinkPost(int client) {
	if (GetGameTime() > g_flHuntModeEndTime[client]) {
		SDKUnhook(client, SDKHook_PostThinkPost, OnHuntThinkPost);
		return;
	}
	
	if (!TF2_IsPlayerInCondition(client, TFCond_Zoomed)) {
		return;
	}
	
	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);
	
	int huntable[MAXPLAYERS];
	int nHuntable = GetClientsInRange(vecOrigin, RangeType_Visibility,
			huntable, sizeof(huntable));
	
	TFTeam clientTeam = TF2_GetClientTeam(client);
	for (int i = 0; i < nHuntable; i++) {
		int target = huntable[i];
		if (!IsClientInGame(target) || !IsPlayerAlive(target) || target == client) {
			continue;
		}
		
		if (TF2_GetClientTeam(target) == clientTeam) {
			continue;
		}
		
		if (!TF2_IsPlayerInCondition(target, TFCond_Disguised)) {
			continue;
		}
		
		if (TF2_IsPlayerInCondition(target, TFCond_Cloaked)) {
			continue;
		}
		
		// this is the only decent smoke effect that has a short duration and startup
		TE_SetupTFParticleEffect("sapper_smoke", NULL_VECTOR, .entity = target,
				.attachPoint = 0, .attachType = PATTACH_ROOTBONE_FOLLOW);
		TE_SendToClient(client);
	}
}
