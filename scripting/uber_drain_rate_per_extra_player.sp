/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdktools>
#include <dhooks>
#include <sourcescramble>
#include <stocksoup/memory>
#include <tf_custom_attributes>

#define BASE_UBER_DRAIN_RATE    0.5

float g_flUberDrainMultiplier;

public void OnPluginStart() {
	GameData hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtMedigunDrainCharge = DHookCreateFromConf(hGameConf,
			"CWeaponMedigun::DrainCharge()");
	if (!dtMedigunDrainCharge) {
		SetFailState("Failed to create detour " ... "CWeaponMedigun::DrainCharge()");
	}
	DHookEnableDetour(dtMedigunDrainCharge, false, OnMedigunDrainCharge);
	
	MemoryPatch patchExtraDrainRate = MemoryPatch.CreateFromConf(hGameConf,
			"CWeaponMedigun::DrainCharge()::PatchExtraDrainRate");
	if (!patchExtraDrainRate.Validate()) {
		SetFailState("Failed to validate patch "
				... "CWeaponMedigun::DrainCharge()::PatchExtraDrainRate");
	}
	
	Address ppValue = patchExtraDrainRate.Address + view_as<Address>(4);
	Address pValue = DereferencePointer(ppValue);
	float value = view_as<float>(LoadFromAddress(pValue, NumberType_Int32));
	if (value != BASE_UBER_DRAIN_RATE) {
		SetFailState("Unexpected value being overwritten for "
				... "CWeaponMedigun::DrainCharge()::PatchExtraDrainRate "
				... "(expected %.2f, got %.2f)", BASE_UBER_DRAIN_RATE, value);
	}
	
	patchExtraDrainRate.Enable();
	StoreToAddress(ppValue, view_as<any>(GetAddressOfCell(g_flUberDrainMultiplier)),
			NumberType_Int32);
	
	delete hGameConf;
}

MRESReturn OnMedigunDrainCharge(int medigun) {
	g_flUberDrainMultiplier = BASE_UBER_DRAIN_RATE;
	if (IsValidEntity(medigun)) {
		g_flUberDrainMultiplier = TF2CustAttr_GetFloat(medigun,
				"ubercharge drain rate per extra player", BASE_UBER_DRAIN_RATE);
	}
	return MRES_Ignored;
}
