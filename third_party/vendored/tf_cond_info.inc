/**
 * Raw access to TF2 condition data.
 * This is mostly Pelipoika's work, with some modifications for cleanliness.
 */

#if defined __tf_cond_info_dma_included
	#endinput
#endif

#define __tf_cond_info_dma_included

#include <tf2_stocks>

#define SHARED_CONDITION_LIST_OFFSET view_as<Address>(0x08)

// (size of) ConditionInfo = 0x14
enum ConditionInfo (+= 0x04) {
	ConditionInfo_Unknown_0x00,
	ConditionInfo_Unknown_0x04,
	ConditionInfo_Duration,
	ConditionInfo_Provider,
	ConditionInfo_Unknown_0x10
};

stock any TF2_GetConditionData(int client, TFCond cond, ConditionInfo info) {
	return LoadFromAddress(TF2_GetConditionInfoAddress(client, cond) + view_as<Address>(info),
			NumberType_Int32);
}

stock void TF2_SetConditionData(int client, TFCond cond, ConditionInfo info, any value) {
	StoreToAddress(TF2_GetConditionInfoAddress(client, cond) + view_as<Address>(info), value,
			NumberType_Int32);
}

stock Address TF2_GetConditionInfoAddress(int client, TFCond cond) {
	// reads pConditionList + (cond * sizeof(cond))
	return view_as<Address>(TF2_GetConditionList(client)
			+ view_as<Address>(view_as<int>(cond) * view_as<int>(ConditionInfo)));
}

#define SHARED_OFFSET_BURN_DURATION 0x208
#define SHARED_OFFSET_BLEED_LIST 0x20C

#define BLEED_INFO_SIZE 0x1C

stock float TF2_GetBurnDuration(int client) {
	int pOffsSharedBurnDuration = FindSendPropInfo("CTFPlayer", "m_Shared")
			+ SHARED_OFFSET_BURN_DURATION;
	return GetEntDataFloat(client, pOffsSharedBurnDuration);
}

stock float TF2_SetBurnDuration(int client, float flBurnDuration) {
	int pOffsSharedBurnDuration = FindSendPropInfo("CTFPlayer", "m_Shared")
			+ SHARED_OFFSET_BURN_DURATION;
	SetEntDataFloat(client, pOffsSharedBurnDuration, flBurnDuration);
}

stock void TF2_ModifyBleedDuration(int client, float flBleedDelta) {
	int nBleedEffects = TF2_GetBleedListCount(client);
	if (!nBleedEffects) {
		return;
	}
	
	int pOffsBleedList = FindSendPropInfo("CTFPlayer", "m_Shared")
			+ SHARED_OFFSET_BLEED_LIST;
	Address pBleedList = view_as<Address>(LoadFromAddress(GetEntityAddress(client)
			+ view_as<Address>(pOffsBleedList), NumberType_Int32));
	
	for (int i; i < nBleedEffects; i++) {
		Address pBleedEndTime = pBleedList + view_as<Address>(BLEED_INFO_SIZE * i)
				+ view_as<Address>(0x0C);
		float flBleedEndTime = view_as<float>(LoadFromAddress(pBleedEndTime, NumberType_Int32));
		flBleedEndTime += flBleedDelta;
		StoreToAddress(pBleedEndTime, view_as<int>(flBleedEndTime), NumberType_Int32);
	}
}

stock int TF2_GetBleedListCount(int client) {
	int pOffsNumBleedEffects = FindSendPropInfo("CTFPlayer", "m_Shared")
			+ SHARED_OFFSET_BLEED_LIST + 0x0C; // m_BleedList->Count();
	return GetEntData(client, pOffsNumBleedEffects);
}

stock float TF2_GetBleedListEndTime(int client, int iBleed) {
	int pOffsBleedList = FindSendPropInfo("CTFPlayer", "m_Shared")
			+ SHARED_OFFSET_BLEED_LIST;
	Address pBleedList = view_as<Address>(LoadFromAddress(GetEntityAddress(client)
			+ view_as<Address>(pOffsBleedList), NumberType_Int32));
	Address pBleedEndTime = pBleedList + view_as<Address>(BLEED_INFO_SIZE * iBleed)
				+ view_as<Address>(0x0C);
	return view_as<float>(LoadFromAddress(pBleedEndTime, NumberType_Int32));
}

stock void TF2_SetBleedListEndTime(int client, int iBleed, float flBleedEndTime) {
	int pOffsBleedList = FindSendPropInfo("CTFPlayer", "m_Shared")
			+ SHARED_OFFSET_BLEED_LIST;
	Address pBleedList = view_as<Address>(LoadFromAddress(GetEntityAddress(client)
			+ view_as<Address>(pOffsBleedList), NumberType_Int32));
	Address pBleedEndTime = pBleedList + view_as<Address>(BLEED_INFO_SIZE * iBleed)
				+ view_as<Address>(0x0C);
	StoreToAddress(pBleedEndTime, view_as<int>(flBleedEndTime), NumberType_Int32);
}

static stock Address TF2_GetConditionList(int client) {
	Address m_Shared = view_as<Address>(FindSendPropInfo("CTFPlayer", "m_Shared"));
	return view_as<Address>(LoadFromAddress(GetEntityAddress(client)
			+ m_Shared + SHARED_CONDITION_LIST_OFFSET, NumberType_Int32));
}
