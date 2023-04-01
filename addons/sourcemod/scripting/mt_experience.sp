#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <ripext>
#include <l4d2util>

#define VALVEURL "http://api.steampowered.com/ISteamUserStats/GetUserStatsForGame/v0002/?appid=550"
char VALVEKEY[64];
enum struct Player{
    int id;
    int rankpoint;  // 综合评分
    int gametime;	// 真实游戏时长
    int tankrocks;	// 坦克饼命中数
    float winrounds;	//胜场百分比（0-1）, <500置默认
    int versustotal;
    int versuswin;
    int versuslose;
}
ArrayList hPlayers;
ConVar temp_prp;
Handle h_mixTimer;
int iPlayersRP[MAXPLAYERS + 1] = {-1};
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)

public Plugin myinfo = { 
    name = "MixTeamTime",
    author = "SirP",
    description = "Adds mix team by time",
    version = "1.0"
};


#define TRANSLATIONS            "mt_team.phrases"

#define TEAM_SURVIVOR           2 
#define TEAM_INFECTED           3

#define MIN_PLAYERS             1

// Macros
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))


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
    //InitTranslations();
    GetKeyinFile();
    hPlayers = new ArrayList(sizeof(Player));
    temp_prp = CreateConVar("itemp_prp", "-1", "TempVariable");
}

public void OnAllPluginsLoaded() {
    AddMixType("exp", MIN_PLAYERS, 0);
}

public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
    Format(sTitle, DISPLAY_MSG_SIZE, "开始mix（根据经验分队）", iClient);
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
    Format(sMsg, VOTEEND_MSG_SIZE, "正在分队...", iClient);
}
int CheckingClientRPid = 0;
bool checking = false;
bool checkfinished = false;
public Action TimerCallback(Handle timer)
{
    //PrintToConsoleAll("TimerCallback Running - %i CheckingClientRPid", CheckingClientRPid);
    // 开始
    if (CheckingClientRPid == 0){
        CPrintToChatAll("{green}开始获取mix成员的统计信息!");
        CheckingClientRPid++;
    }
    // 确定下一个要检查的id
    while (CheckingClientRPid <= MaxClients){
        if (checking) break;
        if (!IsClientInGame(CheckingClientRPid) || !IsMixMember(CheckingClientRPid)) {
            CheckingClientRPid++;
            //PrintToConsoleAll("CheckingClientRPid > %i(INVAILD)", CheckingClientRPid);
        }
        else
        {
            //PrintToConsoleAll("CheckingClientRPid > %i", CheckingClientRPid);
            break;
        }
    }
    
    if(!checking){
        checking = true;
        GetClientRP(CheckingClientRPid, hPlayers);
    }
    if (CheckingClientRPid > MaxClients) checkfinished = true;
    // 等待赋值完成
    if (!checkfinished){
        if (temp_prp.IntValue == -1){
            return Plugin_Continue;
        } else {
            iPlayersRP[CheckingClientRPid] = temp_prp.IntValue;
            checking = false;
        }
        CPrintToChatAll("{green}%N 的经验分为 %i!", CheckingClientRPid, iPlayersRP[CheckingClientRPid]);
        checking = false;
        // 开始检查下一个
        CheckingClientRPid++;
        if (CheckingClientRPid <= MaxClients){
            return Plugin_Continue;
        }
    }
    
    CPrintToChatAll("{green}所有人全部检查完成，开始分队!");
    MixMembers();
    CheckingClientRPid = 0;
    checking = false;
    checkfinished = false;
    CallEndMix();
    return Plugin_Stop;
}
public void OnMixFailed(const char[] sMixName){
    KillTimer(h_mixTimer);
    h_mixTimer = INVALID_HANDLE;
}
void MixMembers(){
    // 构建player数组
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || !IsMixMember(iClient)) {
            continue;
        }
        if (iPlayersRP[iClient] == -1) continue;
        Player tempPlayer;
        tempPlayer.id = iClient;
        tempPlayer.rankpoint = iPlayersRP[iClient];
        hPlayers.PushArray(tempPlayer);
    }
    //SortADTArrayCustom(hPlayers, SortByRank);
    hPlayers.SortCustom(SortByRank);

    int surv[4], infs[4];

    int total_sum = 0;
    int cinf, csur = 0;
    for (int i = 0; i < hPlayers.Length; i++)
    {
        Player tempPlayer;
        hPlayers.GetArray(i, tempPlayer);
        total_sum += tempPlayer.rankpoint;
    }

    // 从hPlayers数组中依次取出玩家，并将其放入A1或A2中
    int sum1 = 0;
    int sum2 = 0;
    for (int i = 0; i < hPlayers.Length; i++)
    {
        Player tempPlayer;
        hPlayers.GetArray(i, tempPlayer);
        if (cinf >= 4){
            surv[csur] = tempPlayer.id;
            csur++;
            sum1 += tempPlayer.rankpoint;
            continue;
        }else if(csur >= 4)
        {
            infs[cinf] = tempPlayer.id;
            csur++;
            sum2 += tempPlayer.rankpoint;
            continue;
        }
        if (sum1 + tempPlayer.rankpoint <= total_sum / 2)
        {
            surv[csur] = tempPlayer.id;
            csur++;
            sum1 += tempPlayer.rankpoint;
        }
        else
        {
            infs[cinf] = tempPlayer.id;
            csur++;
            sum2 += tempPlayer.rankpoint;
        }
    }

    int surrankpoint, infrankpoint = 0;

    PrintToConsoleAll("Mix成员 经验评分 = 2*对抗胜率*(0.55*真实游戏时长+TANK饼命中数*每小时中饼数)");
    PrintToConsoleAll("-----------------------------------------------------------");

    surrankpoint = sum1;
    infrankpoint = sum2;

    // 分配队伍
    for(int tosurv = 0; tosurv < sizeof(surv); tosurv++){
        if (IsMixMember(surv[tosurv])) SetClientTeam(surv[tosurv], L4D2Team_Survivor);
    }
    for(int toinf = 0; toinf < sizeof(infs); toinf++){
        if (IsMixMember(infs[toinf])) SetClientTeam(infs[toinf], L4D2Team_Infected);
    }
    CPrintToChatAll("[{green}!{default}] {olive}队伍分配完毕!");
    CPrintToChatAll("生还者经验分为 {blue}%i", surrankpoint);
    CPrintToChatAll("特感者经验分为 {red}%i", infrankpoint);
    CPrintToChatAll("[{green}!{default}] {olive}你可以查看控制台输出来获取每个人的经验信息!");
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */

public void OnMixInProgress()
{
    hPlayers.Clear();
    CheckingClientRPid = 0;
    checking = false;
    checkfinished = false;
    h_mixTimer = CreateTimer(1.0, TimerCallback, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

int SortByRank(int indexFirst, int indexSecond, Handle hArrayList, Handle hndl)
{
    Player tPlayerFirst, tPlayerSecond;

    GetArrayArray(hArrayList, indexFirst, tPlayerFirst);
    GetArrayArray(hArrayList, indexSecond, tPlayerSecond);

    if (tPlayerFirst.rankpoint < tPlayerSecond.rankpoint) {
        return -1;
    }

    if (tPlayerFirst.rankpoint > tPlayerSecond.rankpoint) {
        return 1;
    }

    return 0;
}

int abs(int value){
    if (value < 0){
        value = 0 - value;
    }
    return value;
}

/**
 * 获取Steam api key
 * 
 * @noreturn
 */
void GetKeyinFile()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath),"configs/api_key.txt");//檔案路徑設定

    Handle file = OpenFile(sPath, "r");//讀取檔案
    if(file == INVALID_HANDLE)
    {
        SetFailState("file configs/api_key.txt doesn't exist!");
        return;
    }

    char readData[256];
    if(!IsEndOfFile(file) && ReadFileLine(file, readData, sizeof(readData)))//讀一行
    {
        Format(VALVEKEY, sizeof(VALVEKEY), "%s", readData);
    }
}

/**
 * 获取玩家的经验评分
 * 一般来说，如果失败会返回1085分 
 * 
 * @param iClient 玩家id
 * @noreturn
 */
int rankpt = -1;
int GetClientRP(int iClient, ArrayList hPlayers)
{
    temp_prp.IntValue = -1;
    Player iPlayer;
    iPlayer.id = iClient;
    // 获取信息
    char URL[1024];
    char id64[64];
    GetClientAuthId(iPlayer.id,AuthId_SteamID64,id64,sizeof(id64));
    if(StrEqual(id64,"STEAM_ID_STOP_IGNORING_RETVALS")){
        iPlayer.gametime = 700;
        iPlayer.tankrocks = 700;
        iPlayer.winrounds = 0.5;
        float rp = 2.0 * iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks));
        iPlayer.rankpoint = RoundToNearest(rp);
        rankpt = iPlayer.rankpoint;
        PrintToConsoleAll("%N(获取失败)  %i=2*%.2f*(0.55*%i+%i*1)",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);
        temp_prp.IntValue = rankpt;
        return rankpt;
    }
    Format(URL,sizeof(URL),"%s&key=%s&steamid=%s",VALVEURL,VALVEKEY,id64);
    HTTPRequest request = new HTTPRequest(URL);
    request.Get(OnReceived, iClient);
    PrintToServer("%s",URL);
    return temp_prp.IntValue;    
}


public void OnReceived(HTTPResponse response, int id)
{
    Player iPlayer;
    iPlayer.id = id;
    char buff[50];
    if (response.Data == null) {
        PrintToServer("Invalid JSON response");
        iPlayer.gametime = 700;
        iPlayer.tankrocks = 700;
        iPlayer.winrounds = 0.5;
        float rp = 2.0 * iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks));
        iPlayer.rankpoint = RoundToNearest(rp);
        temp_prp.IntValue = iPlayer.rankpoint;
        PrintToConsoleAll("%N(获取失败)  %i=2*%f*(0.55*%i*+%i*1)",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);\
        return;  
    }
    JSONObject json = view_as<JSONObject>(response.Data);
    if (json.HasKey("playerstats")){
        json=view_as<JSONObject>(json.Get("playerstats"));
    }
    else
    {
        PrintToServer("JSON response dont have key `playerstats`");
        iPlayer.gametime = 700;
        iPlayer.tankrocks = 700;
        iPlayer.winrounds = 0.5;
        float rp = 2.0 * iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks));
        iPlayer.rankpoint = RoundToNearest(rp);
        temp_prp.IntValue = iPlayer.rankpoint;
        CPrintToChatAll("{red} %N 未公开游戏游戏详情，将以1085分参与mix");
        PrintToConsoleAll("%N(获取失败)  %i=2*%f*(0.55*%i*+%i*1)",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);\
        return;  
    }
    JSONArray jsonarray=view_as<JSONArray>(json.Get("stats"));
    for(int j=0;j<jsonarray.Length;j++)
    {
        json=view_as<JSONObject>(jsonarray.Get(j));
        json.GetString("name",buff,sizeof(buff));
        if(StrEqual(buff,"Stat.TotalPlayTime.Total"))		
        {
            iPlayer.gametime = json.GetInt("value")/3600;
        }else if(StrEqual(buff,"Stat.SpecAttack.Tank")){
            iPlayer.tankrocks = json.GetInt("value");
        }else if(StrEqual(buff,"Stat.GamesLost.Versus")){
            iPlayer.versuslose = json.GetInt("value");
        }else if(StrEqual(buff,"Stat.GamesWon.Versus")){
            iPlayer.versuswin = json.GetInt("value");
        }
    }
    iPlayer.versustotal = iPlayer.versuswin + iPlayer.versuslose;
    iPlayer.winrounds = float(iPlayer.versuswin) / float(iPlayer.versustotal);
    if(iPlayer.versustotal < 700){
        iPlayer.winrounds = 0.5;
    }
    float rpm = float(iPlayer.tankrocks) / float(iPlayer.gametime);
    float rp = 2.0 * iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks) * rpm);
    iPlayer.rankpoint = RoundToNearest(rp);
    temp_prp.IntValue = iPlayer.rankpoint;
    PrintToConsoleAll("%N  %i=2*%f*(0.55*%i*+%i*%f)",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks, rpm);\
}
