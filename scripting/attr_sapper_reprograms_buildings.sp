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
#include <stocksoup/memory>
#include <stocksoup/var_strings>
#include <stocksoup/tf/tempents_stocks>
#include <stocksoup/tf/hud_notify>

#include <tf2utils>
#include <tf_custom_attributes>
#include <dhooks_gameconf_shim>

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

// custom spawnflag to tell other plugins to not destroy this building on loadout changes
// kind of a dumb hack, but I don't want to make this a shared library
#define SF_BASEOBJ_CUSTOM_NO_AUTODESTROY (1 << 16)

enum struct ReprogrammedBuilding {
	int buildingref;
	int ownerserial;
	
	// if the building can be destroyed when [un]equipping the gunslinger or changing class
	// buildings can never be destroyed manually
	bool autodestroyable;
}

ArrayList g_ConvertedBuildings;

static int offs_hBuilder, offs_hOwner;

Handle g_SDKChangeObjectTeam;
Handle g_SDKBuildingSpawnControlPanels, g_SDKBuildingDestroyScreens,
		g_SDKBuildingSetScreenActive;
Handle g_SDKBuildingDetonate;
Handle g_SDKPlayerGetObjectOfType;

int offs_WeaponBase_fnEquip;
int offs_WeaponBase_fnDetach;

Handle g_SDKWeaponEquip, g_SDKWeaponDetach;

public void OnPluginStart() {
	LoadTranslations("common.phrases");
	
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	Handle dtSentryFire = GetDHooksDefinition(hGameConf, "CObjectSentrygun::SentryThink()");
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
	
	Handle dtDetonateObjectOfType = GetDHooksDefinition(hGameConf,
			"CTFPlayer::DetonateObjectOfType()");
	DHookEnableDetour(dtDetonateObjectOfType, false, OnPlayerDetonateBuildingPre);
	
	offs_WeaponBase_fnEquip = GameConfGetOffset(hGameConf, "CTFWeaponBase::Equip()");
	offs_WeaponBase_fnDetach = GameConfGetOffset(hGameConf, "CTFWeaponBase::Detach()");
	
	Handle dtRemoveAllObjects = GetDHooksDefinition(hGameConf, "CTFPlayer::RemoveAllObjects()");
	if (!dtRemoveAllObjects) {
		SetFailState("Failed to create detour %s", "CTFPlayer::RemoveAllObjects()");
	}
	DHookEnableDetour(dtRemoveAllObjects, false, OnRemoveAllObjectsPre);
	
	ClearDHooksDefinitions();
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
	
	// bunch of stuff we have to resolve at runtime
	static Handle s_dtWrenchEquip, s_dtWrenchDetach;
	if (!s_dtWrenchEquip) {
		int wrench = CreateEntityByName("tf_weapon_wrench");
		RemoveEntity(wrench);
		
		Address pFunction = GetVirtualFnAddressFromEntity(wrench, offs_WeaponBase_fnEquip);
		s_dtWrenchEquip = DHookCreateDetour(pFunction, CallConv_THISCALL, ReturnType_Void,
				ThisPointer_CBaseEntity);
		DHookAddParam(s_dtWrenchEquip, HookParamType_CBaseEntity);
		DHookEnableDetour(s_dtWrenchEquip, false, OnWrenchEquipPre);
		
	}
	
	if (!s_dtWrenchDetach) {
		int wrench = CreateEntityByName("tf_weapon_wrench");
		RemoveEntity(wrench);
		
		Address pFunction = GetVirtualFnAddressFromEntity(wrench, offs_WeaponBase_fnDetach);
		s_dtWrenchDetach = DHookCreateDetour(pFunction, CallConv_THISCALL, ReturnType_Void,
				ThisPointer_CBaseEntity);
		DHookEnableDetour(s_dtWrenchDetach, false, OnWrenchDetachPre);
	}
	
	if (!g_SDKWeaponEquip) {
		int baseMelee = CreateEntityByName("tf_weaponbase_melee");
		RemoveEntity(baseMelee);
		
		Address pFunction = GetVirtualFnAddressFromEntity(baseMelee, offs_WeaponBase_fnEquip);
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetAddress(pFunction);
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		g_SDKWeaponEquip = EndPrepSDKCall();
	}
	
	if (!g_SDKWeaponDetach) {
		int baseMelee = CreateEntityByName("tf_weaponbase_melee");
		RemoveEntity(baseMelee);
		
		Address pFunction = GetVirtualFnAddressFromEntity(baseMelee, offs_WeaponBase_fnDetach);
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetAddress(pFunction);
		g_SDKWeaponDetach = EndPrepSDKCall();
	}
}

Action SimulateReprogrammedBuilding(int client, int argc) {
	if (argc < 3) {
		ReplyToCommand(client,
				"Usage: cattr_reprog_building [builder] [sapper owner] [building type int]");
		return Plugin_Handled;
	}
	
	char targetName[64], ownerName[64], buildingType[8];
	GetCmdArg(1, targetName, sizeof(targetName));
	GetCmdArg(2, ownerName, sizeof(ownerName));
	GetCmdArg(3, buildingType, sizeof(buildingType));
	
	TFObjectType objectType = view_as<TFObjectType>(StringToInt(buildingType));
	
	int target = FindTarget(client, targetName, .immunity = false);
	if (target == -1) {
		return Plugin_Handled;
	}
	
	int owner = FindTarget(client, ownerName, .immunity = false);
	if (owner == -1) {
		return Plugin_Handled;
	}
	
	for (int i, n = TF2Util_GetPlayerObjectCount(target); i < n; i++) {
		int ent = TF2Util_GetPlayerObject(target, i);
		if (GetEntProp(ent, Prop_Send, "m_iObjectType") != view_as<any>(objectType)) {
			continue;
		}
		ReprogramBuilding(ent, owner, false);
	}
	return Plugin_Handled;
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
MRESReturn OnSentryGunThinkPre(int sentry) {
	s_ActualBuildingOwner = GetEntPropEnt(sentry, Prop_Send, "m_hOwnerEntity");
	s_ActualBuildingBuilder = GetEntPropEnt(sentry, Prop_Send, "m_hBuilder");
	
	int newOwner = GetModifiedBuildingOwner(sentry);
	
	// I can't remember why we set these props or what the side effects were.
	// I *think* the builder controls whether the sentry can be controlled by the Wrangler.
	SetEntDataEnt2(sentry, offs_hBuilder, newOwner);
	// SetEntDataEnt2(sentry, offs_hOwner, newOwner);
	
	return MRES_Ignored;
}

/**
 * Restores the actual builder on "reprogrammed" buildings.
 */
MRESReturn OnSentryGunThinkPost(int sentry) {
	SetEntDataEnt2(sentry, offs_hBuilder, s_ActualBuildingBuilder);
	SetEntDataEnt2(sentry, offs_hOwner, s_ActualBuildingOwner);
	
	s_ActualBuildingOwner = INVALID_ENT_REFERENCE;
	return MRES_Ignored;
}

/**
 * Called when an object is sapped; checks if we should be setting up the reprogrammer.
 */
void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int sapperattach = event.GetInt("sapperid");
	
	if (!IsValidEntity(sapperattach)) {
		return;
	}
	
	int sapper = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Secondary);
	
	char reprogrammerProps[512];
	if (!TF2CustAttr_GetString(sapper, "sapper reprograms buildings", reprogrammerProps,
			sizeof(reprogrammerProps))) {
		// not a reprogramming sapper
		return;
	}
	
	float flSapTime = ReadFloatVar(reprogrammerProps, "sap_time", 5.0);
	float flSelfDestructTime = ReadFloatVar(reprogrammerProps, "self_destruct_time", 15.0);
	int autoRemoveTypes = ReadIntVar(reprogrammerProps, "can_autoremove");
	
	TE_SetupTFParticleEffect("bot_radio_waves", NULL_VECTOR, .entity = sapperattach);
	TE_SendToAll();
	
	DataPack data;
	CreateDataTimer(flSapTime, OnReprogramComplete, data, TIMER_FLAG_NO_MAPCHANGE);
	
	WritePackEntity(data, sapperattach);
	WritePackClient(data, attacker);
	data.WriteCell(autoRemoveTypes);
	data.WriteFloat(flSelfDestructTime);
}

Action OnReprogramComplete(Handle timer, DataPack data) {
	data.Reset();
	
	int sapperattach = ReadPackEntity(data);
	int attacker = ReadPackClient(data);
	int autoRemoveTypes = data.ReadCell();
	float flSelfDestructTime = data.ReadFloat();
	
	if (!IsValidEntity(sapperattach)) {
		// sapper was destroyed, don't do the sap effect
		return Plugin_Handled;
	}
	int building = GetEntPropEnt(sapperattach, Prop_Data, "m_hParent");
	
	bool allowAutoDestroy =
			!!(autoRemoveTypes & (1 << view_as<int>(TF2_GetObjectType(building))));
	ReprogramBuilding(building, attacker, allowAutoDestroy);
	
	RemoveEntity(sapperattach);
	
	CreateTimer(flSelfDestructTime, OnReprogrammedBuildingSelfDestruct,
			EntIndexToEntRef(building), TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Handled;
}

void ReprogramBuilding(int building, int owner, bool destroyable) {
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
	
	AddConvertedBuildingInfo(building, owner, destroyable);
}

Action OnReprogrammedBuildingSelfDestruct(Handle timer, int buildingref) {
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

MRESReturn OnPlayerDetonateBuildingPre(int client, Handle hParams) {
	int objectType = DHookGetParam(hParams, 1);
	int objectMode = DHookGetParam(hParams, 2);
	bool bForceRemoval = DHookGetParam(hParams, 3);
	
	if (bForceRemoval) {
		return MRES_Ignored;
	}
	
	int building = SDKCall(g_SDKPlayerGetObjectOfType, client, objectType, objectMode);
	if (!IsValidEntity(building)) {
		return MRES_Ignored;
	}
	
	if (CanBuildingDetonate(building, .forced = false)) {
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
	// we iterate backwards through this in case removals mutate the array
	for (int i = TF2Util_GetPlayerObjectCount(client); i-- > 0;) {
		int ent = TF2Util_GetPlayerObject(client, i);
		
		if (!CanBuildingDetonate(ent, .forced = true)) {
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

MRESReturn OnWrenchEquipPre(int wrench, Handle hParams) {
	int owner = DHookGetParam(hParams, 1);
	int building = SDKCall(g_SDKPlayerGetObjectOfType, owner, TFObject_Sentry,
			TFObjectMode_None);
	if (!IsValidEntity(building) || CanBuildingDetonate(building, .forced = true)) {
		return MRES_Ignored;
	}
	
	// our building is reprogrammed, don't destroy if we switch to / from gunslinger
	// still have to call the baseclass ::Equip
	SDKCall(g_SDKWeaponEquip, wrench, owner);
	return MRES_Supercede;
}

MRESReturn OnWrenchDetachPre(int wrench) {
	int owner = GetEntPropEnt(wrench, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner >= MaxClients) {
		return MRES_Ignored;
	}
	
	int building = SDKCall(g_SDKPlayerGetObjectOfType, owner, TFObject_Sentry,
			TFObjectMode_None);
	if (!IsValidEntity(building) || CanBuildingDetonate(building, .forced = true)) {
		return MRES_Ignored;
	}
	
	// don't destroy if we switch to / from gunslinger
	// still have to call the baseclass ::Detach
	SDKCall(g_SDKWeaponDetach, wrench);
	return MRES_Supercede;
}

/**
 * Adds the new owner to a list for later overwriting in the sentry's think function.
 */
void AddConvertedBuildingInfo(int building, int attacker, bool autodestroyable) {
	ReprogrammedBuilding info;
	info.buildingref = EntIndexToEntRef(building);
	info.ownerserial = GetClientSerial(attacker);
	info.autodestroyable = autodestroyable;
	
	g_ConvertedBuildings.PushArray(info, sizeof(info));
	
	// TODO clean up older entries here if you're putting this on a production server
	int spawnflags = GetEntProp(building, Prop_Data, "m_spawnflags");
	
	if (!autodestroyable) {
		SetEntProp(building, Prop_Data, "m_spawnflags",
				spawnflags | SF_BASEOBJ_CUSTOM_NO_AUTODESTROY);
	}
}

void RemoveConvertedBuildingInfo(int building) {
	int buildingref = EntIndexToEntRef(building);
	for (int i; i < g_ConvertedBuildings.Length; i++) {
		ReprogrammedBuilding info;
		g_ConvertedBuildings.GetArray(i, info, sizeof(info));
		
		if (info.buildingref == buildingref) {
			g_ConvertedBuildings.Erase(i);
			
			int spawnflags = GetEntProp(building, Prop_Data, "m_spawnflags");
			SetEntProp(building, Prop_Data, "m_spawnflags",
					spawnflags & ~SF_BASEOBJ_CUSTOM_NO_AUTODESTROY);
			
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

bool CanBuildingDetonate(int building, bool forced = false) {
	int buildingref = EntIndexToEntRef(building);
	for (int i; i < g_ConvertedBuildings.Length; i++) {
		ReprogrammedBuilding info;
		g_ConvertedBuildings.GetArray(i, info, sizeof(info));
		
		if (info.buildingref != buildingref) {
			continue;
		}
		int owner = GetClientFromSerial(info.ownerserial);
		if (!owner) {
			continue;
		}
		
		if (!forced || !info.autodestroyable) {
			return false;
		}
	}
	return true;
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

Address GetVirtualFnAddressFromEntity(int entity, int offset) {
	Address pVTable = DereferencePointer(GetEntityAddress(entity));
	return DereferencePointer(pVTable + view_as<Address>(offset * 4));
}
