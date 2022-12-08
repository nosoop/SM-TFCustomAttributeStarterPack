#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>

#pragma newdecls required

#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>
#include <tf_custom_attributes>

Handle g_SDKCallFindEntityInSphere;
Handle g_SDKCallGetCombatCharacterPtr;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	StartPrepSDKCall(SDKCall_EntityList);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CGlobalEntityList::FindEntityInSphere()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer,
			VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CBaseEntity::MyCombatCharacterPointer()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallGetCombatCharacterPtr = EndPrepSDKCall();
	
	delete hGameConf;
}

public void OnEntityDestroyed(int entity) {
	if (!IsValidEntity(entity) || !IsValidEdict(entity)) {
		return;
	}
	
	char className[64];
	GetEntityClassname(entity, className, sizeof(className));
	if (!StrEqual(className, "tf_projectile_energy_ring")) {
		return;
	}
	
	int owner = TF2_GetEntityOwner(entity);
	if (!IsValidEntity(owner)) {
		return;
	}
	
	int weapon = GetEntPropEnt(entity, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	float flKillRadius =
			TF2CustAttr_GetFloat(weapon, "energy ring instakill radius on destroy");
	if (!flKillRadius) {
		return;
	}
	
	float vecDestroy[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vecDestroy);
	
	int rangeEntity = -1;
	while ((rangeEntity = FindEntityInSphere(rangeEntity, vecDestroy, flKillRadius)) != -1) {
		if (IsEntityCombatCharacter(rangeEntity) && rangeEntity != owner) {
			SDKHooks_TakeDamage(rangeEntity, entity, owner, 31337.0,
					DMG_BULLET | DMG_PREVENT_PHYSICS_FORCE, weapon);
		}
	}
}

static int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius, Address_Null);
}

static bool IsEntityCombatCharacter(int entity) {
	return SDKCall(g_SDKCallGetCombatCharacterPtr, entity) != Address_Null;
}
