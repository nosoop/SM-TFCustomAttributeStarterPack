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

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.ca_rage_info");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.ca_rage_info).");
	}
	
	Handle detourActivateRageBuff = DHookCreateFromConf(hGameConf,
			"CTFPlayerShared::ActivateRageBuff()");
	DHookEnableDetour(detourActivateRageBuff, false, OnActivateRageBuffPre);
	
	delete hGameConf;
}

public void OnMapStart() {
	PrecacheSound(SOUND_HUNT_ACTIVATE);
}

public MRESReturn OnActivateRageBuffPre(Address pPlayerShared, Handle hParams) {
	int client = DHookGetParam(hParams, 1);
	
	if (GetEntProp(client, Prop_Send, "m_bRageDraining")) {
		return MRES_Supercede;
	}
	
	if (GetEntPropFloat(client, Prop_Send, "m_flRageMeter") < 100.0) {
		return MRES_Supercede;
	}
	
	int hPrimary = GetPlayerWeaponSlot(client, 0);
	
	// check if weapon contains rage effect, skip if not
	if (!IsValidEntity(hPrimary) || !TF2CustAttr_GetInt(hPrimary, "rage smokes out spies")) {
		return MRES_Ignored;
	}
	
	ActivateHuntMode(client);
	
	// set rage to drain, game will handle draining duration
	// standard rage drain takes 10 seconds, so we can just do an if rage draining for the checks
	SetEntProp(client, Prop_Send, "m_bRageDraining", true);
	
	return MRES_Supercede;
}

void ActivateHuntMode(int client) {
	// apply damage vulnerability custom attribute when rage is draining
	// this was supposed to be an increased damage vuln and custom icon
	// but the sprite effect was being stupid finicky
	TF2_AddCondition(client, TFCond_MarkedForDeath, 10.0);
	
	SDKHook(client, SDKHook_PostThinkPost, OnHuntThinkPost);
	
	EmitSoundToAll(SOUND_HUNT_ACTIVATE, client);
}

public void OnHuntThinkPost(int client) {
	if (!GetEntProp(client, Prop_Send, "m_bRageDraining")) {
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
