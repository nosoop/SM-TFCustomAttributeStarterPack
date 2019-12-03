#if defined __tf_cattr_lunch_effect_included
	#endinput
#endif

#define __tf_cattr_lunch_effect_included

/**
 * Called when a player activates their lunch item.
 */
typedef LunchEffectCallback = function void(int owner, int weapon, const char[] effectName);

/**
 * Registers a custom drink effect.  The given callback is fired if the player owns a drink item
 * with "custom drink effect" set to the registered name.
 */
native bool TF2CustomAttrDrink_Register(const char[] effectName,
		LunchEffectCallback callback);

/**
 * Registers a custom lunchbox effect.  The given callback is fired if the player uses a lunch
 * item with "custom lunchbox effect" set to the registered name.
 * 
 * For drink items, the effect occurs once the player is finished drinking.
 * For Sandvich-like items, the effect occurs whenever the player takes a bite (four times
 * during the taunt).
 */
native bool TF2CustomAttrLunchbox_Register(const char[] effectName,
		LunchEffectCallback callback);

public SharedPlugin __tf_cattr_lunch_effect = {
	name = "cattr-custom-lunchbox",
	file = "custom_lunchbox_effect.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
