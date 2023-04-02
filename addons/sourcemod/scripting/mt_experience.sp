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
ArrayList team1, team2, a_players;
Player tempPlayer;
ConVar temp_prp;
Handle h_mixTimer;
int prps[MAXPLAYERS + 1] = {-1};
int diffs;
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

#define MIN_PLAYERS             8

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
    a_players = new ArrayList(sizeof(Player));
    temp_prp = CreateConVar("itemp_prp", "-1", "TempVariable");
    /*for (int i = 0; i < 8; i++){
        Player P1;
        P1.id = i;
        prps[i] = GetRandomInt(100, 10000);
        a_players.PushArray(P1);
        PrintToServer("Set: %i - %i", P1.id, prps[i]);
    }
    min_diff();
    print_result();*/
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
        GetClientRP(CheckingClientRPid);
    }
    if (CheckingClientRPid > MaxClients) checkfinished = true;
    // 等待赋值完成
    if (!checkfinished){
        if (temp_prp.IntValue == -1){
            return Plugin_Continue;
        } else {
            prps[CheckingClientRPid] = temp_prp.IntValue;
            checking = false;
        }
        CPrintToChatAll("{green}%N 的经验分为 %i!", CheckingClientRPid, prps[CheckingClientRPid]);
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
        if (prps[iClient] == -1) continue;
        tempPlayer.id = iClient;
        tempPlayer.rankpoint = prps[iClient];
        a_players.PushArray(tempPlayer);
    }
    //SortADTArrayCustom(a_players, SortByRank);
    a_players.SortCustom(SortByRank);
    int surrankpoint, infrankpoint = 0;

    min_diff();

    PrintToConsoleAll("Mix成员 经验评分 = 2*对抗胜率*(0.55*真实游戏时长+TANK饼命中数*每小时中饼数)");
    PrintToConsoleAll("-----------------------------------------------------------");

    for (int i = 0; i < team1.Length; i++)
    {
        team1.GetArray(i, tempPlayer);
        if (IsMixMember(tempPlayer.id)) SetClientTeam(tempPlayer.id, L4D2Team_Survivor);
    }
    for (int i = 0; i < team2.Length; i++)
    {
        team2.GetArray(i, tempPlayer);
        if (IsMixMember(tempPlayer.id)) SetClientTeam(tempPlayer.id, L4D2Team_Survivor);
    }

    CPrintToChatAll("[{green}!{default}] {olive}队伍分配完毕!");
    CPrintToChatAll("生还方经验分为 {blue}%i", surrankpoint);
    CPrintToChatAll("特感方经验分为 {red}%i", infrankpoint);
    CPrintToChatAll("双方分差 {olive}%i", diffs);
    CPrintToChatAll("[{green}!{default}] {olive}你可以查看控制台输出来获取每个人的经验信息!");
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */

public void OnMixInProgress()
{
    a_players.Clear();
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

    if (prps[tPlayerFirst.id] < prps[tPlayerSecond.id]) {
        return -1;
    }

    if (prps[tPlayerFirst.id] > prps[tPlayerSecond.id]) {
        return 1;
    }

    return 0;
}

int abs(int value){
    if (value < 0) return -value;
    return value;   
}
// 定义一个函数，用来计算两个数组的和的差值
int diff_sum(ArrayList array1, ArrayList array2)
{
    // 初始化两个数组的和
    int sum1 = 0;
    int sum2 = 0;
    // 遍历第一个数组，累加元素
    for (int i = 0; i < array1.Length; i++)
    {
        array1.GetArray(i, tempPlayer);
        sum1 += prps[tempPlayer.id];
    }
    // 遍历第二个数组，累加元素
    for (int i = 0; i < array2.Length; i++)
    {
        array2.GetArray(i, tempPlayer);
        sum2 += prps[tempPlayer.id];
    }
    // 返回两个数组的和的绝对值差
    return abs(sum1 - sum2);
}

// 定义一个函数，用来打印结果
void print_result()
{
    // 打印最小差值
    PrintToServer("The minimum difference is %d.", diffs);
    // 打印第一个分组
    PrintToServer("The first group is:");
    for (int i = 0; i < team1.Length; i++)
    {
        team1.GetArray(i, tempPlayer);
        PrintToServer("%i - %i", tempPlayer.id, prps[tempPlayer.id]);
    }
    // 打印第二个分组
    PrintToServer("The second group is:");
    for (int i = 0; i < team2.Length; i++)
    {
        team2.GetArray(i, tempPlayer);
        PrintToServer("%i - %i", tempPlayer.id, prps[tempPlayer.id]);
    }
}

// 定义一个函数，用来找出所有可能的分组方式，并返回最小的差值和对应的分组
void min_diff()
{
    // 对数组进行排序
    a_players.SortCustom(SortByRank);
    // 初始化最小差值和分组
    diffs = 2147483647; // 最大的整数值
    //min_group = null;
    // 遍历所有可能的分组方式
    for (int i = 0; i < a_players.Length - 3; i++)
    {
        for (int j = i + 1; j < a_players.Length - 2; j++)
        {
            for (int k = j + 1; k < a_players.Length - 1; k++)
            {
                for (int l = k + 1; l < a_players.Length; l++)
                {
                    // 将数组分成两个子数组
                    ArrayList group1 = new ArrayList();// = {array[i], array[j], array[k], array[l]};
                    group1.Resize(4);
                    a_players.GetArray(i, tempPlayer);  
                    group1.SetArray(0,tempPlayer);
                    a_players.GetArray(j, tempPlayer);  
                    group1.SetArray(1,tempPlayer);
                    a_players.GetArray(k, tempPlayer);  
                    group1.SetArray(2,tempPlayer);
                    a_players.GetArray(l, tempPlayer);  
                    group1.SetArray(3,tempPlayer);

                    int m, n, o, p;
                    for (m=0; m<a_players.Length; m++){
                        if (m != i && m != j && m != k && m != l) break;
                    }
                    for (n=0; n<a_players.Length; n++){
                        if (n != i && n != j && n != k && n != l && n != m) break;
                    }
                    for (o=0; o<a_players.Length; o++){
                        if (o != i && o != j && o != k && o != l && o != m && o != n) break;
                    }
                    for (p=0; p<a_players.Length; p++){
                        if (p != i && p != j && p != k && p != l && p != m && p != n && p != o) break;
                    }                    
                    
                    ArrayList group2 = new ArrayList();
                    group2.Resize(4);
                    a_players.GetArray(m, tempPlayer);  
                    group2.SetArray(0,tempPlayer);
                    a_players.GetArray(n, tempPlayer);  
                    group2.SetArray(1,tempPlayer);
                    a_players.GetArray(o, tempPlayer);  
                    group2.SetArray(2,tempPlayer);
                    a_players.GetArray(p, tempPlayer);  
                    group2.SetArray(3,tempPlayer);

                    int diff = diff_sum(group1, group2);
                    // 如果差值小于当前最小差值，更新最小差值和分组
                    if (diff < diffs)
                    {
                        diffs = diff;
                        if (team1 != INVALID_HANDLE){
                            team1.Resize(0);
                        }
                        if (team2 != INVALID_HANDLE){
                            team1.Resize(0);
                        }
                        team1 = group1.Clone();
                        team2 = group2.Clone();
                    }
                    delete group1;
                    delete group2;

                }
            }
        }
    }
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
int GetClientRP(int iClient)
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
        CPrintToChatAll("{red} %N 无法获取Steam64位ID，将以1085分参与mix", iClient);
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
        CPrintToChatAll("{red} %N 获取游戏信息失败，将以1085分参与mix", id);
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
        CPrintToChatAll("{red} %N 未公开游戏详情，将以1085分参与mix", id);
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
