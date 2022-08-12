#if defined __tf_cattr_ball_impact_effect_included
	#endinput
#endif

#define __tf_cattr_ball_impact_effect_included

/**
 * Called when an entity is hit by a stunball-like projectile whose weapon has a custom effect.
 */
typedef BallImpactEffectCallback = function void(int target, int projectile, float flFlightTime,
		const char[] effectName);

/**
 * Registers a custom ball effect.
 */
native bool TF2CustomAttrBall_Register(const char[] effectName,
		BallImpactEffectCallback callback);

public SharedPlugin __tf_cattr_ball_impact_effect = {
	name = "cattr-custom-ball",
	file = "custom_ball_impact_effect.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
