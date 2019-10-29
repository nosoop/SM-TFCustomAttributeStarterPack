/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

enum eMinigunState {
	AC_STATE_IDLE = 0,
	AC_STATE_STARTFIRING,
	AC_STATE_FIRING,
	AC_STATE_SPINNING,
	AC_STATE_DRYFIRE
};

int g_ShieldRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

Handle g_DHookItemPostFrame;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookItemPostFrame = DHookCreateFromConf(hGameConf, "CBaseCombatWeapon::ItemPostFrame()");
	delete hGameConf;
}

public void OnMapStart() {
	int minigun = -1;
	while ((minigun = FindEntityByClassname(minigun, "tf_weapon_minigun")) != -1) {
		HookMinigun(minigun);
	}
}

public void OnEntityCreated(int entity, const char[] className) {
	if (StrEqual(className, "tf_weapon_minigun")) {
		HookMinigun(entity);
	}
}

static void HookMinigun(int minigun) {
	DHookEntity(g_DHookItemPostFrame, false, minigun, .callback = OnMinigunPostFramePre);
}

public MRESReturn OnMinigunPostFramePre(int minigun) {
	int owner = TF2_GetEntityOwner(minigun);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	int iWeaponState = GetEntProp(minigun, Prop_Send, "m_iWeaponState");
	
	char attr[64];
	if (!TF2CustAttr_GetString(minigun, "minigun rage creates shield on deploy",
			attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	int shieldLevel = ReadIntVar(attr, "level", 1);
	float flMinRage = ReadFloatVar(attr, "min_rage", 0.0);
	bool cancelable = !!ReadIntVar(attr, "rage_cancelable", false);
	
	switch (iWeaponState) {
		case AC_STATE_SPINNING, AC_STATE_FIRING, AC_STATE_DRYFIRE: {
			if (GetEntPropFloat(owner, Prop_Send, "m_flRageMeter") / 100.0 >= flMinRage) {
				AttachProjectileShield(owner);
				
				if (shieldLevel > 1) {
					SetEntityModel(g_ShieldRef[owner],
							"models/props_mvm/mvm_player_shield2.mdl");
				}
			}
		}
		default: {
			DestroyProjectileShield(owner, .cancelRageDrain = cancelable);
		}
	}
	
	return MRES_Ignored;
}

int AttachProjectileShield(int client) {
	if (IsValidEntity(g_ShieldRef[client])) {
		return g_ShieldRef[client];
	}
	
	int shield = CreateEntityByName("entity_medigun_shield");
	if (!IsValidEntity(shield)) {
		return INVALID_ENT_REFERENCE;
	}
	
	g_ShieldRef[client] = EntIndexToEntRef(shield);
	
	TFTeam team = TF2_GetClientTeam(client);
	SetEntPropEnt(shield, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(shield, Prop_Send, "m_iTeamNum", team);
	SetEntProp(shield, Prop_Data, "m_iInitialTeamNum", team);
	
	DispatchKeyValue(shield, "skin", team == TFTeam_Red? "0" : "1");
	SetEntProp(client, Prop_Send, "m_bRageDraining", true);
	DispatchSpawn(shield);
	
	SetEntityModel(shield, "models/props_mvm/mvm_player_shield.mdl");
	
	EmitGameSoundToAll("WeaponMedi_Shield.Deploy", shield);
	return g_ShieldRef[client];
}

void DestroyProjectileShield(int client, bool cancelRageDrain = false) {
	if (!IsValidEntity(g_ShieldRef[client])) {
		return;
	}
	
	// retract sound normally plays below 25% rage
	if (GetEntPropFloat(client, Prop_Send, "m_flRageMeter") > 25.0) {
		EmitGameSoundToAll("WeaponMedi_Shield.Retract", g_ShieldRef[client]);
	}
	
	RemoveEntity(g_ShieldRef[client]);
	
	if (cancelRageDrain) {
		SetEntProp(client, Prop_Send, "m_bRageDraining", false);
	}
}
