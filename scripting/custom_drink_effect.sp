/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/log_server>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_custom_attributes>

#define CUSTOM_DRINK_EFFECT_MAX_NAME_LENGTH 64

enum eTFTauntAttack {
	TF_TAUNTATTACK_LUNCHBOX = 5
};

StringMap g_DrinkForwards;
int offs_CTFPlayer_iTauntAttack;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("cattr-custom-drink");
	
	CreateNative("TF2CustomAttrDrink_Register", RegisterCustomDrinkEffect);
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	Handle dtLunchBoxPrimaryAttack =
			DHookCreateFromConf(hGameConf, "CTFPlayer::DoTauntAttack()");
	DHookEnableDetour(dtLunchBoxPrimaryAttack, false, OnDoTauntAttackPre);
	
	Address pTauntAttackInfo = GameConfGetAddress(hGameConf,
			"CTFPlayer::DoTauntAttack()::TauntAttackOffset");
	offs_CTFPlayer_iTauntAttack = LoadFromAddress(pTauntAttackInfo, NumberType_Int32);
	if (offs_CTFPlayer_iTauntAttack & 0xFFFF != offs_CTFPlayer_iTauntAttack) {
		SetFailState("Couldn't determine offset for CTFPlayer::m_iTauntAttack.");
	}
	LogServer("offsetof(CTFPlayer, m_iTauntAttack) == 0x%04X", offs_CTFPlayer_iTauntAttack);
	
	delete hGameConf;
	
	g_DrinkForwards = new StringMap();
}

public int RegisterCustomDrinkEffect(Handle plugin, int argc) {
	char buffName[CUSTOM_DRINK_EFFECT_MAX_NAME_LENGTH];
	GetNativeString(1, buffName, sizeof(buffName));
	if (!buffName[0]) {
		ThrowNativeError(1, "Cannot have an empty custom drink effect name.");
	}
	
	Handle hFwd;
	if (!g_DrinkForwards.GetValue(buffName, hFwd)) {
		hFwd = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_String);
		g_DrinkForwards.SetValue(buffName, hFwd);
	}
	AddToForward(hFwd, plugin, GetNativeFunction(2));
}

public MRESReturn OnDoTauntAttackPre(int client) {
	if (GetClientTauntAttack(client) != TF_TAUNTATTACK_LUNCHBOX) {
		return MRES_Ignored;
	}
	
	int weapon = TF2_GetClientActiveWeapon(client);
	
	char attr[64];
	if (!IsValidEntity(weapon)
			|| !TF2CustAttr_GetString(weapon, "custom drink effect", attr, sizeof(attr))) {
		return MRES_Ignored;
	}
	
	HandleCustomDrinkEffect(client, weapon, attr);
	
	return MRES_Supercede;
}

void HandleCustomDrinkEffect(int client, int weapon, const char[] effectName) {
	// TODO fire off private forward
	Handle hFwd;
	if (!g_DrinkForwards.GetValue(effectName, hFwd) || !GetForwardFunctionCount(hFwd)) {
		LogError("Custom drink effect '%s' is not associated with a plugin", effectName);
		return;
	}
	
	Call_StartForward(hFwd);
	Call_PushCell(client);
	Call_PushCell(weapon);
	Call_PushString(effectName);
	Call_Finish();
}

static eTFTauntAttack GetClientTauntAttack(int client) {
	return view_as<eTFTauntAttack>(GetEntData(client, offs_CTFPlayer_iTauntAttack));
}