#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <tf2_stocks>

#pragma newdecls required

#include <tf_custom_attributes>
#include <sourcescramble>
#include <stocksoup/log_server>
#include <stocksoup/memory>

#define FLOAT_MAX view_as<float>(0x7F7FFFFF)

Address g_offset_CTFPlayerShared_pOuter;

float g_flDefaultCloakTimerValue;

MemoryPatch g_PatchCloakTimer;
MemoryBlock g_CloakTimerAmount;

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
	
	Handle dtUpdateCloakMeter = DHookCreateFromConf(hGameConf,
			"CTFPlayerShared::UpdateCloakMeter()");
	DHookEnableDetour(dtUpdateCloakMeter, false, OnUpdateCloakMeterPre);
	
	g_offset_CTFPlayerShared_pOuter =
			view_as<Address>(GameConfGetOffset(hGameConf, "CTFPlayerShared::m_pOuter"));
	
	delete hGameConf;
}

public MRESReturn OnUpdateCloakMeterPre(Address pShared) {
	int client = GetClientFromPlayerShared(pShared);
	UpdateCloakDebuffAmount(g_flDefaultCloakTimerValue);
	
	if (!TF2_IsPlayerInCondition(client, TFCond_Cloaked)) {
		return MRES_Ignored;
	}
	
	int watch = GetPlayerWeaponSlot(client, TFWeaponSlot_Building);
	if (!IsValidEntity(watch)) {
		return MRES_Ignored;
	}
	float flNewRate = TF2CustAttr_GetFloat(watch, "cloak debuff time scale",
			1.0 / (1 + g_flDefaultCloakTimerValue));
	
	float flTimeValue = CalculateReductionRateFromMultiplier(flNewRate);
	UpdateCloakDebuffAmount(flTimeValue);
	return MRES_Ignored;
}

// calculation for new debuff time
// rate = 1 / (1 + time_value)
// rate * (1 + time_value) = 1
// time_value = (1 - rate) / rate

float CalculateReductionRateFromMultiplier(float flTimeScale) {
	if (flTimeScale <= 0.0) {
		// if debuff rate = 0, use largest float to try and instantly clear the condition
		return FLOAT_MAX;
	}
	return (1 - flTimeScale) / flTimeScale;
}

void UpdateCloakDebuffAmount(float flValue) {
	g_CloakTimerAmount.StoreToOffset(0, view_as<int>(flValue), NumberType_Int32);
}

static int GetClientFromPlayerShared(Address pPlayerShared) {
	Address pOuter = view_as<Address>(LoadFromAddress(
			pPlayerShared + g_offset_CTFPlayerShared_pOuter, NumberType_Int32));
	return GetEntityFromAddress(pOuter);
}
