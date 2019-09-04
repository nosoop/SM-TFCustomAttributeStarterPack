#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdkhooks>
#include <tf2_stocks>
#include <stocksoup/math>
#include <stocksoup/tf/entity_prop_stocks>

#include <tf_custom_attributes>
#include <tf_cattr_buff_override>

#include <stocksoup/log_server>

float g_flAimingControlEndTime[MAXPLAYERS + 1];
float g_flAimingControlTurnRate[MAXPLAYERS + 1];

public void OnCustomBuffHandlerAvailable() {
	TF2CustomAttrRageBuff_Register("rocket-aiming-control", OnRocketControlPulse);
}

public void OnPluginStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flAimingControlEndTime[client] = 0.0;
}

public void OnGameFrame() {
	int rocket = -1;
	while ((rocket = FindEntityByClassname(rocket, "tf_projectile_rocket")) != -1) {
		HomingRocketThink(rocket);
	}
	// TODO futureproof against other rocket classes??
	while ((rocket = FindEntityByClassname(rocket, "tf_projectile_energy_ball")) != -1) {
		HomingRocketThink(rocket);
	}
}

void HomingRocketThink(int rocket) {
	// compute tweening for aim position
	int launcher = GetEntPropEnt(rocket, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(launcher)) {
		return;
	}
	
	int owner = TF2_GetEntityOwner(launcher);
	if (owner < 1 || owner > MaxClients) {
		return;
	}
	
	if (GetGameTime() > g_flAimingControlEndTime[owner]) {
		return;
	}
	
	float vecRocketPosition[3], vecDesiredPosition[3];
	ComputeAimPoint(owner, vecDesiredPosition);
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsOrigin", vecRocketPosition);
	
	// compute desired location
	float vecCurrentVelocity[3], vecDesiredVelocity[3];
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", vecCurrentVelocity);
	
	float flCurrentSpeed = NormalizeVector(vecCurrentVelocity, vecCurrentVelocity);
	
	// this is where the rocket should be going
	MakeVectorFromPoints(vecRocketPosition, vecDesiredPosition, vecDesiredVelocity);
	NormalizeVector(vecDesiredVelocity, vecDesiredVelocity);
	
	// controls turning rate
	for (int i; i < 3; i++) {
		vecCurrentVelocity[i] = LerpFloat(g_flAimingControlTurnRate[owner],
				vecCurrentVelocity[i], vecDesiredVelocity[i]);
	}
	NormalizeVector(vecCurrentVelocity, vecCurrentVelocity);
	ScaleVector(vecCurrentVelocity, flCurrentSpeed);
	
	SetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", vecCurrentVelocity);
	
	float angVelocity[3];
	GetVectorAngles(vecCurrentVelocity, angVelocity);
	TeleportEntity(rocket, NULL_VECTOR, angVelocity, NULL_VECTOR);
}

public void OnRocketControlPulse(int owner, int target, const char[] name, int buffItem) {
	// only apply to self
	if (target != owner) {
		return;
	}
	
	g_flAimingControlEndTime[target] = GetGameTime() + BUFF_PULSE_CONDITION_DURATION;
	g_flAimingControlTurnRate[target] = TF2CustAttr_GetFloat(buffItem,
			"rocket control buff turn rate", 1.0);
}

void ComputeAimPoint(int client, float vecAimPoint[3]) {
	// TODO optimization: compute aim point once per client before OnGameFrame
	
	float angEye[3], vecStartPosition[3];
	GetClientEyePosition(client, vecStartPosition);
	GetClientEyeAngles(client, angEye);
	
	Handle trace = TR_TraceRayFilterEx(vecStartPosition, angEye, MASK_SHOT, RayType_Infinite,
			TraceEntityFilterPlayer);
	if (TR_DidHit(trace)) {
		float vecEndPosition[3];
		TR_GetEndPosition(vecEndPosition, trace);
		float flDistance = GetVectorDistance(vecStartPosition, vecEndPosition, false) - 10.0;
		GetAngleVectors(angEye, vecAimPoint, NULL_VECTOR, NULL_VECTOR);
		
		ScaleVector(vecAimPoint, flDistance);
		AddVectors(vecStartPosition, vecAimPoint, vecAimPoint);
	}
	delete trace;
}

// hit non-player entities
public bool TraceEntityFilterPlayer(int entity, int contentsMask) {
	return entity > MaxClients || !entity;
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-buff-override")) {
		OnCustomBuffHandlerAvailable();
	}
}

// unused lol
stock void PointOnLineNearestPoint(const float vecStartPos[3], const float vecEndPos[3],
		const float vecPoint[3], bool clampEnds, float vecIntersectPos[3]) {
	float vecEndToStart[3], vecOrgToStart;
	SubtractVectors(vecEndPos, vecStartPos);
	SubtractVectors(vecPoint, vecStartPos);
	
	float flNumerator = GetVectorDotProduct(vecEndToStart, vecOrgToStart);
	float flDenominator = GetVectorLength(vecEndToStart) * GetVectorLength(vecOrgToStart);
	float flIntersectDist = GetVectorLength(vecOrgToStart) * (flNumerator / flDenominator);
	float flLineLength = NormalizeVector(vecEndToStart);
	
	if (clampEnds) {
		if (flIntersectDist > flLineLength) {
			flIntersectDist = flLineLength;
		} else if (flIntersectDist < 0.0) {
			flIntersectDist = 0.0;
		}
	}
	
	ScaleVector(vecEndToStart, flIntersectDist);
	AddVectors(vecStartPos, vecEndToStart, vecIntersectPos);
}
