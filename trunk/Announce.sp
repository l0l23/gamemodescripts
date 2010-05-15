/*
 *	This is a general announcements plugin. It reports via chat hint, or center text (depending on
 *	feature - some are only chat) many different events. This list of events include (but may not be
 *	limited to):
 *		Tank health at the end of a round when all survivors die (or escape).
 *		When a Charger gets leveled (killed by a melee), it will be reported by who and what weapon.
 *		When an Infected dies, a message will be sent about who (all parties involved) killed him and how much damage they did.
 *		L4D1 used to report player connection info, L4D2 is stingy.. connects and team changing is now reported.
 *		Friendly Fire is bad, and now you can't fake it because this plugin will tattle.
 *
 *	Not an announcement, but certain models don't get precached all the time. Some plugins (or even admin commands)
 *	like to access these models, so they are getting pre-cached here.
 *
 *	Many of the features of this plugin came from other plugins (before I expanded upon or completely
 *	rewrote them)..
 *	Assist original author: [E]c
 *	PreCaching idea came from: mi123645 (part of the code of one of his plugins)
 *	TankHP from: http://forums.alliedmods.net/showthread.php?t=116961
 *	Charger Leveling from: http://forums.alliedmods.net/showthread.php?t=125326
 *	PlayerInfo original author: Sky
 *	FF author: Frustian
 *	Round Start Notification: http://forums.alliedmods.net/showthread.php?t=123344
 *
 *	ToDo:
 *		Make the FF announce type dynamic (when the cvar changes, it will happen live)..
 *		- This is the only non bool cvar and the only one I havent hooked yet.
 *		Improve the Round Start messaging.. also do what I plan to do with the above /\..
 *		Assist needs an overhaul.. I still believe it to be inaccurate and more importantly, it overflows the chat
 *		- when killing a tank with 3-4 people.. have to shorten it or break it up into 2 messages.
 *
 *	Version History:
 *		1.0 -	Initial release
 *		1.0.1 -	Cleaned up code a little and made sure it only works in L4D2 (tank id is dif in L4D1).
 *		1.1 -	Added charger leveling report (added melee weapon that original didn't have).
 *		1.2 -	Added pre-caching of player models that could cause crashing if they spawned on the wrong map.
 *		1.3 -	Added Assist plugin (heavily modified it).
 *		1.4 -	Added PlayerInfo plugin after fixing it.
 *		1.4.1 -	Fixed some string issues (to prevent overflows) and tag mismatches.
 *		1.5 -	Added Friendly Fire Announce.
 *		1.5.1 -	Added AutoConfigs.
 *		1.5.2 -	Added Debugging (not complete).
 *		1.5.3 -	Fixed some errors and worked on Tank reporting, I screwed it up somehow merging everything.
 *		1.5.4 -	Replaced \x0? with Colors from Colors.inc v1.03 and updated some of the print commands.
 *				Rewrote playerInfo to not spam as much, and finished debug prints (I think).
 *		1.5.5 -	Fixed Charger Leveled display.
 *		1.5.6 -	Fixed some errors.
 *		1.6 -	Added Witch spawn and cr0wn reports.
 *		1.6.1 -	Updated Level A Charge chat messages.
 *		1.7 -	Added Round Start notification.
 *		1.7.1 -	Added Assist reporting to Witch kills.
 *				Cleaned up Assist reporting code to make it easier to read.
 *				Added MAX_WITCHES, used to track how many witches die in a map. Can be a resource hog if set too high.
 *				Added Tank detection for L4D1, should be good to use in either game now.
 *				Fixed bug in FF code that I somehow slipped in.
 *				Fixed Assist method of reporting.. should send out 2 (or more) message lines instead of truncating.
 *		1.7.2	Added Welcome Message (not completed yet).
 *				Tried fixing Round Started print message.. I believe it is screwing up Assist/Witch-Assist.
 *
 */

#include <sourcemod>
#include <sdktools>
#include <colors>

#pragma semicolon 1

#define PLUGIN_VERSION "1.7.2"

#define TEST_DEBUG			0
#define TEST_DEBUG_LOG		0

#define TEAM_SPECTATORS		1
#define TEAM_SURVIVORS		2
#define TEAM_INFECTED		3

#define MAX_WITCHES			16	// If there are ever anymore then this (killed) on 1 map.. OMG!
								// This value is used in at least 1 for loop every map,
								// so don't go crazy if you don't have to.
#define MAX_CHAT_LENGTH		MAX_MESSAGE_LENGTH	// formerly 256.. will replace later

#define TAG_DEBUG	"[DEBUG] "
#define TAG_TANK	"{lightgreen}[TankHP]{default} "
#define TAG_WITCH	"{lightgreen}[Witch]{default} "
#define TAG_LEVEL	"{lightgreen}[Level]{default} "
#define TAG_INFO	"{lightgreen}[Join]{default} "
#define TAG_ASSIST	"{lightgreen}[Assist]{default} "
#define TAG_FF		"{lightgreen}[FF]{default} "

new Handle:	g_hEnabled			=	INVALID_HANDLE;
new Handle:	g_hPreCache			=	INVALID_HANDLE;
new Handle:	g_hTankHP			=	INVALID_HANDLE;
new Handle:	g_hLevel			=	INVALID_HANDLE;
new Handle:	g_hAssists			=	INVALID_HANDLE;
new Handle:	g_hReportTank		=	INVALID_HANDLE;
new Handle:	g_hReportAttacks	=	INVALID_HANDLE;
new Handle:	g_hPlayerInfo		=	INVALID_HANDLE;
new Handle:	g_hFFAnnounce		=	INVALID_HANDLE;
new Handle:	g_hWitchAnnounce	=	INVALID_HANDLE;

new bool:	g_bEnabled			=	true;
new bool:	g_bPreCache			=	true;
new bool:	g_bTankHP			=	true;
new bool:	g_bLevel			=	true;
new bool:	g_bAssists			=	true;
new bool:	g_bReportTank		=	false;
new bool:	g_bReportAttacks	=	false;
new bool:	g_bPlayerInfo		=	true;
new bool:	g_bFFAnnounce		=	true;
new bool:	g_bWitchAnnounce	=	true;

new bool:	g_bL4D2Version		=	false;

// Tank and Witch
new				ZOMBIECLASS_TANK;		// This value varies depending on which L4D game it is, holds the the tank class value
static bool:	DisplayedOnce = false;
new Handle:		g_hCvar_WitchHealth	=	INVALID_HANDLE;
new Handle:		g_hCvar_WitchSpeed	=	INVALID_HANDLE;
new 			WitchesKilled		=	0;

new bool:	Connecting[MAXPLAYERS+1];
new bool:	Joining[MAXPLAYERS+1];				// No need to spam join specator, join team when someone connects..
new Handle:	JoiningTimer[MAXPLAYERS+1];			// Used to disable joining specator team when someone connects.

// FF Announce
new Handle:	g_hFFAnnounceType;					// Type of chat message to use
new 		DamageCache[MAXPLAYERS+1][MAXPLAYERS+1];	// Used to temporarily store Friendly Fire Damage between teammates
new Handle:	FFTimer[MAXPLAYERS+1];				// Used to be able to disable the FF timer when they do more FF
new bool:	FFActive[MAXPLAYERS+1];				// Stores whether players are in a state of friendly firing teammates
new Handle:	g_hCvar_DirectorReady;

// Round Start Sound
new Handle:	g_hStartSound			=	INVALID_HANDLE;
new Handle:	g_hStartMessage			=	INVALID_HANDLE;
new Handle:	g_hStartMessageType		=	INVALID_HANDLE;
new Handle:	g_hStartMessageSound	=	INVALID_HANDLE;
new String:	soundFilePath[PLATFORM_MAX_PATH];
new bool:	g_bStartSound	=	true;
new bool:	isStarting		=	true;

// Assist
new Damage[MAXPLAYERS+1][MAXPLAYERS+1];
new WitchDamage[MAXPLAYERS+1][MAX_WITCHES+1];
new String:Temp1[] = " | Assists: ";
new String:Temp2[] = ", ";
new String:Temp3[] = " (";
new String:Temp4[] = " dmg)";
new String:Temp5[] = "{green}";
new String:Temp6[] = "{default}";
new String:Temp7[] = ".";
new String:Temp8[] = "{olive}";
new String:Temp9[] = "{green}%N{default} was killed by {green}";
// Witch-Assist
new String:Temp10[] = "A {green}Witch{default}";
new String:Temp11[] = ")";
new String:Temp12[] = " was killed by {green}";

// Charger Level
new String:Weapon0[] = "an {olive}unknown weapon{default}";
new String:Weapon1[] = "a {olive}baseball bat{default}";
new String:Weapon2[] = "a {olive}cricket bat{default}";
new String:Weapon3[] = "a {olive}crowbar{default}";
new String:Weapon4[] = "an {olive}electric guitar{default}";
new String:Weapon5[] = "a {olive}fireaxe{default}";
new String:Weapon6[] = "a {olive}frying pan{default}";
new String:Weapon7[] = "a {olive}katana{default}";
new String:Weapon8[] = "a {olive}knife{default}";
new String:Weapon9[] = "a {olive}machete{default}";
new String:Weapon10[] = "a {olive}tonfa{default}";
new String:Weapon11[] = "a {olive}golf club{default}";

public Plugin:myinfo = 
{
	name = "[L4D2] General Announcements",
	author = "Dirka_Dirka",
	description = "Multiple announcements (player connects, charger leveling, tank health, kill assists, etc).",
	version = PLUGIN_VERSION,
	url = ""
}

public OnPluginStart()
{
	// Require Left 4 Dead (2)
	decl String:game_name[64];
	GetGameFolderName(game_name, sizeof(game_name));
	if (!StrEqual(game_name, "left4dead2", false) && !StrEqual(game_name, "left4dead", false))
		SetFailState("[Announce] Plugin supports Left 4 Dead (2) only.");
	if (StrEqual(game_name, "left4dead2", false))
	{
		g_bL4D2Version = true;
		ZOMBIECLASS_TANK = 8;
	} else {
		ZOMBIECLASS_TANK = 5;
	}
	
	// Create plugin version info
	CreateConVar("l4d_announce_ver", PLUGIN_VERSION, "Version of the General Announce plugin.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	SetConVarString(FindConVar("l4d_announce_ver"), PLUGIN_VERSION);
	
	// Create plugin cvars
	g_hEnabled = CreateConVar("l4d_announce_enable", "1", "Enable this plugin, which announces Charger Leveling and Killer Tank HP.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hPreCache = CreateConVar("l4d_precache_models", "1", "Toggle precaching of models", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hTankHP = CreateConVar("l4d_announce_TankHP", "1", "Toggle announcements of Tank HP at end of round.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hLevel = CreateConVar("l4d_announce_Level", "1", "Toggle announcements of Chargers getting Leveled.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hAssists = CreateConVar("l4d_announce_Assists", "1", "Toggle announcements of kill Assists.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hReportTank = CreateConVar("l4d_announce_tank_only", "0", "If enabled, this will only report Tank kills.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hReportAttacks = CreateConVar("l4d_announce_attacks_only", "0", "Enabling this will show attacks without any assists.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hPlayerInfo = CreateConVar("l4d_announce_playerinfo", "1", "Toggle announcements of players connecting and changing teams.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hFFAnnounce = CreateConVar("l4d_announce_ff", "1", "Toggle announcements of friendly fire.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hWitchAnnounce = CreateConVar("l4d_announce_witch", "1", "Toggle announcements of witch spawning and cr0wning.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hStartSound = CreateConVar("l4d_announce_startsound", "1", "Toggle sound and message playing when a round starts.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hFFAnnounceType = CreateConVar("l4d_announce_fftype", "1", "Where to display the friendly fire announcements (1:In chat; 2: In a hint box; 3: In center text)", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 1.0, true, 3.0);
	g_hStartMessage = CreateConVar("l4d_announce_startmessage", "The {green}Round has Started{default}!!", "Round start message to display (empty to disable). Can use color codes as per colors.inc", FCVAR_NOTIFY|FCVAR_PLUGIN);
	g_hStartMessageType = CreateConVar("l4d_announce_startmessagetype", "1", "Where to display the round start message (1:In chat; 2: In a hint box; 3: In center text)", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 1.0, true, 3.0);
	g_hStartMessageSound = CreateConVar("l4d_announce_startsoundfile", ".\\ambient\\random_amb_sfx\\foghorn_close.wav", "Round start sound file to play (empty to disable)", FCVAR_NOTIFY|FCVAR_PLUGIN);
	
	AutoExecConfig(true, "l4d_announce");
//	new Handle:g_hConfig = LoadGameConfigFile("l4d2_announce");
//	if (g_hConfig == INVALID_HANDLE)
//	{
//		SetFailState("[Announce] Could not load l4d2_announce gamedata.");
//	}
	
	g_hCvar_DirectorReady = FindConVar("director_ready_duration");
	g_hCvar_WitchHealth = FindConVar("z_witch_health");
	g_hCvar_WitchSpeed = FindConVar("z_witch_speed");
	
	// Hook convar changes & read values from them
	HookConVarChange(g_hEnabled, ConVarChanged_Enable);
	g_bEnabled = GetConVarBool(g_hEnabled);
	HookConVarChange(g_hPreCache, ConVarChanged_PreCache);
	g_bPreCache = GetConVarBool(g_hPreCache);
	HookConVarChange(g_hTankHP, ConVarChanged_TankHP);
	g_bTankHP = GetConVarBool(g_hTankHP);
	HookConVarChange(g_hLevel, ConVarChanged_Level);
	g_bLevel = GetConVarBool(g_hLevel);
	HookConVarChange(g_hAssists, ConVarChanged_Assists);
	g_bAssists = GetConVarBool(g_hAssists);
	HookConVarChange(g_hReportTank, ConVarChanged_ReportTank);
	g_bReportTank = GetConVarBool(g_hReportTank);
	HookConVarChange(g_hReportAttacks, ConVarChanged_ReportAttacks);
	g_bReportAttacks = GetConVarBool(g_hReportAttacks);
	HookConVarChange(g_hPlayerInfo, ConVarChanged_PlayerInfo);
	g_bPlayerInfo = GetConVarBool(g_hPlayerInfo);
	HookConVarChange(g_hFFAnnounce, ConVarChanged_FFAnnounce);
	g_bFFAnnounce = GetConVarBool(g_hFFAnnounce);
	HookConVarChange(g_hWitchAnnounce, ConVarChanged_WitchAnnounce);
	g_bWitchAnnounce = GetConVarBool(g_hWitchAnnounce);
	HookConVarChange(g_hStartSound, ConVarChanged_StartSound);
	g_bStartSound = GetConVarBool(g_hStartSound);
	
	HookConVarChange(g_hCvar_WitchHealth, ConVarChanged_WitchHealth);
	HookConVarChange(g_hCvar_WitchSpeed, ConVarChanged_WitchSpeed);
	
	_Announce_ModuleEnabled();
}

public OnMapStart()
{
	if (!g_bEnabled) return;
	if (!g_bPreCache || !g_bStartSound || !g_bWitchAnnounce) return;
	
	DebugPrintToAll("OnMapStart begining..");
	DebugPrintToAll("Running L4D2? %b", g_bL4D2Version);
	
	if (g_bWitchAnnounce)
	{
		WitchesKilled = 0;
		for (new i=0; i<=MaxClients; i++)
		{
			for (new j=0; j<=MAX_WITCHES; j++)
				WitchDamage[i][j] = 0;
		}
	}
	
	if (g_bPreCache)
	{
		DebugPrintToAll("Begin PreCaching..");
		//Precache models here so that the server doesn't crash
		if (g_bL4D2Version)
		{
			SetConVarInt(FindConVar("precache_l4d1_survivors"), 1, true, true);
			if (!IsModelPrecached("models/infected/common_male_ceda.mdl")) PrecacheModel("models/infected/common_male_ceda.mdl", true);
			if (!IsModelPrecached("models/infected/common_male_clown.mdl")) PrecacheModel("models/infected/common_male_clown.mdl", true);
			if (!IsModelPrecached("models/infected/common_male_mud.mdl")) PrecacheModel("models/infected/common_male_mud.mdl", true);
			if (!IsModelPrecached("models/infected/common_male_roadcrew.mdl")) PrecacheModel("models/infected/common_male_roadcrew.mdl", true);
			if (!IsModelPrecached("models/infected/common_male_riot.mdl")) PrecacheModel("models/infected/common_male_riot.mdl", true);
			if (!IsModelPrecached("models/infected/common_male_fallen_survivor.mdl")) PrecacheModel("models/infected/common_male_fallen_survivor.mdl", true);
			if (!IsModelPrecached("models/infected/common_male_jimmy.mdl.mdl")) PrecacheModel("models/infected/common_male_jimmy.mdl.mdl", true);
			if (!IsModelPrecached("models/infected/boomette.mdl")) PrecacheModel("models/infected/boomette.mdl", true);
			if (!IsModelPrecached("models/infected/witch.mdl")) PrecacheModel("models/infected/witch.mdl", true);
			if (!IsModelPrecached("models/infected/witch_bride.mdl")) PrecacheModel("models/infected/witch_bride.mdl");
			if (!IsModelPrecached("models/survivors/survivor_teenangst.mdl")) PrecacheModel("models/survivors/survivor_teenangst.mdl", true);
			if (!IsModelPrecached("models/survivors/survivor_biker.mdl")) PrecacheModel("models/survivors/survivor_biker.mdl", true);
			if (!IsModelPrecached("models/survivors/survivor_manager.mdl")) PrecacheModel("models/survivors/survivor_manager.mdl", true);
			if (!IsModelPrecached("models/v_models/v_bile_flask.mdl")) PrecacheModel("models/v_models/v_bile_flask.mdl", true);
		
			DebugPrintToAll("L4D2 check PASSED, precaching completed.");
		}
		else DebugPrintToAll("L4D2 check FAILED, no precaching done..");
	}
	
	if (g_bStartSound)
	{
		DebugPrintToAll("Begin StartSound..");
		
		GetConVarString(g_hStartMessageSound, soundFilePath, sizeof(soundFilePath));
		TrimString(soundFilePath);
	
		if (strlen(soundFilePath) == 0)
		{
			soundFilePath = "";
			DebugPrintToAll("StartSound: no file found..");
		}
		else
		{
			DebugPrintToAll("StartSound: file found: %s, precaching..", soundFilePath);
			
			PrefetchSound(soundFilePath);
			PrecacheSound(soundFilePath);
		}
		
		DebugPrintToAll("StartSound completed.");
	}
	
	DebugPrintToAll("OnMapStart completed.");
}

public ConVarChanged_Enable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bEnabled = GetConVarBool(g_hEnabled);
	
	if (g_bEnabled)
		_Announce_ModuleEnabled();
	else
		_Announce_ModuleDisabled();
	
	DebugPrintToAll("ConVarChange Detected: g_bEnabled = %b", g_bEnabled);
}

_Announce_ModuleEnabled()
{
	HookEvent("round_start", Round_Start_Event);
	HookEvent("round_end", Round_End_Event);
	HookEvent("player_left_start_area", Player_Left_Start);
	if (g_bL4D2Version)
	{
		HookEvent("charger_killed", ChargerKilled_Event);
	}
	HookEvent("player_hurt", Event_Player_Hurt);
	HookEvent("player_death", Event_Player_Death);
	HookEvent("player_team", Event_JoinTeam);
	HookEvent("player_hurt_concise", Event_HurtConcise, EventHookMode_Post);
	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("witch_killed", Event_WitchKilled);
	HookEvent("witch_harasser_set", Event_WitchPissed);
	
	DebugPrintToAll("Events Hooked");
}

_Announce_ModuleDisabled()
{
	UnhookEvent("round_start", Round_Start_Event);
	UnhookEvent("round_end", Round_End_Event);
	UnhookEvent("player_left_start_area", Player_Left_Start);
	if (g_bL4D2Version)
	{
		UnhookEvent("charger_killed", ChargerKilled_Event);
	}
	UnhookEvent("player_hurt", Event_Player_Hurt);
	UnhookEvent("player_death", Event_Player_Death);
	UnhookEvent("player_team", Event_JoinTeam);
	UnhookEvent("player_hurt_concise", Event_HurtConcise, EventHookMode_Post);
	UnhookEvent("witch_spawn", Event_WitchSpawn);
	UnhookEvent("witch_killed", Event_WitchKilled);
	UnhookEvent("witch_harasser_set", Event_WitchPissed);
	
	DebugPrintToAll("Events Unhooked");
}

public ConVarChanged_PreCache(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bPreCache = GetConVarBool(g_hPreCache);
	
	DebugPrintToAll("ConVarChange Detected: g_bPreCache = %b", g_bPreCache);
}

public ConVarChanged_TankHP(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bTankHP = GetConVarBool(g_hTankHP);
	
	DebugPrintToAll("ConVarChange Detected: g_bTankHP = %b", g_bTankHP);
}

public ConVarChanged_Level(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bLevel = GetConVarBool(g_hLevel);
	
	DebugPrintToAll("ConVarChange Detected: g_bLevel = %b", g_bLevel);
}

public ConVarChanged_Assists(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bAssists = GetConVarBool(g_hAssists);
	
	DebugPrintToAll("ConVarChange Detected: g_bAssists = %b", g_bAssists);
}

public ConVarChanged_ReportTank(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bReportTank = GetConVarBool(g_hReportTank);
	
	DebugPrintToAll("ConVarChange Detected: g_bReportTank = %b", g_bReportTank);
}

public ConVarChanged_ReportAttacks(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bReportAttacks = GetConVarBool(g_hReportAttacks);
	
	DebugPrintToAll("ConVarChange Detected: g_bReportAttacks = %b", g_bReportAttacks);
}

public ConVarChanged_PlayerInfo(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bPlayerInfo = GetConVarBool(g_hPlayerInfo);
	
	DebugPrintToAll("ConVarChange Detected: g_bPlayerInfo = %b", g_bPlayerInfo);
}

public ConVarChanged_FFAnnounce(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bFFAnnounce = GetConVarBool(g_hFFAnnounce);
	
	DebugPrintToAll("ConVarChange Detected: g_bFFAnnounce = %b", g_bFFAnnounce);
}

public ConVarChanged_WitchAnnounce(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bWitchAnnounce = GetConVarBool(g_hWitchAnnounce);
	
	DebugPrintToAll("ConVarChange Detected: g_bWitchAnnounce = %b", g_bWitchAnnounce);
}

public ConVarChanged_WitchHealth(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_hCvar_WitchHealth = FindConVar("z_witch_health");
	
	new witchhealth = GetConVarInt(FindConVar("z_witch_health"));
	
	DebugPrintToAll("ConVarChange Detected: z_witch_health = %i", witchhealth);
}

public ConVarChanged_WitchSpeed(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_hCvar_WitchSpeed = FindConVar("z_witch_speed");
	
	new witchspeed = GetConVarInt(FindConVar("z_witch_speed"));
	
	DebugPrintToAll("ConVarChange Detected: z_witch_speed = %i", witchspeed);
}

public ConVarChanged_StartSound(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bStartSound = GetConVarBool(g_hStartSound);
	
	DebugPrintToAll("ConVarChange Detected: g_bStartSound = %b", g_bStartSound);
}

public Action:Round_Start_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Continue;
	
	DebugPrintToAll("Round Start Event begining..");
	DebugPrintToAll("Running L4D2? %b", g_bL4D2Version);
	isStarting = true;
	
	if (g_bTankHP)
	{
		DisplayedOnce = false;
		DebugPrintToAll("Killer Tank display reset.");
	}
	
	if (g_bPlayerInfo || g_bAssists)
	{
		for (new a=1; a <= MaxClients; a++)
		{
			if (g_bPlayerInfo)
			{
				Joining[a] = false;
			}
			if (g_bAssists)
			{
				for (new v=1; v <= MaxClients; v++)
				{
					Damage[a][v] = 0;
				}
			}
		}
		if (g_bPlayerInfo) DebugPrintToAll("Player team joining info cleared.");
		if (g_bAssists) DebugPrintToAll("Assist Damage array cleared.");
	}
	
	DebugPrintToAll("Round Start Event completed.");
	return Plugin_Continue;
}

public Action:Player_Left_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Handled;
	if (!g_bStartSound) return Plugin_Handled;
	
	DebugPrintToAll("StartSound: Begining playback..");
	
	if (isStarting && strlen(soundFilePath) > 0)
	{
		EmitSoundToAll(soundFilePath, GetClientOfUserId(GetEventInt(event, "userid"))); 
		
		decl String:str[MAX_CHAT_LENGTH];
		GetConVarString(g_hStartMessage, str, sizeof(str));
		
		if (GetConVarInt(g_hStartMessageType) == 1) CPrintToChatAll("%s", str);
		//else if (GetConVarInt(g_hStartMessageType) == 2) PrintHintTextToAll(str);
		//else if (GetConVarInt(g_hStartMessageType) == 3) PrintCenterTextToAll(str);
		else
		{
			DebugPrintToAll("StartSound: Invalid message type: %i, expecting 0,1,2.. aborting..", GetConVarInt(g_hStartMessageType));
			isStarting = false;
			return Plugin_Handled;
		}
	}
	else DebugPrintToAll("StartSound: Either no sound to playback or it already played (%b)..", isStarting);
	
	isStarting = false;
	DebugPrintToAll("StartSound: Playback completed.");
	
	return Plugin_Continue;
}

public Action:Round_End_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Continue;
	
	DebugPrintToAll("Round End Event begining..");
	if (g_bTankHP)
	{
		if (DisplayedOnce)
		{
			DebugPrintToAll("Killer Tank displayed already, aborting..");
			return Plugin_Continue;
		}
		
		for (new i=1; i <= MaxClients; i++)
		{
			//ingame?
			if (!IsClientInGame(i)) continue;
			//infected?
			if (GetClientTeam(i) != TEAM_INFECTED) continue;
			//alive?
			if (!IsPlayerAlive(i)) continue;
			// TANK?!?
			if (GetEntProp(i, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK) continue;

			new health = GetEntProp(i, Prop_Send, "m_iHealth");
			CPrintToChatAll("%sTank: {green}%N{default}, has {olive}%i{default} Health remaining!", TAG_TANK, i, health);
			DebugPrintToAll("Killer Tank displaying.. Tank: %N, Health remaining: %i", i, health);
		}
		
		DebugPrintToAll("Killer Tank display completed");
		DisplayedOnce = true;
	}
	
	// 3 if statements to save 1 for loop..
	if (g_bPlayerInfo || g_bAssists)
	{
		for (new a=1; a <= MaxClients; a++)
		{
			if (g_bPlayerInfo)
			{
				Joining[a] = false;
			}
			if (g_bAssists)
			{
				for (new v=1; v <= MaxClients; v++)
				{
					Damage[a][v] = 0;
				}
			}
		}
		if (g_bPlayerInfo) DebugPrintToAll("Player team joining info cleared.");
		if (g_bAssists) DebugPrintToAll("Assist Damage array cleared.");
	}
	
	DebugPrintToAll("Round End Event completed.");
	return Plugin_Continue;
}

public OnClientPutInServer(client)
{
	if (!g_bEnabled) return;
	if (!g_bPlayerInfo) return;
	
	if (IsFakeClient(client)) return;
	
	Connecting[client] = true;
	DebugPrintToAll("Client PutInServer.. %N", client);
}

public OnClientConnected(client)
{
	if (!g_bEnabled) return;
	if (!g_bPlayerInfo) return;
	
	if (IsFakeClient(client)) return;
	
	Joining[client] = false;
	
	CSkipNextClient(client);
	CPrintToChatAll("%sPlayer: {green}%N{default} has connected to the server.", TAG_INFO, client);
	DebugPrintToAll("Client Connected.. %N", client);
}

public OnClientDisconnect(client)
{
	if (!g_bEnabled) return;
	if (!g_bPlayerInfo) return;
	
	if (IsFakeClient(client)) return;
	
	Joining[client] = false;
	Connecting[client] = false;
	
/*	 Don't need the disconnect - L4D2 already reports that.. Leaving this here for when Valve breaks yet another function.
	CSkipNextClient(client);
	CPrintToChatAll("%sPlayer: {green}%N{default} has disconnected from the server.", TAG_INFO, client);
*/
	DebugPrintToAll("Client Disconnected.. %N", client);
}

public Event_JoinTeam(Handle:event, String:event_name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return;
	if (!g_bPlayerInfo) return;
	
	DebugPrintToAll("Player joining a team..");
	
	new playerClient = GetClientOfUserId(GetEventInt(event, "userid"));
	new clientTeam = GetEventInt(event, "team");
	
	if (!playerClient) return;
	if (IsFakeClient(playerClient)) return;
	
	new Handle:pack;
	
	if (Joining[playerClient])		// If the player has just changed teams recently..
	{
		KillTimer(JoiningTimer[playerClient]);
		JoiningTimer[playerClient] = CreateDataTimer(1.0, AnnounceJoining, pack);
		WritePackCell(pack, playerClient);
		WritePackCell(pack, clientTeam);
		DebugPrintToAll("Team: Player: %N has changed teams again. Restarting announcement timer..", playerClient);
	}
	else 							// This is the first team join the player has done..
	{
		Joining[playerClient] = true;
		JoiningTimer[playerClient] = CreateDataTimer(1.0, AnnounceJoining, pack);
		WritePackCell(pack, playerClient);
		WritePackCell(pack, clientTeam);
		DebugPrintToAll("Team: Player: %N has just changed teams for the first time, starting announcement timer..", playerClient);
	}
	
	switch(GetClientTeam(playerClient))
	{
		case TEAM_SPECTATORS:
		{
			// Do nothing
		}
		case TEAM_SURVIVORS, TEAM_INFECTED:
		{
			if (Connecting[playerClient])
			{
				if(GetConVarInt(FindConVar("l4d_mapvote_announce_mode")) != 0)
				{
					//CreateTimer(TIMER_WELCOME, Timer_WelcomeMessage, client);
				}
			} else
				Connecting[playerClient] = false;
		}
	}
	
	DebugPrintToAll("Player joining a team complete.");
}

public Action:AnnounceJoining(Handle:timer, Handle:pack)
{
	if (!g_bEnabled) return;
	if (!g_bPlayerInfo) return;
	
	DebugPrintToAll("Player joining a team announcement beginin..");
	
	ResetPack(pack);
	new playerClient = ReadPackCell(pack);
	new clientTeam = ReadPackCell(pack);
	
	if (!Joining[playerClient])
	{
		DebugPrintToAll("Team: Player join error, perhaps %N disconnected?", playerClient);
		return;
	}
	Joining[playerClient] = false;
	
	switch (clientTeam)
	{
		case TEAM_SPECTATORS:
		{
			CSkipNextClient(playerClient);
			CPrintToChatAll("%sPlayer: {green}%N{default} has joined the Spectators.", TAG_INFO, playerClient);
			DebugPrintToAll("Player: %N joined team %i", playerClient, TEAM_SPECTATORS);
		}
		case TEAM_SURVIVORS:
		{
			CSkipNextClient(playerClient);
			CPrintToChatAll("%sPlayer: {green}%N{default} has joined the Survivors.", TAG_INFO, playerClient);
			DebugPrintToAll("Player: %N joined team %i", playerClient, TEAM_SURVIVORS);
		}
		case TEAM_INFECTED:
		{
			CSkipNextClient(playerClient);
			CPrintToChatAll("%sPlayer: {green}%N{default} has joined the Infected.", TAG_INFO, playerClient);
			DebugPrintToAll("Player: %N joined team %i", playerClient, TEAM_INFECTED);
		}
		default:
		{
			DebugPrintToAll("Player: %N failed to join a team: %i", playerClient, clientTeam);
		}
	}
	
	DebugPrintToAll("Player joining a team announcement complete.");
}

public Action:Event_Player_Hurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Continue;
	if (!g_bAssists && !g_bWitchAnnounce) return Plugin_Continue;
	
	DebugPrintToAll("Assist: Player Hurt begining..");
	
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	DebugPrintToAll("Assist: Attacker: %i, Victim: %i", attacker, victim);
	
	if (!victim || !attacker)
	{
		DebugPrintToAll("Assist: No valid victim(%i) or attacker(%i), aborting..", victim, attacker);
		return Plugin_Handled;
	}
	
	if (!(GetClientTeam(attacker) == TEAM_SURVIVORS) || !(GetClientTeam(victim) == TEAM_INFECTED))
	{
		DebugPrintToAll("Assist: Either attacker team(%i) or victim team(%i) is incorrect (should be different), aborting..", GetClientTeam(attacker), GetClientTeam(victim));
		return Plugin_Handled;
	}
	
	new zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
	DebugPrintToAll("Assist: victim: %N's zombieclass: %i..", victim, zombieclass);
	
	if (g_bReportTank)
	{
		DebugPrintToAll("Assist: Report Tank only check begining..");
		
		if (zombieclass != ZOMBIECLASS_TANK)
		{
			DebugPrintToAll("Assist: Victim is NOT a tank, aborting..");
			return Plugin_Handled;
		}
		DebugPrintToAll("Assist: Report Tank only check completed.");
	}
	
	if ((zombieclass == ZOMBIECLASS_TANK) && GetEntProp(victim, Prop_Send, "m_isIncapacitated"))
	{
		DebugPrintToAll("Assist: Tank is dead. aborting damage calculations..");
		return Plugin_Handled;
	}
	
	new DamageHealth = GetEventInt(event, "dmg_health");
	
	Damage[attacker][victim] += DamageHealth;
	DebugPrintToAll("Assist: Damage added to victim: %i.", DamageHealth);
	
	DebugPrintToAll("Assist Event: Player Hurt completed.");
	return Plugin_Continue;
}

public Action:Event_Player_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Continue;
	if (!g_bAssists) return Plugin_Continue;
	
	DebugPrintToAll("Assist: Player Death begining..");
	
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	DebugPrintToAll("Assist: Attacker: %i, Victim: %i, begin validity check..", attacker, victim);
	
	if (!victim || !attacker)
	{
		DebugPrintToAll("Assist: No valid victim(%i) or attacker(%i), aborting..", victim, attacker);
		return Plugin_Handled;
	} else {
		DebugPrintToAll("Assist: Attacker: %N, Victim: %N, checking teams..", attacker, victim);
	}
	
	if (!(GetClientTeam(attacker) == TEAM_SURVIVORS) || !(GetClientTeam(victim) == TEAM_INFECTED))
	{
		DebugPrintToAll("Assist: Either attacker team(%i) or victim team(%i) is incorrect (should be different), aborting..", GetClientTeam(attacker), GetClientTeam(victim));
		return Plugin_Handled;
	}
	
	if (g_bReportTank)
	{
		DebugPrintToAll("Assist: Report Tank only check begining..");
		
		new zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if (!g_bL4D2Version) return Plugin_Handled;
		if (zombieclass != ZOMBIECLASS_TANK)
		{
			DebugPrintToAll("Assist: L4D Victim is NOT a tank, aborting..");
			return Plugin_Handled;
		}
		DebugPrintToAll("Assist: Report Tank only check completed.");
	}
	
	decl String:sMessage[MAX_CHAT_LENGTH];
	decl String:buffer[MAX_CHAT_LENGTH + MAX_CHAT_LENGTH];
	decl String:sName[MAX_NAME_LENGTH];
	GetClientName(attacker, sName, sizeof(sName));
	decl String:sDamage[10];
	
	new numberofattackers = 0;
	
	for (new i=0; i <= MaxClients; i++)
	{
		if (Damage[i][victim] > 0) numberofattackers++;
	}
	
	new numberofassists = numberofattackers - 1;
	
	DebugPrintToAll("Assist: Number of attackers: %i, number who assisted: %i (should be 1 less).", numberofattackers, numberofassists);
	
	if (!g_bReportAttacks)
	{
		if (!numberofassists)
		{
			Damage[attacker][victim] = 0;
			DebugPrintToAll("Assist: Nothing to report - Only an attacker (with no assists) and g_bReportAttacks = false, aborting after resetting damage..");
			return Plugin_Continue;
		}
	}
	new msglength = strlen(TAG_ASSIST) + strlen(Temp9) + strlen(sName) + strlen(Temp6) + strlen(Temp3) + strlen(Temp8) + strlen(sDamage) + strlen(Temp6) + strlen(Temp4);
	
	IntToString(Damage[attacker][victim], String:sDamage, sizeof(sDamage));
	StrCat(String:buffer, sizeof(buffer), TAG_ASSIST);
	StrCat(String:buffer, sizeof(buffer), String:Temp9);
	StrCat(String:buffer, sizeof(buffer), String:sName);
	StrCat(String:buffer, sizeof(buffer), String:Temp6);
	StrCat(String:buffer, sizeof(buffer), String:Temp3);
	StrCat(String:buffer, sizeof(buffer), String:Temp8);
	StrCat(String:buffer, sizeof(buffer), String:sDamage);
	StrCat(String:buffer, sizeof(buffer), String:Temp6);
	StrCat(String:buffer, sizeof(buffer), String:Temp4);
	
	if (!numberofassists)
	{
		StrCat(String:buffer, sizeof(buffer), String:Temp7); // .
		TrimString(buffer);
		
		Damage[attacker][victim] = 0;
		DebugPrintToAll("Assist: Only an attacker (no assists), reporting single event and resetting damage..");
	}
	else
	{
		msglength += strlen(Temp1);
		StrCat(String:buffer, sizeof(buffer), String:Temp1);  // | Assists:
		
		DebugPrintToAll("Assist: Attacker + assists. begin reporting each assister..");
		
		new assisters = 0;
		
		for (new i=1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsClientConnected(i))
				continue;
			if (GetClientTeam(i) != TEAM_SURVIVORS)
				continue;
			if (!(Damage[i][victim] > 0))
				continue;
			if (i == attacker)
				continue;
			
			assisters++;
			DebugPrintToAll("Assist: Assister %N (%1 of %i) found..", i, i, assisters);

			decl String:tName[MAX_NAME_LENGTH];
			decl String:tDamage[10];
			GetClientName(i, tName, sizeof(tName));
			TrimString(tName);
			IntToString(Damage[i][victim], String:tDamage, sizeof(tDamage));
			TrimString(tDamage);
			
			DebugPrintToAll("Assist: Check line length. msglength = %i.", msglength);
			msglength += strlen(Temp5) + strlen(tName) + strlen(Temp6) + strlen(Temp3) + strlen(Temp8) + strlen(tDamage) + strlen(Temp6) + strlen(Temp4) + strlen(Temp2);
			DebugPrintToAll("Assist: Check line length after next printing. msglength = %i.", msglength);
			if (msglength > MAX_CHAT_LENGTH)
			{
				strcopy(String:sMessage, sizeof(sMessage), String:buffer);
				TrimString(sMessage);
				CPrintToChatAll(sMessage);
				buffer = "\0";
				msglength = strlen(buffer);
				DebugPrintToAll("Assist: Line too long. Adding a line and resetting buffer..");
			} else {
				DebugPrintToAll("Assist: Line length ok, continuing..");
			}
			
			StrCat(String:buffer, sizeof(buffer), String:Temp5);
			StrCat(String:buffer, sizeof(buffer), String:tName);
			StrCat(String:buffer, sizeof(buffer), String:Temp6);
			StrCat(String:buffer, sizeof(buffer), String:Temp3);
			StrCat(String:buffer, sizeof(buffer), String:Temp8);
			StrCat(String:buffer, sizeof(buffer), String:tDamage);
			StrCat(String:buffer, sizeof(buffer), String:Temp6);
			StrCat(String:buffer, sizeof(buffer), String:Temp4);
			if ((i < MaxClients) && (assisters < numberofassists))
			{
				StrCat(String:buffer, sizeof(buffer), String:Temp2);  // ,
				DebugPrintToAll("Assist: Assister (%N) is not the last one #%i, continue reporting..", assisters, numberofassists);
			} else {
				StrCat(String:buffer, sizeof(buffer), String:Temp7);  // .
				TrimString(buffer);
				DebugPrintToAll("Assist: Assister (%N) is the last one #%i, finish line.", assisters, numberofassists);
			}
			
			Damage[i][victim] = 0;
			DebugPrintToAll("Assist: Reseting damage for victim(%N) from attacker(%N)..", victim, i);
		}
		DebugPrintToAll("Assist: Move buffer to message pre- buffer size: %i, Message size: %i..", msglength, strlen(sMessage));
		strcopy(String:sMessage, sizeof(sMessage), String:buffer);
		buffer = "\0";
		msglength = strlen(buffer);
		DebugPrintToAll("Assist: buffer size: %i, Message size: %i..", msglength, strlen(sMessage)); 
	}
	DebugPrintToAll("Assist: Printing Message (last) line..");
	CPrintToChatAll(sMessage);
	
	DebugPrintToAll("Assist: Player Death completed.");
	return Plugin_Continue;
}

public Action:Event_HurtConcise(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Continue;
	if (!g_bFFAnnounce) return Plugin_Continue;
	
	DebugPrintToAll("FF Event: Hurt Concise begining..");
	
	new attacker = GetEventInt(event, "attackerentid");
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!victim || !attacker)
	{
		DebugPrintToAll("FF: No valid victim(%i) or attacker(%i), aborting..", victim, attacker);
		return Plugin_Handled;
	}
	
	DebugPrintToAll("FF: Attacker: %i, Victim: %i, begin validity check..", attacker, victim);
	
	// Are the attacker and victim valid?
	if (!victim && !attacker) return Plugin_Handled;
	if (attacker > MaxClients) return Plugin_Handled;
	if (!IsClientConnected(attacker) || !IsClientInGame(attacker) || IsFakeClient(attacker)) return Plugin_Handled;
	if (!IsClientConnected(victim) || !IsClientInGame(victim)) return Plugin_Handled;
	DebugPrintToAll("FF: Valid attacker and victim clients. Checking teams..");
	
	// This is the friendly fire check
	if (GetClientTeam(attacker) != TEAM_SURVIVORS || GetClientTeam(victim) != TEAM_SURVIVORS)
	{
	//	if (GetClientTeam(attacker) != TEAM_INFECTED || GetClientTeam(victim) != TEAM_INFECTED))
	//		return Plugin_Handled;
		return Plugin_Handled;
	}
	DebugPrintToAll("FF: Both attacker and victim are on the same team. Checking director_ready_duration..");
	
	// If director_ready_duration is 0, it usually means that the game is in a ready up state (like downtown1's ready up mod).
	// This allows me to disable the FF messages in ready up.
	if (!GetConVarInt(g_hCvar_DirectorReady)) return Plugin_Handled;
	
	DebugPrintToAll("FF: Passed attacker and victim checks, and director_ready_duration..");
	
	new damage = GetEventInt(event, "dmg_health");
	new Handle:pack;
	
	if (FFActive[attacker])		// If the player is already friendly firing teammates, resets the announce timer and adds to the damage
	{
		DamageCache[attacker][victim] += damage;
		KillTimer(FFTimer[attacker]);
		FFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
		DebugPrintToAll("FF: Friendly fire in progress, resetting timer. DamageCache: %i, Damage: %i", DamageCache[attacker][victim], damage);
	}
	else 						// If it's the first friendly fire by that player, it will start the announce timer and store the damage done.
	{
		DamageCache[attacker][victim] = damage;
		FFActive[attacker] = true;
		FFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
		DebugPrintToAll("FF: New friendly fire starting. DamageCache: %i, Damage: %i", DamageCache[attacker][victim], damage);
		for (new i=1; i <= MaxClients; i++)
		{
			if (i != attacker && i != victim)
			{
				DamageCache[attacker][i] = 0;
			}
		}
		DebugPrintToAll("FF: DamageCache reset for everyone who isnt the attacker or victim..");
	}
	
	DebugPrintToAll("FF Event: Hurt Concise completed.");
	return Plugin_Continue;
}

public Action:AnnounceFF(Handle:timer, Handle:pack)
{
	decl String:victim[MAX_NAME_LENGTH];
	decl String:attacker[MAX_NAME_LENGTH];
	
	DebugPrintToAll("FF: Announcement begining..");
	
	ResetPack(pack);
	new attackerc = ReadPackCell(pack);
	FFActive[attackerc] = false;
	
	if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
		GetClientName(attackerc, attacker, sizeof(attacker));
	else
		attacker = "Disconnected Player";
	
	DebugPrintToAll("FF: Determined who the attacker is: %s", attacker);
	
	for (new i=1; i < MaxClients; i++)
	{
		if (DamageCache[attackerc][i] != 0 && attackerc != i)
		{
			DebugPrintToAll("FF: There was an attack, reporting damage (%i)..", DamageCache[attackerc][i]);
			
			if (IsClientInGame(i) && IsClientConnected(i))
			{
				GetClientName(i, victim, sizeof(victim));
				switch(GetConVarInt(g_hFFAnnounceType))
				{
					case 1:		// Chat message
					{
						if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
						{
							CPrintToChat(attackerc, "%sYou did {olive}%d{default} friendly fire damage to {green}%s{default}.", TAG_FF, DamageCache[attackerc][i], victim);
						//	CSkipNextClient(attackerc);
							DebugPrintToAll("FF: Chat message sent to attacker: %s", attacker);
						}
						if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
						{
							CPrintToChat(i, "%s{green}%s{default} did {olive}%d{default} friendly fire damage to you.", TAG_FF, attacker, DamageCache[attackerc][i]);
						//	CSkipNextClient(i);
							DebugPrintToAll("FF: Chat message sent to victim: %s", victim);
						}
					}
					case 2:		// Hint box message
					{
						if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
						{
							PrintHintText(attackerc, "You did %d friendly fire damage to %s",DamageCache[attackerc][i],victim);
							DebugPrintToAll("FF: Hint message sent to attacker: %s", attacker);
						}
						if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
						{
							PrintHintText(i, "%s did %d friendly fire damage to you",attacker,DamageCache[attackerc][i]);
							DebugPrintToAll("FF: Hint message sent to victim: %s", victim);
						}
					}
					case 3:		// Center text message
					{
						if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
						{
							PrintCenterText(attackerc, "You did %d friendly fire damage to %s",DamageCache[attackerc][i],victim);
							DebugPrintToAll("FF: Center text message sent to attacker: %s", attacker);
						}
						if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
						{
							PrintCenterText(i, "%s did %d friendly fire damage to you",attacker,DamageCache[attackerc][i]);
							DebugPrintToAll("FF: Center text message sent to victim: %s", victim);
						}
					}
				}
			}
			DamageCache[attackerc][i] = 0;
			
			DebugPrintToAll("FF: Reports complete, resetting damage (%i) from attacker (%s) to victim (%s)..", DamageCache[attackerc][i], attacker, victim);
		}
	}
	// this wont work here - damage is 0.
//	if ((GetConVarInt(g_hFFAnnounceType)) == 1) CPrintToChatAll("%s{green}%s{default} did {olive}%d{default} friendly fire damage to {green}%s{default}.", TAG_FF, attackerc, DamageCache[attackerc][i], victim);
	
	DebugPrintToAll("FF: Announcement completed.");
}

public ChargerKilled_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return;
	if (!g_bLevel) return;
	
	DebugPrintToAll("Level: Charger leveled detection begining..");
	
	new bool:IsCharging = GetEventBool(event, "charging");
	new bool:IsMelee = GetEventBool(event, "melee");
	if (!IsMelee || !IsCharging) 
	{
		DebugPrintToAll("Level: Not a leveled charger.. IsCharging (%b), IsMelee (%b)", IsCharging, IsMelee);
		return;
	}
	
	DebugPrintToAll("Level: Determining attacker, charger and weapon..");
	
	new survivor = GetClientOfUserId(GetEventInt(event, "attacker"));
	new charger = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!survivor || !charger)
	{
		DebugPrintToAll("Level: Not a valid attacker (%i) or charger (%i), aborting..", survivor, charger);
		return;
	}
	
	decl String:weaponname[64];
	GetClientWeapon(survivor, weaponname, sizeof(weaponname));
	
	new String:weapon[64] = "";
	
	if (StrEqual(weaponname, "weapon_melee"))
	{
		GetEntPropString(GetPlayerWeaponSlot(survivor, 1), Prop_Data, "m_strMapSetScriptName", weaponname, sizeof(weaponname));
		DebugPrintToAll("Level: Melee weapon found (%s)", weaponname);
	}
	else
	{
		DebugPrintToAll("Level: Charger was not killed by a melee weapon (%s), aborting..", weaponname);
		return;
	}
	
	if (StrEqual(weaponname, "baseball_bat")) StrCat(String:weapon, sizeof(Weapon1), String:Weapon1);
	else if (StrEqual(weaponname, "cricket_bat")) StrCat(String:weapon, sizeof(Weapon2), String:Weapon2);
	else if (StrEqual(weaponname, "crowbar")) StrCat(String:weapon, sizeof(Weapon3), String:Weapon3);
	else if (StrEqual(weaponname, "electric_guitar")) StrCat(String:weapon, sizeof(Weapon4), String:Weapon4);
	else if (StrEqual(weaponname, "fireaxe")) StrCat(String:weapon, sizeof(Weapon5), String:Weapon5);
	else if (StrEqual(weaponname, "frying_pan")) StrCat(String:weapon, sizeof(Weapon6), String:Weapon6);
	else if (StrEqual(weaponname, "katana")) StrCat(String:weapon, sizeof(Weapon7), String:Weapon7);
	else if (StrEqual(weaponname, "knife")) StrCat(String:weapon, sizeof(Weapon8), String:Weapon8);
	else if (StrEqual(weaponname, "machete")) StrCat(String:weapon, sizeof(Weapon9), String:Weapon9);
	else if (StrEqual(weaponname, "tonfa")) StrCat(String:weapon, sizeof(Weapon10), String:Weapon10);
	else if (StrEqual(weaponname, "golf_club")) StrCat(String:weapon, sizeof(Weapon11), String:Weapon11);
	else StrCat(String:weapon, sizeof(Weapon0), String:Weapon0);
	
	CSkipNextClient(survivor);
	CPrintToChatAll("%s{green}%N{default} leveled {green}%N{default} with %s!!", TAG_LEVEL, survivor, charger, weapon);
	CPrintToChat(survivor, "%sYou just {olive}Leveled a Charge{default} on {green}%N{default} with %s!!", TAG_LEVEL, charger, weapon);
	
	DebugPrintToAll("Level: Charger (%N) was leveled by (%N) with %s. Completed.", charger, survivor, weapon);
}


public Event_WitchSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return;
	if (!g_bWitchAnnounce) return;
	
	DebugPrintToAll("Witch: Spawn reporting begining..");
	
	for (new i=1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsClientConnected(i))
			continue;
		
		if (GetClientTeam(i) == TEAM_INFECTED)
		{
			CPrintToChat(i, "%sA {green}Witch{default} has spawned with {olive}%i{default}HP and {olive}%i{default} speed.", TAG_WITCH, GetConVarInt(g_hCvar_WitchHealth), GetConVarInt(g_hCvar_WitchSpeed));
			DebugPrintToAll("Witch: Spawn reported to %N of team %i. Witch health (%i) and speed (%i).", i, GetClientTeam(i), GetConVarInt(g_hCvar_WitchHealth), GetConVarInt(g_hCvar_WitchSpeed));
		}
	}
	
	DebugPrintToAll("Witch: Spawn reporting completed.");
}

public Event_WitchPissed(Handle: event, const String: name[], bool: dontBroadcast)
{
	if (!g_bEnabled) return;
	if (!g_bWitchAnnounce) return;
	
	DebugPrintToAll("Witch: Annoyed reporting begining..");
	
	new pisser = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!pisser) return;
	new bool:firstPisser = GetEventBool(event, "first");
	
	for (new i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsClientConnected(i))
			continue;
		
		if (firstPisser)
		{
			if (i == TEAM_SURVIVORS)
			{
				if (i != pisser)
					CPrintToChat(i, "%%sUh Oh, {green}%N{default} just pissed off the {olive}witch{default}.. Watch Out!", TAG_WITCH, pisser);
				else
					CPrintToChat(pisser, "%sUh Oh, you just pissed off the {olive}witch{default}.. Watch Out!", TAG_WITCH);
			}
			if (i == TEAM_INFECTED)
				CPrintToChat(i, "%sALERT! ALERT! {green}%N{default} just pissed off the {olive}witch{default}!", TAG_WITCH, pisser);
			
			DebugPrintToAll("Witch: %N just pissed off the witch.", pisser);
		} else {
			if (i == TEAM_SURVIVORS)
			{
				if (i != pisser)
					CPrintToChat(i, "%sBe very quiet, {green}%N{default} is aggrivating the {olive}witch{default}!", TAG_WITCH, pisser);
				else
					CPrintToChat(pisser, "%sShhhh, you just annoyed the {olive}witch{default}!", TAG_WITCH);
			}
			if (i == TEAM_INFECTED)
				CPrintToChat(i, "%sALERT! ALERT! {green}%N{default} is aggrivating the {olive}witch{default}!", TAG_WITCH, pisser);
			
			DebugPrintToAll("Witch: %N just annoyed the witch.", pisser);
		}
	}
	
	DebugPrintToAll("Witch: Annoyed reporting completed.");
}

public Event_WitchKilled(Handle: event, const String: name[], bool: dontBroadcast)
{
	if (!g_bEnabled) return;
	if (!g_bWitchAnnounce || !g_bAssists) return;
	
	DebugPrintToAll("Witch: Killed, begin reporting..");
	
	WitchesKilled++;
	
	DebugPrintToAll("Witch: Cr0wning detection begining..");
	
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!attacker) return;
	
	new bool:crowned = GetEventBool(event, "oneshot");
	
	if (crowned)
	{
		CSkipNextClient(attacker);
		CPrintToChatAll("%sA Witch was {olive}cr0wned{default} by {green}%N{default}!!", TAG_WITCH, attacker);
		CPrintToChat(attacker, "%sYou just {olive}cr0wned{default} a Witch!!", TAG_WITCH);
		
		DebugPrintToAll("Witch: Cr0wn(%i) detected on Witch(%i) and reported to everyone", crowned, WitchesKilled);
	}
	else
	{
		DebugPrintToAll("Witch: No Cr0wning on Witch(%i), report the kill..", WitchesKilled);
		
		if (g_bAssists)
		{
			AnnounceAssists(attacker);
		}
		else
		{
			DebugPrintToAll("Witch: Assist reporting off, just alert everyone Witch(%i) died..", WitchesKilled);
			CSkipNextClient(attacker);
			CPrintToChatAll("%sA Witch was killed by {green}%N{default}!", TAG_WITCH, attacker);
			CPrintToChat(attacker, "%sYou just killed a Witch!", TAG_WITCH);
		}
		
		DebugPrintToAll("Witch: Cr0wn(%i) did not occur on Witch(%i) and reported..", crowned, WitchesKilled);
	}
	
	DebugPrintToAll("Witch: Cr0wning detection and reporting completed.");
}

stock AnnounceAssists(attacker)
{
	DebugPrintToAll("Witch-Assist: Begin report for Witch(%i) killers. Begining with %N..", WitchesKilled, attacker);
	
	decl String:sMessage[MAX_CHAT_LENGTH];
	decl String:buffer[MAX_CHAT_LENGTH + MAX_CHAT_LENGTH];
	decl String:sName[MAX_NAME_LENGTH];
	GetClientName(attacker, sName, sizeof(sName));
	decl String:sDamage[10];
	decl String:sKilled[10];
	
	new numberofattackers = 0;
	
	for (new i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsClientConnected(i))
			continue;
		if (GetClientTeam(i) != TEAM_SURVIVORS)
			continue;
		if ((WitchDamage[i][WitchesKilled] = GetEntProp(i, Prop_Send, "m_checkpointDamageToWitch")) == 0)
			continue;
		
		numberofattackers++;
		DebugPrintToAll("Witch-Assist: Attacker found (%N) of: %i.. Damage done to witch(s) by this attacker: %i", i, numberofattackers, WitchDamage[i][WitchesKilled]);
		
		if (WitchesKilled > 1)
		{
			DebugPrintToAll("Witch-Assist: Fixing damage by attacker(%i) on witch(%i)", i, WitchesKilled);
			for (new j=1; j<WitchesKilled; j++)
			{
				if (WitchDamage[i][j])
				{
					WitchDamage[i][WitchesKilled] -= WitchDamage[i][j];
					DebugPrintToAll("Witch-Assist: Removing Damage: %i.. New damage total: %i", WitchDamage[i][j], WitchDamage[i][WitchesKilled]);
				}
			}
			if (!WitchDamage[i][WitchesKilled])
			{
				numberofattackers--;
				DebugPrintToAll("Witch-Assist: Attacker: %N didn't attack this witch, adjusting numberofattackers: %i", i, numberofattackers);
			}
			
			DebugPrintToAll("Witch-Assist: Damage done to this witch: %i by attacker: %N", WitchesKilled, i);
		}
	}
	new numberofassists = numberofattackers - 1;	
	
	DebugPrintToAll("Witch-Assist: Number of attackers: %i, number who assisted: %i (should be 1 less).", numberofattackers, numberofassists);
	
	if (!g_bReportAttacks)
	{
		if (!numberofassists)
		{
			DebugPrintToAll("Witch: Not a cr0wn and g_bReportAttacks = false, but attacker(%i) killed the witch alone..", attacker);
			//
			// Need to expand this with a timer so as to prevent this from reporting a pseudo cr0wn on a moly kill.
			//
			
			if (GetEntProp(attacker, Prop_Send, "m_isIncapacitated"))
			{
				DebugPrintToAll("Witch: Not even close to a cr0wn.. attacker(%i) is down! aborting..", attacker);
				return;
			}
			
			CSkipNextClient(attacker);
			CPrintToChatAll("%s{green}%N{default} just FAILED at his {olive}cr0wn{default} attempt!! But he managed to kill her anyway.", TAG_WITCH, attacker);
			CPrintToChat(attacker, "%sYou just FAILED at {olive}cr0wning{default} a Witch!! At least she is dead.", TAG_WITCH);
			
			DebugPrintToAll("Witch: Attacker failed to cr0wn the witch, but he did kill her without issue.");
			return;
		}
	}
	
	new msglength = strlen(TAG_WITCH);
	IntToString(WitchDamage[attacker][WitchesKilled], String:sDamage, sizeof(sDamage));
	StrCat(String:buffer, sizeof(buffer), TAG_WITCH);
	if (WitchesKilled > 1)
	{
		StrCat(String:buffer, sizeof(buffer), String:Temp10);
		StrCat(String:buffer, sizeof(buffer), String:Temp3);
		IntToString(WitchesKilled, String:sKilled, sizeof(sKilled));
		StrCat(String:buffer, sizeof(buffer), String:sKilled);
		StrCat(String:buffer, sizeof(buffer), String:Temp11);
		StrCat(String:buffer, sizeof(buffer), String:Temp12);
		msglength += strlen(Temp10) + strlen(Temp3) + strlen(sKilled) + strlen(Temp11) + strlen(Temp12);
	} else {
		StrCat(String:buffer, sizeof(buffer), String:Temp10);
		StrCat(String:buffer, sizeof(buffer), String:Temp12);
		msglength += strlen(Temp10) + strlen(Temp12);
	}
	StrCat(String:buffer, sizeof(buffer), String:sName);
	StrCat(String:buffer, sizeof(buffer), String:Temp6);
	StrCat(String:buffer, sizeof(buffer), String:Temp3);
	StrCat(String:buffer, sizeof(buffer), String:Temp8);
	StrCat(String:buffer, sizeof(buffer), String:sDamage);
	StrCat(String:buffer, sizeof(buffer), String:Temp6);
	StrCat(String:buffer, sizeof(buffer), String:Temp4);
	msglength += strlen(sName) + strlen(Temp6) + strlen(Temp3) + strlen(Temp8) + strlen(sDamage) + strlen(Temp6) + strlen(Temp4);
	
	if (!numberofassists)
	{
		StrCat(String:buffer, sizeof(buffer), String:Temp7); // .
		TrimString(buffer);
		
		DebugPrintToAll("Witch-Assist: Only an attacker (no assists), reporting single event..");
	} else {
		DebugPrintToAll("Witch-Assist: Attacker + assists. begin reporting each assister..");
		StrCat(String:buffer, sizeof(buffer), String:Temp1);  // | Assists:
		msglength += strlen(Temp1);
		
		new assisters = 0;
		
		for (new i=1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsClientConnected(i))
				continue;
			if (GetClientTeam(i) != TEAM_SURVIVORS)
				continue;
			if (!(WitchDamage[i][WitchesKilled] > 0))
				continue;
			if (i == attacker)
				continue;
			
			assisters++;
			DebugPrintToAll("Witch-Assist: Assister %N (%i of %i) found..", i, i, assisters);
			
			decl String:tName[MAX_NAME_LENGTH];
			decl String:tDamage[10];
			GetClientName(i, tName, sizeof(tName));
			TrimString(tName);
			IntToString(WitchDamage[i][WitchesKilled], String:tDamage, sizeof(tDamage));
			TrimString(tDamage);
			
			DebugPrintToAll("Witch-Assist: Check line length. msglength = %i.", msglength);
			msglength = strlen(Temp5) + strlen(tName) + strlen(Temp6) + strlen(Temp3) + strlen(Temp8) + strlen(tDamage) + strlen(Temp6) + strlen(Temp4) + strlen(Temp2);
			DebugPrintToAll("Witch-Assist: Check line length after next printing. msglength = %i.", msglength);
			if (msglength > MAX_CHAT_LENGTH)
			{
				strcopy(String:sMessage, sizeof(sMessage), String:buffer);
				TrimString(sMessage);
				CPrintToChatAll("%s", sMessage);
				buffer = "\0";
				msglength = strlen(buffer);
				DebugPrintToAll("Witch-Assist: Line too long. Adding a line and resetting buffer..");
			} else {
				DebugPrintToAll("Witch-Assist: Line length ok, continuing..");
			}
			
			StrCat(String:buffer, sizeof(buffer), String:Temp5);
			StrCat(String:buffer, sizeof(buffer), String:tName);
			StrCat(String:buffer, sizeof(buffer), String:Temp6);
			StrCat(String:buffer, sizeof(buffer), String:Temp3);
			StrCat(String:buffer, sizeof(buffer), String:Temp8);
			StrCat(String:buffer, sizeof(buffer), String:tDamage);
			StrCat(String:buffer, sizeof(buffer), String:Temp6);
			StrCat(String:buffer, sizeof(buffer), String:Temp4);
			if ((i < MaxClients) && (assisters < numberofassists))
			{
				StrCat(String:buffer, sizeof(buffer), String:Temp2);  // ,
				DebugPrintToAll("Witch-Assist: Assister (%N) is not the last one(%i), continue reporting..", assisters, numberofassists);
			}
			else
			{
				StrCat(String:buffer, sizeof(buffer), String:Temp7);  // .
				TrimString(buffer);
				DebugPrintToAll("Witch-Assist: Assister (%N) is the last one(%i), finish line.", assisters, numberofassists);
			}
		}
		strcopy(String:sMessage, sizeof(sMessage), String:buffer);
	}
	
	DebugPrintToAll("Witch-Assist: Printing Message (last) line. length = %i", msglength);
	CPrintToChatAll("%s", sMessage);
	DebugPrintToAll("Witch-Assist: Witch(%i) report completed.", WitchesKilled);
}

stock DebugPrintToAll(const String:format[], any:...)
{
	#if TEST_DEBUG	|| TEST_DEBUG_LOG
	decl String:buffer[192];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	#if TEST_DEBUG
	PrintToChatAll("%s%s", TAG_DEBUG, buffer);
	PrintToConsole(0, "%s%s", TAG_DEBUG, buffer);
	#endif
	
	LogMessage("%s", buffer);
	#else
	//suppress "format" never used warning
	if(format[0])
		return;
	else
		return;
	#endif
}
