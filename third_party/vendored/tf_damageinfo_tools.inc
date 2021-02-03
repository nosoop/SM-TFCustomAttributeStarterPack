#if defined __tf_radius_damage_included
	#endinput
#endif

#define __tf_radius_damage_included

methodmap CTakeDamageInfo < Handle {
	public native CTakeDamageInfo(int inflictor, int attacker, float damage, int damagetype,
			int weapon, const float damageForce[3] = NULL_VECTOR,
			const float damagePosition[3] = NULL_VECTOR,
			const float reportedPosition[3] = NULL_VECTOR, int damagecustom = 0);
};

methodmap CTFRadiusDamageInfo < Handle {
	public native CTFRadiusDamageInfo(CTakeDamageInfo info, const float src[3], float radius,
			int ignoreEntity = INVALID_ENT_REFERENCE, float blastJumpRadius = 0.0,
			float forceScale = 1.0);
	
	/**
	 * Calls into the gamerules system to apply the given radius damage info.
	 */
	public native void Apply();
};

public SharedPlugin __pl_tf_damageinfo_tools = {
	name = "tf2_damageinfo_tools",
	file = "tf_damageinfo_tools.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
