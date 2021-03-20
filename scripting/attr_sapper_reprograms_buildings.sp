/**
 * [TF2CA] Sapper Reprograms Buildings
 * 
 * Note:  This is unfit for production use.  Not all building team switch cases are covered.
 * 
 * In particular, what's been reported:  Engineer can't shoot their reprogrammed buildings, Spy
 * teammates can't use reprogrammed teleporters, and reprogrammed teleporters don't have
 * teleport recharge (i.e., they recharge instantly).
 */
#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdkhooks>
#include <tf2_stocks>

#include <stocksoup/datapack>
#include <stocksoup/var_strings>
#include <stocksoup/tf/tempents_stocks>
#include <stocksoup/tf/hud_notify>

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

enum struct ReprogrammedBuilding {
	int buildingref;
	int ownerserial;
}

ArrayList g_ConvertedBuildings;

static int offs_hBuilder, offs_hOwner;

Handle g_SDKChangeObjectTeam;
Handle g_SDKBuildingSpawnControlPanels, g_SDKBuildingDestroyScreens,
		g_SDKBuildingSetScreenActive;
Handle g_SDKBuildingDetonate;
Handle g_SDKPlayerGetObjectOfType;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtSentryFire = DHookCreateFromConf(hGameConf, "CObjectSentrygun::SentryThink()");
	DHookEnableDetour(dtSentryFire, false, OnSentryGunThinkPre);
	DHookEnableDetour(dtSentryFire, true, OnSentryGunThinkPost);
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayer::GetObjectOfType()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKPlayerGetObjectOfType = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CBaseObject::SpawnControlPanels()");
	g_SDKBuildingSpawnControlPanels = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CBaseObject::DestroyScreens()");
	g_SDKBuildingDestroyScreens = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CBaseObject::SetControlPanelsActive()");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_SDKBuildingSetScreenActive = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::ChangeTeam()");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKChangeObjectTeam = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::DetonateObject()");
	g_SDKBuildingDetonate = EndPrepSDKCall();
	
	Handle dtDetonateObjectOfType = DHookCreateFromConf(hGameConf,
			"CTFPlayer::DetonateObjectOfType()");
	DHookEnableDetour(dtDetonateObjectOfType, false, OnPlayerDetonateBuildingPre);
	
	Handle dtRemoveAllObjects = DHookCreateFromConf(hGameConf, "CTFPlayer::RemoveAllObjects()");
	if (!dtRemoveAllObjects) {
		SetFailState("Failed to create detour %s", "CTFPlayer::RemoveAllObjects()");
	}
	DHookEnableDetour(dtRemoveAllObjects, false, OnRemoveAllObjectsPre);
	
	delete hGameConf;
	
	HookEvent("player_sapped_object", OnObjectSapped);
	
	g_ConvertedBuildings = new ArrayList(sizeof(ReprogrammedBuilding));
	
	offs_hBuilder = FindSendPropInfo("CBaseObject", "m_hBuilder");
	offs_hOwner = FindSendPropInfo("CBaseObject", "m_hOwnerEntity");
	if (offs_hBuilder == -1) {
		SetFailState("Could not find m_hBuilder for CBaseObject");
	}
	
	RegAdminCmd("cattr_reprog_building", SimulateReprogrammedBuilding, ADMFLAG_ROOT);
}

public void OnMapStart() {
	g_ConvertedBuildings.Clear();
}

Action SimulateReprogrammedBuilding(int client, int argc) {
	char targetName[64], ownerName[64], buildingType[8];
	GetCmdArg(1, targetName, sizeof(targetName));
	GetCmdArg(2, ownerName, sizeof(ownerName));
	GetCmdArg(3, buildingType, sizeof(buildingType));
	
	TFObjectType objectType = view_as<TFObjectType>(StringToInt(buildingType));
	
	int target = FindTarget(client, targetName, .immunity = false);
	int owner = FindTarget(client, ownerName, .immunity = false);
	
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "obj_*")) != -1) {
		if (!HasEntProp(ent, Prop_Send, "m_iObjectType")
				|| GetEntProp(ent, Prop_Send, "m_iObjectType") != objectType) {
			continue;
		}
		
		if (GetEntPropEnt(ent, Prop_Send, "m_hBuilder") != target) {
			continue;
		}
		ReprogramBuilding(ent, owner);
	}
}

// contains temporary client index
static int s_ActualBuildingOwner;
static int s_ActualBuildingBuilder;

/**
 * Overrides the builder on "reprogrammed" buildings only when the sentry is thinking.
 * This allows us to keep the building owner the same, while still granting kill credit to the
 * Spy (as the weapon handling sets the builder as the attacker and occurs during the think).
 * 
 * It's unfortunate that we have to do this scoped stuff, because ke::SaveAndSet and extension
 * detours handle this case in a much cleaner manner.
 */
public MRESReturn OnSentryGunThinkPre(int sentry) {
	s_ActualBuildingOwner = GetEntPropEnt(sentry, Prop_Send, "m_hOwnerEntity");
	s_ActualBuildingBuilder = GetEntPropEnt(sentry, Prop_Send, "m_hBuilder");
	
	int newOwner = GetModifiedBuildingOwner(sentry);
	SetEntDataEnt2(sentry, offs_hBuilder, newOwner);
	SetEntDataEnt2(sentry, offs_hOwner, newOwner);
	
	return MRES_Ignored;
}

/**
 * Restores the actual builder on "reprogrammed" buildings.
 */
public MRESReturn OnSentryGunThinkPost(int sentry) {
	SetEntDataEnt2(sentry, offs_hBuilder, s_ActualBuildingBuilder);
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
	
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	
	char reprogrammerProps[512];
	if (!TF2CustAttr_GetString(sapper, "sapper reprograms buildings", reprogrammerProps,
			sizeof(reprogrammerProps))) {
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
	
	int building = GetEntPropEnt(sapperattach, Prop_Data, "m_hParent");
	ReprogramBuilding(building, attacker);
	
	RemoveEntity(sapperattach);
	
	CreateTimer(flSelfDestructTime, OnReprogrammedBuildingSelfDestruct,
			EntIndexToEntRef(building), TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Handled;
}

void ReprogramBuilding(int building, int owner) {
	/**
	 * properly convert the building to the other team
	 * 
	 * m_iTeamNum is enough to change the sentry's own targeting, but other sentries won't
	 * care as they proceed to get shidded on
	 */
	TFTeam attackerTeam = TF2_GetClientTeam(owner);
	ChangeBuildingTeam(building, attackerTeam);
	RespawnBuildingScreens(building);
	
	SetEntProp(building, Prop_Send, "m_nSkin", attackerTeam == TFTeam_Red? 0 : 1);
	
	AddConvertedBuildingInfo(building, owner);
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

public MRESReturn OnPlayerDetonateBuildingPre(int client, Handle hParams) {
	int a = DHookGetParam(hParams, 1);
	int b = DHookGetParam(hParams, 2);
	bool bForceRemoval = DHookGetParam(hParams, 3);
	
	if (bForceRemoval) {
		return MRES_Ignored;
	}
	
	int building = SDKCall(g_SDKPlayerGetObjectOfType, client, a, b);
	if (!IsValidEntity(building)) {
		return MRES_Ignored;
	}
	
	if (client == GetModifiedBuildingOwner(building)) {
		return MRES_Ignored;
	}
	
	TF_HudNotifyCustom(client, "obj_status_sapper", TF2_GetClientTeam(client),
			"Cannot destroy reprogrammed building!");
	return MRES_Supercede;
}

MRESReturn OnRemoveAllObjectsPre(int client, Handle hParams) {
	bool detonate = DHookGetParam(hParams, 1);
	
	if (GetClientTeam(client) != GetEntProp(client, Prop_Send, "m_iTeamNum")) {
		return MRES_Ignored;
	}
	
	if (GetEntProp(client, Prop_Send, "m_iDesiredPlayerClass")
			== GetEntProp(client, Prop_Send, "m_iClass")) {
		return MRES_Ignored;
	}
	
	// remove non-reprogrammed buildings we own
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "obj_*")) != -1) {
		if (!HasEntProp(ent, Prop_Send, "m_hBuilder")
				|| GetEntPropEnt(ent, Prop_Send, "m_hBuilder") != client) {
			// not a building we own
			continue;
		}
		
		if (client != GetModifiedBuildingOwner(ent)) {
			// this was reprogrammed, so don't destroy it
			continue;
		}
		
		Event event = CreateEvent("object_removed");
		if (event) {
			event.SetInt("userid", GetClientUserId(client));
			event.SetInt("objecttype", view_as<any>(TF2_GetObjectType(ent)));
			event.SetInt("index", EntRefToEntIndex(ent));
			event.Fire();
		}
		
		if (detonate) {
			SDKCall(g_SDKBuildingDetonate, ent);
		} else {
			RemoveEntity(ent);
		}
	}
	
	return MRES_Supercede;
}

/**
 * Adds the new owner to a list for later overwriting in the sentry's think function.
 */
void AddConvertedBuildingInfo(int building, int attacker) {
	ReprogrammedBuilding info;
	info.buildingref = EntIndexToEntRef(building);
	info.ownerserial = GetClientSerial(attacker);
	
	g_ConvertedBuildings.PushArray(info, sizeof(info));
	
	// TODO clean up older entries here if you're putting this on a production server
}

void RemoveConvertedBuildingInfo(int building) {
	int buildingref = EntIndexToEntRef(building);
	for (int i; i < g_ConvertedBuildings.Length; i++) {
		ReprogrammedBuilding info;
		g_ConvertedBuildings.GetArray(i, info, sizeof(info));
		
		if (info.buildingref == buildingref) {
			g_ConvertedBuildings.Erase(i);
			return;
		}
	}
}

/**
 * Returns the "reprogrammed" building owner if they exist, otherwise return the original
 * builder.
 */
int GetModifiedBuildingOwner(int building) {
	int buildingref = EntIndexToEntRef(building);
	for (int i; i < g_ConvertedBuildings.Length; i++) {
		ReprogrammedBuilding info;
		g_ConvertedBuildings.GetArray(i, info, sizeof(info));
		
		if (info.buildingref != buildingref) {
			continue;
		}
		int owner = GetClientFromSerial(info.ownerserial);
		if (owner) {
			return owner;
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

/**
 * Rebuilds the VGUI screen entities for the specified building and makes them active.
 * This handles Dispenser screens.
 */
void RespawnBuildingScreens(int building) {
	if (g_SDKBuildingSpawnControlPanels && g_SDKBuildingDestroyScreens
			&& g_SDKBuildingSetScreenActive) {
		SDKCall(g_SDKBuildingDestroyScreens, building);
		SDKCall(g_SDKBuildingSpawnControlPanels, building);
		SDKCall(g_SDKBuildingSetScreenActive, building, true);
	}
}
