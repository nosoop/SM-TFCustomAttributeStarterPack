/**
 * [TF2] Custom Attribute: MvM Attributes
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdkhooks>

#include <tf_custom_attributes>
#include <tf2utils>

#include <stocksoup/string>
#include <stocksoup/tf/enum/charge_resist_types>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2] Custom Attribute: MvM Attributes",
	author = "nosoop",
	description = "Implements a useful subset of MvM populator attributes",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomAttributeStarterPack"
}

#define MVMATTR_NONE                            (0)
#define MVMATTR_SUPPRESS_FIRE                   (1 << 1)
#define MVMATTR_SPAWN_WITH_FULL_CHARGE          (1 << 2)
#define MVMATTR_ALWAYS_CRIT                     (1 << 3)
#define MVMATTR_VACCINATOR_BULLET               (1 << 4)
#define MVMATTR_VACCINATOR_BLAST                (1 << 5)
#define MVMATTR_VACCINATOR_FIRE                 (1 << 6)
#define MVMATTR_IMMUNE_BULLET                   (1 << 7)
#define MVMATTR_IMMUNE_BLAST                    (1 << 8)
#define MVMATTR_IMMUNE_FIRE                     (1 << 9)
#define MVMATTR_PROJECTILE_SHIELD               (1 << 10) // unused
#define MVMATTR_RESTRICT_MELEE_ONLY             (1 << 11)
#define MVMATTR_RESTRICT_PRIMARY_ONLY           (1 << 12)
#define MVMATTR_RESTRICT_SECONDARY_ONLY         (1 << 13)

#define MVMATTR_VACCINATOR_FORCE (MVMATTR_VACCINATOR_BULLET | MVMATTR_VACCINATOR_BLAST | MVMATTR_VACCINATOR_FIRE)
#define MVMATTR_WEAPON_RESTRICTS (MVMATTR_RESTRICT_MELEE_ONLY | MVMATTR_RESTRICT_PRIMARY_ONLY | MVMATTR_RESTRICT_SECONDARY_ONLY)

int g_iMvMFlags[MAXPLAYERS + 1];
StringMap g_UnknownKeys;

public void OnPluginStart() {
	g_UnknownKeys = new StringMap();
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnMapStart() {
	g_UnknownKeys.Clear();
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_SpawnPost, OnClientSpawnPost);
	SDKHook(client, SDKHook_WeaponSwitch, OnClientWeaponSwitchPre);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result) {
	if (g_iMvMFlags[client] & MVMATTR_ALWAYS_CRIT) {
		result = true;
		return Plugin_Changed;
	}
	// warn: this causes prediction issues on 1.10
	// see https://github.com/alliedmodders/sourcemod/pull/1573
	return Plugin_Continue;
}

void OnClientSpawnPost(int client) {
	if (g_iMvMFlags[client] & MVMATTR_SPAWN_WITH_FULL_CHARGE) {
		SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
		
		int maybeMedigun = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
		if (IsValidEntity(maybeMedigun)
				&& TF2Util_GetWeaponID(maybeMedigun) == TF_WEAPON_MEDIGUN) {
			SetEntPropFloat(maybeMedigun, Prop_Send, "m_flChargeLevel", 1.0);
		}
	}
	
	if (g_iMvMFlags[client] & MVMATTR_IMMUNE_BULLET) {
		TF2_AddCondition(client, TFCond_BulletImmune);
	}
	
	if (g_iMvMFlags[client] & MVMATTR_IMMUNE_BLAST) {
		TF2_AddCondition(client, TFCond_BlastImmune);
	}
	
	if (g_iMvMFlags[client] & MVMATTR_IMMUNE_FIRE) {
		TF2_AddCondition(client, TFCond_FireImmune);
	}
}

Action OnClientWeaponSwitchPre(int client, int weapon) {
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	int flags = g_iMvMFlags[client];
	if (flags & MVMATTR_WEAPON_RESTRICTS == 0) {
		return Plugin_Continue;
	}
	
	int slot = TF2Util_GetWeaponSlot(weapon);
	if ((slot == TFWeaponSlot_Primary && flags & MVMATTR_RESTRICT_PRIMARY_ONLY)
			|| (slot == TFWeaponSlot_Secondary && flags & MVMATTR_RESTRICT_SECONDARY_ONLY)
			|| (slot == TFWeaponSlot_Melee && flags & MVMATTR_RESTRICT_MELEE_ONLY)) {
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

void OnClientWeaponSwitchPost(int client, int weapon) {
	g_iMvMFlags[client] = MVMATTR_NONE;
	for (int i; i < 3; i++) {
		int playerWeapon = GetPlayerWeaponSlot(client, i);
		if (IsValidEntity(playerWeapon)) {
			g_iMvMFlags[client] |= ComputeAttributeFlags(playerWeapon);
		}
	}
	
	if (g_iMvMFlags[client] & MVMATTR_ALWAYS_CRIT) {
		TF2_AddCondition(client, TFCond_CritMmmph);
	} else {
		TF2_RemoveCondition(client, TFCond_CritMmmph);
	}
	
	// vaccinator: preset resist type
	int itemdef = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	if (itemdef == 998 & g_iMvMFlags[client] & MVMATTR_VACCINATOR_FORCE) {
		// TODO block CWeaponMedigun::CycleResistType
		if (g_iMvMFlags[client] & MVMATTR_VACCINATOR_BULLET) {
			SetEntProp(weapon, Prop_Send, "m_nChargeResistType", Resist_Bullet);
		} else if (g_iMvMFlags[client] & MVMATTR_VACCINATOR_BLAST) {
			SetEntProp(weapon, Prop_Send, "m_nChargeResistType", Resist_Blast);
		} else if (g_iMvMFlags[client] & MVMATTR_VACCINATOR_FIRE) {
			SetEntProp(weapon, Prop_Send, "m_nChargeResistType", Resist_Fire);
		}
	}
}

int ComputeAttributeFlags(int item) {
	int attrFlags = MVMATTR_NONE;
	
	char itemAttrs[512];
	if (!TF2CustAttr_GetString(item, "mvm attributes", itemAttrs, sizeof(itemAttrs))) {
		return attrFlags;
	}
	
	int next;
	char mvmAttr[32];
	float lastSpewTime;
	while ((next = SplitStringIter(itemAttrs, " ", mvmAttr, sizeof(mvmAttr), next, true)) != -1) {
		if (StrEqual(mvmAttr, "SuppressFire")) {
			attrFlags |= MVMATTR_SUPPRESS_FIRE;
		} else if (StrEqual(mvmAttr, "SpawnWithFullCharge")) {
			attrFlags |= MVMATTR_SPAWN_WITH_FULL_CHARGE;
		} else if (StrEqual(mvmAttr, "AlwaysCrit")) {
			attrFlags |= MVMATTR_ALWAYS_CRIT;
		} else if (StrEqual(mvmAttr, "VaccinatorBullets")) {
			attrFlags |= MVMATTR_VACCINATOR_BULLET;
		} else if (StrEqual(mvmAttr, "VaccinatorBlast")) {
			attrFlags |= MVMATTR_VACCINATOR_BLAST;
		} else if (StrEqual(mvmAttr, "VaccinatorFire")) {
			attrFlags |= MVMATTR_VACCINATOR_FIRE;
		} else if (StrEqual(mvmAttr, "ImmuneBullet")) {
			attrFlags |= MVMATTR_IMMUNE_BULLET;
		} else if (StrEqual(mvmAttr, "ImmuneBlast")) {
			attrFlags |= MVMATTR_IMMUNE_BLAST;
		} else if (StrEqual(mvmAttr, "ImmuneFire")) {
			attrFlags |= MVMATTR_IMMUNE_FIRE;
		} else if (StrEqual(mvmAttr, "ProjectileShield")) {
			attrFlags |= MVMATTR_PROJECTILE_SHIELD;
		} else if (StrEqual(mvmAttr, "MeleeOnly")) {
			attrFlags |= MVMATTR_RESTRICT_MELEE_ONLY;
		} else if (StrEqual(mvmAttr, "PrimaryOnly")) {
			attrFlags |= MVMATTR_RESTRICT_PRIMARY_ONLY;
		} else if (StrEqual(mvmAttr, "SecondaryOnly")) {
			attrFlags |= MVMATTR_RESTRICT_SECONDARY_ONLY;
		} else if (!g_UnknownKeys.GetValue(mvmAttr, lastSpewTime)
				|| lastSpewTime > GetGameTime() + 30.0) {
			// warn for undefined attribute only every now and then to avoid repeated messages on recompute
			LogMessage("Warning: Unknown MvM attribute '%s'", mvmAttr);
			g_UnknownKeys.SetValue(mvmAttr, GetGameTime());
		}
	}
	return attrFlags;
}
