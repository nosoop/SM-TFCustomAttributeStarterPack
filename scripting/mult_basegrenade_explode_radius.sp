/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <tf_custom_attributes>

Handle g_SDKCallGetEnemy;
Handle g_DHookGrenadeGetDamageRadius;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookGrenadeGetDamageRadius = DHookCreateFromConf(hGameConf,
			"CBaseGrenade::GetDamageRadius()");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::GetEnemy()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallGetEnemy = EndPrepSDKCall();
	
	delete hGameConf;
}

public void OnEntityCreated(int entity, const char[] className) {
	// kludge to verify that the entity is a base grenade-like
	if (HasEntProp(entity, Prop_Send, "m_bDefensiveBomb")) {
		DHookEntity(g_DHookGrenadeGetDamageRadius, true, entity,
				.callback = OnGetGrenadeDamageRadiusPost);
	}
}

public MRESReturn OnGetGrenadeDamageRadiusPost(int grenade, Handle hReturn) {
	float flRadius = DHookGetReturn(hReturn);
	
	int originalLauncher = GetEntPropEnt(grenade, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(originalLauncher)) {
		return MRES_Ignored;
	}
	
	float flScale = TF2CustAttr_GetFloat(originalLauncher,
			"mult basegrenade explode radius", 1.0);
	if (IsValidEntity(GetEntityEnemy(grenade))) {
		// enemy is valid on direct hit
		flScale *= TF2CustAttr_GetFloat(originalLauncher,
				"mult basegrenade direct radius", 1.0);
	}
	if (flScale == 1.0) {
		return MRES_Ignored;
	}
	DHookSetReturn(hReturn, flRadius * flScale);
	return MRES_Override;
}

int GetEntityEnemy(int entity) {
	return SDKCall(g_SDKCallGetEnemy, entity);
}
