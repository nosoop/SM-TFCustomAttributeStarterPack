#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <tf2_stocks>

#include <tf_custom_attributes>

#pragma newdecls required

int offs_CTFPlayer_iClass;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtRegenThink = DHookCreateFromConf(hGameConf, "CTFPlayer::RegenThink()");
	
	DHookEnableDetour(dtRegenThink, false, OnPlayerRegenThinkPre);
	DHookEnableDetour(dtRegenThink, true, OnPlayerRegenThinkPost);
	
	offs_CTFPlayer_iClass = FindSendPropInfo("CTFPlayer", "m_iClass");
	
	delete hGameConf;
}

/**
 * probably the most disgusting hack I've written so far
 * prevent medic regen logic from happening by changing the class only when
 * CTFPlayer::RegenThink() occurs
 * 
 * see: https://gist.github.com/sigsegv-mvm/ee7ed6c6deaec50c5de59cd03fe6c4b2
 * 
 * CTFPlayer->IsPlayerClass() in disassembly view compares against m_iClass
 */

bool s_bContextBypassMedicRegen;

MRESReturn OnPlayerRegenThinkPre(int client) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (!IsValidEntity(hActiveWeapon)) {
		return MRES_Ignored;
	}
	
	if (TF2_GetPlayerClass(client) != TFClass_Medic) {
		return MRES_Ignored;
	}
	
	s_bContextBypassMedicRegen =
			!!TF2CustAttr_GetInt(hActiveWeapon, "disable medic regen while active", false);
	
	if (s_bContextBypassMedicRegen) {
		SetEntData(client, offs_CTFPlayer_iClass, view_as<int>(TFClass_Unknown));
	}
	return MRES_Ignored;
}

MRESReturn OnPlayerRegenThinkPost(int client) {
	if (s_bContextBypassMedicRegen) {
		SetEntData(client, offs_CTFPlayer_iClass, view_as<int>(TFClass_Medic));
	}
	s_bContextBypassMedicRegen = false;
	
	return MRES_Ignored;
}
