#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#include <tf_custom_attributes>

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3],
		int damagecustom) {
	if (attacker < 1 || attacker >= MaxClients || !IsValidEntity(weapon)) {
		return;
	}
	
	// value is a multiplier on 90 degrees
	float mult = ClampFloat(TF2CustAttr_GetFloat(weapon, "disorient on hit"), 0.0, 1.0);
	if (mult == 0.0) {
		return;
	}
	
	float ang = mult * 90.0;
	
	float angEye[3];
	GetClientEyeAngles(victim, angEye);
	
	// pitch: enusre full range of deviation by preclamping for range
	angEye[0] = ClampFloat(angEye[0], -90.0 + ang, 90.0 - ang);
	angEye[0] = angEye[0] + GetRandomFloat(-ang, ang);
	
	// yaw: ensure angle is within [-180, 180)
	angEye[1] = NormalizeAngle(angEye[1] + GetRandomFloat(-ang, ang));
	
	TeleportEntity(victim, NULL_VECTOR, angEye, NULL_VECTOR);
}

stock float ClampFloat(float value, float min, float max) {
	if (value > max) {
		return max;
	} else if (value < min) {
		return min;
	}
	return value;
}

// https://stackoverflow.com/a/43780476
stock float NormalizeAngle(float value) {
	return value - 360.0 * RoundToFloor((value + 180.0) / 360.0);
}
