# 关于mix_team

该插件添加功能mix队伍投票。mix_team插件本身并不实现玩家混合，但提供了API。
多种预置mix类型可用：

1. capitan(队长选人)
2. random(随机分配)
3. exp(基于游戏经验分配)
4. randmap(随机官方地图)
5. ranthirdmap(随机第三方地图)
6. rank(基于[VersusStat](https://github.com/TouchMe-Inc/l4d2_versus_stats)分配)

##命令
`!mix <type>` - 开始 <type> 类型的mix.

`!unmix` / `!cancelmix` - 终端mix.

## 如何创建 mix 类型?
您必须编写和编译一个实现所有方法的插件：
```pawn
#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded()
{
	// 添加超时为60秒（可以被打断），至少要求4人的mix类型。指令：!mix supermix
	AddMixType("supermix", 4, 60);
}

// 设定投票名称
public void GetVoteDisplayMessage(int iClient, char[] sTitle) { // 必需！！！
	Format(sTitle, DISPLAY_MSG_SIZE, "My vote title!");
}

// 设定投票成功消息
public void GetVoteEndMessage(int iClient, char[] sMsg) { // 必需！！！
	Format(sMsg, VOTEEND_MSG_SIZE, "Vote done!");
}

public void OnMixInProgress() // 必需！！！入口点
{
	// mix主流程
	
	...
	CallEndMix(); // 必需！！！出口点
}
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)    
[ripext](https://github.com/ErikMinekus/sm-ripext/releases/tag/1.3.1)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)
