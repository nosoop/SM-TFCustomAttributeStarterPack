#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <sourcescramble>
#include <tf_custom_attributes>

#define MAX_CLASSNAME_LENGTH 64

MemoryPatch g_OverwriteLunchboxEntityClass;
MemoryBlock g_pszLunchboxClass;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtLunchboxSecondaryAttack =
			DHookCreateFromConf(hGameConf, "CTFLunchBox::SecondaryAttack()");
	if (!dtLunchboxSecondaryAttack) {
		SetFailState("Failed to create detour %s", "CTFLunchBox::SecondaryAttack()");
	}
	DHookEnableDetour(dtLunchboxSecondaryAttack, false, OnLunchBoxSecondaryAttackPre);
	
	g_OverwriteLunchboxEntityClass = MemoryPatch.CreateFromConf(hGameConf,
			"CTFLunchBox::SecondaryAttack()::OverwriteDroppedEntityClass");
	
	g_pszLunchboxClass = new MemoryBlock(MAX_CLASSNAME_LENGTH);
	
	delete hGameConf;
}

MRESReturn OnLunchBoxSecondaryAttackPre(int lunchbox) {
	g_OverwriteLunchboxEntityClass.Disable();
	
	char buffer[MAX_CLASSNAME_LENGTH];
	if (!TF2CustAttr_GetString(lunchbox, "lunchbox override pickup type", buffer,
			sizeof(buffer))) {
		return MRES_Ignored;
	}
	
	static char validClasses[][] = {
		"item_healthammokit",
		"item_ammopack_small", "item_ammopack_medium", "item_ammopack_full",
		"item_healthkit_small", "item_healthkit_medium", "item_healthkit_full",
	};
	
	bool bufferValid;
	for (int i; i < sizeof(validClasses); i++) {
		if (StrEqual(buffer, validClasses[i])) {
			bufferValid = true;
			break;
		}
	}
	
	if (!bufferValid) {
		LogError("Attempted to set lunchbox item to invalid entity '%s'", buffer);
		return MRES_Ignored;
	}
	
	// patch sets assigned char pointer to override then skips the other assignment cases
	for (int i; i < sizeof(buffer); i++) {
		g_pszLunchboxClass.StoreToOffset(i, buffer[i] & 0xFF, NumberType_Int8);
	}
	
	g_OverwriteLunchboxEntityClass.Enable();
	StoreToAddress(g_OverwriteLunchboxEntityClass.Address + view_as<Address>(0x01),
			view_as<int>(g_pszLunchboxClass.Address), NumberType_Int32);
	
	return MRES_Ignored;
}
