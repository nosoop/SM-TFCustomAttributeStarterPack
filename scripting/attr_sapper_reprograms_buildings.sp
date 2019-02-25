/**
 * [TF2CA] Sapper Reprograms Buildings
 * 
 * Note:  This is unfit for production use.  Not all building team switch cases are covered.
 */
#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdkhooks>
#include <tf2_stocks>

#include <stocksoup/datapack>
#include <stocksoup/var_strings>
#include <stocksoup/tf/tempents_stocks>

#include <tf_custom_attributes>
#include <tf2_morestocks>

#pragma newdecls required
#include <stocksoup/log_server>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Sapper Building Reprogrammer",
	author = "nosoop",
	description = "Sapped buildings will be converted to the Spy's team if left unsapped.",
	version = PLUGIN_VERSION,
	url = "localhost"
}

ArrayList g_ConvertedBuildings;

static int offs_hBuilder, offs_hOwner;

Handle g_SDKChangeObjectTeam;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.ca_sapper_reprograms_buildings");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.ca_sapper_reprograms_buildings).");
	}
	
	Handle dtSentryFire = DHookCreateFromConf(hGameConf, "CObjectSentrygun::SentryThink()");
	DHookEnableDetour(dtSentryFire, false, OnSentryGunThinkPre);
	DHookEnableDetour(dtSentryFire, true, OnSentryGunThinkPost);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::ChangeTeam()");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKChangeObjectTeam = EndPrepSDKCall();
	
	delete hGameConf;
	
	HookEvent("player_sapped_object", OnObjectSapped);
	
	g_ConvertedBuildings = new ArrayList(2);
	
	offs_hBuilder = FindSendPropInfo("CBaseObject", "m_hBuilder");
	offs_hOwner = FindSendPropInfo("CBaseObject", "m_hOwnerEntity");
	if (offs_hBuilder == -1) {
		SetFailState("Could not find m_hBuilder for CBaseObject");
	}
}

public void OnMapStart() {
	g_ConvertedBuildings.Clear();
}

// contains temporary client index
static int s_ActualBuildingOwner;

/**
 * Overrides the builder on "reprogrammed" buildings only when the sentry is thinking.
 * This allows us to keep the building owner the same, while still granting kill credit to the
 * Spy (as the weapon handling sets the builder as the attacker and occurs during the think).
 * 
 * It's unfortunate that we have to do this scoped stuff, because ke::SaveAndSet and extension
 * detours handle this case in a much cleaner manner.
 */
public MRESReturn OnSentryGunThinkPre(int sentry) {
	s_ActualBuildingOwner = GetEntPropEnt(sentry, Prop_Send, "m_hBuilder");
	
	int newOwner = GetModifiedBuildingOwner(sentry);
	SetEntDataEnt2(sentry, offs_hBuilder, newOwner);
	SetEntDataEnt2(sentry, offs_hOwner, newOwner);
	
	return MRES_Ignored;
}

/**
 * Restores the actual builder on "reprogrammed" buildings.
 */
public MRESReturn OnSentryGunThinkPost(int sentry) {
	SetEntDataEnt2(sentry, offs_hBuilder, s_ActualBuildingOwner);
	SetEntDataEnt2(sentry, offs_hOwner, s_ActualBuildingOwner);
	
	s_ActualBuildingOwner = INVALID_ENT_REFERENCE;
	return MRES_Ignored;
}

/**
 * Called when an object is sapped; checks if we should be setting up the reprogrammer.
 */
public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int sapperattach = event.GetInt("sapperid");
	
	if (!IsValidEntity(sapperattach)) {
		return;
	}
	
	// TODO create proper attribute handling for sap time and self-destruct time
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(sapper);
	if (!attr) {
		// no custom attributes
		return;
	}
	
	char reprogrammerProps[512];
	attr.GetString("sapper reprograms buildings", reprogrammerProps, sizeof(reprogrammerProps));
	delete attr;
	
	if (!reprogrammerProps[0]) {
		// not a reprogramming sapper
		return;
	}
	
	float flSapTime = ReadFloatVar(reprogrammerProps, "sap_time", 5.0);
	float flSelfDestructTime = ReadFloatVar(reprogrammerProps, "self_destruct_time", 15.0);
	
	TE_SetupTFParticleEffect("bot_radio_waves", NULL_VECTOR, .entity = sapperattach);
	TE_SendToAll();
	
	DataPack data;
	CreateDataTimer(flSapTime, OnReprogramComplete, data, TIMER_FLAG_NO_MAPCHANGE);
	
	WritePackEntity(data, sapperattach);
	WritePackClient(data, attacker);
	data.WriteFloat(flSelfDestructTime);
}

public Action OnReprogramComplete(Handle timer, DataPack data) {
	data.Reset();
	
	int sapperattach = ReadPackEntity(data);
	int attacker = ReadPackClient(data);
	float flSelfDestructTime = data.ReadFloat();
	
	if (!IsValidEntity(sapperattach)) {
		// sapper was destroyed, don't do the sap effect
		return Plugin_Handled;
	}
	
	TFTeam attackerTeam = TF2_GetClientTeam(attacker);
	int building = GetEntPropEnt(sapperattach, Prop_Data, "m_hParent");
	
	RemoveEntity(sapperattach);
	
	/**
	 * properly convert the building to the other team
	 * 
	 * m_iTeamNum is enough to change the sentry's own targeting, but other sentries won't
	 * care as they proceed to get shidded on
	 */
	ChangeBuildingTeam(building, attackerTeam);
	
	SetEntProp(building, Prop_Send, "m_nSkin", attackerTeam == TFTeam_Red? 0 : 1);
	
	AddConvertedBuildingInfo(building, attacker);
	
	CreateTimer(flSelfDestructTime, OnReprogrammedBuildingSelfDestruct,
			EntIndexToEntRef(building), TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Handled;
}

public Action OnReprogrammedBuildingSelfDestruct(Handle timer, int buildingref) {
	int building = EntRefToEntIndex(buildingref);
	if (!IsValidEntity(building)) {
		// :crab: building is dead :crab:
		return Plugin_Handled;
	}
	
	int attacker = GetModifiedBuildingOwner(building);
	
	RemoveConvertedBuildingInfo(building);
	
	// set building owner back to correct team so damage isn't friendly fire
	int builder = GetEntPropEnt(building, Prop_Send, "m_hBuilder");
	ChangeBuildingTeam(building, TF2_GetClientTeam(builder));
	
	SDKHooks_TakeDamage(building, 0, attacker, 5000.0);
	
	return Plugin_Handled;
}

/**
 * Adds the new owner to a list for later overwriting in the sentry's think function.
 */
void AddConvertedBuildingInfo(int building, int attacker) {
	int index = g_ConvertedBuildings.Push(EntIndexToEntRef(building));
	g_ConvertedBuildings.Set(index, GetClientSerial(attacker), 1);
	
	// TODO clean up older entries here if you're putting this on a production server
}

void RemoveConvertedBuildingInfo(int building) {
	int index = g_ConvertedBuildings.FindValue(EntIndexToEntRef(building), 0);
	if (index != -1) {
		g_ConvertedBuildings.Erase(index);
	}
}

int GetModifiedBuildingOwner(int building) {
	int index = g_ConvertedBuildings.FindValue(EntIndexToEntRef(building), 0);
	if (index != -1) {
		int client = GetClientFromSerial(g_ConvertedBuildings.Get(index, 1));
		if (client) {
			return client;
		}
	}
	return GetEntPropEnt(building, Prop_Send, "m_hBuilder");
}

/**
 * Registers the object under the specified team and changes the team number property.
 * Sentries that are not on this team will attempt to target the building.
 */
void ChangeBuildingTeam(int building, TFTeam team) {
	SDKCall(g_SDKChangeObjectTeam, building, team);
}
