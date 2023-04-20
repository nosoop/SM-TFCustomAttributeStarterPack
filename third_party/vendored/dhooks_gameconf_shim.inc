/**
 * dhooks_gameconf_shim
 * (c) 2023 nosoop
 * 
 * DHooks stores the hook definitions in-extension.  Because it's keyed globally, it has the
 * annoying property of conflicting if multiple game config files use the same name for
 * different hook definitions, no matter which plugin is loading them.
 * 
 * This issue is tracked here: https://github.com/alliedmodders/sourcemod/issues/1879
 * 
 * This include file implements some functions to parse the gameconfig within the plugin and
 * provide drop-in replacements for compatibility reasons.
 * 
 * This currently does not cover full compatibility of the game config parsing logic, but should
 * be sufficent for most use cases.  Any unexpected values will raise errors, so they can be
 * tracked down and fixed.
 * 
 * To use this shim:
 * 
 * 1. Call `ReadDHooksDefinitions` around the same time you call `LoadGameConfigFile` with the
 *    same file.  You may also wish to rename the "Functions" section in the config file to a
 *    different name to prevent DHooks itself from processing the section;
 *    `ReadDHooksDefinitions` provides a parameter to customize the section read.
 * 2. Replace every instance of `DHookCreateFromConf` with `GetDHooksDefinition`.  If you are
 *    using the `FromConf` methods, replace such instances with `GetDHooksHookDefinition` and
 *    `GetDHooksDetourDefinition` depending on the type.
 * 3. Call `ClearDHooksDefinitions` when you delete the gameconf handle.
 * 
 * Those are the only external-facing symbols.
 */

#include <dhooks>

/**
 * Internal constants.
 */
#define MAX_DHOOKS_SDKCONF_NAME_LENGTH    128
#define MAX_DHOOKS_PARAM_NAME_LENGTH      64

/**
 * Plugin-internal list of definitions.
 */
static StringMap s_DHooksDefinitions;
static char s_CurrentHookListSectionName[64];

enum DHookGameConfParseState {
	GameConfParse_Root,
	GameConfParse_GameList,
	GameConfParse_Game,
	GameConfParse_HookList,
	GameConfParse_HookSetup,
	GameConfParse_ParamList,
	GameConfParse_ParamInfo,
}

/**
 * Container for a DHooks argument definition (corresponding to an entry under the "arguments"
 * section).
 */
enum struct DHookSetupParamDefinition {
	char m_Name[MAX_DHOOKS_PARAM_NAME_LENGTH];
	HookParamType m_ParamType;
	int m_ParamSize;
	DHookPassFlag m_PassFlags;
	DHookRegister m_CustomRegister;
	
	void Init(const char[] name) {
		strcopy(this.m_Name, sizeof(DHookSetupParamDefinition::m_Name), name);
		this.m_ParamSize = -1;
		this.m_PassFlags = DHookPass_ByVal;
		this.m_CustomRegister = DHookRegister_Default;
	}
	
	bool ParseKeyValue(const char[] key, const char[] value) {
		if (StrEqual(key, "type")) {
			return GetHookParamTypeFromString(value, this.m_ParamType);
		} else if (StrEqual(key, "size")) {
			int parsedSize = StringToInt(value, 0);
			if (parsedSize < 1) {
				return false;
			}
			this.m_ParamSize = parsedSize;
			return true;
		} else if (StrEqual(key, "flags")) {
			return GetPassFlagsFromString(value, this.m_PassFlags);
		}
		return false;
	}
}

/**
 * Container for a DHooks hook definition (corresponding to an entry under the "Functions"
 * section).
 */
enum struct DHookSetupDefinition {
	SDKFuncConfSource m_HookSource;
	char m_ConfName[MAX_DHOOKS_SDKCONF_NAME_LENGTH];
	
	HookType m_VirtualHookType;
	
	CallingConvention m_DetourCallConv;
	
	ThisPointerType m_ThisPtrType;
	ReturnType m_ReturnType;
	ArrayList m_ParamList;
	
	void Init() {
		this.m_ParamList = new ArrayList(sizeof(DHookSetupParamDefinition));
		this.m_ConfName = "";
	}
	
	void Destroy() {
		delete this.m_ParamList;
	}
	
	void AddParameter(const DHookSetupParamDefinition paramdef) {
		// replace existing matching param by name or push it
		for (int i, n = this.m_ParamList.Length; i < n; i++) {
			DHookSetupParamDefinition internaldef;
			this.m_ParamList.GetArray(i, internaldef, sizeof(internaldef));
			
			if (StrEqual(internaldef.m_Name, paramdef.m_Name)) {
				this.m_ParamList.SetArray(i, paramdef);
				return;
			}
		}
		
		this.m_ParamList.PushArray(paramdef);
	}
	
	bool ParseKeyValue(const char[] key, const char[] value) {
		if (StrEqual(key, "signature")) {
			this.m_HookSource = SDKConf_Signature;
			strcopy(this.m_ConfName, sizeof(DHookSetupDefinition::m_ConfName), value);
			return true;
		} else if (StrEqual(key, "address")) {
			this.m_HookSource = SDKConf_Address;
			strcopy(this.m_ConfName, sizeof(DHookSetupDefinition::m_ConfName), value);
			return true;
		} else if (StrEqual(key, "offset")) {
			this.m_HookSource = SDKConf_Virtual;
			strcopy(this.m_ConfName, sizeof(DHookSetupDefinition::m_ConfName), value);
			return true;
		} else if (StrEqual(key, "callconv")) {
			return GetCallConvFromString(value, this.m_DetourCallConv);
		} else if (StrEqual(key, "hooktype")) {
			return GetHookTypeFromString(value, this.m_VirtualHookType);
		} else if (StrEqual(key, "return")) {
			return GetReturnTypeFromString(value, this.m_ReturnType);
		} else if (StrEqual(key, "this")) {
			return GetThisPtrTypeFromString(value, this.m_ThisPtrType);
		}
		return false;
	}
	
	DHookSetup CreateHook(Handle gameconf) {
		DHookSetup hook;
		if (this.m_HookSource == SDKConf_Virtual) {
			hook = DHookCreate(0, this.m_VirtualHookType, this.m_ReturnType,
					this.m_ThisPtrType);
		} else {
			// address or signature
			hook = DHookCreateDetour(Address_Null, this.m_DetourCallConv, this.m_ReturnType,
					this.m_ThisPtrType);
		}
		
		if (!hook.SetFromConf(gameconf, this.m_HookSource, this.m_ConfName)) {
			return null;
		}
		
		for (int i, n = this.m_ParamList.Length; i < n; i++) {
			DHookSetupParamDefinition paramdef;
			this.m_ParamList.GetArray(i, paramdef, sizeof(paramdef));
			
			hook.AddParam(paramdef.m_ParamType, paramdef.m_ParamSize, paramdef.m_PassFlags,
					paramdef.m_CustomRegister);
		}
		
		return hook;
	}
}

/**
 * Processes DHooks hook setup definitions from a game config file.
 * 
 * @param file       File to load.  The path must be relative to the 'gamedata' folder and the
 *                   extension should be omitted.
 * @param section    Section to read definitions from.  By default, this reads from the same
 *                   section as DHooks does, but may be changed to prevent DHooks from reading
 *                   them itself.
 */
stock bool ReadDHooksDefinitions(const char[] file, const char[] section = "Functions") {
	if (!s_DHooksDefinitions) {
		s_DHooksDefinitions = new StringMap();
	}
	
	// TODO create parser
	SMCParser gameConfigParser = CreateGameConfParser();
	
	char gameconf[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, gameconf, sizeof(gameconf), "gamedata/%s.txt", file);
	
	if (!FileExists(gameconf)) {
		ThrowError("Game config file %s not found", file);
		return false;
	}
	
	strcopy(s_CurrentHookListSectionName, sizeof(s_CurrentHookListSectionName), section);
	gameConfigParser.ParseFile(gameconf);
	
	delete gameConfigParser;
	
	return true;
}

/**
 * Constructs a DHookSetup instance from a parsed config file.
 * Drop-in replacement for DHookCreateFromConf().
 */
stock DHookSetup GetDHooksDefinition(Handle gameconf, const char[] name) {
	DHookSetupDefinition hookdef;
	if (!s_DHooksDefinitions.GetArray(name, hookdef, sizeof(hookdef))) {
		return null;
	}
	
	return hookdef.CreateHook(gameconf);
}

/**
 * Constructs a DynamicHook instance from a parsed config file.
 * Drop-in replacement for DynamicHook.FromConf().  Returns null if the game config entry was
 * not specified as a virtual hook.
 */
stock DynamicHook GetDHooksHookDefinition(Handle gameconf, const char[] name) {
	DHookSetupDefinition hookdef;
	if (!s_DHooksDefinitions.GetArray(name, hookdef, sizeof(hookdef))) {
		return null;
	} else if (hookdef.m_HookSource != SDKConf_Virtual) {
		return null;
	}
	
	return view_as<DynamicHook>(hookdef.CreateHook(gameconf));
}

/**
 * Constructs a DynamicDetour instance from a parsed config file.
 * Drop-in replacement for DynamicDetour.FromConf().  Returns null if the game config entry was
 * not specified as a detour.
 */
stock DynamicDetour GetDHooksDetourDefinition(Handle gameconf, const char[] name) {
	DHookSetupDefinition hookdef;
	if (!s_DHooksDefinitions.GetArray(name, hookdef, sizeof(hookdef))) {
		return null;
	} else if (hookdef.m_HookSource != SDKConf_Address
			&& hookdef.m_HookSource != SDKConf_Signature) {
		return null;
	}
	
	return view_as<DynamicDetour>(hookdef.CreateHook(gameconf));
}

/**
 * Clears the internal definition list.  You should call this around the same time you close the
 * corresponding gamedata handle.
 */
stock void ClearDHooksDefinitions() {
	if (!s_DHooksDefinitions) {
		return;
	}
	
	StringMapSnapshot definitionNames = s_DHooksDefinitions.Snapshot();
	for (int i, n = definitionNames.Length; i < n; i++) {
		char name[MAX_DHOOKS_SDKCONF_NAME_LENGTH];
		definitionNames.GetKey(i, name, sizeof(name));
		
		DHookSetupDefinition hookdef;
		if (s_DHooksDefinitions.GetArray(name, hookdef, sizeof(hookdef))) {
			hookdef.Destroy();
			continue;
		}
	}
	s_DHooksDefinitions.Clear();
}

/**
 * Internal parsing logic.
 */
static SMCParser CreateGameConfParser() {
	SMCParser gameConfigParser = new SMCParser();
	
	gameConfigParser.OnStart = OnGameConfigStartParse;
	gameConfigParser.OnEnd = OnGameConfigEndParse;
	
	gameConfigParser.OnEnterSection = OnGameConfigEnterSection;
	gameConfigParser.OnLeaveSection = OnGameConfigLeaveSection;
	
	gameConfigParser.OnKeyValue = OnGameConfigKeyValue;
	
	return gameConfigParser;
}

static DHookGameConfParseState s_ParseState = GameConfParse_Root;
static int s_nParseStateIgnoreNestedSections;

static char s_CurrentHookName[MAX_DHOOKS_SDKCONF_NAME_LENGTH];
static DHookSetupDefinition s_CurrentHookDefinition;
static DHookSetupParamDefinition s_CurrentParamDefinition;

static void OnGameConfigStartParse(SMCParser smc) {
	s_ParseState = GameConfParse_Root;
	s_nParseStateIgnoreNestedSections = 0;
	
	s_CurrentHookName = "";
}

/**
 * Push new parse state depending on the current section.
 */
static SMCResult OnGameConfigEnterSection(SMCParser smc, const char[] name, bool opt_quotes) {
	/**
	 * If we're ignoring a parent section, increment and don't emit a change in parse state.
	 */
	if (s_nParseStateIgnoreNestedSections) {
		s_nParseStateIgnoreNestedSections++;
		return SMCParse_Continue;
	}
	
	switch (s_ParseState) {
		case GameConfParse_Root: {
			if (StrEqual(name, "Games")) {
				s_ParseState = GameConfParse_GameList;
			} else {
				return ThrowSMCParseFailure("Entering unexpected section '%s'", name);
			}
		}
		case GameConfParse_GameList: {
			if (IsSupportedGameSection(name)) {
				s_ParseState = GameConfParse_Game;
			} else {
				// ignore sections irrelevant to the game
				s_nParseStateIgnoreNestedSections++;
			}
		}
		case GameConfParse_Game: {
			if (StrEqual(name, s_CurrentHookListSectionName)) {
				s_ParseState = GameConfParse_HookList;
			} else {
				s_nParseStateIgnoreNestedSections++;
			}
		}
		case GameConfParse_HookList: {
			s_ParseState = GameConfParse_HookSetup;
			
			// initialize current hook context and retrieve an existing definition if present
			strcopy(s_CurrentHookName, sizeof(s_CurrentHookName), name);
			s_CurrentHookDefinition.Init();
			s_DHooksDefinitions.GetArray(name,
					s_CurrentHookDefinition, sizeof(s_CurrentHookDefinition));
		}
		case GameConfParse_HookSetup: {
			if (StrEqual(name, "arguments")) {
				s_ParseState = GameConfParse_ParamList;
			} else {
				return ThrowSMCParseFailure("Entering unexpected section '%s'", name);
			}
		}
		case GameConfParse_ParamList: {
			s_ParseState = GameConfParse_ParamInfo;
			
			s_CurrentParamDefinition.Init(name);
		}
		case GameConfParse_ParamInfo: {
			// ignore further nested sections
			s_nParseStateIgnoreNestedSections++;
		}
		default: {
			return ThrowSMCParseFailure("Entering unexpected section '%s'", name);
		}
	}
	return SMCParse_Continue;
}

/**
 * Pop parse state and go back to previous one.
 */
static SMCResult OnGameConfigLeaveSection(SMCParser smc) {
	/**
	 * If we're leaving an ignored section, decrement and don't emit a change in parse state.
	 */
	if (s_nParseStateIgnoreNestedSections) {
		s_nParseStateIgnoreNestedSections--;
		return SMCParse_Continue;
	}
	
	switch (s_ParseState) {
		case GameConfParse_ParamInfo: {
			s_ParseState = GameConfParse_ParamList;
			s_CurrentHookDefinition.AddParameter(s_CurrentParamDefinition);
		}
		case GameConfParse_ParamList: {
			s_ParseState = GameConfParse_HookSetup;
		}
		case GameConfParse_HookSetup: {
			s_ParseState = GameConfParse_HookList;
			
			// add current hook to internal list
			s_DHooksDefinitions.SetArray(s_CurrentHookName,
					s_CurrentHookDefinition, sizeof(s_CurrentHookDefinition));
		}
		case GameConfParse_HookList: {
			s_ParseState = GameConfParse_Game;
		}
		case GameConfParse_Game: {
			s_ParseState = GameConfParse_GameList;
		}
		case GameConfParse_GameList: {
			s_ParseState = GameConfParse_Root;
		}
		default: {
			return ThrowSMCParseFailure("Unhandled section leave");
		}
	}
	return SMCParse_Continue;
}

static SMCResult OnGameConfigKeyValue(SMCParser smc, const char[] key, const char[] value,
		bool key_quotes, bool value_quotes) {
	/**
	 * Not in a section we care about.
	 */
	if (s_nParseStateIgnoreNestedSections) {
		return SMCParse_Continue;
	}
	
	switch (s_ParseState) {
		case GameConfParse_HookSetup: {
			if (s_CurrentHookDefinition.ParseKeyValue(key, value)) {
				return SMCParse_Continue;
			}
		}
		case GameConfParse_ParamInfo: {
			if (s_CurrentParamDefinition.ParseKeyValue(key, value)) {
				return SMCParse_Continue;
			}
		}
	}
	return ThrowSMCParseFailure("Unexpected key / value pair '%s' / '%s'", key, value);
}

static void OnGameConfigEndParse(SMCParser smc, bool halted, bool failed) {
	if (halted || failed) {
		return;
	}
	
	if (s_ParseState != GameConfParse_Root) {
		LogError("Parse state not at root on end parse");
	}
}

static SMCResult ThrowSMCParseFailure(const char[] message, any ...) {
	char buffer[512];
	VFormat(buffer, sizeof(buffer), message, 2);
	
	LogError("%s (parse state %d)", buffer, s_ParseState);
	return SMCParse_HaltFail;
}

static bool IsSupportedGameSection(const char[] game) {
	char gamedir[64];
	if (GetGameFolderName(gamedir, sizeof(gamedir)) && StrEqual(game, gamedir)) {
		return true;
	}
	return StrEqual(game, "#default");
}

static bool GetHookTypeFromString(const char[] value, HookType &type) {
	if (StrEqual(value, "entity")) {
		type = HookType_Entity;
	} else if (StrEqual(value, "gamerules")) {
		type = HookType_GameRules;
	} else if (StrEqual(value, "raw")) {
		type = HookType_Raw;
	} else {
		return false;
	}
	return true;
}

static bool GetThisPtrTypeFromString(const char[] value, ThisPointerType &type) {
	if (StrEqual(value, "ignore")) {
		type = ThisPointer_Ignore;
	} else if (StrEqual(value, "entity")) {
		type = ThisPointer_CBaseEntity;
	} else if (StrEqual(value, "address")) {
		type = ThisPointer_Address;
	} else {
		return false;
	}
	return true;
}

static bool GetCallConvFromString(const char[] value, CallingConvention &callconv) {
	if (StrEqual(value, "cdecl")) {
		callconv = CallConv_CDECL;
	} else if (StrEqual(value, "thiscall")) {
		callconv = CallConv_THISCALL;
	} else if (StrEqual(value, "stdcall")) {
		callconv = CallConv_STDCALL;
	} else if (StrEqual(value, "fastcall")) {
		callconv = CallConv_FASTCALL;
	} else {
		return false;
	}
	return true;
}

static bool GetReturnTypeFromString(const char[] value, ReturnType &type) {
	if (StrEqual(value, "void")) {
		type = ReturnType_Void;
	} else if (StrEqual(value, "int")) {
		type = ReturnType_Int;
	} else if (StrEqual(value, "bool")) {
		type = ReturnType_Bool;
	} else if (StrEqual(value, "float")) {
		type = ReturnType_Float;
	} else if (StrEqual(value, "string")) {
		type = ReturnType_String;
	} else if (StrEqual(value, "stringptr")) {
		type = ReturnType_StringPtr;
	} else if (StrEqual(value, "charptr")) {
		type = ReturnType_CharPtr;
	} else if (StrEqual(value, "vector")) {
		type = ReturnType_Vector;
	} else if (StrEqual(value, "vectorptr")) {
		type = ReturnType_VectorPtr;
	} else if (StrEqual(value, "cbaseentity")) {
		type = ReturnType_CBaseEntity;
	} else if (StrEqual(value, "edict")) {
		type = ReturnType_Edict;
	} else {
		type = ReturnType_Unknown;
	}
	return true;
}

static bool GetHookParamTypeFromString(const char[] value, HookParamType &type) {
	if (StrEqual(value, "int")) {
		type = HookParamType_Int;
	} else if (StrEqual(value, "bool")) {
		type = HookParamType_Bool;
	} else if (StrEqual(value, "float")) {
		type = HookParamType_Float;
	} else if (StrEqual(value, "string")) {
		type = HookParamType_String;
	} else if (StrEqual(value, "stringptr")) {
		type = HookParamType_StringPtr;
	} else if (StrEqual(value, "charptr")) {
		type = HookParamType_CharPtr;
	} else if (StrEqual(value, "vectorptr")) {
		type = HookParamType_VectorPtr;
	} else if (StrEqual(value, "cbaseentity")) {
		type = HookParamType_CBaseEntity;
	} else if (StrEqual(value, "objectptr")) {
		type = HookParamType_ObjectPtr;
	} else if (StrEqual(value, "edict")) {
		type = HookParamType_Edict;
	} else if (StrEqual(value, "object")) {
		type = HookParamType_Object;
	} else {
		type = HookParamType_Unknown;
	}
	return true;
}

static bool GetPassFlagsFromString(const char[] value, DHookPassFlag &flags) {
	flags = view_as<DHookPassFlag>(0);
	if (StrContains(value, "byval") != -1) {
		flags |= DHookPass_ByVal;
	}
	if (StrContains(value, "byref") != -1) {
		flags |= DHookPass_ByRef;
	}
	if (StrContains(value, "odtor") != -1) {
		flags |= DHookPass_ODTOR;
	}
	if (StrContains(value, "octor") != -1) {
		flags |= DHookPass_OCTOR;
	}
	if (StrContains(value, "oassignop") != -1) {
		flags |= DHookPass_OASSIGNOP;
	}
	// "ocopyctor" and "ounalign" do not have flags defined in SM
	return true;
}
