/**
 * [TF2CA] Attribute: Rage Meter Scaling
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required
#include <tf_custom_attributes>
#include <stocksoup/log_server>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Rage Meter Nultiplier",
	author = "nosoop",
	description = "Scales the amount of rage gained from damage",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop"
}

Handle g_SDKCallGetBaseEntity;
Handle g_DHookOnModifyRage;

static Address g_offset_CTFPlayerShared_pOuter;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.ca_rage_meter_mult");
	
	g_DHookOnModifyRage = DHookCreateFromConf(hGameConf, "CTFPlayerShared::ModifyRage()");
	
	DHookEnableDetour(g_DHookOnModifyRage, false, OnModifyRagePre);
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::GetBaseEntity()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallGetBaseEntity = EndPrepSDKCall();
	
	g_offset_CTFPlayerShared_pOuter =
			view_as<Address>(GameConfGetOffset(hGameConf, "CTFPlayerShared::m_pOuter"));
	
	delete hGameConf;
}

public MRESReturn OnModifyRagePre(Address pPlayerShared, Handle hParams) {
	Address pOuter = view_as<Address>(LoadFromAddress(
			pPlayerShared + g_offset_CTFPlayerShared_pOuter, NumberType_Int32));
	int client = GetEntityFromAddress(pOuter);
	
	int hSecondary = GetPlayerWeaponSlot(client, 1);
	
	LogServer("updating rage");
	
	if (!IsValidEntity(hSecondary)) {
		return MRES_Ignored;
	}
	
	char className[64];
	GetEntityClassname(hSecondary, className, sizeof(className));
	
	if (!StrEqual(className, "tf_weapon_buff_item")) {
		return MRES_Ignored;
	}
	
	KeyValues attributes = TF2CustAttr_GetAttributeKeyValues(hSecondary);
	if (!attributes) {
		return MRES_Ignored;
	}
	
	float flMultiplier = attributes.GetFloat("banner rage fill multiplier", 1.0);
	delete attributes;
	
	if (flMultiplier == 1.0) {
		return MRES_Ignored;
	}
	
	
	float flDelta = DHookGetParam(hParams, 1);
	LogServer("orig delta: %.4f", flDelta);
	DHookSetParam(hParams, 1, flDelta * flMultiplier);
	return MRES_ChangedHandled;
}

int GetEntityFromAddress(Address pEntity) {
	return SDKCall(g_SDKCallGetBaseEntity, pEntity);
}
