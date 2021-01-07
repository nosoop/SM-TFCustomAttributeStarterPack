#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <tf2utils>
#include <tf_custom_attributes>

#include <stocksoup/tf/weapon>

#pragma newdecls required

enum CustomReloadMode {
	// not a custom reload mode; don't process
	ReloadMode_Regular = 0,
	
	// reloads the full clip at once, deducting a matching amount from reserve
	ReloadMode_FullClip,
	
	// reloading causes any chambered ammo to be discarded, deducting up to a full clip's worth
	ReloadMode_LoseChambered,
	
	// reloading only consumes one ammo from reserve
	ReloadMode_ConsumeOne,
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtWeaponIncrementAmmo = DHookCreateFromConf(hGameConf, "CTFWeaponBase::IncrementAmmo()");
	if (!dtWeaponIncrementAmmo) {
		SetFailState("Failed to create detour %s", "CTFWeaponBase::IncrementAmmo()");
	}
	DHookEnableDetour(dtWeaponIncrementAmmo, false, OnWeaponReplenishClipPre);
	
	// handles weapons that replenish the entire clip at once
	// (to override behavior on pistols, SMGs, &c.)
	// this is bugged with Rocket Launchers
	Handle dtWeaponFinishReload = DHookCreateFromConf(hGameConf, "CBaseCombatWeapon::FinishReload()");
	if (!dtWeaponFinishReload) {
		SetFailState("Failed to create detour %s", "CBaseCombatWeapon::FinishReload()");
	}
	DHookEnableDetour(dtWeaponFinishReload, false, OnWeaponReplenishClipPre);
	
	delete hGameConf;
}

// extremely dumb hack because weapons that have m_bReloadsSingly set to false don't play
// reload starting / end animations
// sigh. the things I have to work around, valve.
MRESReturn OnWeaponReplenishClipPre(int weapon) {
	CustomReloadMode mode =
			view_as<CustomReloadMode>(TF2CustAttr_GetInt(weapon, "reload full clip at once"));
	if (mode == ReloadMode_Regular) {
		return MRES_Ignored;
	}
	
	// special reload modes ditch the original increment ammo logic
	int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
	if (mode == ReloadMode_LoseChambered) {
		// we lose all ammo in clip on reload
		clip = 0;
	}
	
	int reserve = TF2_GetWeaponAmmo(weapon);
	int needed = TF2Util_GetWeaponMaxClip(weapon) - clip;
	
	if (mode != ReloadMode_ConsumeOne && reserve < needed) {
		needed = reserve;
	}
	
	SetEntProp(weapon, Prop_Send, "m_iClip1", clip + needed);
	
	if (mode == ReloadMode_ConsumeOne) {
		needed = 1;
	}
	
	TF2_SetWeaponAmmo(weapon, reserve - needed);
	return MRES_Supercede;
}
