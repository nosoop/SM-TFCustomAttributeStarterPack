#if defined __tf_cattr_drink_effect_included
	#endinput
#endif

#define __tf_cattr_drink_effect_included

/**
 * Called when a player has finished drinking their drink.
 */
typedef DrinkEffectCallback = function void(int owner, int weapon, const char[] effectName);

/**
 * Registers a custom drink effect.  The given callback is fired if the player owns a drink item
 * with "custom drink effect" set to the registered name.
 */
native bool TF2CustomAttrDrink_Register(const char[] effectName,
		DrinkEffectCallback callback);

public SharedPlugin __tf_cattr_drink_effect = {
	name = "cattr-custom-drink",
	file = "custom_drink_effect.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
