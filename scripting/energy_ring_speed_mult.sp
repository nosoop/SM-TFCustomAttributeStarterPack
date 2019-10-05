#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#include <tf_custom_attributes>

public void OnEntityCreated(int entity, const char[] className) {
	if (StrEqual(className, "tf_projectile_energy_ring")) {
		RequestFrame(EnergyRingPostSpawnPost, EntIndexToEntRef(entity));
	}
}

public void EnergyRingPostSpawnPost(int entref) {
	if (!IsValidEntity(entref)) {
		return;
	}
	
	int weapon = GetEntPropEnt(entref, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(weapon)) {
		return;
	}
	
	// we should implement this as a TF2Attributes HookValueFloat(mult_projectile_speed) later
	float flSpeedModifier = TF2CustAttr_GetFloat(weapon, "mult energy ring speed", 1.0);
	if (flSpeedModifier == 1.0) {
		return;
	}
	
	float vecVelocity[3];
	GetEntPropVector(entref, Prop_Data, "m_vecAbsVelocity", vecVelocity);
	
	// the pomson starts to break down around 3600HU/s (3x speed)
	ScaleVector(vecVelocity, flSpeedModifier);
	TeleportEntity(entref, NULL_VECTOR, NULL_VECTOR, vecVelocity);
}
