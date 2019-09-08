/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

Handle g_SDKCallInitGrenade;
Handle g_SDKCallIsEntityWeapon;
Handle g_DHookSecondaryAttack;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::IsBaseCombatWeapon()");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_SDKCallIsEntityWeapon = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CTFWeaponBaseGrenadeProj::InitGrenade(int float)");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallInitGrenade = EndPrepSDKCall();
	
	g_DHookSecondaryAttack = DHookCreateFromConf(hGameConf,
			"CBaseCombatWeapon::SecondaryAttack()");
	
	delete hGameConf;
}

public void OnEntityCreated(int entity, const char[] className) {
	if (entity && IsEntityWeapon(entity)) {
		DHookEntity(g_DHookSecondaryAttack, false, entity, .callback = OnSecondaryAttackPre);
	}
}

public MRESReturn OnSecondaryAttackPre(int weapon) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	if (GetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack") > GetGameTime()) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "alt fire throws cleaver", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	float speed = ReadFloatVar(attr, "velocity", 3000.0);
	ThrowCleaver(owner, speed);
	
	SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack", GetGameTime() + 5.0);
	return MRES_Ignored;
}

// mostly gleaned from CTFJar::TossJarThink()
// 
void ThrowCleaver(int client, float flSpeed = 3000.0) {
	float angEyes[3], vecEyePosition[3];
	GetClientEyeAngles(client, angEyes);
	GetClientEyePosition(client, vecEyePosition);
	
	float vecAimForward[3], vecAimUp[3], vecAimRight[3];
	GetAngleVectors(angEyes, vecAimForward, vecAimRight, vecAimUp);
	
	float vecVelocity[3], vecAngImpulse[3];
	GetCleaverVelocityVector(vecVelocity, vecAimForward, vecAimRight, vecAimUp);
	GetCleaverAngularImpulse(vecAngImpulse);
	
	NormalizeVector(vecVelocity, vecVelocity);
	ScaleVector(vecVelocity, flSpeed);
	
	int cleaver = CreateEntityByName("tf_projectile_cleaver");
	
	// it is important that teleporting happens before dispatch otherwise spawn angles are wrong
	TeleportEntity(cleaver, vecEyePosition, angEyes, NULL_VECTOR);
	DispatchSpawn(cleaver);
	
	// use for physics logic
	SDKCall(g_SDKCallInitGrenade, cleaver, vecVelocity, vecAngImpulse, client, 0, 5.0);
}

// CTFCleaver::GetVelocityVector()
void GetCleaverVelocityVector(float velocity[3], const float vecForward[3],
		const float vecRight[3], const float vecUp[3]) {
	float vecResult[3];
	vecResult = vecForward;
	ScaleVector(vecResult, 10.0);
	AddVectors(vecResult, vecUp, vecResult);
	NormalizeVector(vecResult, velocity);
	ScaleVector(velocity, 3000.0);
	#pragma unused vecRight
}

// CTFCleaver::GetAngularImpulse()
void GetCleaverAngularImpulse(float vecAngImpulse[3]) {
	vecAngImpulse[0] = 0.0;
	vecAngImpulse[1] = 500.0;
	vecAngImpulse[2] = 0.0;
}

bool IsEntityWeapon(int entity) {
	return SDKCall(g_SDKCallIsEntityWeapon, entity);
}
