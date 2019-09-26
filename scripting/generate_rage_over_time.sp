#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#include <tf_custom_attributes>

// other meters have a range of [0, 1], so this is pretty unusual
#define RAGE_FULL_AMOUNT 100.0

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

// TODO cache rage generation attribute value on custattr's side
public void OnClientPostThinkPost(int client) {
	float flRageMeter = GetEntPropFloat(client, Prop_Send, "m_flRageMeter");
	bool bRageDraining = !!GetEntProp(client, Prop_Send, "m_bRageDraining");
	
	if (bRageDraining || flRageMeter >= 100.0) {
		return;
	}
	
	for (int i; i < 3 && flRageMeter < 100.0; i++) {
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		float flRageOverTime = TF2CustAttr_GetFloat(weapon, "generate rage over time", 0.0);
		if (!flRageOverTime) {
			continue;
		}
		
		// rage is to 100
		flRageMeter += (GetGameFrameTime() / flRageOverTime) * 100.0;
	}
	SetEntPropFloat(client, Prop_Send, "m_flRageMeter", flRageMeter);
}
