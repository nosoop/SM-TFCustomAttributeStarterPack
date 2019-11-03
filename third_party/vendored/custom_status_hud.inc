#if defined __custom_status_hud_included
	#endinput
#endif

#define __custom_status_hud_included

/**
 * Called whenever the plugin is ready to update the custom client HUD.
 * 
 * @param entries		A map of string values to be displayed.  Keys determine sorting in
 * 						alphabetical order.
 */
forward Action OnCustomStatusHUDUpdate(int client, StringMap entries);

public SharedPlugin __pl_custom_status_hud = {
	name = "custom_status_hud",
	file = "custom_status_hud.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
