/**
 * 
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <tf_custom_attributes>
#include <tf2_stocks>
#include <stocksoup/var_strings>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2CA] Building Health Override",
	author = "nosoop",
	description = "Attribute that allows constrol over building health.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomAttributeStarterPack"
}

public void OnPluginStart() {
	HookEvent("player_builtobject", OnObjectBuilt);
}

void OnObjectBuilt(Event event, const char[] className, bool dontBroadcast) {
	int building = event.GetInt("index");
	int builder = GetClientOfUserId(event.GetInt("userid"));
	
	if (!builder) {
		return;
	}
	
	int override = GetObjectHealthOverride(builder, TF2_GetObjectType(building),
			TF2_GetObjectMode(building));
	if (override > 0) {
		SetEntProp(building, Prop_Send, "m_iMaxHealth", override);
	}
}

int GetObjectHealthOverride(int client, TFObjectType objectType,
		TFObjectMode objectMode = TFObjectMode_None) {
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	char value[128];
	if (!IsValidEntity(melee)
			|| !TF2CustAttr_GetString(melee, "mod building health", value, sizeof(value))) {
		return 0;
	}
	
	switch (objectType) {
		case TFObject_Sentry: {
			return ReadIntVar(value, "sentry");
		}
		case TFObject_Dispenser: {
			return ReadIntVar(value, "dispenser");
		}
		case TFObject_Teleporter: {
			switch (objectMode) {
				case TFObjectMode_Entrance: {
					int entranceHealth;
					if ((entranceHealth = ReadIntVar(value, "teleporter_entrance")) > 0) {
						return entranceHealth;
					}
				}
				case TFObjectMode_Exit: {
					int entranceHealth;
					if ((entranceHealth = ReadIntVar(value, "teleporter_exit")) > 0) {
						return entranceHealth;
					}
				}
			}
			return ReadIntVar(value, "teleporter");
		}
	}
	return 0;
}
