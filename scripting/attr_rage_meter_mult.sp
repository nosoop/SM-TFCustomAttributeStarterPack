/**
 * [TF2CA] Attribute: Rage Meter Scaling
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/memory>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Rage Meter Nultiplier",
	author = "nosoop",
	description = "Scales the amount of rage gained from damage",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop"
}

Handle g_DHookOnModifyRage;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	
	g_DHookOnModifyRage = DHookCreateFromConf(hGameConf, "CTFPlayerShared::ModifyRage()");
	
	DHookEnableDetour(g_DHookOnModifyRage, false, OnModifyRagePre);
	
	delete hGameConf;
}

public MRESReturn OnModifyRagePre(Address pPlayerShared, Handle hParams) {
	int client = TF2Util_GetPlayerFromSharedAddress(pPlayerShared);
	
	// LogServer("updating rage");
	
	float flMultiplier = 1.0;
	
	int hSecondary = GetPlayerWeaponSlot(client, 1);
	if (IsValidEntity(hSecondary)) {
		char className[64];
		GetEntityClassname(hSecondary, className, sizeof(className));
		if (StrEqual(className, "tf_weapon_buff_item")) {
			flMultiplier *= TF2CustAttr_GetFloat(hSecondary, "banner rage fill multiplier",
					1.0);
		}
	}
	
	for (int i; i < 3; i++) {
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		flMultiplier *= TF2CustAttr_GetFloat(weapon, "rage fill multiplier", 1.0);
	}
	
	if (flMultiplier == 1.0) {
		return MRES_Ignored;
	}
	
	float flDelta = DHookGetParam(hParams, 1);
	// LogServer("orig delta: %f", flDelta);
	DHookSetParam(hParams, 1, flDelta * flMultiplier);
	return MRES_ChangedHandled;
}
