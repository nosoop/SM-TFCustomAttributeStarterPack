#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <dhooks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>
#include <custom_status_hud>

Handle g_DHookPrimaryAttack;

float g_flFullClipRefillTime[MAXPLAYERS + 1][3];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_DHookPrimaryAttack = DHookCreateFromConf(hGameConf, "CTFWeaponBase::PrimaryAttack()");
	
	delete hGameConf;
	
	HookEvent("post_inventory_application", OnInventoryAppliedPost);
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "*")) != -1) {
		if (HasEntProp(entity, Prop_Data, "m_flNextPrimaryAttack")) {
			HookWeaponEntity(entity);
		}
	}
	
}

public void OnInventoryAppliedPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	for (int i; i < sizeof(g_flFullClipRefillTime[]); i++) {
		g_flFullClipRefillTime[client][i] = 0.0;
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

public void OnEntityCreated(int entity, const char[] className) {
	if (HasEntProp(entity, Prop_Data, "m_flNextPrimaryAttack")) {
		HookWeaponEntity(entity);
	}
}

void HookWeaponEntity(int weapon) {
	DHookEntity(g_DHookPrimaryAttack, true, weapon, .callback = OnWeaponPrimaryAttackPost);
}

public void OnClientPostThinkPost(int client) {
	if (!IsPlayerAlive(client)) {
		return;
	}
	
	for (int i; i < sizeof(g_flFullClipRefillTime[]); i++) {
		float flRefillTime = g_flFullClipRefillTime[client][i];
		if (!flRefillTime) {
			continue;
		}
		
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		if (GetGameTime() > flRefillTime) {
			FullRefillWeaponClip(weapon);
			EmitGameSoundToClient(client, "TFPlayer.ReCharged");
			g_flFullClipRefillTime[client][i] = 0.0;
		}
	}
}

public MRESReturn OnWeaponPrimaryAttackPost(int weapon) {
	int owner = TF2_GetEntityOwner(weapon);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	float flRefillTime = TF2CustAttr_GetFloat(weapon, "full clip refill after time");
	if (flRefillTime <= 0.0) {
		return MRES_Ignored;
	}
	
	int slot = TF2Util_GetWeaponSlot(weapon);
	if (slot < 0 || slot > sizeof(g_flFullClipRefillTime[])) {
		// TODO note that slot is invalid
		return MRES_Ignored;
	}
	
	float flNewRefillTime = GetGameTime() + flRefillTime;
	float flCurrentRefillTime = g_flFullClipRefillTime[owner][slot];
	if (!flCurrentRefillTime || flNewRefillTime < flCurrentRefillTime) {
		g_flFullClipRefillTime[owner][slot] = flNewRefillTime;
	}
	
	return MRES_Ignored;
}

void FullRefillWeaponClip(int weapon) {
	SetEntProp(weapon, Prop_Data, "m_iClip1", TF2Util_GetWeaponMaxClip(weapon));
}

public Action OnCustomStatusHUDUpdate(int client, StringMap entries) {
	bool changed;
	for (int i; i < sizeof(g_flFullClipRefillTime[]); i++) {
		float flNextRefillTime = g_flFullClipRefillTime[client][i];
		if (!flNextRefillTime || GetGameTime() > flNextRefillTime) {
			continue;
		}
		
		int weapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(weapon)) {
			continue;
		}
		
		char refillText[64];
		if (!TF2CustAttr_GetString(weapon, "full clip refill after time progress display",
				refillText, sizeof(refillText))) {
			// don't display text
			continue;
		}
		
		changed = true;
		
		float flRemainingTime = flNextRefillTime - GetGameTime();
		float flMaxRefillTime = TF2CustAttr_GetFloat(weapon, "full clip refill after time");
		
		char keyBuffer[16], buffer[64];
		Format(keyBuffer, sizeof(keyBuffer), "clip_slot_%d", i);
		Format(buffer, sizeof(buffer), "%s: %.0f%%", refillText,
				FloatAbs(1.0 - flRemainingTime / flMaxRefillTime) * 100.0);
		
		entries.SetString(keyBuffer, buffer);
	}
	return changed? Plugin_Changed : Plugin_Continue;
}
