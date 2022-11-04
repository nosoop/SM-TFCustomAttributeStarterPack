/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <tf2_stocks>
#include <stocksoup/tf/entity_prop_stocks>
#include <tf_cattr_buff_override>

public void OnCustomBuffHandlerAvailable() {
	TF2CustomAttrRageBuff_Register("crit-banner", OnCritBannerPulse);
}

void OnCritBannerPulse(int owner, int target, const char[] name, int buffItem) {
	TFTeam buffTeam = TF2_GetClientTeam(owner);
	
	// disallow enemies, allow disguised players, disallow cloaked
	if (TF2_GetClientTeamFromClient(target, owner) != buffTeam
			|| TF2_IsPlayerInCondition(target, TFCond_Cloaked)
			|| TF2_IsPlayerInCondition(target, TFCond_Stealthed)) {
		return;
	}
	
	// the game internally does this
	TF2_AddCondition(target, TFCond_MarkedForDeath, BUFF_PULSE_CONDITION_DURATION, owner);
	TF2_AddCondition(target, TFCond_Kritzkrieged, BUFF_PULSE_CONDITION_DURATION, owner);
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "cattr-buff-override")) {
		OnCustomBuffHandlerAvailable();
	}
}
