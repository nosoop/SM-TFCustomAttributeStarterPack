/**
 * [TF2] CalculateMaxSpeed Detour
 * 
 * Provides a global forward that is called after CTFPlayer::TeamFortress_CalculateMaxSpeed()
 * is called, to allow updating the max speed.
 */

#if defined __tf2_calculatemaxspeed_detour_included
	#endinput
#endif

#define __tf2_calculatemaxspeed_detour_included

/**
 * Called after TF2 performs its max speed calculations.
 */
forward Action TF2_OnCalculateMaxSpeed(int client, float &flMaxSpeed);

/**
 * Do not edit below this line!
 */
public Extension __ext_tf_calcmaxspeed = 
{
	name = "TF2 Calculate Max Speed Detour",
	file = "tf_calcmaxspeed.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};
