#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <nativevotes>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#include <left4dhooks>
#define REQUIRE_PLUGIN

#include "include/mix_team.inc"


public Plugin myinfo =
{
	name = "MixTeam",
	author = "TouchMe",
	description = "Mixing players for versus mode",
	version = "2.2",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


// Libs
#define LIB_READY               "readyup" 
#define LIB_DHOOK               "left4dhooks"

// Forwards
#define FORWARD_DISPLAY_MSG     "GetVoteDisplayMessage"
#define FORWARD_VOTEEND_MSG     "GetVoteEndMessage"
#define FORWARD_IN_PROGRESS     "OnMixInProgress"
#define FORWARD_ON_MIX_SUCCESS  "OnMixSuccess"
#define FORWARD_ON_MIX_FAILED   "OnMixFailed"

// Other
#define TRANSLATIONS            "mix_team.phrases"
#define VOTE_TIME               15

// Macros
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))

// Sugar
#define SetHumanSpec            L4D_SetHumanSpec
#define TakeOverBot             L4D_TakeOverBot


enum struct TypeItem
{
	Handle plugin;
	char name[MIX_NAME_SIZE];
	int minPlayers;
	int timeout;
}

methodmap TypeList < ArrayList
{
	public TypeList() {
		return view_as<TypeList>(new ArrayList(sizeof(TypeItem)));
	}

	public int Add(Handle hPlugin, const char[] sName, int iMinPlayers, int iTimeout)
	{
		if (hPlugin == null || IsEmptyString(sName, MIX_NAME_SIZE) || iMinPlayers > MaxClients || iTimeout < 0) {
			return -1;
		}

		TypeItem item;

		item.plugin = hPlugin;
		strcopy(item.name, sizeof(item.name), sName);
		item.minPlayers = iMinPlayers;
		item.timeout = iTimeout;
		
		return this.PushArray(item);
	}

	public int Find(const char[] sName)
	{
		TypeItem item;

		for (int index = 0; index < this.Length; index++)
		{
			this.GetArray(index, item);

			if (StrEqual(item.name, sName, false)) {
				return index;
			}
		}

		return TYPE_NONE;
	}

	public Handle GetPlugin(int index)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			return item.plugin;
		}

		return null;
	}

	public void GetName(int index, char[] sName, int iLen)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			strcopy(sName, iLen, item.name);
		}
	}

	public int GetMinPlayers(int index)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			return item.minPlayers;
		}

		return 0;
	}

	public int GetTimeout(int index)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			return item.timeout;
		}

		return 0;
	}
}

TypeList
	g_hTypeList = null;

enum struct Players
{
	bool member;
	int team;
}

Players 
	g_tPlayers[MAXPLAYERS + 1];

int
	g_iMixTimeout = 0,
	g_iMixState = STATE_NONE,
	g_iMixType = TYPE_NONE;

bool
	g_bReadyUpAvailable = false,
	g_bDHookAvailable = false,
	g_bGamemodeAvailable = false,
	g_bRoundIsLive = false;

ConVar
	g_hGameMode = null;

GlobalForward
	g_fOnMixSuccess,
	g_fOnMixFailed;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
	g_bDHookAvailable = LibraryExists(LIB_DHOOK);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName) 
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = false;
	}

	if (StrEqual(sName, LIB_DHOOK)) {
		g_bDHookAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = true;
	}

	if (StrEqual(sName, LIB_DHOOK)) {
		g_bDHookAvailable = true;
	}
}

/**
  * @requared readyup
  * Global event. Called when all players are ready.
  */
public void OnRoundIsLive() 
{
	if (IsMix()) {
		AbortMix();
	}
}

/**
 * Called before OnPluginStart.
 * 
 * @param myself      Handle to the plugin
 * @param late        Whether or not the plugin was loaded "late" (after map load)
 * @param error       Error message buffer in case load failed
 * @param err_max     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure 
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	CreateNative("AddMixType", Native_AddMixType);
	CreateNative("GetMixState", Native_GetMixState);
	CreateNative("GetMixType", Native_GetMixType);
	CreateNative("CallCancelMix", Native_CallCancelMix);
	CreateNative("CallEndMix", Native_CallEndMix);
	CreateNative("IsMixMember", Native_IsMixMember);
	CreateNative("GetLastTeam", Native_GetLastTeam);
	CreateNative("SetClientTeam", Native_SetClientTeam);

	RegPluginLibrary("mix_team");

	return APLRes_Success;
}

/**
 * Adds a mix to the system.
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return index or -1
 */
int Native_AddMixType(Handle hPlugin, int iParams)
{
	if (iParams < 3) {
		return -1;
	}

	char sName[MIX_NAME_SIZE];

	if (GetNativeString(1, sName, sizeof(sName)) == SP_ERROR_NONE)
	{
		int iMinPlayers = GetNativeCell(2);
		int iTimeout = GetNativeCell(3);

		return g_hTypeList.Add(hPlugin, sName, iMinPlayers, iTimeout);
	}

	return -1;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return g_iMixState
 */
int Native_GetMixState(Handle hPlugin, int iParams) {
	return g_iMixState;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return g_iMixType
 */
int Native_GetMixType(Handle hPlugin, int iParams) {
	return g_iMixType;
}

/**
 * Forces the mix to stop.
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return 
 */
int Native_CallCancelMix(Handle hPlugin, int iParams)
{
	AbortMix();
	return 0;
}

/**
 * Forcibly ends the mix.
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return
 */
int Native_CallEndMix(Handle hPlugin, int iParams)
{
	FinishMix();

	return 0;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return
 */
int Native_IsMixMember(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	return g_tPlayers[iClient].member;
}

/**
 * Returns the team the player was on after voting for the mix.
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Returns the command if the player was in the mix, otherwise -1
 */
int Native_GetLastTeam(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	if (!g_tPlayers[iClient].member) {
		return -1;
	}

	return g_tPlayers[iClient].team;
}

/**
 * Sets a command to a player.
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return
 */
int Native_SetClientTeam(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);
	int iTeam = GetNativeCell(2);

	return SetupClientTeam(iClient, iTeam);
}


/**
  * Called when the map starts loading.
  */
public void OnMapInit(const char[] sMapName) 
{
	g_bRoundIsLive = false;
	g_iMixState = STATE_NONE;
	g_iMixType = TYPE_NONE;
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
	InitTranslations();
	InitCvars();
	InitEvents();
	InitCmds();
	InitForwards();

	g_hTypeList = new TypeList();
}

/**
 * Called when the plugin is about to be unloaded.
 */
public void OnPluginEnd()
{
	if (g_hTypeList != null) {
		delete g_hTypeList;
	}
}

/**
 * Loads dictionary files. On failure, stops the plugin execution.
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
 * Initializing the necessary cvars.
 */
void InitCvars()
{
	g_hGameMode = FindConVar("mp_gamemode");
	g_hGameMode.AddChangeHook(OnGamemodeChanged);
}

/**
 * Called when a console variable value is changed.
 * 
 * @param convar       Handle to the convar that was changed
 * @param oldValue     String containing the value of the convar before it was changed
 * @param newValue     String containing the new value of the convar
 * @noreturn
 */
public void OnGamemodeChanged(ConVar convar, const char[] sOldGameMode, const char[] sNewGameMode) {
	g_bGamemodeAvailable = IsVersusMode(sNewGameMode);
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all plugin configs are done executing.
 * This will always be called once and only once per map. It will be called after OnMapStart().
*/
public void OnConfigsExecuted() 
{
	char sGameMode[16];
	GetConVarString(g_hGameMode, sGameMode, sizeof(sGameMode));
	g_bGamemodeAvailable = IsVersusMode(sGameMode);
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitEvents() 
{
	HookEvent("versus_round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);

	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

/**
 * Round start event.
 */
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	if (!g_bReadyUpAvailable)
	{
		g_bRoundIsLive = true;

		if (IsMix()) {
			AbortMix();
		}
	}

	return Plugin_Continue;
}

/**
 * Round end event.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}
	
	return Plugin_Continue;
}

/**
 * Player change his team.
 */
public Action Event_PlayerTeam(Event event, char[] event_name, bool dontBroadcast)
{
	if (!IsMix()) {
		return Plugin_Continue;
	}

	int iClient = GetClientOfUserId(event.GetInt("userid"));
	int iOldTeam = event.GetInt("oldteam");
	int iNewTeam = event.GetInt("team");

	if (IS_VALID_CLIENT(iClient)
	&& !IsFakeClient(iClient)
	&& !g_tPlayers[iClient].member
	&& iOldTeam == TEAM_NONE
	&& iNewTeam != TEAM_SPECTATOR) {
		SetupClientTeam(iClient, TEAM_SPECTATOR);
	}

	return Plugin_Continue;
}

/**
 * Called before client disconnected.
 */
public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) 
{
	if (!IsMix()) {
		return Plugin_Continue;
	}

	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (IS_VALID_CLIENT(iClient) && g_tPlayers[iClient].member)
	{
		AbortMix();
		CPrintToChatAll("%t", "CLIENT_LEAVE", iClient);
	}

	return Plugin_Continue;
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitCmds() 
{
	AddCommandListener(Cmd_OnPlayerJoinTeam, "jointeam");
	RegConsoleCmd("sm_mix", Cmd_VoteMix, "Start Team Mix Voting");
	RegConsoleCmd("sm_unmix", Cmd_CancelMix, "Cancel the current Mix");
	RegAdminCmd("sm_fmix", Cmd_ForceMix, ADMFLAG_BAN, "Run forced Mix");
}

/**
 * Blocking a team change if there is a mix of teams now.
 *
 * @param iClient     Client index
 * @param sCmd        No desc
 * @param iArgs       Number of parameters
 * @return            Plugin_Stop | Plugin_Continue
 */
public Action Cmd_OnPlayerJoinTeam(int iClient, const char[] sCmd, int iArgs)
{
	if (IsMix())
	{
		CPrintToChat(iClient, "%T", "CANT_CHANGE_TEAM", iClient);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

/**
 * Action on command input at the start of the mix.
 *
 * @param iClient     Client index
 * @param iArgs       Number of parameters
 * @return            Plugin_Handled | Plugin_Continue
 */
public Action Cmd_VoteMix(int iClient, int iArgs)
{	
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient) || IS_SPECTATOR(iClient)) {
		return Plugin_Handled;
	}

	if (!iArgs)
	{
		CPrintToChat(iClient, "%T", "NO_ARGUMENT", iClient);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	char sArg[32]; GetCmdArg(1, sArg, sizeof(sArg));

	int iMixType = g_hTypeList.Find(sArg);

	if (iMixType == TYPE_NONE)
	{
		CPrintToChat(iClient, "%T", "BAD_ARGUMENT", iClient, sArg);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	if (CanRunMix(iClient, iMixType))
	{
		g_iMixType = iMixType;
		RunVoteMix(iClient);
	}

	return Plugin_Continue;
}

/**
 * Abort the mix before it's finished.
 *
 * @param iClient     Client index
 * @param iArgs       Number of parameters
 * @return            Plugin_Handled | Plugin_Continue
 */
public Action Cmd_CancelMix(int iClient, int iArgs)
{
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient)) {
		return Plugin_Handled;
	}

	if (!IsMix() || !g_tPlayers[iClient].member) {
		return Plugin_Continue;
	}

	int iEndTime = g_iMixTimeout - GetTime();

	if (iEndTime < 0)
	{
		AbortMix();
		CPrintToChatAll("%t", "CANCEL_MIX_SUCCESS", iClient);
	} 

	else {
		CPrintToChat(iClient, "%T", "CANCEL_MIX_FAIL", iClient, iEndTime);
	}

	return Plugin_Continue;
}

/**
 * Action on command input at the start of the mix.
 *
 * @param iClient     Client index
 * @param iArgs       Number of parameters
 * @return            Plugin_Handled | Plugin_Continue
 */
public Action Cmd_ForceMix(int iClient, int iArgs)
{	
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient)) {
		return Plugin_Handled;
	}

	if (!iArgs)
	{
		CPrintToChat(iClient, "%T", "NO_ARGUMENT", iClient);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	char sArg[32]; GetCmdArg(1, sArg, sizeof(sArg));

	int iMixType = g_hTypeList.Find(sArg);

	if (iMixType == TYPE_NONE)
	{
		CPrintToChat(iClient, "%T", "BAD_ARGUMENT", iClient, sArg);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	if (CanRunMix(iClient, iMixType)) 
	{
		g_iMixType = iMixType;
		RunMix();
	}

	return Plugin_Continue;
}

bool CanRunMix(int iClient, int iMixType)
{
	if (InSecondHalfOfRound())
	{
		CPrintToChat(iClient, "%T", "SECOND_HALF_OF_ROUND", iClient);
		return false;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CPrintToChat(iClient, "%T", "LEFT_READYUP", iClient);
		return false;
	} 
		
	if (!g_bReadyUpAvailable && g_bRoundIsLive) 
	{
		CPrintToChat(iClient, "%T", "ROUND_LIVE", iClient);
		return false;
	}

	if (IsMix()) 
	{
		CPrintToChat(iClient, "%T", "ALREADY_IN_PROGRESS", iClient);
		return false;
	}

	int iMinPlayers = g_hTypeList.GetMinPlayers(iMixType);
	int iTotalPlayers = GetPlayerCount();

	if (iTotalPlayers < iMinPlayers)
	{
		CPrintToChat(iClient, "%T", "BAD_TEAM_SIZE", iClient, iMinPlayers);
		return false;
	}

	return true;
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitForwards() 
{
	g_fOnMixSuccess = new GlobalForward(FORWARD_ON_MIX_SUCCESS, ET_Ignore, Param_String);
	g_fOnMixFailed = new GlobalForward(FORWARD_ON_MIX_FAILED, ET_Ignore, Param_String);
}

/**
 * Start voting.
 * 
 * @param iClient     Client index
 * @return            Return description
 */
public void RunVoteMix(int iClient) 
{
	if (!NativeVotes_IsVoteTypeSupported(NativeVotesType_Custom_YesNo))
	{
		CPrintToChat(iClient, "%T", "UNSUPPORTED", iClient);
		return;
	}

	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T", "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	g_iMixState = STATE_VOTING;

	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(false);
	}

	int iTotalPlayers, iTeam;
	int[] iPlayers = new int[MaxClients];
	
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
			continue;
		}

		iTeam = GetClientTeam(iPlayer);

		if (iTeam == TEAM_INFECTED || iTeam == TEAM_SURVIVOR)
		{
			iPlayers[iTotalPlayers++] = iPlayer;
			g_tPlayers[iPlayer].member = true;
			g_tPlayers[iPlayer].team = iTeam;
		}

		else {
			g_tPlayers[iPlayer].member = false;
		}
	}

	NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_Display);
	hVote.Initiator = iClient;
	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

/**
  * Callback when voting is over and results are available.
  *
  * @param hVote 			Voting ID.
  * @param iAction 			Current action.
  * @param iParam1 		    Client index | Vote status.
  *
  * @return                 None
  */
public int HandlerVote(NativeVote hVote, MenuAction iAction, int iParam1, int iParam2)
{
	switch (iAction)
	{
		case MenuAction_End:
		{
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true);
			}

			hVote.Close();
		}

		case MenuAction_Display:
		{
			char sVoteDisplayMessage[DISPLAY_MSG_SIZE];

			Handle hPlugin = g_hTypeList.GetPlugin(g_iMixType);
			Function hFunc = GetFunctionByName(hPlugin, FORWARD_DISPLAY_MSG);
		
			if (hFunc == INVALID_FUNCTION) {
				SetFailState("Failed to get the function id of " ... FORWARD_DISPLAY_MSG);
			}

			// call FORWARD_DISPLAY_MSG
			Call_StartFunction(hPlugin, hFunc);
			Call_PushCell(iParam1);
			Call_PushStringEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
			Call_Finish();

			NativeVotes_RedrawVoteTitle(sVoteDisplayMessage);

			return view_as<int>(Plugin_Changed);
		}

		case MenuAction_VoteCancel:
		{
			if (iParam1 == VoteCancel_NoVotes) {
				hVote.DisplayFail(NativeVotesFail_NotEnoughVotes);
			}

			else {
				hVote.DisplayFail(NativeVotesFail_Generic);
			}
		}

		case MenuAction_VoteEnd:
		{
			if (iParam1 == NATIVEVOTES_VOTE_NO) {
				hVote.DisplayFail(NativeVotesFail_Loses);
			}

			else
			{
				Function hFunc;
				Handle hPlugin = g_hTypeList.GetPlugin(g_iMixType);

				if ((hFunc = GetFunctionByName(hPlugin, FORWARD_VOTEEND_MSG)) == INVALID_FUNCTION) {
					SetFailState("Failed to get the function id of " ... FORWARD_VOTEEND_MSG);
				}

				char sVoteEndMsg[VOTEEND_MSG_SIZE];

				for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
				{
					if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || IS_SPECTATOR(iPlayer)) {
						continue;
					}

					SetGlobalTransTarget(iPlayer);

					// call FORWARD_VOTEEND_MSG
					Call_StartFunction(hPlugin, hFunc);
					Call_PushCell(iPlayer);
					Call_PushStringEx(sVoteEndMsg, sizeof(sVoteEndMsg), SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
					Call_Finish();
								
					hVote.DisplayPassCustomToOne(iPlayer, sVoteEndMsg);
				}

				RunMix();
			}
		}
	}
	
	return 0;
}

void RunMix()
{
	g_iMixState = STATE_IN_PROGRESS;
	g_iMixTimeout = GetTime() + g_hTypeList.GetTimeout(g_iMixType);

	Function hFunc;
	Handle hPlugin = g_hTypeList.GetPlugin(g_iMixType);

	if ((hFunc = GetFunctionByName(hPlugin, FORWARD_IN_PROGRESS)) == INVALID_FUNCTION) {
		SetFailState("Failed to get the function id of " ... FORWARD_IN_PROGRESS);
	}
	
	SetAllClientSpectator();

	Action aReturn = Plugin_Continue;
				
	// call FORWARD_IN_PROGRESS
	Call_StartFunction(hPlugin, hFunc);
	Call_Finish(aReturn);

	if (aReturn == Plugin_Continue) {
		FinishMix();
	}
}

/**
 * Initiation of the end of the command mix.
 */
void FinishMix()
{
	char sMixName[MIX_NAME_SIZE];
	g_hTypeList.GetName(g_iMixType, sMixName, MIX_NAME_SIZE);

	Call_StartForward(g_fOnMixSuccess);
	Call_PushString(sMixName);
	Call_Finish();

	g_iMixState = STATE_NONE;
	g_iMixType = TYPE_NONE;
}

/**
 * Interrupt if players are disconnected or the round has started.
 */
void AbortMix()
{
	if (NativeVotes_IsVoteInProgress()) {
		NativeVotes_Cancel(); 
	}

	RollbackPlayers();

	char sMixName[MIX_NAME_SIZE];
	g_hTypeList.GetName(g_iMixType, sMixName, MIX_NAME_SIZE);

	Call_StartForward(g_fOnMixFailed);
	Call_PushString(sMixName);
	Call_Finish();

	g_iMixState = STATE_NONE;
	g_iMixType = TYPE_NONE;
}

/**
 * Checks if a mix is ​​currently running.
 *
 * @return             Returns true if a mix is ​​currently in progress, otherwise false
 */
bool IsMix() {
	return g_iMixState != STATE_NONE;
}

/**
 * Returns the number of players in the game.
 * 
 * @return             Client count
 */
int GetPlayerCount() 
{
	int iCount = 0;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IS_REAL_CLIENT(iClient) || IS_SPECTATOR(iClient)) {
			continue;
		}

		iCount++;
	}

	return iCount;
}

/**
 * Returns players to teams before the mix starts.
 *
* @noreturn
*/
void RollbackPlayers()
{
	SetAllClientSpectator();

	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		if (!IS_REAL_CLIENT(iClient) || !g_tPlayers[iClient].member) {
			continue;
		}

		SetupClientTeam(iClient, g_tPlayers[iClient].team);
	}
}

/**
 * Sets everyone to spectator team.
 */
void SetAllClientSpectator()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IS_REAL_CLIENT(iClient)) { 
			continue;
		}

		SetupClientTeam(iClient, TEAM_SPECTATOR);
	}
}

/**
 * Checks if a string is empty.
 */
bool IsEmptyString(const char[] str, int maxlength)
{
	int len = strlen(str);
	if (len == 0)
		return true;
	
	if (len > maxlength)
		len = maxlength;
	
	for (int i = 0; i < len; ++i)
	{
		if (IsCharSpace(str[i]))
			continue;
		
		if (str[i] == '\r' || str[i] == '\n')
			continue;
		
		return false;
	}
	
	return true;
}

/**
 * Displays all types of mixes.
 */
void CPrintExampleArguments(int iClient)
{
	char sMixName[MIX_NAME_SIZE];
	for (int index = 0; index < g_hTypeList.Length; index++)
	{
		g_hTypeList.GetName(index, sMixName, MIX_NAME_SIZE);
		CPrintToChat(iClient, "%T", "ARGUMENT_EXAMPLE", iClient, sMixName);
	}
}

/**
 * Checks if the current round is the second.
 *
 * @return            Returns true if is second round, otherwise false
 */
bool InSecondHalfOfRound() {
	return view_as<bool>(GameRules_GetProp("m_bInSecondHalfOfRound"));
}

/**
 * Sets the client team.
 * 
 * @param iClient     Client index
 * @param iTeam       Param description
 * @return            true if success
 */
bool SetupClientTeam(int iClient, int iTeam)
{
	if (GetClientTeam(iClient) == iTeam) {
		return true;
	}

	if (iTeam == TEAM_INFECTED || iTeam == TEAM_SPECTATOR)
	{
		ChangeClientTeam(iClient, iTeam);
		return true;
	}

	int iBot = FindSurvivorBot();
	if (iTeam == TEAM_SURVIVOR && iBot != -1)
	{
		if (g_bDHookAvailable)
		{
			ChangeClientTeam(iClient, TEAM_NONE);
			SetHumanSpec(iBot, iClient);
			TakeOverBot(iClient);
		}

		else {
			CheatCommand(iClient, "sb_takecontrol");
		}

		return true;
	}

	return false;
}

/**
 * Hack to execute cheat commands.
 */
void CheatCommand(int iClient, const char[] sCmd, const char[] sArgs = "")
{
	int iFlags = GetCommandFlags(sCmd);
	SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
	FakeClientCommand(iClient, "%s %s", sCmd, sArgs);
	SetCommandFlags(sCmd, iFlags);
}

/**
 * Finds a free bot.
 * 
 * @return     Bot index or -1
 */
int FindSurvivorBot()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || !IsFakeClient(iClient) || !IS_SURVIVOR(iClient)) {
			continue;
		}

		return iClient;
	}

	return -1;
}

/**
 * Is the game mode versus.
 *
 * @param sGameMode     A string containing the name of the game mode
 *
 * @return              Returns true if verus, otherwise false
 */
bool IsVersusMode(const char[] sGameMode) {
	return (StrEqual(sGameMode, "versus", false) || StrEqual(sGameMode, "mutation12", false));
}
