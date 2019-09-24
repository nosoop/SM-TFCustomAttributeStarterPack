/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/weapon>
#include <tf_custom_attributes>
#include <tf2attributes>

Handle g_SDKCallFireEnergyBall;
Handle g_SDKCallGetProjectileFireSetup;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtBaseGunFireProjectile = DHookCreateFromConf(hGameConf,
			"CTFWeaponBaseGun::FireProjectile()");
	DHookEnableDetour(dtBaseGunFireProjectile, false, OnBaseGunFireProjectilePre);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFWeaponBaseGun::FireEnergyBall()");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallFireEnergyBall = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CTFWeaponBase::GetProjectileFireSetup()");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	{
		// work around SM1.10 bug #1059
		// https://github.com/alliedmodders/sourcemod/issues/1059
		// PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByValue);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer,
			.encflags = VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_Pointer,
			.encflags = VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallGetProjectileFireSetup = EndPrepSDKCall();
	
	delete hGameConf;
}

public MRESReturn OnBaseGunFireProjectilePre(int weapon, Handle hParams) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	char buffer[128];
	if (!TF2CustAttr_GetString(weapon, "override projectile energy ball",
			buffer, sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	int clip = GetEntProp(weapon, Prop_Data, "m_iClip1");
	if (!clip) {
		return MRES_Supercede;
	}
	
	// refer to CTFWeaponBaseGun::FireRocket()
	// CTFWeaponBaseGun::FireEnergyBall has wrong offsets (shoots from left)
	float vecOffset[3], vecSrc[3];
	vecOffset[0] = 23.5;
	vecOffset[1] = 12.0;
	vecOffset[2] = GetEntityFlags(owner) & FL_DUCKING? 8.0 : -3.0;
	
	float angBaseAim[3], vecFwdBaseAim[3];
	SDKCall(g_SDKCallGetProjectileFireSetup, weapon, owner, vecOffset[0], vecOffset[1],
			vecOffset[2], vecSrc, angBaseAim, false, 1100.0);
	GetAngleVectors(angBaseAim, vecFwdBaseAim, NULL_VECTOR, NULL_VECTOR);
	
	ScaleVector(vecFwdBaseAim, 1100.0 * GetProjectileSpeedMultiplier(weapon));
	
	// base damage is based on weapon
	int energyBall = SDKCall(g_SDKCallFireEnergyBall, weapon, owner, false);
	TeleportEntity(energyBall, vecSrc, angBaseAim, vecFwdBaseAim);
	
	SetEntProp(weapon, Prop_Data, "m_iClip1", clip - 1);
	
	// TF2_SetWeaponAmmo(weapon, TF2_GetWeaponAmmo(weapon) - 1);
	return MRES_Supercede;
}

float GetProjectileSpeedMultiplier(int weapon) {
	// preferably we'd use applyattributefloat or whatever, but this is what we've got for now
	float result = 1.0;
	
	Address pAttribute;
	if (!!(pAttribute = TF2Attrib_GetByName(weapon, "Projectile speed increased"))) {
		result *= TF2Attrib_GetValue(pAttribute);
	}
	
	if (!!(pAttribute = TF2Attrib_GetByName(weapon, "Projectile speed decreased"))) {
		result *= TF2Attrib_GetValue(pAttribute);
	}
	
	if (!!(pAttribute = TF2Attrib_GetByName(weapon, "Projectile speed increased HIDDEN"))) {
		result *= TF2Attrib_GetValue(pAttribute);
	}
	
	return result;
}
