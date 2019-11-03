/**
 * Helper functions for getting values from CTakeDamageInfo objects in DHooks.
 */

#if defined __dhook_takedamageinfo_included
	#endinput
#endif

#define __dhook_takedamageinfo_included

enum TakeDamageInfo (+= 0x04) {
	// vectors
	TakeDamageInfo_DamageForce,
	TakeDamageInfo_DamagePosition = 12,
	TakeDamageInfo_ReportedPosition = 24,

	TakeDamageInfo_Inflictor = 36,
	TakeDamageInfo_Attacker,
	TakeDamageInfo_Weapon,
	TakeDamageInfo_Damage,
	TakeDamageInfo_MaxDamage,
	TakeDamageInfo_BaseDamage,
	TakeDamageInfo_BitsDamageType,
	TakeDamageInfo_DamageCustom,
	TakeDamageInfo_DamageStats,
	TakeDamageInfo_AmmoType,
	TakeDamageInfo_DamagedOtherPlayers,
	TakeDamageInfo_PlayerPenetrationCount,
	TakeDamageInfo_DamageBonus,
	TakeDamageInfo_DamageBonusProvider,
	TakeDamageInfo_ForceFriendlyFire,
	TakeDamageInfo_DamageForForce,
	TakeDamageInfo_CritType
};

static int s_nParam;
static Handle s_hParamHandle;

/**
 * Set the "context" to avoid having to repeatedly fill in values for
 * DHook(Set/Get)ParamObjectPtrVar
 */
stock void SetTakeDamageInfoContext(Handle hParams, int param) {
	s_nParam = param;
	s_hParamHandle = hParams;
}

stock int GetDamageInfoHandle(TakeDamageInfo offset) {
	return DHookGetParamObjectPtrVar(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Ehandle);
}

stock void SetDamageInfoHandle(TakeDamageInfo offset, int entity) {
	DHookSetParamObjectPtrVar(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Ehandle, entity);
}

stock float GetDamageInfoFloat(TakeDamageInfo offset) {
	return DHookGetParamObjectPtrVar(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Float);
}

stock void SetDamageInfoFloat(TakeDamageInfo offset, float value) {
	DHookSetParamObjectPtrVar(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Float, value);
}

stock int GetDamageInfoInt(TakeDamageInfo offset) {
	return DHookGetParamObjectPtrVar(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Int);
}

stock void SetDamageInfoInt(TakeDamageInfo offset, int value) {
	DHookSetParamObjectPtrVar(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Int, value);
}

stock void GetDamageInfoVector(TakeDamageInfo offset, float vec[3]) {
	/* ret */ DHookGetParamObjectPtrVarVector(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Vector, vec);
}

stock void SetDamageInfoVector(TakeDamageInfo offset, float vec[3]) {
	DHookSetParamObjectPtrVarVector(s_hParamHandle, s_nParam, view_as<int>(offset),
			ObjectValueType_Vector, vec);
}
