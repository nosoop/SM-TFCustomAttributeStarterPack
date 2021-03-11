/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>

#pragma newdecls required

#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>
#include <tf_custom_attributes>

#include <smlib/clients>

#define SOUND_WUNDERWAFFE_IMPACT "weapons/physcannon/energy_disintegrate5.wav"

public void OnMapStart() {
	AddFileToDownloadsTable("sound/" ... SOUND_WUNDERWAFFE_IMPACT);
	PrecacheSound(SOUND_WUNDERWAFFE_IMPACT);
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
	
	char attr[64];
	if (!TF2CustAttr_GetString(weapon, "energy ring impact effect on destroy",
			attr, sizeof(attr))) {
		return;
	}
	
	
	float vecDestroy[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vecDestroy);
	
	EmitSoundToAll(SOUND_WUNDERWAFFE_IMPACT, entity, .level = SNDLEVEL_MINIBIKE);
	
	float flShakeRadius = ReadFloatVar(attr, "radius");
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}
		
		float vecClientOrigin[3];
		GetClientAbsOrigin(i, vecClientOrigin);
		if (GetVectorDistance(vecClientOrigin, vecDestroy) > flShakeRadius) {
			continue;
		}
		
		Client_Shake(i,
				.amplitude = ReadFloatVar(attr, "amplitude"),
				.frequency = ReadFloatVar(attr, "frequency"),
				.duration = ReadFloatVar(attr, "duration"));
	}
}
