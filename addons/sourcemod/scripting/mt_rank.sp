#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <versus_stats>


public Plugin myinfo = { 
	name = "MixTeamRank",
	author = "TouchMe",
	description = "Adds rank mix",
	version = "2.0.0",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mt_rank.phrases"

#define MIN_PLAYERS             4


enum struct Player {
	int id;
	int rank;
}


/**
 * Loads dictionary files. On failure, stops the plugin execution.
 * 
 * @noreturn
 */
void InitTranslations()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

	if (FileExists(sPath)) {
		LoadTranslations(TRANSLATIONS);
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 * 
 * @noreturn
 */
public void OnPluginStart() {
	InitTranslations();
}

public void OnAllPluginsLoaded()
{
	int iCalcMinPlayers = (FindConVar("survivor_limit").IntValue * 2);

	AddMixType("rank", (iCalcMinPlayers < MIN_PLAYERS) ? MIN_PLAYERS : iCalcMinPlayers, 0);
}

public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
	Format(sTitle, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTEEND_MSG_SIZE, "%T", "VOTE_END_MSG", iClient);
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */
public void OnMixInProgress()
{
	Handle hPlayers = CreateArray(sizeof(Player));
	Player tPlayer;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || !IsMixMember(iClient)) {
			continue;
		}

		tPlayer.id = iClient;
		tPlayer.rank = GetClientRank(iClient);

		if (!tPlayer.rank)
		{
			CallCancelMix();
			CPrintToChatAll("%t", "NO_RANK", iClient);
			return;
		}

		PushArrayArray(hPlayers, tPlayer);
	}

	SortADTArrayCustom(hPlayers, SortByRank);

	// TEMPLATE:
	// 1,             (2  2)  1                // Players: 4   Center: 1,2
	// 1, 2,          (2, 1), 2, 1             // Players: 6   Center: 2,3
	// 1, 2, 1,       (2, 2), 1, 2, 1          // Players: 8   Center: 3,4
	// 1, 2, 1, 2,    (2, 1), 2, 1, 2, 1       // Players: 10  Center: 4,5
	// 1, 2, 1, 2, 1, (2, 2), 1, 2, 1, 2, 1    // Players: 12  Center: 5,6

	int iPlayers = GetArraySize(hPlayers);
	int iHalfPlayers = iPlayers / 2;
	bool bIsSurvivorTeam = false;

	for (int iIndex = 0; iIndex < iHalfPlayers - 1; iIndex++)
	{
		bIsSurvivorTeam = (iIndex % 2 == 0);

		GetArrayArray(hPlayers, iIndex, tPlayer);
		SetClientTeam(tPlayer.id, bIsSurvivorTeam ? TEAM_SURVIVOR : TEAM_INFECTED);

		GetArrayArray(hPlayers, iPlayers - iIndex - 1, tPlayer);
		SetClientTeam(tPlayer.id, bIsSurvivorTeam ? TEAM_SURVIVOR : TEAM_INFECTED);
	}

	// Center
	{
		GetArrayArray(hPlayers, iHalfPlayers, tPlayer);
		SetClientTeam(tPlayer.id, TEAM_INFECTED);

		GetArrayArray(hPlayers, iHalfPlayers - 1, tPlayer);
		SetClientTeam(tPlayer.id, (iPlayers % 4 != 0) ? TEAM_SURVIVOR : TEAM_INFECTED);
	}

	// Required
	CallEndMix();
}

/**
  * @param index1        First index to compare.
  * @param index2        Second index to compare.
  * @param array         Array that is being sorted (order is undefined).
  * @param hndl          Handle optionally passed in while sorting.
  * @return              -1 if first should go before second
  *                      0 if first is equal to second
  *                      1 if first should go after second
  */
int SortByRank(int indexFirst, int indexSecond, Handle hArrayList, Handle hndl)
{
	Player tPlayerFirst, tPlayerSecond;

	GetArrayArray(hArrayList, indexFirst, tPlayerFirst);
	GetArrayArray(hArrayList, indexSecond, tPlayerSecond);

	if (tPlayerFirst.rank < tPlayerSecond.rank) {
		return -1;
	}

	if (tPlayerFirst.rank > tPlayerSecond.rank) {
		return 1;
	}

	return 0;
}
