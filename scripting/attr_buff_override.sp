/**
 * [TF2CA] Attribute: Banner Buff Override
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <dhooks>

#pragma newdecls required
#include <tf_custom_attributes>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Banner Buff Override",
	author = "nosoop",
	description = "Overrides the behavior of the Soldier's buff items.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop"
}

// taken from game code
#define SOLDIER_BUFF_RADIUS 450.0

Handle g_SDKCallGetBaseEntity;
Handle g_DHookOnModifyRage;

static Address g_offset_CTFPlayerShared_pOuter;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.ca_buff_override");
	
	g_DHookOnModifyRage = DHookCreateFromConf(hGameConf, "CTFPlayerShared::PulseRageBuff()");
	
	DHookEnableDetour(g_DHookOnModifyRage, false, OnPulseRageBuffPre);
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::GetBaseEntity()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallGetBaseEntity = EndPrepSDKCall();
	
	g_offset_CTFPlayerShared_pOuter =
			view_as<Address>(GameConfGetOffset(hGameConf, "CTFPlayerShared::m_pOuter"));
	
	delete hGameConf;
}

public MRESReturn OnPulseRageBuffPre(Address pPlayerShared, Handle hParams) {
	int client = GetClientFromPlayerShared(pPlayerShared);
	TFTeam buffTeam = TF2_GetClientTeam(client);
	
	// check for buff banner-like
	int hSecondary = GetPlayerWeaponSlot(client, 1);
	if (!IsWeaponBuffItem(hSecondary)) {
		return MRES_Ignored;
	}
	
	KeyValues attributes = TF2CustAttr_GetAttributeKeyValues(hSecondary);
	if (!attributes) {
		return MRES_Ignored;
	}
	
	int customBuffType = attributes.GetNum("custom soldier buff type", 0);
	delete attributes;
	
	// TODO allow plugins to implement buff types with a private forward instead
	if (!customBuffType || customBuffType != 666) {
		LogError("incorrect custom buff type (%d)", customBuffType);
		return MRES_Ignored;
	}
	
	float flRadiusSq = Pow(SOLDIER_BUFF_RADIUS, 2.0);
	// TODO there is a mod_soldier_buff_range attribute but it's not present in items_game
	
	float vecBuffOrigin[3];
	GetClientAbsOrigin(client, vecBuffOrigin);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientConnected(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != buffTeam) {
			continue;
		}
		
		if (TF2_IsPlayerInCondition(i, TFCond_Disguised)
				&& TF2_GetDisguiseTeam(i) != buffTeam) {
			continue;
		}
		
		if (TF2_IsPlayerInCondition(i, TFCond_Cloaked)
				|| TF2_IsPlayerInCondition(i, TFCond_Stealthed)) {
			continue;
		}
		
		float vecTargetOrigin[3];
		GetClientAbsOrigin(i, vecTargetOrigin);
		if (GetVectorDistance(vecBuffOrigin, vecTargetOrigin, true) > flRadiusSq) {
			continue;
		}
		
		/** 
		 * TODO maybe split this off into a custom buff handler in the future, but we'll worry
		 * about that if I have to do more of these
		 */
		
		// the game internally does this
		TF2_AddCondition(i, TFCond_MarkedForDeath, 1.2, client);
		TF2_AddCondition(i, TFCond_Kritzkrieged, 1.2, client);
		
		// there is a player_buff event we could implement but it shouldn't really matter
	}
	
	return MRES_Supercede;
}

TFTeam TF2_GetDisguiseTeam(int client) {
	return view_as<TFTeam>(GetEntProp(client, Prop_Send, "m_nDisguiseTeam"));
}

static int GetClientFromPlayerShared(Address pPlayerShared) {
	Address pOuter = view_as<Address>(LoadFromAddress(
			pPlayerShared + g_offset_CTFPlayerShared_pOuter, NumberType_Int32));
	return GetEntityFromAddress(pOuter);
}

static int GetEntityFromAddress(Address pEntity) {
	return SDKCall(g_SDKCallGetBaseEntity, pEntity);
}

static bool IsWeaponBuffItem(int weapon) {
	if (!IsValidEntity(weapon)) {
		return false;
	}
	
	char className[64];
	GetEntityClassname(weapon, className, sizeof(className));
	
	return StrEqual(className, "tf_weapon_buff_item");
}
