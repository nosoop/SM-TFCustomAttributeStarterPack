/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#include <smlib/clients>

#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>

#pragma newdecls required

Handle g_DHookPerformPileOfDesperateGameSpecificFootstepHacks;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookPerformPileOfDesperateGameSpecificFootstepHacks =
			DHookCreateFromConf(hGameConf, "CBasePlayer::OnEmitFootstepSound()");
	
	delete hGameConf;
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	DHookEntity(g_DHookPerformPileOfDesperateGameSpecificFootstepHacks, true, client,
			.callback = OnEmitFootstepSound);
}

MRESReturn OnEmitFootstepSound(int client, Handle hParams) {
	if (IsFakeClient(client)) {
		return MRES_Ignored;
	}
	
	int activeWeapon = TF2_GetClientActiveWeapon(client);
	if (!IsValidEntity(activeWeapon)) {
		return MRES_Ignored;
	}
	
	/**
	 * check attribute, then client, then iterate over other weapons
	 * varstrings + iteration aren't a good mix since I CBA to scale it but whatever
	 */
	char attr[128];
	if (!TF2CustAttr_GetString(activeWeapon, "shake on step", attr, sizeof(attr))
			&& !TF2CustAttr_GetString(client, "shake on step", attr, sizeof(attr))) {
		for (int slot = TFWeaponSlot_Primary; slot <= TFWeaponSlot_Melee && !attr[0]; slot++) {
			int holsteredWeapon = GetPlayerWeaponSlot(client, slot);
			if (!IsValidEntity(holsteredWeapon) || holsteredWeapon == activeWeapon) {
				continue;
			}
			TF2CustAttr_GetString(holsteredWeapon, "shake on step", attr, sizeof(attr));
		}
		if (!attr[0]) {
			return MRES_Ignored;
		}
	}
	
	float amplitude = ReadFloatVar(attr, "amplitude", 20.0);
	float frequency = ReadFloatVar(attr, "frequency", 10.0);
	float radius = ReadFloatVar(attr, "range", 1024.0);
	
	float origin[3];
	GetClientAbsOrigin(client, origin);
	
	ScreenShake(origin, amplitude, frequency, 1.0, radius);
	return MRES_Ignored;
}

void ScreenShake(const float center[3], float amplitude, float frequency, float duration,
		float radius) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		float targetOrigin[3];
		GetClientAbsOrigin(i, targetOrigin);
		
		float distfactor = (radius - GetVectorDistance(center, targetOrigin, false)) / radius;
		if (distfactor < 0.0) {
			continue;
		}
		
		Client_Shake(i, .amplitude = amplitude * distfactor, .frequency = frequency,
				.duration = duration);
	}
}
