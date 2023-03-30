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
    PrintToConsoleAll("TimerCallback Running");
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
        }
        else
        {
            PrintToConsoleAll("CheckingClientRPid > %i", CheckingClientRPid);
            break;
        }
    }
    if (CheckingClientRPid > MaxClients) checkfinished = true;
    if(!checking){
        checking = true;
        if (IsMixMember(CheckingClientRPid)) GetClientRP(CheckingClientRPid, hPlayers);
    }
    // 等待赋值完成
    if (!checkfinished){
        if (temp_prp.IntValue == -1){
            return Plugin_Continue;
        } else {
            iPlayersRP[CheckingClientRPid] = temp_prp.IntValue;
        }
        CPrintToChatAll("{green} %N 的经验分为 %i!", CheckingClientRPid, iPlayersRP[CheckingClientRPid]);
        //PrintToConsoleAll("iPlayersRP[%N] - %i", CheckingClientRPid, iPlayersRP[CheckingClientRPid]);
        checking = false;
        // 开始检查下一个
        if (CheckingClientRPid <= MaxClients){
            CheckingClientRPid++;
            return Plugin_Continue;
        }
    }
    // 所有人全部检查完成，开始分队
    CPrintToChatAll("{green} 所有人全部检查完成，开始分队!");
    CheckingClientRPid = 0;
    checking = false;
    checkfinished = false;
    MixMembers();
    KillTimer(h_mixTimer);
    h_mixTimer = INVALID_HANDLE;
    return Plugin_Stop;
}
public void OnMixFailed(const char[] sMixName){
    KillTimer(h_mixTimer);
    h_mixTimer = INVALID_HANDLE;
}
void MixMembers(){
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
        //PrintToConsoleAll("hPlayers[%N] - %i", tempPlayer.id, tempPlayer.rankpoint);
        PrintToConsoleAll("hPlayers.Length = %i", hPlayers.Length);
    }
    SortADTArrayCustom(hPlayers, SortByRank);

    int surv[4];
    int infs[4];

    // 假设hPlayers是一个Player数组，已经按rankpoint从大到小排序
    // 假设surv和infs是两个int数组，用来存放分配后的玩家id
    // 假设n是玩家的总数，这里是8
    int n = 8;
    // 定义一个二维数组dp，dp[i][j]表示前i个玩家中有j个分配给surv队伍时，两队的评分差距的最小值
    int dp[9][5];

    // 初始化dp数组为无穷大
    for (int i = 0; i <= n; i++) {
        for (int j = 0; j <= n/2; j++) {
            dp[i][j] = 2147483647;
        }
    }

    // 定义一个二维数组path，path[i][j]表示前i个玩家中有j个分配给surv队伍时，第i个玩家是分配给surv队伍还是infs队伍
    bool path[9][5];

    // 初始化path数组为false
    for (int i = 0; i <= n; i++) {
        for (int j = 0; j <= n/2; j++) {
            path[i][j] = false;
        }
    }

    // 定义一个变量sum，表示所有玩家的评分总和
    int sum = 0;

    // 计算sum的值
    for (int i = 0; i < n; i++) {
        Player tempPlayer;
        hPlayers.GetArray(i, tempPlayer);  //  adt_trie.inc GetArrayArray(hPlayers, i, tempPlayer);
        sum += tempPlayer.rankpoint;
        PrintToConsoleAll("sum %i", sum);
    }

    // 动态规划的状态转移方程为：
    // dp[i][j] = min(dp[i-1][j], dp[i-1][j-1] + abs(2 * hPlayers[i-1].rankpoint - sum / (n/2)))
    // path[i][j] = true if dp[i-1][j-1] + abs(2 * hPlayers[i-1].rankpoint - sum / (n/2)) < dp[i-1][j], else false

    // 边界条件为：
    // dp[0][0] = 0
    dp[0][0] = 0;

    // 遍历所有状态，更新dp和path数组
    for (int i = 1; i <= n; i++) {
        for (int j = 0; j <= n/2; j++) {
            // 如果j等于0，表示前i个玩家都分配给infs队伍，那么dp[i][j]等于前i个玩家的评分总和减去平均值的绝对值
            if (j == 0) {
                dp[i][j] = abs(sum - i * sum / (n/2));
            }
            // 如果j等于i，表示前i个玩家都分配给surv队伍，那么dp[i][j]等于前i个玩家的评分总和减去平均值的绝对值
            else if (j == i) {
                dp[i][j] = abs(sum - (n - i) * sum / (n/2));
            }
            // 否则，根据状态转移方程更新dp[i][j]和path[i][j]
            else {
                Player tempPlayer;
                GetArrayArray(hPlayers, i-1, tempPlayer);
                int temp = dp[i-1][j-1] + abs(2 * tempPlayer.rankpoint - sum / (n/2));
                if (temp < dp[i-1][j]) {
                    dp[i][j] = temp;
                    path[i][j] = true;
                }
                else {
                    dp[i][j] = dp[i-1][j];
                    path[i][j] = false;
                }
            }
        }
    }

    int surrankpoint, infrankpoint = 0;

    // 根据path数组回溯找出最优的分配方案
    int i = n;
    int j = n/2;
    PrintToConsoleAll("Mix成员 经验评分 = 2*对抗胜率*(0.55*真实游戏时长+TANK饼命中数*每小时中饼数)");
    PrintToConsoleAll("-----------------------------------------------------------");
    // z 3417
    // p 3145

    while (i > 0 && j >= 0) {
        // 如果path[i][j]为true，表示第i个玩家分配给surv队伍
        if (path[i][j]) {
            // 将第i个玩家的id存入surv数组
            Player tempPlayer;
            GetArrayArray(hPlayers, i-1, tempPlayer);
            surv[j-1] = tempPlayer.id;
            //PrintToConsoleAll("%N  %i=2*%.2f*(0.75*%i+%i)",tempPlayer.id, tempPlayer.winrounds ,tempPlayer.rankpoint, tempPlayer.gametime, tempPlayer.tankrocks);
            surrankpoint = surrankpoint + tempPlayer.rankpoint;
            // 更新i和j的值
            i--;
            j--;
        }
        // 否则，表示第i个玩家分配给infs队伍
        else {
            // 将第i个玩家的id存入infs数组
            Player tempPlayer;
            GetArrayArray(hPlayers, i-1, tempPlayer);
            infs[n/2 - j - 1] = tempPlayer.id;
            //PrintToConsoleAll("%N  %i=2*%.2f*(0.75*%i+%i)",tempPlayer.id, tempPlayer.winrounds ,tempPlayer.rankpoint, tempPlayer.gametime, tempPlayer.tankrocks);
            infrankpoint = infrankpoint + tempPlayer.rankpoint;
            // 更新i的值
            i--;
        }
    }

    

    // 分配队伍
    for(int tosurv = 0; tosurv < sizeof(surv); tosurv++){
        SetClientTeam(surv[tosurv], L4D2Team_Survivor);
    }
    for(int toinf = 0; toinf < sizeof(infs); toinf++){
        SetClientTeam(infs[toinf], L4D2Team_Infected);
    }
    CPrintToChatAll("[{green}!{default}] {olive}队伍分配完毕!");
    CPrintToChatAll("生还者经验分平均为 {blue}%i", RoundToNearest(surrankpoint));
    CPrintToChatAll("特感者经验分平均为 {red}%i", RoundToNearest(infrankpoint));
    CPrintToChatAll("[{green}!{default}] {olive}你可以查看控制台输出来获取每个人的经验信息!");
    // Required
    CallEndMix();

}

/**
 * Starting the mix.
 * 
 * @noreturn
 */

public void OnMixInProgress()
{
    hPlayers.Clear();
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
        PrintToConsoleAll("%N  %i=2*%.2f*(0.55*%i+%i*1)",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);
        temp_prp.IntValue = rankpt;
        return rankpt;
    }
    Format(URL,sizeof(URL),"%s&key=%s&steamid=%s",VALVEURL,VALVEKEY,id64);
    HTTPRequest request = new HTTPRequest(URL);
    request.Get(OnReceived, iClient);
    PrintToServer("%s",URL);
    //PrintToConsoleAll("rankpt: %i", rankpt);
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
        PrintToConsoleAll("%N  %i=2*%f*(0.55*%i*+%i*1)",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);\
        return;  
    }
    JSONObject json = view_as<JSONObject>(response.Data);
    json=view_as<JSONObject>(json.Get("playerstats"));
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

/**
 * Hack to execute cheat commands.
 * 
 * @noreturn
 */
void CheatCommand(int iClient, const char[] sCmd, const char[] sArgs = "")
{
    int iFlags = GetCommandFlags(sCmd);
    SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
    FakeClientCommand(iClient, "%s %s", sCmd, sArgs);
    SetCommandFlags(sCmd, iFlags);
}
/**
 * Sets the client team.
 * 
 * @param iClient     Client index
 * @param iTeam       Param description
 * @return            true if success
 */
bool SetClientTeam(int iClient, int iTeam)
{
    if (!IS_VALID_CLIENT(iClient)) {
        return false;
    }

    if (GetClientTeam(iClient) == iTeam) {
        return true;
    }

    if (iTeam != TEAM_SURVIVOR) {
        ChangeClientTeam(iClient, iTeam);
        return true;
    }
    else if (FindSurvivorBot() > 0)
    {
        CheatCommand(iClient, "sb_takecontrol");
        return true;
    }

    return false;
}
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