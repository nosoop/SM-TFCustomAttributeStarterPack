/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <dhooks>
#include <sdktools>
#include <tf_custom_attributes>

public Plugin myinfo = {
	name = "[TF2] Custom Attribute: Custom Ball Impact Effect",
	author = "nosoop",
	description = "Handler to create custom ball impact effects.",
	version = "1.0.0",
	url = "https://github.com/nosoop/SM-TFCustomAttributeStarterPack"
}

#define CUSTOM_BALL_IMPACT_EFFECT_MAX_NAME_LENGTH    64

Handle g_DHookApplyBallImpactEffect;

StringMap g_BallImpactEffectForwards;

int offs_CTFGrenadePipebombProjectile_flCreationTime;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("cattr-custom-ball");
	CreateNative("TF2CustomAttrBall_Register", RegisterCustomBallImpactEffect);
}

public void OnPluginStart() {
	GameData hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookApplyBallImpactEffect = DHookCreateFromConf(hGameConf,
			"CTFStunBall::ApplyBallImpactEffectOnVictim()");
	if (!g_DHookApplyBallImpactEffect) {
		SetFailState("Failed to create virtual hook "
				... "CTFStunBall::ApplyBallImpactEffectOnVictim()");
	}
	delete hGameConf;
	
	g_BallImpactEffectForwards = new StringMap();
	
	int offs_CTFGrenadePipebombProjectile_iType =
			FindSendPropInfo("CTFGrenadePipebombProjectile", "m_iType");
	if (offs_CTFGrenadePipebombProjectile_iType <= 0) {
		SetFailState("Could not determine offset for "
				... "CTFGrenadePipebombProjectile::m_flCreationTime");
	}
	
	offs_CTFGrenadePipebombProjectile_flCreationTime =
			offs_CTFGrenadePipebombProjectile_iType + 0x4;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_projectile_stun_ball")
			|| StrEqual(classname, "tf_projectile_ball_ornament")) {
		HookStunball(entity);
	}
}

void HookStunball(int entity) {
	DHookEntity(g_DHookApplyBallImpactEffect, false, entity, .callback = OnBallImpactEffectPre);
}

MRESReturn OnBallImpactEffectPre(int entity, Handle hParams) {
	int target = DHookGetParam(hParams, 1);
	
	if (!IsValidEntity(target)) {
		return MRES_Ignored;
	}
	
	int launcher = GetEntPropEnt(entity, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(launcher)) {
		return MRES_Ignored;
	}
	
	char attr[64];
	if (!TF2CustAttr_GetString(launcher, "custom ball impact effect", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	float flFlightTime = GetGameTime() - GetEntDataFloat(entity,
			offs_CTFGrenadePipebombProjectile_flCreationTime);
	
	HandleCustomBallImpact(target, entity, flFlightTime, attr);
	
#if defined _DEBUG
	char cname[64];
	GetEntityClassname(target, cname, sizeof(cname));
	PrintToServer("Impact on entity %d (%s), flight %f", entity, cname, flFlightTime);
#endif
	
	return MRES_Supercede;
}

int RegisterCustomBallImpactEffect(Handle plugin, int argc) {
	char buffName[CUSTOM_BALL_IMPACT_EFFECT_MAX_NAME_LENGTH];
	GetNativeString(1, buffName, sizeof(buffName));
	if (!buffName[0]) {
		ThrowNativeError(1, "Cannot have an empty custom ball impact effect name.");
	}
	
	PrivateForward hFwd;
	if (!g_BallImpactEffectForwards.GetValue(buffName, hFwd)) {
		hFwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Float, Param_String);
		g_BallImpactEffectForwards.SetValue(buffName, hFwd);
	}
	hFwd.AddFunction(plugin, GetNativeFunction(2));
}

void HandleCustomBallImpact(int target, int projectile, float flFlightTime,
		const char[] effectName) {
	PrivateForward hFwd;
	if (!g_BallImpactEffectForwards.GetValue(effectName, hFwd) || !hFwd.FunctionCount) {
		LogError("Custom ball impact effect '%s' is not associated with a plugin", effectName);
		return;
	}
	
	Call_StartForward(hFwd);
	Call_PushCell(target);
	Call_PushCell(projectile);
	Call_PushFloat(flFlightTime);
	Call_PushString(effectName);
	Call_Finish();
}
