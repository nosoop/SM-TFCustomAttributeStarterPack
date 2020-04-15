#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>
#include <tf2attributes>

#pragma newdecls required

#include <stocksoup/entity_tools>
#include <stocksoup/tf/tempents_stocks>
#include <stocksoup/tf/weapon>
#include <stocksoup/tf/econ>
#include <tf_custom_attributes>

#define OIL_PUDDLE_MODEL "models/props_farm/haypile001.mdl"

#define OIL_PUDDLE_TRIGGER_MODEL "models/props_gameplay/cap_point_base.mdl"

#define OIL_DAMAGE_TRIGGER_NAME "cattr_oil_trigger"

#define COLLISION_GROUP_PUSHAWAY 0x11

#define HUO_LONG_IGNITE_RADIUS 135.0

#define OIL_PUDDLE_BASE_SIZE 42.0
#define OIL_PUDDLE_SCALE 1.0

// NOTE: make sure "airblast disabled" is set on the weapon so client doesn't predict airblast

Handle g_DHookRocketTouch;

Handle g_SDKCallInitGrenade;
Handle g_SDKCallFindEntityInSphere;

ArrayList g_OilPuddleWorldRefs;
ArrayList g_OilPuddleIgniteRefs;

int offs_CTFMinigun_flNextFireRingTime;

ConVar g_OilSpillSelfDmg;
ConVar g_OilSpillLifetime;
ConVar g_OilSpillPlayerMaxActive;
ConVar g_OilSpillDamagePerTick;

int g_OilFlamethrowerRef[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtFlamethrowerSecondary = DHookCreateFromConf(hGameConf,
			"CTFFlameThrower::SecondaryAttack()");
	DHookEnableDetour(dtFlamethrowerSecondary, false, OnFlamethrowerSecondaryAttack);
	
	Handle dtRingOfFireAttack = DHookCreateFromConf(hGameConf,
			"CTFMinigun::RingOfFireAttack()");
	DHookEnableDetour(dtRingOfFireAttack, false, OnMinigunRingOfFirePre);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CTFWeaponBaseGrenadeProj::InitGrenade(int float)");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallInitGrenade = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_EntityList);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CGlobalEntityList::FindEntityInSphere()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer,
			VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();
	
	g_DHookRocketTouch = DHookCreateFromConf(hGameConf, "CTFBaseRocket::RocketTouch()");
	
	offs_CTFMinigun_flNextFireRingTime = GameConfGetOffset(hGameConf,
			"CTFMinigun::m_flNextFireRingTime");
	
	delete hGameConf;
	
	g_OilPuddleWorldRefs = new ArrayList();
	g_OilPuddleIgniteRefs = new ArrayList();
	
	g_OilSpillSelfDmg = CreateConVar("cattr_flamethrower_oil_selfdmg", "1.0",
			"Multiplier for self-inflicted oil damage.");
	
	g_OilSpillLifetime = CreateConVar("cattr_flamethrower_oil_lifetime", "10.0",
			"Number of seconds that oil puddles will be live.");
	
	g_OilSpillPlayerMaxActive = CreateConVar("cattr_flamethrower_oil_max_active", "5",
			"Maximum number of oil puddles active per player.");
	
	g_OilSpillDamagePerTick = CreateConVar("cattr_flamethrower_oil_dmg_per_tick", "3.0",
			"Amount of damage oil deals per oil think (1/11th sec.).");
}

public void OnPluginEnd() {
	// clean up all existing oil entities
	while (g_OilPuddleWorldRefs.Length) {
		int oilpuddle = EntRefToEntIndex(g_OilPuddleWorldRefs.Get(0));
		if (IsValidEntity(oilpuddle)) {
			RemoveEntity(oilpuddle);
		}
		g_OilPuddleWorldRefs.Erase(0);
	}
}

public void OnMapStart() {
	// TODO precache shart
	PrecacheModel(OIL_PUDDLE_MODEL);
	PrecacheModel(OIL_PUDDLE_TRIGGER_MODEL);
	
	PrecacheSound("physics/flesh/flesh_bloody_impact_hard1.wav");
}

public void OnEntityCreated(int entity, const char[] className) {
	if (StrEqual(className, "tf_projectile_balloffire")) {
		DHookEntity(g_DHookRocketTouch, false, entity, .callback = OnBallOfFireTouchPre);
	}
}

/**
 * Process ignited oil patches.
 */
public void OnGameFrame() {
	if (GetGameTickCount() % 6) {
		return;
	}
	
	// run logic on ignited oil entities
	if (g_OilPuddleIgniteRefs.Length) {
		for (int i; i < g_OilPuddleIgniteRefs.Length;) {
			int oilpuddle = EntRefToEntIndex(g_OilPuddleIgniteRefs.Get(i));
			if (!IsValidEntity(oilpuddle)) {
				g_OilPuddleIgniteRefs.Erase(i);
				continue;
			}
			
			OilPuddleIgniteThink(oilpuddle);
			
			i++;
		}
	}
	
	// clean up expired oil references (they should expire in insertion order)
	// also clean up oil references if we're approaching the entity limit
	while (g_OilPuddleWorldRefs.Length) {
		int oilpuddle = EntRefToEntIndex(g_OilPuddleWorldRefs.Get(0));
		if (IsValidEntity(oilpuddle) && GetEntityCount() < GetMaxEntities() - 128) {
			break;
		}
		
		if (IsValidEntity(oilpuddle)) {
			RemoveEntity(oilpuddle);
		}
		
		g_OilPuddleWorldRefs.Erase(0);
	}
	
	// iterate over oil triggers and ignite on nearby burning players
	int oiltrigger = -1;
	while ((oiltrigger = FindEntityByTargetName(
			oiltrigger, OIL_DAMAGE_TRIGGER_NAME, "tf_generic_bomb")) != -1) {
		float vecOrigin[3];
		GetEntPropVector(oiltrigger, Prop_Data, "m_vecAbsOrigin", vecOrigin);
		
		int entity = -1;
		while ((entity = FindEntityInSphere(entity, vecOrigin,
				OIL_PUDDLE_BASE_SIZE * OIL_PUDDLE_SCALE)) != -1) {
			if (entity < 1 || entity > MaxClients) {
				continue;
			}
			
			if (TF2_IsPlayerInCondition(entity, TFCond_OnFire)) {
				AcceptEntityInput(oiltrigger, "Detonate");
			}
		}
	}
	
}

/**
 * Overwrites the standard airblast behavior, shooting oil instead.
 */
public MRESReturn OnFlamethrowerSecondaryAttack(int weapon) {
	if (!TF2CustAttr_GetInt(weapon, "oil replaces airblast")) {
		return MRES_Ignored;
	}
	
	if (GetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack") > GetGameTime()) {
		return MRES_Supercede;
	}
	
	int iAmmoUse = TF2Attrib_HookValueInt(FindConVar("tf_flamethrower_burstammo").IntValue, 
			"mult_airblast_cost", weapon);
	
	int iAmmoCount = TF2_GetWeaponAmmo(weapon);
	if (iAmmoUse > iAmmoCount) {
		return MRES_Supercede;
	}
	TF2_SetWeaponAmmo(weapon, iAmmoCount - iAmmoUse);
	
	SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack",
			GetGameTime() + TF2Attrib_HookValueFloat(1.0, "mult_airblast_refire_time", weapon));
	
	LeakOil(weapon);
	
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	g_OilFlamethrowerRef[owner] = EntIndexToEntRef(weapon);
	
	int nOwnedOilEntities, nMaxOilEntities = g_OilSpillPlayerMaxActive.IntValue;
	for (int i = g_OilPuddleWorldRefs.Length - 1; i >= 0; i--) {
		int oilpuddle = EntRefToEntIndex(g_OilPuddleWorldRefs.Get(i));
		if (!IsValidEntity(oilpuddle)) {
			continue;
		}
		
		int puddleowner = GetEntPropEnt(oilpuddle, Prop_Send, "m_hOwnerEntity");
		if (owner == puddleowner && nOwnedOilEntities++ >= nMaxOilEntities - 1) {
			RemoveEntity(oilpuddle);
		}
	}
	
	return MRES_Supercede;
}

/**
 * Always detonate oil spills that are hit by Dragon's Fury projectiles.
 * See https://github.com/nosoop/SM-TFCustomAttributeStarterPack/issues/2
 * 
 * We skip the burn call, as that causes issues with the burning particle effect.
 */
public MRESReturn OnBallOfFireTouchPre(int fireball, Handle hParams) {
	int target = DHookGetParam(hParams, 1);
	if (!target || !IsValidEntity(target)) {
		return MRES_Ignored;
	}
	
	char targetName[64];
	GetEntityTargetName(target, targetName, sizeof(targetName));
	
	if (!StrEqual(targetName, OIL_DAMAGE_TRIGGER_NAME)) {
		return MRES_Ignored;
	}
	AcceptEntityInput(target, "Detonate");
	RemoveEntity(fireball);
	return MRES_Supercede;
}

/**
 * Shoots an "oil" projectile.
 */
void LeakOil(int weapon) {
	// EmitGameSoundToAll("Physics.WaterSplash", weapon);
	EmitSoundToAll("physics/flesh/flesh_bloody_impact_hard1.wav", .entity = weapon);
	
	int oilprojectile = CreateEntityByName("tf_projectile_stun_ball");
	if (!IsValidEntity(oilprojectile)) {
		return;
	}
	
	// TODO setup physics and effect
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	
	TFTeam ownerTeam = TF2_GetClientTeam(owner);
	for (int i; i < 7; i++) {
		TE_SetupTFParticleEffect(
				ownerTeam == TFTeam_Red? "peejar_trail_red" : "peejar_trail_blu",
				NULL_VECTOR, .entity = oilprojectile, .attachType = PATTACH_ROOTBONE_FOLLOW);
		TE_SendToAll();
	}
	
	/* */
	float vecSpawnOrigin[3], vecSpawnAngles[3], vecVelocity[3], vecAngVelocity[3];
	GetProjectileDynamics(owner, vecSpawnOrigin, vecSpawnAngles, vecVelocity, vecAngVelocity);
	
	SetEntPropEnt(oilprojectile, Prop_Data, "m_hThrower", owner);
	
	DispatchSpawn(oilprojectile);
	
	// I don't think we need initgrenade, but we'll leave it for now just in case
	TeleportEntity(oilprojectile, vecSpawnOrigin, vecSpawnAngles, NULL_VECTOR);
	SDKCall(g_SDKCallInitGrenade, oilprojectile, vecVelocity, vecAngVelocity, owner, 0, 5.0);
	
	// stick to ground
	SetEntProp(oilprojectile, Prop_Send, "m_iType", 2);
	
	SDKHook(oilprojectile, SDKHook_VPhysicsUpdatePost, OnOilProjectileUpdate);
	
	// hide baseball
	SetEntPropFloat(oilprojectile, Prop_Send, "m_flModelScale", 0.01);
	
	RemoveEntityDelayed(oilprojectile, 5.0);
}

/** 
 * Checks if the oil projectile has made contact with the world, creating an oil puddle if so.
 */
public void OnOilProjectileUpdate(int oilEntity) {
	if (!GetEntProp(oilEntity, Prop_Send, "m_bTouched")) {
		return;
	}
	
	float vecOrigin[3];
	GetEntPropVector(oilEntity, Prop_Data, "m_vecAbsOrigin", vecOrigin);
	
	int owner = GetEntPropEnt(oilEntity, Prop_Send, "m_hThrower");
	CreateOilPuddle(owner, vecOrigin);
	
	RemoveEntity(oilEntity);
}

/**
 * Spawns an oil puddle at the given position.
 */
void CreateOilPuddle(int owner, const float vecOrigin[3]) {
	float vecOilPuddleOrigin[3];
	vecOilPuddleOrigin = vecOrigin;
	vecOilPuddleOrigin[2] -= 16.0;
	
	int puddle = CreateEntityByName("prop_dynamic_override");
	if (!IsValidEntity(puddle)) {
		return;
	}
	
	SetEntPropEnt(puddle, Prop_Send, "m_hOwnerEntity", owner);
	SetEntityModel(puddle, OIL_PUDDLE_MODEL);
	DispatchKeyValueFloat(puddle, "modelscale", OIL_PUDDLE_SCALE);
	DispatchSpawn(puddle);
	
	TeleportEntity(puddle, vecOilPuddleOrigin, NULL_VECTOR, NULL_VECTOR);
	
	SetEntityRenderColor(puddle, 0, 0, 0);
	
	RemoveEntityDelayed(puddle, g_OilSpillLifetime.FloatValue);
	
	// create oil damage trigger -- tf_generic_bomb is affected by every weapon
	int damagetrigger = CreateEntityByName("tf_generic_bomb");
	DispatchKeyValueVector(damagetrigger, "origin", vecOrigin);
	DispatchKeyValueFloat(damagetrigger, "damage", 0.0);
	DispatchKeyValueFloat(damagetrigger, "radius", 0.0);
	DispatchKeyValue(damagetrigger, "health", "1");
	SetEntityModel(damagetrigger, OIL_PUDDLE_TRIGGER_MODEL);
	
	// the control point model we use is about half the size of the hay pile model
	DispatchKeyValueFloat(damagetrigger, "modelscale", 0.5 * OIL_PUDDLE_SCALE);
	
	DispatchKeyValue(damagetrigger, "targetname", OIL_DAMAGE_TRIGGER_NAME);
	
	AcceptEntityInput(damagetrigger, "DisableShadow");
	
	DispatchSpawn(damagetrigger);
	
	ParentEntity(puddle, damagetrigger);
	
	HookSingleEntityOutput(damagetrigger, "OnDetonate", OnOilTriggerIgnite);
	
	SetEntProp(damagetrigger, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_PUSHAWAY);
	SetEntityRenderMode(damagetrigger, RENDER_TRANSALPHA);
	SetEntityRenderColor(damagetrigger, .a = 0);
	
	SDKHook(damagetrigger, SDKHook_OnTakeDamage, OnOilTriggerTakeDamage);
	
	g_OilPuddleWorldRefs.Push(EntIndexToEntRef(puddle));
}

/**
 * Called when the oil spill's damage trigger entity is hit.
 * The Huo-Long Heater's spin-up effect does not affect this.
 */
public Action OnOilTriggerTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	int oilpuddle = GetEntPropEnt(victim, Prop_Data, "m_hParent");
	if (!IsValidEntity(oilpuddle)) {
		return Plugin_Continue;
	}
	
	// TODO should we only negate all damage and do a detonation check in OnTakeDamagePost?
	// that would allow plugins to hook OTD on bombs and modify their damagetype
	return ShouldActivateOilTrigger(weapon, inflictor, damagetype)?
			Plugin_Continue : Plugin_Stop;
}

/**
 * Called when the hit detection entity has been detonated (hit with flame or other conditions
 * that fired its "Detonate" input).
 * 
 * Adds the oil puddle to the plugin's "burning oil puddle" list for damage checks.
 */
public void OnOilTriggerIgnite(const char[] output, int caller, int activator, float delay) {
	int oilpuddle = GetEntPropEnt(caller, Prop_Data, "m_hParent");
	if (!IsValidEntity(oilpuddle)) {
		return;
	}
	
	int owner = GetEntPropEnt(oilpuddle, Prop_Data, "m_hOwnerEntity");
	if (!IsValidEntity(owner)) {
		RemoveEntity(oilpuddle);
		return;
	}
	
	TE_SetupTFParticleEffect(
			TF2_GetClientTeam(owner) == TFTeam_Red? "burningplayer_red" : "burningplayer_blue",
			NULL_VECTOR, .entity = oilpuddle);
	TE_SendToAll();
	
	EmitGameSoundToAll("Fire.Engulf", .entity = oilpuddle);
	
	g_OilPuddleIgniteRefs.Push(EntIndexToEntRef(oilpuddle));
}

void OilPuddleIgniteThink(int oilpuddle) {
	float vecOrigin[3];
	GetEntPropVector(oilpuddle, Prop_Data, "m_vecAbsOrigin", vecOrigin);
	
	int owner = GetEntPropEnt(oilpuddle, Prop_Data, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients) {
		RemoveEntity(oilpuddle);
		return;
	}
	
	int weapon = GetPlayerWeaponSlot(owner, TFWeaponSlot_Primary);
	if (!IsValidEntity(weapon)
			|| EntRefToEntIndex(g_OilFlamethrowerRef[owner]) != weapon) {
		RemoveEntity(oilpuddle);
		return;
	}
	
	int entity = -1;
	while ((entity = FindEntityInSphere(entity, vecOrigin,
			OIL_PUDDLE_BASE_SIZE * OIL_PUDDLE_SCALE)) != -1) {
		// damage players
		if (entity > 0 && entity <= MaxClients) {
			// ignore teammates (hit self)
			if (owner != entity && TF2_GetClientTeam(owner) == TF2_GetClientTeam(entity)) {
				continue;
			}
			
			float flDamageScale = owner == entity? g_OilSpillSelfDmg.FloatValue : 1.0;
			
			SDKHooks_TakeDamage(entity, oilpuddle, owner,
					g_OilSpillDamagePerTick.FloatValue * flDamageScale,
					DMG_PLASMA | DMG_PREVENT_PHYSICS_FORCE, weapon);
			
			if (!TF2_IsPlayerInCondition(entity, TFCond_OnFire)) {
				TF2_AddCondition(entity, TFCond_BurningPyro, .inflictor = owner);
				TF2_IgnitePlayer(entity, owner);
			}
			
			continue;
		}
		
		// ignite nearby puddles
		if (IsEntityOilTrigger(entity)) {
			AcceptEntityInput(entity, "Detonate");
		}
	}
}

/** 
 * Burn any oil puddles near Huo-Long Heater heavies.
 */
public MRESReturn OnMinigunRingOfFirePre(int minigun, Handle hParams) {
	float flNextFireRingTime = GetEntDataFloat(minigun, offs_CTFMinigun_flNextFireRingTime);
	if (flNextFireRingTime > GetGameTime()) {
		return MRES_Ignored;
	}
	
	int owner = GetEntPropEnt(minigun, Prop_Send, "m_hOwnerEntity");
	if (!IsValidEntity(owner)) {
		return MRES_Ignored;
	}
	
	float vecOrigin[3];
	GetEntPropVector(owner, Prop_Data, "m_vecAbsOrigin", vecOrigin);
	
	int entity = -1;
	while ((entity = FindEntityInSphere(entity, vecOrigin, HUO_LONG_IGNITE_RADIUS)) != -1) {
		if (IsEntityOilTrigger(entity)) {
			AcceptEntityInput(entity, "Detonate");
		}
	}
	
	return MRES_Ignored;
}

bool IsEntityOilTrigger(int entity) {
	char targetName[64];
	GetEntityTargetName(entity, targetName, sizeof(targetName));
	return StrEqual(targetName, OIL_DAMAGE_TRIGGER_NAME);
}

/**
 * Return true the oil trigger can be activated by the given `weapon`, `inflictor`, or
 * `damagetype`.
 */
bool ShouldActivateOilTrigger(int weapon, int inflictor, int damagetype) {
	// contact fire damage (flamethrower, flares)
	if (damagetype & DMG_PLASMA) {
		return true;
	}
	
	// weapons that ignite on hit (SVF and potential custom weapons)
	if (TF2Attrib_HookValueInt(0, "set_dmgtype_ignite", weapon)) {
		return true;
	}
	
	// Huntsman arrows
	if (HasEntProp(inflictor, Prop_Send, "m_bArrowAlight")
			&& !!GetEntProp(inflictor, Prop_Send, "m_bArrowAlight")) {
		return true;
	}
	
	return false;
}

void RemoveEntityDelayed(int entity, float flTime) {
	CreateTimer(flTime, RemoveEntityDelayedFinished, EntIndexToEntRef(entity));
}

Action RemoveEntityDelayedFinished(Handle timer, int oilref) {
	int oilEntity = EntRefToEntIndex(oilref);
	if (IsValidEntity(oilEntity)) {
		RemoveEntity(oilEntity);
	}
}

/** 
 * This is the reversed logic for CTFBat_Wood::GetBallDynamics(), which determines the spawning
 * parameters for the baseball.
 */
void GetProjectileDynamics(int client, float vecSpawnOrigin[3], float vecSpawnAngles[3],
		float vecVelocity[3], float vecAngVelocity[3]) {
	float vecEyeAngles[3], vecEyeForward[3], vecEyeUp[3];
	GetClientEyeAngles(client, vecEyeAngles);
	GetAngleVectors(vecEyeAngles, vecEyeForward, NULL_VECTOR, vecEyeUp);
	
	// spawn height from origin
	// CopyVector(vecEyeForward, vecSpawnOrigin);
	vecSpawnOrigin = vecEyeForward;
	
	float flModelScale = GetEntPropFloat(client, Prop_Send, "m_flModelScale");
	ScaleVector(vecSpawnOrigin, 32.0 * flModelScale);
	
	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);
	AddVectors(vecOrigin, vecSpawnOrigin, vecSpawnOrigin);
	vecSpawnOrigin[2] += 50.0 * flModelScale;
	
	GetEntPropVector(client, Prop_Data, "m_angAbsRotation", vecSpawnAngles);
	
	float vecEyeForwardScale[3];
	vecEyeForwardScale = vecEyeForward;
	ScaleVector(vecEyeForwardScale, 10.0);
	
	AddVectors(vecEyeForwardScale, vecEyeUp, vecEyeUp);
	NormalizeVector(vecEyeUp, vecEyeUp);
	
	ScaleVector(vecEyeUp, 250.0);
	vecVelocity = vecEyeUp;
	
	vecAngVelocity[1] = GetRandomFloat(0.0, 100.0);
	return;
}

int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius);
}
