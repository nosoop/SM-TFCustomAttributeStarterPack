/**
 * Sniper Rifle rage effect that provides a faster firing / reload speed on the weapon.
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2attributes>
#include <tf2_stocks>
#include <dhooks>
#include <sdkhooks>

#pragma newdecls required

#include <stocksoup/tf/entity_prop_stocks>
#include <tf_cattr_buff_override>
#include <tf_custom_attributes>

int g_BuffWeaponRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_flBuffEndTime[MAXPLAYERS + 1];

public void OnPluginStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flBuffEndTime[client] = 0.0;
	g_BuffWeaponRef[client] = INVALID_ENT_REFERENCE;
	
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
}

public void OnCustomBuffHandlerAvailable() {
	TF2CustomAttrRageBuff_Register("sniper rifle full auto", OnFullAutoUpdate);
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-buff-override")) {
		OnCustomBuffHandlerAvailable();
	}
}

public void OnFullAutoUpdate(int owner, int target, const char[] name, int buffItem) {
	// only apply to self
	if (target != owner) {
		return;
	}
	
	if (TF2_GetClientActiveWeapon(owner) == buffItem) {
		float value = TF2CustAttr_GetFloat(buffItem, "sniper rifle full auto rate", 0.4);
		TF2Attrib_AddCustomPlayerAttribute(owner, "faster reload rate", value,
				BUFF_PULSE_CONDITION_DURATION);
	}
	g_BuffWeaponRef[owner] = EntIndexToEntRef(buffItem);
	g_flBuffEndTime[owner] = GetGameTime() + BUFF_PULSE_CONDITION_DURATION;
}

public void OnWeaponSwitchPost(int client, int weapon) {
	if (g_flBuffEndTime[client] > GetGameTime() && IsValidEntity(weapon)
			&& weapon == EntRefToEntIndex(g_BuffWeaponRef[client])) {
		float value = TF2CustAttr_GetFloat(weapon, "sniper rifle full auto rate", 0.4);
		TF2Attrib_AddCustomPlayerAttribute(client, "faster reload rate", value,
				g_flBuffEndTime[client] - GetGameTime());
	} else {
		TF2Attrib_RemoveCustomPlayerAttribute(client, "faster reload rate");
	}
}
