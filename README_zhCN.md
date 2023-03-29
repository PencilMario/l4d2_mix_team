# 关于mix_team

该插件添加功能mix队伍投票。mix_team插件本身并不实现玩家混合，但提供了API。
多种预置mix类型可用：

1. capitan(队长选人)
2. random(随机分配)
3. exp(基于游戏经验分配)
4. randmap(随机官方地图)
5. ranthirdmap(随机第三方地图)
6. rank(基于[VersusStat](https://github.com/TouchMe-Inc/l4d2_versus_stats)分配)

## Commands
`!mix <type>` - start mix <type>.

`!unmix` or `!cancelmix` - abort the mix.

## How to create mix type?
You must write and compile a plugin that implements all methods:
```pawn
#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded()
{
	// add mix type with timeout 60sec (can be interrupted). Run: "!mix supermix"
	AddMixType("supermix", 4, 60);
}

// MANDATORY set the name of the vote
public void GetVoteDisplayMessage(int iClient, char[] sTitle) { // Required!!!
	Format(sTitle, DISPLAY_MSG_SIZE, "My vote title!");
}

// MANDATORY set a message in case of success
public void GetVoteEndMessage(int iClient, char[] sMsg) { // Required!!!
	Format(sMsg, VOTEEND_MSG_SIZE, "Vote done!");
}

public void OnMixInProgress() // Required!!! Point of entry
{
	// Payload
	
	...
	CallEndMix(); // Required!!! Exit point
}
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)    
[ripext](https://github.com/ErikMinekus/sm-ripext/releases/tag/1.3.1)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)
