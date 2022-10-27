#if defined __cattr_starterpack_tf_var_strings_included
	#endinput
#endif

#define __cattr_starterpack_tf_var_strings_included

#include <tf2utils>
#include <stocksoup/var_strings>

stock bool ReadTFCondVar(const char[] varstring, const char[] key, TFCond &value) {
	char condString[32];
	if (!ReadStringVar(varstring, key, condString, sizeof(condString))) {
		return false;
	}
	
	int result;
	if (StringToIntEx(condString, result)) {
		value = view_as<TFCond>(result);
		return true;
	}
	
	static StringMap s_Conditions;
	if (!s_Conditions) {
		char buffer[64];
		
		s_Conditions = new StringMap();
		for (TFCond cond; cond <= TF2Util_GetLastCondition(); cond++) {
			if (TF2Util_GetConditionName(cond, buffer, sizeof(buffer))) {
				s_Conditions.SetValue(buffer, cond);
			}
		}
	}
	
	if (s_Conditions.GetValue(condString, value)) {
		return true;
	}
	
	// log message if given string does not resolve to a condition
	static StringMap s_LoggedConditions;
	if (!s_LoggedConditions) {
		s_LoggedConditions = new StringMap();
	}
	any ignored;
	if (!s_LoggedConditions.GetValue(condString, ignored)) {
		LogError("Could not translate condition name %s to index.", condString);
		s_LoggedConditions.SetValue(condString, true);
	}
	return false;
}
