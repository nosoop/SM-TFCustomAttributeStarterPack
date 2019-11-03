/**
 * Include description here.
 */

#if defined __tf_ontakedamage_included
	#endinput
#endif

#define __tf_ontakedamage_included

enum CritType {
	CritType_None = 0,
	CritType_MiniCrit,
	CritType_Crit
};

/**
 * Called before the CTFPlayer::OnTakeDamage() function is called.
 * 
 * Note that the crit type may be further altered after this forward (when the game calls
 * CTFGameRules::ApplyOnDamageModifyRules(), which checks for attributes including
 * "minicrits_become_crits").
 */
forward Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType);

public SharedPlugin __pl_tf_ontakedamage = {
	name = "tf_ontakedamage",
	file = "tf_ontakedamage.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
