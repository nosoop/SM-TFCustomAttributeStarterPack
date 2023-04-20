#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <dhooks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/entity_prop_stocks>
#include <dhooks_gameconf_shim>

Handle g_DHookProjectileTouch;
Handle g_SDKCallBaseObjectStartUpgrading;
Handle g_SDKCallBaseObjectGetMaxUpgradeLevel;
Handle g_SDKCallCanBeUpgradedFromPlayer;
Handle g_SDKCallTeleporterFindMatch;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	g_DHookProjectileTouch = GetDHooksDefinition(hGameConf,
			"CTFBaseProjectile::ProjectileTouch()");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::StartUpgrading()");
	g_SDKCallBaseObjectStartUpgrading = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::GetMaxUpgradeLevel()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallBaseObjectGetMaxUpgradeLevel = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CBaseObject::CanBeUpgraded(CTFPlayer)");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	g_SDKCallCanBeUpgradedFromPlayer = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CObjectTeleporter::FindMatch()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallTeleporterFindMatch = EndPrepSDKCall();
	
	ClearDHooksDefinitions();
	delete hGameConf;
}

public void OnEntityCreated(int entity, const char[] className) {
	// check if baseprojectile
	if (!IsValidEdict(entity) || !HasEntProp(entity, Prop_Send, "m_hOriginalLauncher")) {
		return;
	}
	
	// TODO remove syringe limitation -- this causes weird crashes on rockets
	// hooking ProjectileTouch also prevents rocket jumping???
	if (!StrEqual(className, "tf_projectile_syringe")) {
		return;
	}
	
	DHookEntity(g_DHookProjectileTouch, true, entity, .callback = OnProjectileTouchPost);
}

MRESReturn OnProjectileTouchPost(int entity, Handle hParams) {
	int originalLauncher = GetEntPropEnt(entity, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(originalLauncher)) {
		return MRES_Ignored;
	}
	
	int upgradeAmount = TF2CustAttr_GetInt(originalLauncher, "projectile upgrades buildings");
	if (!upgradeAmount) {
		return MRES_Ignored;
	}
	
	int other = DHookGetParam(hParams, 1);/*!DHookIsNullParam(hParams, 1) ? DHookGetParam(hParams, 1) : -1;*/
	if (!IsValidEntity(other)) {
		return MRES_Ignored;
	}
	
	int owner = TF2_GetEntityOwner(entity);
	if (!IsValidEntity(owner)) {
		return MRES_Ignored;
	}
	
	// not an upgradable building
	if (!HasEntProp(other, Prop_Send, "m_iUpgradeMetal")
			|| TF2_GetObjectType(other) == TFObject_Sapper) {
		return MRES_Ignored;
	}
	
	// building isn't friendly
	if (GetEntProp(other, Prop_Data, "m_iTeamNum") != GetClientTeam(owner)) {
		return MRES_Ignored;
	}
	
	// don't upgrade if object is in the process of building or can't be upgraded
	if (!!GetEntProp(other, Prop_Send, "m_bBuilding") || !CanBuildingBeUpgraded(other, owner)) {
		return MRES_Ignored;
	}
	
	int metal = GetMetalCount(owner);
	if (metal < upgradeAmount) {
		upgradeAmount = metal;
	}
	
	// not enough metal to upgrade
	if (!upgradeAmount) {
		return MRES_Ignored;
	}
	
	SetMetalCount(owner, metal - upgradeAmount);
	
	int upgradeMetal = GetEntProp(other, Prop_Send, "m_iUpgradeMetal") + upgradeAmount;
	SetEntProp(other, Prop_Send, "m_iUpgradeMetal", upgradeMetal);
	
	int upgradeRequired = GetEntProp(other, Prop_Send, "m_iUpgradeMetalRequired");
	
	int upgradeLevel = GetEntProp(other, Prop_Send, "m_iUpgradeLevel");
	
	// this calls CObjectTeleporter::CopyUpgradeStateToMatch()
	// so we need to have applied the upgrade before continuing -- or call it twice
	int teleportMatch = -1;
	if (TF2_GetObjectType(other) == TFObject_Teleporter) {
		teleportMatch = FindMatchingTeleporter(other);
	}
	
	if (upgradeMetal >= upgradeRequired && GetBuildingMaxUpgradeLevel(other) > upgradeLevel) {
		StartBuildingUpgrade(other);
		SetEntProp(other, Prop_Send, "m_iUpgradeMetal", 0);
		
		// upgrade teleporter on match
		if (IsValidEntity(teleportMatch)) {
			StartBuildingUpgrade(teleportMatch);
			SetEntProp(teleportMatch, Prop_Send, "m_iUpgradeMetal", 0);
		}
	}
	
	// RemoveEntity(entity);
	return MRES_Ignored;
}

void StartBuildingUpgrade(int building) {
	SDKCall(g_SDKCallBaseObjectStartUpgrading, building);
}

int GetBuildingMaxUpgradeLevel(int building) {
	return SDKCall(g_SDKCallBaseObjectGetMaxUpgradeLevel, building);
}

bool CanBuildingBeUpgraded(int building, int builder = INVALID_ENT_REFERENCE) {
	int originalBuilder = GetEntPropEnt(building, Prop_Send, "m_hBuilder");
	return SDKCall(g_SDKCallCanBeUpgradedFromPlayer, building,
			IsValidEntity(builder)? builder : originalBuilder);
}

int FindMatchingTeleporter(int building) {
	return SDKCall(g_SDKCallTeleporterFindMatch, building);
}

static int GetMetalCount(int client) {
	return GetEntProp(client, Prop_Send, "m_iAmmo", .element = 3);
}

static void SetMetalCount(int client, int metal) {
	SetEntProp(client, Prop_Send, "m_iAmmo", metal, .element = 3);
}
