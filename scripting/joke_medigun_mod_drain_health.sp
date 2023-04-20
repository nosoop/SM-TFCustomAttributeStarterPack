/**
 * Monolith plugin for Karma Charger's Medick-Gun.
 * 
 * For damaging teammates to work properly, mp_friendlyfire must be set to 1.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>
#include <sdkhooks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <stocksoup/tf/client>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/tempents_stocks>
#include <smlib/clients>
#include <tf2utils>

#include <dhooks_gameconf_shim>

Handle g_DHookWeaponPostFrame;
Handle g_SDKCallFindEntityInSphere;
Handle g_SDKCallGetCombatCharacterPtr;

// read from CTFPlayer::DeathSound() disasm
// TODO actually read from gameconf? have to find windows sigs if I did
int offs_CTFPlayer_LastDamageType = 0x2168;

bool bIsPlayerDraining[MAXPLAYERS + 1];

float g_flDamageAccumulated[MAXPLAYERS + 1];

char g_MedicScripts[][] = {
	"medic_sf13_influx_big03",
	"medic_sf13_magic_reac07",
	"Medic.CritDeath",
};

ConVar cattr_medigun_drain_gratuitous_violence;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
		SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
	}
	
	StartPrepSDKCall(SDKCall_EntityList);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CGlobalEntityList::FindEntityInSphere()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer,
			VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallFindEntityInSphere = EndPrepSDKCall();

	if (!g_SDKCallFindEntityInSphere) {
		SetFailState("Failed to setup SDKCall for CGlobalEntityList::FindEntityInSphere()");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual,
			"CBaseEntity::MyCombatCharacterPointer()");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallGetCombatCharacterPtr = EndPrepSDKCall();

	if (!g_SDKCallGetCombatCharacterPtr) {
		SetFailState("Failed to setup SDKCall for CBaseEntity::MyCombatCharacterPointer()");
	}

	Handle dtMedigunAllowedToHealTarget = GetDHooksDefinition(hGameConf,
			"CWeaponMedigun::AllowedToHealTarget()");

	if (!dtMedigunAllowedToHealTarget) {
		SetFailState("Failed to setup detour for CWeaponMedigun::AllowedToHealTarget()");
	}

	DHookEnableDetour(dtMedigunAllowedToHealTarget, false, OnAllowedToHealTargetPre);

	Handle dtRecalculateChargeEffects = GetDHooksDefinition(hGameConf,
			"CTFPlayerShared::RecalculateChargeEffects()");

	if (!dtRecalculateChargeEffects) {
		SetFailState("Failed to setup detour for CTFPlayerShared::RecalculateChargeEffects()");
	}
	
	DHookEnableDetour(dtRecalculateChargeEffects, false, OnRecalculateChargeEffectsPre);

	Handle dtStopHealing = GetDHooksDefinition(hGameConf,
			"CTFPlayerShared::StopHealing()");

	if (!dtStopHealing) {
		SetFailState("Failed to setup detour for CTFPlayerShared::StopHealing()");
	}

	DHookEnableDetour(dtStopHealing, false, OnStopHealingPre);

	Handle dtMedigunSecondaryAttack = GetDHooksDefinition(hGameConf,
			"CWeaponMedigun::SecondaryAttack()");

	if (!dtMedigunSecondaryAttack) {
		SetFailState("Failed to setup detour for CWeaponMedigun::SecondaryAttack()");
	}

	DHookEnableDetour(dtMedigunSecondaryAttack, false, OnMedigunSecondaryAttackPre);
	
	g_DHookWeaponPostFrame = GetDHooksDefinition(hGameConf,
			"CBaseCombatWeapon::ItemPostFrame()");

	if (!g_DHookWeaponPostFrame) {
		SetFailState("Failed to setup detour for CBaseCombatWeapon::ItemPostFrame()");
	}
	
	Handle dtCreateRagdoll = GetDHooksDefinition(hGameConf, "CTFPlayer::CreateRagdollEntity()");
	
	if (!dtCreateRagdoll) {
		SetFailState("Failed to setup detour for CTFPlayer::CreateRagdollEntity()");
	}

	DHookEnableDetour(dtCreateRagdoll, false, OnCreateRagdollPre);
	
	int offslastDamage = FindSendPropInfo("CTFPlayer", "m_flMvMLastDamageTime");
	if (offslastDamage < 0) {
		SetFailState("Could not get offset for CTFPlayer::m_flMvMLastDamageTime");
	}
	
	offs_CTFPlayer_LastDamageType = offslastDamage + 0x14;
	
	ClearDHooksDefinitions();
	
	delete hGameConf;
	
	cattr_medigun_drain_gratuitous_violence =
			CreateConVar("cattr_medigun_drain_gratuitous_violence", "1",
			"Use dramatic death effects for players killed using medigun drain.");
	
	HookEvent("player_death", OnPlayerDeath);
}

public void OnMapStart() {
	PrecacheScriptSound("MVM.BombExplodes");
	PrecacheSound("mvm/mvm_bomb_explode.wav");
	for (int i; i < sizeof(g_MedicScripts); i++) {
		PrecacheScriptSound(g_MedicScripts[i]);
	}
	
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_weapon_medigun")) != -1) {
		DHookEntity(g_DHookWeaponPostFrame, true, entity, .callback = OnMedigunPostFramePost);
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flDamageAccumulated[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);
}

// CTFPlayerShared::StopHealing() doesn't get called when a player disconnects.
public void OnClientDisconnect_Post(int iClient) {
	bIsPlayerDraining[iClient] = false;
}

static bool s_ForceCritDeathSound;
void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage,
		int damagetype) {
	if (!s_ForceCritDeathSound) {
		return;
	}
	
	// forces crit damagetype so we get the crit death sound
	SetEntData(victim, offs_CTFPlayer_LastDamageType, DMG_CRIT);
}

public void OnEntityCreated(int entity, const char[] className) {
	if (StrEqual(className, "tf_weapon_medigun")) {
		DHookEntity(g_DHookWeaponPostFrame, true, entity, .callback = OnMedigunPostFramePost);
	}
}

static bool s_ForceGibRagdoll;
MRESReturn OnCreateRagdollPre(int client, Handle hParams) {
	if (!s_ForceGibRagdoll) {
		return MRES_Ignored;
	}
	DHookSetParam(hParams, 1, true);
	return MRES_ChangedHandled;
}

// setting this up as a post hook causes windows srcds to crash
MRESReturn OnAllowedToHealTargetPre(int medigun, Handle hReturn, Handle hParams) {
	if (!TF2CustAttr_GetFloat(medigun, "medigun drains health")) {
		return MRES_Ignored;
	}

	int healer = TF2_GetEntityOwner(medigun);
	int target = DHookGetParam(hParams, 1);

	if (!IsEntityInGameClient(healer) || !IsEntityInGameClient(target)) {
		DHookSetReturn(hReturn, false);
		return MRES_Supercede;
	}

	if (IsTargetInUberState(target) || TF2_IsPlayerInCondition(target, TFCond_Cloaked)) {
		DHookSetReturn(hReturn, false);
		return MRES_Supercede;
	}

	DHookSetReturn(hReturn, true);

	bIsPlayerDraining[healer] = true;

	return MRES_Supercede;
}

MRESReturn OnRecalculateChargeEffectsPre(Address pPlayerShared, Handle hParams) {
	int client = TF2Util_GetPlayerFromSharedAddress(pPlayerShared);

	bool bIsPlayerBeingDrained = false;

	if (!IsEntityInGameClient(client)) {
		return MRES_Ignored;
	}

	int numHealers = GetEntProp(client, Prop_Send, "m_nNumHealers");

	for (int i = 0; i < numHealers; i++) {
		int healer = TF2Util_GetPlayerHealer(client, i);
		if (!IsEntityInGameClient(healer)) {
			return MRES_Ignored;
		}

		int weapon = TF2_GetClientActiveWeapon(healer);
		if (!weapon || !IsValidEntity(weapon)
				|| TF2Util_GetWeaponID(weapon) != TF_WEAPON_MEDIGUN) {
			return MRES_Ignored;
		}

		if (!bIsPlayerDraining[healer]) {
			return MRES_Ignored;
		}

		if (IsTargetInUberState(client)) {
			SetEntPropEnt(weapon, Prop_Send, "m_hHealingTarget", -1);
			bIsPlayerBeingDrained = true;
		}
	}

	if (bIsPlayerBeingDrained) {
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

MRESReturn OnMedigunPostFramePost(int medigun) {
	int healer = TF2_GetEntityOwner(medigun);
	if (!bIsPlayerDraining[healer]) {
		return MRES_Ignored;
	}

	int healTarget = GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget");
	if (!IsEntityInGameClient(healTarget)) {
		// don't process non-client targets
		return MRES_Ignored;
	}
	
	float flDrainRate = TF2CustAttr_GetFloat(medigun, "medigun drains health");
	if (flDrainRate == 0.0) {
		return MRES_Ignored;
	}
	
	// TODO fix not being able to damage friendly players with owner set without friendlyfire??
	
	// use accumulator to allow fractional damage per tick
	g_flDamageAccumulated[healTarget] += flDrainRate * GetGameFrameTime();
	if (g_flDamageAccumulated[healTarget] < 1.0) {
		return MRES_Ignored;
	}
	
	s_ForceGibRagdoll = cattr_medigun_drain_gratuitous_violence.BoolValue;
	s_ForceCritDeathSound = cattr_medigun_drain_gratuitous_violence.BoolValue;
	
	int damageInflicted = RoundToFloor(g_flDamageAccumulated[healTarget]);
	
	SDKHooks_TakeDamage(healTarget, medigun, healer, float(damageInflicted),
			DMG_PREVENT_PHYSICS_FORCE | DMG_ALWAYSGIB);
	
	g_flDamageAccumulated[healTarget] -= damageInflicted;
	
	s_ForceCritDeathSound = false;
	s_ForceGibRagdoll = false;
	
	if (!IsPlayerAlive(healTarget)) {
		float flChargeLevel = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
		flChargeLevel += 0.1;
		if (flChargeLevel > 1.0) {
			flChargeLevel = 1.0;
		}
		SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", flChargeLevel);
	}
	
	return MRES_Ignored;
}

MRESReturn OnStopHealingPre(Address pPlayerShared, Handle hParams) {
	int healer = DHookGetParam(hParams, 1);
	if (!IsEntityInGameClient(healer)) {
		return MRES_Ignored;
	}

	int iWeapon = GetPlayerWeaponSlot(healer, 1);
	if (iWeapon <= 0 || !IsValidEntity(iWeapon) || !TF2Util_IsEntityWeapon(iWeapon)) {
		return MRES_Ignored;
	}

	if (!TF2CustAttr_GetFloat(iWeapon, "medigun drains health")) {
		return MRES_Ignored;
	}

	bIsPlayerDraining[healer] = false;

	return MRES_Ignored;
}

void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!s_ForceGibRagdoll) {
		return;
	}
	
	float vecOrigin[3], vecMins[3], vecMaxs[3];
	GetClientAbsOrigin(client, vecOrigin);
	GetClientMins(client, vecMins);
	GetClientMaxs(client, vecMaxs);
	
	vecOrigin[2] += (vecMaxs[2] - vecMins[2]) / 2.0;
	
	TE_SetupTFExplosion(vecOrigin, view_as<float>({ 0.0, 1.0, 0.0 }), TF_WEAPON_ROCKETLAUNCHER);
	TE_SendToAll();
}

MRESReturn OnMedigunSecondaryAttackPre(int medigun) {
	// TODO handle medigun
	if (TF2CustAttr_GetFloat(medigun, "ubercharge nukes everything in radius") == 0.0) {
		return MRES_Ignored;
	}
	
	float flChargeMeter = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
	if (flChargeMeter < 1.0) {
		return MRES_Supercede;
	}
	
	int owner = TF2_GetEntityOwner(medigun);
	
	EmitGameSoundToAll(g_MedicScripts[GetRandomInt(0, sizeof(g_MedicScripts) - 1)], owner);
	EmitGameSoundToAll("MVM.BombExplodes", owner);
	
	MedicDetonate(medigun);
	
	return MRES_Supercede;
}

void MedicDetonate(int medigun) {
	float radius = TF2CustAttr_GetFloat(medigun, "ubercharge nukes everything in radius");
	if (radius == 0.0) {
		return;
	}
	
	int owner = TF2_GetEntityOwner(medigun);
	if (!IsValidEntity(owner) || !IsPlayerAlive(owner)) {
		return;
	}
	
	// ForcePlayerSuicide(owner);
	SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", 0.0);
	
	float vecOrigin[3];
	GetClientAbsOrigin(owner, vecOrigin);
	
	Client_Shake(owner);
	
	TE_SetupTFParticleEffect("fluidSmokeExpl_ring_mvm", vecOrigin);
	TE_SendToAll();
	
	int entity = -1;
	while ((entity = FindEntityInSphere(entity, vecOrigin, radius)) != -1) {
		// damage combat characters (buildings, players, tanks...)
		if (IsEntityCombatCharacter(entity) && entity != owner) {
			s_ForceCritDeathSound = cattr_medigun_drain_gratuitous_violence.BoolValue;
			s_ForceGibRagdoll = cattr_medigun_drain_gratuitous_violence.BoolValue;
			SDKHooks_TakeDamage(entity, medigun, owner, 69420.0,
					DMG_PREVENT_PHYSICS_FORCE | DMG_ALWAYSGIB);
			s_ForceCritDeathSound = false;
			s_ForceGibRagdoll = false;
			continue;
		}
		
		// destroy nearby buildings??
	}
}

static int FindEntityInSphere(int startEntity, const float vecPosition[3], float flRadius) {
	return SDKCall(g_SDKCallFindEntityInSphere, startEntity, vecPosition, flRadius, Address_Null);
}

bool IsEntityCombatCharacter(int entity) {
	return SDKCall(g_SDKCallGetCombatCharacterPtr, entity) != Address_Null;
}

stock bool IsEntityInGameClient(int entity) {
	if (entity <= 0 || entity > MaxClients) {
		return false;
	}

	if (!IsClientInGame(entity)) {
		return false;
	}
	
	return true;
}

stock bool IsTargetInUberState(int client) {
	return (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) 
		 || TF2_IsPlayerInCondition(client, TFCond_UberchargeFading) 
		 || TF2_IsPlayerInCondition(client, TFCond_UberchargedHidden) 
		 || TF2_IsPlayerInCondition(client, TFCond_UberchargedCanteen) 
		 || TF2_IsPlayerInCondition(client, TFCond_UberchargedOnTakeDamage));
}
