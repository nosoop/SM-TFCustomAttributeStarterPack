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

#define SOUND_WUNDERWAFFE_IMPACT "weapons/wunderwaffe/wunderwaffe_projectile_impact.wav"

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

#define	SHAKE_START					0			// Starts the screen shake for all players within the radius.
#define	SHAKE_STOP					1			// Stops the screen shake for all players within the radius.
#define	SHAKE_AMPLITUDE				2			// Modifies the amplitude of an active screen shake for all players within the radius.
#define	SHAKE_FREQUENCY				3			// Modifies the frequency of an active screen shake for all players within the radius.
#define	SHAKE_START_RUMBLEONLY		4			// Starts a shake effect that only rumbles the controller, no screen effect.
#define	SHAKE_START_NORUMBLE		5			// Starts a shake that does NOT rumble the controller.

/**
 * Shakes a client's screen with the specified amptitude,
 * frequency & duration.
 * 
 * @param client		Client Index.
 * @param command		Shake Mode, use one of the SHAKE_ definitions.
 * @param amplitude		Shake magnitude/amplitude.
 * @param frequency		Shake noise frequency.
 * @param duration		Shake lasts this long.
 * @return				True on success, false otherwise.
 */
stock bool Client_Shake(int client, int command = SHAKE_START, float amplitude = 50.0,
		float frequency = 150.0, float duration = 3.0) {
	if (command == SHAKE_STOP) {
		amplitude = 0.0;
	} else if (amplitude <= 0.0) {
		return false;
	}
	
	Handle userMessage = StartMessageOne("Shake", client);
	
	if (!userMessage) {
		return false;
	}
	
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available
			&& GetUserMessageType() == UM_Protobuf) {
		PbSetInt(userMessage, "command", command);
		PbSetFloat(userMessage, "local_amplitude", amplitude);
		PbSetFloat(userMessage, "frequency", frequency);
		PbSetFloat(userMessage, "duration", duration);
	} else {
		BfWriteByte(userMessage, command);
		BfWriteFloat(userMessage, amplitude);
		BfWriteFloat(userMessage, frequency);
		BfWriteFloat(userMessage, duration);
	}
	EndMessage();
	return true;
}
