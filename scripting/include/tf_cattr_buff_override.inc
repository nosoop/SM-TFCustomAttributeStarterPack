#if defined __tf_cattr_buff_override_included
	#endinput
#endif

#define __tf_cattr_buff_override_included

// this is the game's condition length
#define BUFF_PULSE_CONDITION_DURATION 1.2

/**
 * Called when a player rage pulse is active.  The only check on the target is to ensure that
 * they are within range of the buff.
 */
typedef PulseRageBuffCallback = function void(int owner, int target, const char[] buffName);

/**
 * Registers a custom rage buff.  The given callback is fired if the player owns a buff item
 * with "custom soldier buff type" set to the registered name.
 */
native bool TF2CustomAttrRageBuff_Register(const char[] buffName,
		PulseRageBuffCallback callback);

public SharedPlugin __tf_cattr_buff_override = {
	name = "cattr-buff-override",
	file = "attr_buff_override.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
