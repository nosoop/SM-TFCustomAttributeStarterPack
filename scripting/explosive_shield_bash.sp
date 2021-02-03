/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <tf2utils>
#include <sdktools>
#include <sdkhooks> // we don't actually use this except for the DMG_* defines
#include <dhooks>

#include <tf2wearables>

#include <tf_custom_attributes>
#include <stocksoup/tf/tempents_stocks>
#include <stocksoup/var_strings>

#include <tf_damageinfo_tools>

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
	}
	
	// Handle dtShieldBash = DHookCreateFromConf(hGameConf, "CTFWearableDemoShield::ShieldBash()");
	// if (!dtShieldBash) {
		// SetFailState("Failed to create detour %s", "CTFWearableDemoShield::ShieldBash()");
	// }
	// DHookEnableDetour(dtShieldBash, true, OnShieldBashPost);
	
	delete hGameConf;
}

// MRESReturn OnShieldBashPost(int shield, Handle hParams) {
public void TF2_OnConditionRemoved(int client, TFCond condition) {
	if (condition != TFCond_Charging) {
		return;
	}
	
	int shield = TF2_GetPlayerLoadoutSlot(client, TF2LoadoutSlot_Secondary);
	
	// PrintToServer("shield bashing...");
	// int client = DHookGetParam(hParams, 1);
	// float flCharge = DHookGetParam(hParams, 2);
	// PrintToServer("shield bash: %N / %f charge", client, flCharge);
	
	char attr[128];
	if (!TF2CustAttr_GetString(shield, "exploding shield bash", attr, sizeof(attr))) {
		// return MRES_Ignored;
		return;
	}
	
	float vecShootPos[3];
	TF2Util_GetPlayerShootPosition(client, vecShootPos);
	
	TE_SetupTFExplosion(vecShootPos, .weaponid = TF_WEAPON_GRENADELAUNCHER, .entity = shield,
			.particleIndex = FindParticleSystemIndex("fluidSmokeExpl_ring_mvm"));
	TE_SendToAll();
	
	char particle[64];
	if (ReadStringVar(attr, "particle", particle, sizeof(particle))) {
		TE_SetupTFParticleEffect(particle, vecShootPos);
		TE_SendToAll();
	}
	
	char sound[64];
	if (ReadStringVar(attr, "sound", sound, sizeof(sound))) {
		EmitGameSoundToAll(sound, shield);
	}
	
	float radius = ReadFloatVar(attr, "radius", 100.0);
	float damage = ReadFloatVar(attr, "damage", 75.0);
	
	// aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
	CTakeDamageInfo damageInfo = new CTakeDamageInfo(client, client, damage,
			DMG_BLAST | DMG_SLOWBURN, shield, vecShootPos, vecShootPos, vecShootPos,
			TF_CUSTOM_STICKBOMB_EXPLOSION);
	
	CTFRadiusDamageInfo radiusInfo = new CTFRadiusDamageInfo(damageInfo, vecShootPos, radius);
	
	radiusInfo.Apply();
	
	delete radiusInfo;
	delete damageInfo;
	
	// return MRES_Ignored;
}

int FindParticleSystemIndex(const char[] name) {
	int particleTable, particleIndex;
	if ((particleTable = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) {
		ThrowError("Could not find string table: ParticleEffectNames");
	}
	if ((particleIndex = FindStringIndex(particleTable, name)) == INVALID_STRING_INDEX) {
		ThrowError("Could not find particle index: %s", name);
	}
	return particleIndex;
}
