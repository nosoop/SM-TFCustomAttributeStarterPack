/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <tf_custom_attributes>

#pragma newdecls required

#include <stocksoup/var_strings>
#include <stocksoup/tf/tempents_stocks>

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Medigun Uber: Group Overheal",
	author = "Author!",
	description = "Description!",
	version = PLUGIN_VERSION,
	url = "localhost"
}

#define DISPENSER_RANGE 64.0

Handle g_SDKCallFindEntityInSphere, g_SDKCallPlayerSharedStartHealing,
		g_SDKCallPlayerSharedStopHealing;
ArrayList g_RadiusHealRecipients[MAXPLAYERS + 1];

float g_flLastHealthParticleDisplayTime[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.ca_group_overheal");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.ca_group_overheal).");
	}
	
	StartPrepSDKCall(SDKCall_EntityList);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CGlobalEntityList::FindEntityInSphere()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer,
			VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayerShared::Heal()");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // inflictor entity
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); // float ??
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); // float ??
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); // float ??
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain); // bool dispenser ??
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer); // healing player
	g_SDKCallPlayerSharedStartHealing = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayerShared::StopHealing()");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallPlayerSharedStopHealing = EndPrepSDKCall();
	
	delete hGameConf;
}

public void OnMapStart() {
	for (int i; i < MAXPLAYERS + 1; i++) {
		delete g_RadiusHealRecipients[i];
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
		g_RadiusHealRecipients[i] = new ArrayList();
	}
}

public void OnClientPutInServer(int client) {
	g_flLastHealthParticleDisplayTime[client] = 0.0;
	SDKHook(client, SDKHook_PostThinkPost, OnPlayerPostThinkPost);
}

public void OnPlayerPostThinkPost(int client) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (!IsUberchargeDeployed(hActiveWeapon)) {
		// stop healing all players in g_RadiusHealRecipients[client] if there are any
		while (g_RadiusHealRecipients[client].Length) {
			int target = GetClientFromSerial(g_RadiusHealRecipients[client].Get(0));
			if (target) {
				StopHealing(target, GetPlayerWeaponSlot(client, 1));
			}
			g_RadiusHealRecipients[client].Erase(0);
		}
		return;
	}
	
	float flHealRange, flHealRate, flOverhealRatio, flOverhealTimeScale;
	bool bFixedHealRate;
	
	// not the correct medigun
	if (!IsGroupOverhealMedigun(hActiveWeapon, flHealRate, flOverhealRatio, flOverhealTimeScale,
			bFixedHealRate, flHealRange)) {
		return;
	}
	
	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);
	
	TFTeam team = TF2_GetClientTeam(client);
	
	// radius check to see which friendly players are in range
	bool bInGroupOverhealRange[MAXPLAYERS + 1];
	int target = -1;
	while ((target = FindEntityInSphere(target, vecOrigin, flHealRange)) != -1) {
		// TODO check for disguised players
		if (target > 0 && target <= MaxClients && TF2_GetClientVisibleTeam(target) == team) {
			bInGroupOverhealRange[target] = true;
		}
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		
		int iHealRecipientIndex =
				g_RadiusHealRecipients[client].FindValue(GetClientSerial(i));
		bool bIsKnownHealRecipient = iHealRecipientIndex != -1;
		
		if (bInGroupOverhealRange[i] && g_flLastHealthParticleDisplayTime[i] < GetGameTime()) {
			float vecParticleOrigin[3];
			GetClientEyePosition(i, vecParticleOrigin);
			vecParticleOrigin[2] += 32.0;
			
			TE_SetupTFParticleEffect(TF2_GetClientVisibleTeam(i) == TFTeam_Red?
					"healthgained_red_giant" : "healthgained_blu_giant", vecParticleOrigin,
					.entity = i, .attachType = PATTACH_CUSTOMORIGIN);
			TE_SendToAll();
			g_flLastHealthParticleDisplayTime[i] = GetGameTime() + 0.5;
		}
		
		// not a new state
		if (bInGroupOverhealRange[i] == bIsKnownHealRecipient) {
			continue;
		}
		
		switch (bInGroupOverhealRange[i]) {
			case true: {
				// in range now, add healer
				g_RadiusHealRecipients[client].Push(GetClientSerial(i));
				StartHealing(i, hActiveWeapon, client, flHealRate, flOverhealRatio,
						flOverhealTimeScale, bFixedHealRate);
			}
			case false: {
				// not in range anymore, remove healer
				g_RadiusHealRecipients[client].Erase(iHealRecipientIndex);
				StopHealing(i, hActiveWeapon);
			}
		}
	}
}

TFTeam TF2_GetClientVisibleTeam(int client) {
	return TF2_IsPlayerInCondition(client, TFCond_Disguised)?
			view_as<TFTeam>(GetEntProp(client, Prop_Send, "m_nDisguiseTeam"))
			: TF2_GetClientTeam(client);
}

bool IsUberchargeDeployed(int weapon) {
	if (!IsValidEntity(weapon)
			|| !HasEntProp(weapon, Prop_Send, "m_bChargeRelease")) {
		return false;
	}
	
	return !!GetEntProp(weapon, Prop_Send, "m_bChargeRelease");
}

bool IsGroupOverhealMedigun(int weapon, float &flHealRate = 0.0, float &flOverhealRatio = 0.0,
		float &flOverhealTimeScale = 0.0, bool &bFixedHealing = false,
		float &flHealRange = 0.0) {
	KeyValues attributes = TF2CustAttr_GetAttributeKeyValues(weapon);
	if (!attributes) {
		return false;
	}
	
	char attr[256];
	attributes.GetString("medigun charge is group overheal", attr, sizeof(attr));
	delete attributes;
	
	if (!attr[0]) {
		return false;
	}
	
	flHealRange = ReadFloatVar(attr, "range", DISPENSER_RANGE * 5.0);
	flHealRate = ReadFloatVar(attr, "heal_rate", 30.0);
	flOverhealRatio = ReadFloatVar(attr, "overheal_ratio", 1.5);
	flOverhealTimeScale = ReadFloatVar(attr, "overheal_duration_mult", 2.0);
	bFixedHealing = !!ReadIntVar(attr, "fixed_heal_rate", true);
	
	return true;
}

int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius);
}

/**
 * 
 * @param target				The client that is receiving healing.
 * @param inflictor				The entity providing the healing (e.g., Dispenser, Medigun).
 * @param healer				The client that is providing healing.
 * @param flHealRate			Base amount of healing per second.
 * @param flOverhealRatio		Determines the multiplier of maximum health that this heal is
 * 								allowed to heal to.
 * @param flOverhealTimeMult	Rate at which overhealed health decays, as a time scalar (i.e.,
 * 								larger numbers mean longer overheal time and slower decay).
 * @param bFixedHealRate		Determines if the heal rate is boosted if the player wasn't in
 * 								combat recently.
 */
void StartHealing(int target, int inflictor, int healer, float flHealRate,
		float flOverhealRatio, float flOverhealDecayRate, bool bFixedHealRate) {
	SDKCall(g_SDKCallPlayerSharedStartHealing, GetPlayerSharedPointer(target), inflictor,
			flHealRate, flOverhealRatio, flOverhealDecayRate, bFixedHealRate, healer);
}

void StopHealing(int target, int inflictor) {
	SDKCall(g_SDKCallPlayerSharedStopHealing, GetPlayerSharedPointer(target), inflictor);
}

Address GetPlayerSharedPointer(int client) {
	if (!IsClientInGame(client)) {
		ThrowError("Invalid client entity");
	}
	int sharedoffs = FindSendPropInfo("CTFPlayer", "m_Shared");
	return GetEntityAddress(client) + view_as<Address>(sharedoffs);
}
