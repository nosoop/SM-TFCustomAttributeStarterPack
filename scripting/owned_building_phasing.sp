/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <dhooks>
#include <stocksoup/memory>
#include <tf2utils>

#include <stocksoup/var_strings>
#include <tf_custom_attributes>
#include <dhooks_gameconf_shim>

#define PHASE_ALLOW_SENTRIES      (1 << 0)
#define PHASE_ALLOW_DISPENSERS    (1 << 1)

int g_fAllowPhaseTypes[MAXPLAYERS + 1];
bool g_bLastPhaseState[MAXPLAYERS + 1];

ConVar tf_solidobjects;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	} else if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	Handle dtShouldHitEntity = GetDHooksDefinition(hGameConf,
			"CTraceFilterObject::ShouldHitEntity()");
	if (!dtShouldHitEntity) {
		SetFailState("Failed to create detour " ... "CTraceFilterObject::ShouldHitEntity()");
	}
	DHookEnableDetour(dtShouldHitEntity, true, TraceFilterObjectShouldHitEntityPost);
	
	ClearDHooksDefinitions();
	delete hGameConf;
	
	CreateTimer(0.1, UpdateBuildingPhaseState, .flags = TIMER_REPEAT);
	
	/**
	 * This bypasses CTraceFilterObject entirely on the client, so we don't have to deal with
	 * issues on client prediction or fudging the builder - the remaining complexity is patching
	 * CTraceFilterObject on the server for the appropriate rules.
	 */
	tf_solidobjects = FindConVar("tf_solidobjects");
}

public void OnClientPutInServer(int client) {
	g_fAllowPhaseTypes[client] = 0;
	g_bLastPhaseState[client] = false;
	
	if (!IsFakeClient(client)) {
		tf_solidobjects.ReplicateToClient(client, "1");
	}
}

Action UpdateBuildingPhaseState(Handle timer) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) {
			continue;
		}
		
		bool bAllowPhase = AllowPredictBuildingPhase(i);
		if (bAllowPhase != g_bLastPhaseState[i]) {
			tf_solidobjects.ReplicateToClient(i, bAllowPhase ? "0" : "1");
			g_bLastPhaseState[i] = bAllowPhase;
		}
	}
}

/**
 * Patch up prediction to allow phasing through certain objects.  The player may try to clip
 * through other buildings if sufficently close to one they can phase through, but will be
 * pulled back by the server.
 * 
 * We need to do this instead of letting the client think that buildings are never solid to
 * prevent mispredictions while a player is standing on an object.
 */
bool AllowPredictBuildingPhase(int client) {
	int nBuildings = TF2Util_GetPlayerObjectCount(client);
	if (!nBuildings) {
		return false;
	}
	
	UpdatePhasingTypes(client);
	if (!g_fAllowPhaseTypes[client] || IsFakeClient(client)) {
		return false;
	}
	
	int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	
	float vecBuilderOrigin[3];
	GetClientAbsOrigin(client, vecBuilderOrigin);
	
	float vecBuilderVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vecBuilderVelocity);
	
	float distThreshold = GetVectorLength(vecBuilderVelocity) * 0.5;
	if (distThreshold < 80.0) {
		distThreshold = 80.0;
	}
	
	for (int i; i < nBuildings; i++) {
		int building = TF2Util_GetPlayerObject(client, i);
		
		if (groundEntity == building) {
			// fail fast if the entity we're standing on is a building
			return false;
		}
		
		if (!CanPhaseThroughObject(client, building)) {
			continue;
		}
		
		float vecBuildingOrigin[3];
		GetEntPropVector(building, Prop_Data, "m_vecAbsOrigin", vecBuildingOrigin);
		
		float dist = GetVectorDistance(vecBuilderOrigin, vecBuildingOrigin);
		if (dist < distThreshold) {
			return true;
		}
	}
	return false;
}

void UpdatePhasingTypes(int client) {
	g_fAllowPhaseTypes[client] = 0;
	
	int meleeWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (!IsValidEntity(meleeWeapon)) {
		return;
	}
	
	char attr[48];
	if (!TF2CustAttr_GetString(meleeWeapon, "owned building phasing", attr, sizeof(attr))) {
		return;
	}
	
	if (ReadIntVar(attr, "sentry")) {
		g_fAllowPhaseTypes[client] |= PHASE_ALLOW_SENTRIES;
	}
	if (ReadIntVar(attr, "dispenser")) {
		g_fAllowPhaseTypes[client] |= PHASE_ALLOW_DISPENSERS;
	}
}

/**
 * Functor that determines if a trace should hit an object.
 * This trace is performed during player movement.
 * 
 * Setting the return to 'false' allows us to move through the object.
 */
MRESReturn TraceFilterObjectShouldHitEntityPost(Address pFilterObject, Handle hReturn,
		Handle hParams) {
	int entity = DHookGetParam(hParams, 1);
	
	// retrieve the entity that is performing the trace
	// offset found based off of `CTraceFilterSimple::SetPassEntity()`
	Address pEntity = DereferencePointer(pFilterObject + view_as<Address>(0x04));
	int passEntity = GetEntityFromAddress(pEntity);
	
	if (passEntity < 1 || passEntity > MaxClients) {
		return MRES_Ignored;
	}
	
	char cname[8];
	if (!GetEntityClassname(entity, cname, sizeof(cname)) || strncmp(cname, "obj_", 4)) {
		return MRES_Ignored;
	}
	
	if (CanPhaseThroughObject(passEntity, entity)) {
		DHookSetReturn(hReturn, false);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

/**
 * Determines if the given client is allowed to phase through the given object.
 * If 'false' is returned here, the default game rules apply.
 */
bool CanPhaseThroughObject(int client, int building) {
	if (client != GetEntPropEnt(building, Prop_Send, "m_hBuilder")) {
		return false;
	}
	
	switch (TF2_GetObjectType(building)) {
		case TFObject_Sentry: {
			return g_fAllowPhaseTypes[client] & PHASE_ALLOW_SENTRIES != 0;
		}
		case TFObject_Dispenser: {
			return g_fAllowPhaseTypes[client] & PHASE_ALLOW_DISPENSERS != 0;
		}
		case TFObject_Sapper: {
			// fix for plugins using sapper as a workaround to get additional sentry counts
			return g_fAllowPhaseTypes[client] & PHASE_ALLOW_SENTRIES != 0;
		}
	}
	return false;
}
