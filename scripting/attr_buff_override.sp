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

#define CUSTOM_SOLDIER_BUFF_MAX_NAME_LENGTH 64

Handle g_SDKCallGetBaseEntity;
Handle g_DHookOnModifyRage;

static Address g_offset_CTFPlayerShared_pOuter;

StringMap g_BuffForwards; // <callback>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("cattr-buff-override");
	
	CreateNative("TF2CustomAttrRageBuff_Register", RegisterCustomBuff);
}

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
	
	g_BuffForwards = new StringMap();
}

public int RegisterCustomBuff(Handle plugin, int argc) {
	char buffName[CUSTOM_SOLDIER_BUFF_MAX_NAME_LENGTH];
	GetNativeString(1, buffName, sizeof(buffName));
	if (!buffName[0]) {
		ThrowNativeError(1, "Cannot have an empty buff name.");
	}
	
	Handle hFwd;
	if (!g_BuffForwards.GetValue(buffName, hFwd)) {
		hFwd = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_String);
		g_BuffForwards.SetValue(buffName, hFwd);
	}
	AddToForward(hFwd, plugin, GetNativeFunction(2));
}

public MRESReturn OnPulseRageBuffPre(Address pPlayerShared, Handle hParams) {
	int client = GetClientFromPlayerShared(pPlayerShared);
	
	// check for buff banner-like
	int hSecondary = GetPlayerWeaponSlot(client, 1);
	if (!IsWeaponBuffItem(hSecondary)) {
		return MRES_Ignored;
	}
	
	char buffName[CUSTOM_SOLDIER_BUFF_MAX_NAME_LENGTH];
	if (!TF2CustAttr_GetString(hSecondary, "custom soldier buff type",
			buffName, sizeof(buffName))) {
		return MRES_Ignored;
	}
	
	Handle hFwd;
	if (!g_BuffForwards.GetValue(buffName, hFwd) || !GetForwardFunctionCount(hFwd)) {
		LogError("Buff type '%s' is not associated with a plugin", buffName);
		return MRES_Supercede;
	}
	
	float flRadiusSq = Pow(SOLDIER_BUFF_RADIUS, 2.0);
	// TODO there is a mod_soldier_buff_range attribute class but it's not present in items_game
	
	float vecBuffOrigin[3];
	GetClientAbsOrigin(client, vecBuffOrigin);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientConnected(i) || !IsPlayerAlive(i)) {
			continue;
		}
		
		float vecTargetOrigin[3];
		GetClientAbsOrigin(i, vecTargetOrigin);
		if (GetVectorDistance(vecBuffOrigin, vecTargetOrigin, true) > flRadiusSq) {
			continue;
		}
		
		Call_StartForward(hFwd);
		Call_PushCell(client);
		Call_PushCell(i);
		Call_PushString(buffName);
		Call_Finish();
		
		// there is a player_buff event we could implement but it shouldn't really matter
	}
	
	return MRES_Supercede;
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
