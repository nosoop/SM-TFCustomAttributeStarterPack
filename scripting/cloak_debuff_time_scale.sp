/**
 * The game applies a set decrease on each "debuff" condition's timer while the player is
 * cloaked during CTFPlayerShared::UpdateCloakMeter().  This plugin patches the value so we can
 * substitute it with our own value.
 */

#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <tf2_stocks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <sourcescramble>
#include <stocksoup/log_server>
#include <stocksoup/memory>
#include <stocksoup/tf/entity_prop_stocks>

#define FLOAT_MAX view_as<float>(0x7F7FFFFF)

float g_flDefaultCloakTimerValue;

MemoryPatch g_PatchCloakTimer;
MemoryBlock g_CloakTimerAmount;

float g_flComputedDefuffRates[MAXPLAYERS + 1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	g_PatchCloakTimer = MemoryPatch.CreateFromConf(hGameConf,
			"CTFPlayerShared::UpdateCloakMeter()::ModifyDebuffReduction");
	
	{
		// the address is a float pointer, so we need to deref once to get the pointer, then
		// a second to get the float value
		Address ppFloat = g_PatchCloakTimer.Address + view_as<Address>(0x04);
		
		g_flDefaultCloakTimerValue = view_as<float>(
				DereferencePointer(DereferencePointer(ppFloat)));
		LogServer("Default cloak scaling value @ %08x is %.2f", ppFloat,
				g_flDefaultCloakTimerValue);
		
		if (!g_PatchCloakTimer.Enable()) {
			SetFailState("Failed to inustall debuff reduction patch");
		}
		
		g_CloakTimerAmount = new MemoryBlock(4);
		UpdateCloakDebuffAmount(g_flDefaultCloakTimerValue);
		
		StoreToAddress(ppFloat, view_as<int>(g_CloakTimerAmount.Address), NumberType_Int32);
	}
	
	Handle dtSetCloakRates = DHookCreateFromConf(hGameConf, "CTFWeaponInvis::SetCloakRates()");
	DHookEnableDetour(dtSetCloakRates, false, OnSetCloakRatesPre);
	
	Handle dtUpdateCloakMeter = DHookCreateFromConf(hGameConf,
			"CTFPlayerShared::UpdateCloakMeter()");
	DHookEnableDetour(dtUpdateCloakMeter, false, OnUpdateCloakMeterPre);
	
	delete hGameConf;
}

/**
 * Computes the "reduction rate" (which is the amount of time decremented per second), caching
 * it so we don't have to pull the attribute value on every frame that the player is cloaked.
 * 
 * As of this writing, the game reduces debuffs by 0.75s per second (~42% debuff duration
 * reduction).
 */
MRESReturn OnSetCloakRatesPre(int invisWatch) {
	int owner = TF2_GetEntityOwner(invisWatch);
	if (owner < 1 || owner > MaxClients) {
		return MRES_Ignored;
	}
	
	// if attribute isn't specified, fall back to game's default (with roundabout calculation)
	float flNewRate = TF2CustAttr_GetFloat(invisWatch, "cloak debuff time scale",
			1.0 / (1 + g_flDefaultCloakTimerValue));
	g_flComputedDefuffRates[owner] = CalculateReductionRateFromMultiplier(flNewRate);
	return MRES_Ignored;
}

/**
 * Patches the per-client unique reduction rate into the function.
 */
MRESReturn OnUpdateCloakMeterPre(Address pShared) {
	int client = TF2Util_GetPlayerFromSharedAddress(pShared);
	UpdateCloakDebuffAmount(g_flComputedDefuffRates[client]);
	return MRES_Ignored;
}

// the value that is injected into the game is the amount of time each debuff is reduced per
// second
// 
// calculation for new debuff time based on debuff scalar
// rate = 1 / (1 + time_value)
// rate * (1 + time_value) = 1
// time_value = (1 - rate) / rate

float CalculateReductionRateFromMultiplier(float flTimeScale) {
	if (flTimeScale <= 0.0) {
		// if debuff rate <= 0, use largest float to instantly clear non-infinite conditions
		return FLOAT_MAX;
	}
	return (1 - flTimeScale) / flTimeScale;
}

void UpdateCloakDebuffAmount(float flValue) {
	g_CloakTimerAmount.StoreToOffset(0, view_as<int>(flValue), NumberType_Int32);
}
