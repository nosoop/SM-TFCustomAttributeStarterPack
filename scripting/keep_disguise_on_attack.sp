#pragma semicolon 1
#include <sourcemod>

#include <dhooks>

#pragma newdecls required

#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.ctf2w_attribute_set");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.ctf2w_attribute_set).");
	}
	
	Handle dtRemoveDisguise = DHookCreateFromConf(hGameConf,
			"CTFWeaponBaseGun::ShouldRemoveDisguiseOnPrimaryAttack()");
	DHookEnableDetour(dtRemoveDisguise, true, OnShouldRemoveDisguiseOnPrimaryAttackPost);
	
	delete hGameConf;
}

public MRESReturn OnShouldRemoveDisguiseOnPrimaryAttackPost(int weapon, Handle hReturn) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	bool remove = DHookGetReturn(hReturn);
	if (!remove || !TF2CustAttr_GetInt(weapon, "keep disguise on attack")) {
		return MRES_Ignored;
	}
	
	DHookSetReturn(hReturn, false);
	return MRES_ChangedOverride;
}
