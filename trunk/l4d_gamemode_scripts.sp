#pragma semicolon 1
#include <sourcemod>

/* **	****************************************
	*
	*	Version Notes:
	*		2.0:	Changed to more generic system based upon gamemode and difficulty settings.
	*				Idea from AtomicStrykers even more basic code (basic compared to v1.6).
	*				Original plugin from Thraka (who wrote v1.6).
	*		2.0.1:	What happened to the _ ?.. fixed it.
	*		2.1:	Added game mode overrides to force lobbies into server desired modes and difficulties.
	*		2.2:	Added some map voting abilities and some support for L4D1.
	*
	*	****************************************
	*
	*	Cvars:
	*
	*	gamemode_force_modes				0/1				Turns on/off GameMode forcing.
	*		gamemode_force_coop				0/1
	*			gamemode_force_coopmode		"realism"		Mode to force 'coop' games into. "" = gamemode_force_coop 0 = don't force this type.
	*		gamemode_force_versus			0/1
	*			gamemode_force_versusmode	"mutation12"	Mode to force 'versus' games into. "" = gamemode_force_versus 0 = don't force this type.
	*		gamemode_force_scavenge			0/1
	*			gamemode_force_scavengemode	"scavenge"		Mode to force 'scavenge' games into. "" = gamemode_force_scavenge 0 = don't force this type.
	*		gamemode_force_survival			0/1
	*			gamemode_force_survivalmode	""				Mode to force 'survival' games into. "" = gamemode_force_survival 0 = don't force this type.
	*			To force a server into 'coop' types of games use:
	*				gamemode_force_modes 1, gamemode_force_versusmode "coop", gamemode_force_scavengemode "coop", gamemode_force_survivalmode "coop"
	*			To allow it to be any 'coop' style game.. gamemode_forcecoopmode ""
	*			To further force all 'coop' style games into realism.. gamemode_force_coop "realism"
	*			See below for more details on GameMode forcing.
	*
	*	gamemode_force_difficulty		0/1				Turns on/off Difficulty forcing.
	*		gamemode_force_easy			"Easy"			Difficulty to force 'Easy' games into. "" = "Easy" = don't force.
	*		gamemode_force_normal		""				Difficulty to force 'Normal' games into. "" = "Normal" = don't force.
	*		gamemode_force_hard			"Impossible"	Difficulty to force 'Hard' games into. "" = "Hard" = don't force.
	*		gamemode_force_impossible	"Impossible"	Difficulty to force 'Impossible' games into. "" = "Impossible" = don't force.
	*
	*	gamemode_mapvote_enable			0/1				Turns on/off !mapvote & !changemap & End game map voting.
	*		gamemode_endvote_enable		0/1				Turns on/off End map/game voting (to avoid going back to a lobby).
	*		gamemode_mapvote_admin		0/1				If 1, !mapvote is only for admins.
	*		gamemode_mapvote_time		5-60 secs		Time to display mapvote menu before tallying results.
	*		gamemode_mapchange_time		0.2-60 secs		Time to wait before actually changing maps. This allows for displaying the message.
	*
	*	Commands:
	*	sm_mapvote		Admin OR Any	Brings up a menu to select a desired map to change the game to. After selection is completed, a vote on it is started.
	*	sm_changemap	Admin			Brings up the same menu, but once the selection is map - the map changes.
	*	sm_cancelvote	Admin			Cancels any vote in progress (even ones not related to this plugin).
	*
	*	****************************************
	*
	*	Current valid filenames for GameMode Configs (reference only):
	*		GameMode - coop, realism, survival, scavenge, teamscavenge, versus, teamversus, 
	*					mutation3 (Bleed Out), mutation9 (VIP Gnome), mutation12 (Realism Versus), mutation13 (Follow the Liter - Linear Scavenge)
	*					+ eventually mutationX (1,2,3...)
	*		Difficulty - Easy, Normal, Hard, Impossible
	*
	*		Combined examples (with String:Temp3 and String:Temp2): coop.cfg, mutation12.cfg, realism_Impossible.cfg
	*
	*	If you don't have the file, it wont change anything.
	*	Difficulty based filenames are not required, but are checked for first (they override generic configs).
	*	eg: coop.cfg would run for all coop games, while coop_Easy.cfg would only run for coop games on Easy.
	*	eg: a versus game with no versus.cfg would use whatever settings are currently active on the server.
	*
	*	Forced GameModes will prevent any other in their "class" from loading up, and make the server play the mode
	*	mandated by the convar.
	*
	*	****************************************
	*
	*	Forcing Game Modes & Difficulties:
	*	- Forced Game Modes take place at map start, preventing any gameplay of "undesired" modes.
	*	- If you force your current Game Mode into something else, it will changelevel it right away.
	*	- Forced Difficulties take place as soon as they are set (including mid map).
	*		^ If you force a difficulty to something else, then later allow it, the difficulty will not change the current game.
	*			You can however manually adjust it (with a console command or vote).
	*
	*	****************************************
	*
	*	Map Vote Notes:
	*	- Reads maps from mapvote.txt in left4dead or left4dead2 folder.
	*		^ Reads 1 line at a time (cannot put multiple maps on the same line).
	*		^ Ignores comment lines (starting with ; or // ).
	*		^ Ignores invalid lines (starting with anything else but a letter).
	*		^ First part of the line is the map_file (no extension).
	*		^ If there is only a map_file, it will use the map_file on the menu.
	*		^ Also this map will be used in all votes (reguardless if the map is valid for the current Game Mode or not).
	*		^ Second part of the line is the "Menu Entry" in double quotes (optional if it is only 1 word).
	*		^ If it is not in double quotes, it can only be 1 word.
	*		^ The remaining entries on the line are optional, they are the Game Modes the map can be used in votes for.
	*		^ Valid entries are coop, versus, scavenge, survival. If none are used, all are assumed.
	*		^ You can repeat maps on multiple lines to rename them for different Game Modes
	*			However, there is currently no check for duplicates, so your map list could look funny if you do it.
	*	- If mapvote.txt is changed, this plugin will not know it until you reload it.
	*	- If you change the Vote Access level (for !mapvote command), you will have to reload the plugin as well.
	*	- The menu is currently built at map start and cannot change until the next map.
	*		^ Round Start != Map Start, this only fires OnMapStart.
	*		^ If you want to change Game Modes, you have to do that (and restart the map) before voting.
	*		^ I might add a Game Mode change vote later on.. but it will most likely not let you change mode AND map at the same time.
	*	- !mapvote gives the person who executes it the list of maps to vote on.
	*		^ Everyone else only votes yes/no on his choice.
	*
	*	- The restrictions imposed are to try and speed things up a bit.
	*		^ Allowing for a more dynamic vote could lag the server quite a bit (depending on how many maps there are).
	*
	*	****************************************
	*
	***	*/

#define CVAR_FLAGS FCVAR_PLUGIN
#define PLUGIN_VERSION "2.2"

#define TEST_DEBUG		0
#define TEST_DEBUG_LOG	1

#define TIMER_WELCOME	30.0

#define MAP_SIZE		32		// How many characters a map filename can be eg: c1m1_hotel = 10 chars
#define MAP_NAME_SIZE	64		// How many characters a friendly readable map name can be eg: "Dead Center - Hotel (map 1 of 5)" = 32 chars

// path that exec command looks for:
// REQUIRES the double back-slash to output a single back-slash
new String:Temp1[] = "cfg\\";

// file extension for config files:
new String:Temp2[] = ".cfg";

// seperator for difficulty filenames (eg: coop_Impossible):
new String:Temp3[] = "_";

new Handle:g_hGameMode		=	INVALID_HANDLE;
new Handle:g_hDifficulty	=	INVALID_HANDLE;
new String:g_sGameMode[24]		=	"\0";
new String:g_sDifficulty[24]	=	"\0";
new bool:g_bDifficultyCheck		=	false;	// This is a marker to check if we need to force to another difficulty
								// Either I don't need this, or I'm doing something wrong.. look into it
#define GM_UNKNOWN		0
#define GM_COOP			1		// coop, realism, mutation3 (Bleed Out), mutation9 (Last Gnome on Earth)
#define GM_VERSUS		2		// versus, teamversus, mutation12 (Realism Versus)
#define GM_SCAVENGE		3		// scavenge, teamscavenge, mutation13 (Follow the Liter - Linear Scavenge)
#define	GM_SURVIVAL		4		// survival
new GameMode		=	GM_UNKNOWN;
// add new gamemodes below as they become available:
	// Case is critical... if you enter it wrong here, it won't work.. (in the config, it should be fixed)
	// This is to simplify many of the calculations performed.
	// All game modes are lower case. All difficulties are First Letter Upper Case.
new String:coop[][] = {
	"coop",
	"realism",
	"mutation3",
	"mutation9"
};
new coopCount = 4;			// Number of entries above
new String:versus[][] = {
	"versus",
	"teamversus",
	"mutation12"
};
new versusCount = 3;		// Number of entries above
new String:scavenge[][] = {
	"scavenge",
	"teamscavenge",
	"mutation13"
};
new scavengeCount = 3;		// Number of entries above
new String:survival[][] = {
	"survival"
};
new survivalCount = 1;		// Number of entries above
#define DIF_EASY		0
#define DIF_NORMAL		1
#define	DIF_HARD		2
#define DIF_IMPOSSIBLE	3
new String:difficulties[][] = {
	"Easy",
	"Normal",
	"Hard",
	"Impossible"
};
new difficultyCount = 4;		// Number of entries above

new Handle:g_hForceMode			=	INVALID_HANDLE;
// trying to figure out how to remove these 4 cvars without screwing up the server..
new Handle:g_hForceCoop			=	INVALID_HANDLE;
new Handle:g_hForceVersus		=	INVALID_HANDLE;
new Handle:g_hForceScavenge		=	INVALID_HANDLE;
new Handle:g_hForceSurvival		=	INVALID_HANDLE;
// Above 4..
new Handle:g_hForceCoopMode		=	INVALID_HANDLE;
new Handle:g_hForceVersusMode	=	INVALID_HANDLE;
new Handle:g_hForceScavengeMode	=	INVALID_HANDLE;
new Handle:g_hForceSurvivalMode	=	INVALID_HANDLE;
new Handle:g_hForceDifficulty	=	INVALID_HANDLE;
new Handle:g_hForceEasy			=	INVALID_HANDLE;
new Handle:g_hForceNormal		=	INVALID_HANDLE;
new Handle:g_hForceHard			=	INVALID_HANDLE;
new Handle:g_hForceImpossible	=	INVALID_HANDLE;

new bool:	g_bForceMode		=	false;
new bool:	g_bForceDifficulty	=	false;
// These 4 go with the above 4 Im removing
new bool:	g_bForceCoop		=	false;
new bool:	g_bForceVersus		=	false;
new bool:	g_bForceScavenge	=	false;
new bool:	g_bForceSurvival	=	false;

new String:	g_sForceCoopMode[24]		=	"coop";			// These values are not actually used..
new String:	g_sForceVersusMode[24]		=	"versus";		//  they are set in the config file
new String:	g_sForceScavengeMode[24]	=	"scavenge";
new String:	g_sForceSurvivalMode[24]	=	"survival";
new String:	g_sForceEasy[24]			=	"Easy";
new String:	g_sForceNormal[24]			=	"Normal";
new String:	g_sForceHard[24]			=	"Hard";
new String:	g_sForceImpossible[24]		=	"Impossible";

new Handle:	g_hMapVoteEnable	=	INVALID_HANDLE;
new Handle: g_hEndVoteEnable	=	INVALID_HANDLE;
new Handle:	g_hMapMenu			=	INVALID_HANDLE;
new Handle:	g_hMapVoteAccess	=	INVALID_HANDLE;
new Handle:	g_hMapVoteTime		=	INVALID_HANDLE;
new Handle:	g_hMapChangeTime	=	INVALID_HANDLE;

// These arrays store all the maps in the mapvote.txt file
new Handle:	g_aMapList			=	INVALID_HANDLE;		// Name of map (to be executed)
new Handle:	g_aMapName			=	INVALID_HANDLE;		// Name of map (seen in menu)
new Handle:	g_aMapModeCoop		=	INVALID_HANDLE;		// Is this map for coop votes?
new Handle:	g_aMapModeVersus	=	INVALID_HANDLE;		// Is this map for versus votes?
new Handle:	g_aMapModeScavenge	=	INVALID_HANDLE;		// Is this map for scavenge votes?
new Handle:	g_aMapModeSurvival	=	INVALID_HANDLE;		// Is this map for survival votes?

new Float:	g_fMapChangeTime	=	0.0;
new bool:	g_bMapVoteEnable	=	false;
new bool:	g_bEndVoteEnable	=	false;
new bool:	isFirstRound		=	false;
new bool:	isMapVote			=	false;
new bool:	endMapVote			=	false;
new 		g_MapVoteTime		=	0;		// SM vote menus use ints for time?

new bool:	isReload		=	false;
new bool:	g_bL4D2Version	=	false;

public Plugin:myinfo = 
{
	name = "Game Mode Scripts",
	author = "Dirka_Dirka",
	description = "Executes a config file based on the current mp_gamemode and z_difficulty",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=93212"
}

public OnPluginStart()
{
	// Require Left 4 Dead (2)
	decl String:game_name[64];
	GetGameFolderName(game_name, sizeof(game_name));
	if (!StrEqual(game_name, "left4dead2", false) && !StrEqual(game_name, "left4dead", false))
		SetFailState("[GameMode] Plugin supports Left 4 Dead (2) only.");
	if (StrEqual(game_name, "left4dead2", false))
		g_bL4D2Version = true;
	
	if (g_bL4D2Version)
	{
		// Not sure why I created this bool, but to remove errors/warning, heres a check.
	}
	CreateConVar(
		"gamemode_scripts_ver",
		PLUGIN_VERSION,
		"Version of the L4D game mode scripts plugin.",
		FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD
	);
	
	g_hForceMode = CreateConVar(
		"gamemode_force_modes",
		"1",
		"Enable/Force gamemode overrides (eg: make versus always mutation12, make any/every game coop).",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hForceCoop = CreateConVar(
		"gamemode_force_coop",
		"0",
		"Force gamemode overrides on coop style games.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hForceVersus = CreateConVar(
		"gamemode_force_versus",
		"1",
		"Force gamemode overrides on versus style games.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hForceScavenge = CreateConVar(
		"gamemode_force_scavenge",
		"0",
		"Force gamemode overrides on scavenge style games.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hForceSurvival = CreateConVar(
		"gamemode_force_survival",
		"0",
		"Force gamemode overrides on survival style games.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hForceDifficulty = CreateConVar(
		"gamemode_force_difficulty",
		"0",
		"Enable/Force difficulty overrides (make every game Easy, Normal, Hard or Impossible).",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hForceEasy = CreateConVar(
		"gamemode_force_easy",
		"Easy",
		"Force difficulty to this setting on Easy games (ignored if gamemode_force_difficulty = 0 or if blank).",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceNormal = CreateConVar(
		"gamemode_force_normal",
		"Normal",
		"Force difficulty to this setting on Normal games (ignored if gamemode_force_difficulty = 0 or if blank).",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceHard = CreateConVar(
		"gamemode_force_hard",
		"Hard",
		"Force difficulty to this setting on Hard (Advanced) games (ignored if gamemode_force_difficulty = 0 or if blank).",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceImpossible = CreateConVar(
		"gamemode_force_impossible",
		"Impossible",
		"Force difficulty to this setting on Impossible (Expert) games (ignored if gamemode_force_difficulty = 0 or if blank).",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceCoopMode = CreateConVar(
		"gamemode_force_coopmode",
		"",
		"Force gamemode to this when playing 'coop' games (ignored if blank). Example: realism (harder then coop)",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceVersusMode = CreateConVar(
		"gamemode_force_versusmode",
		"Mutation12",
		"Force gamemode to this when playing 'versus' games (ignored if blank). Example: mutation12 (still versus, but realism)",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceScavengeMode = CreateConVar(
		"gamemode_force_scavengemode",
		"",
		"Force gamemode to this when playing 'scavenge' games (ignored if blank). Example: coop (scavenge not allowed - play coop only, best when all are set to this)",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hForceSurvivalMode = CreateConVar(
		"gamemode_force_survivalmode",
		"",
		"Force gamemode to this when playing 'survial' games (ignored if blank).",
		FCVAR_PLUGIN|FCVAR_NOTIFY
	);
	g_hMapVoteEnable = CreateConVar(
		"gamemode_mapvote_enable",
		"1",
		"Is map vote & admin map change enabled. Changing this ConVar requires a map change to enable it.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hEndVoteEnable = CreateConVar(
		"gamemode_endvote_enabled",
		"0",
		"Enables end of map/game vote to change maps - instead of default action (eg: Return to Lobby).",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hMapVoteAccess = CreateConVar(
		"gamemode_mapvote_admin",
		"1",
		"Is calling a map vote an admin command, or a public one (1 = admin only). Changing this ConVar requires the plugin to reload.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);
	g_hMapVoteTime = CreateConVar(
		"gamemode_mapvote_time",
		"20.0",
		"Time to keep map vote menu open (seconds).",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 5.0,
		true, 60.0
	);
	g_hMapChangeTime = CreateConVar(
		"gamemode_mapchange_time",
		"5.0",
		"Delay from when a map change is issued to when it occurs (seconds). This allows for time to announce it.",
		FCVAR_PLUGIN|FCVAR_NOTIFY,
		true, 0.2,
		true, 60.0
	);
	
	g_hGameMode = FindConVar("mp_gamemode");		//coop, versus, scavenge, survival, mutationX
	HookConVarChange(g_hGameMode, ConVarChange_GameMode);
	GetConVarString(g_hGameMode, g_sGameMode, sizeof(g_sGameMode));
	
	g_hDifficulty = FindConVar("z_difficulty");		//Easy, Normal, Hard, Impossible
	HookConVarChange(g_hDifficulty, ConVarChange_Difficulty);
	GetConVarString(g_hDifficulty, g_sDifficulty, sizeof(g_sDifficulty));
	
	AutoExecConfig(true, "gamemode_scripts");
	
	HookEvent("round_start_post_nav", OnRoundStartPostNav);
	HookEvent("round_end", Event_RoundEnd);
	
	new bool:g_bMapVoteAccess = GetConVarBool(g_hMapVoteAccess);
	if (g_bMapVoteAccess)
		RegAdminCmd("sm_mapvote", Command_MapVote, ADMFLAG_VOTE, "Force a change map vote");
	else
		RegConsoleCmd("sm_mapvote", Command_MapVote, "Call a change map vote");
	RegAdminCmd("sm_changemap", Command_ChangeMap, ADMFLAG_CHANGEMAP, "Forcefully change maps");
	RegAdminCmd("sm_cancelvote", Command_CancelVote, ADMFLAG_CHANGEMAP, "Forcefully cancel a vote in progress");
	
	HookConVarChange(g_hForceMode, ConVarChange_ForceMode);
	g_bForceMode = GetConVarBool(g_hForceMode);
	HookConVarChange(g_hForceDifficulty, ConVarChange_ForceDifficulty);
	g_bForceDifficulty = GetConVarBool(g_hForceDifficulty);
	HookConVarChange(g_hForceCoop, ConVarChange_ForceCoop);
	g_bForceCoop = GetConVarBool(g_hForceCoop);
	HookConVarChange(g_hForceVersus, ConVarChange_ForceVersus);
	g_bForceVersus = GetConVarBool(g_hForceVersus);
	HookConVarChange(g_hForceScavenge, ConVarChange_ForceScavenge);
	g_bForceScavenge = GetConVarBool(g_hForceScavenge);
	HookConVarChange(g_hForceSurvival, ConVarChange_ForceSurvival);
	g_bForceSurvival = GetConVarBool(g_hForceSurvival);
	
	// Make sure the GameModes and Difficulties defined in the config file are valid..
	new String:tempValue[24] = "\0";
	
	GetConVarString(g_hForceCoopMode, tempValue, sizeof(tempValue));
	CheckCase(tempValue, false);
	SetConVarString(g_hForceCoopMode, tempValue);
	GetConVarString(g_hForceCoopMode, g_sForceCoopMode, sizeof(g_sForceCoopMode));
	
	GetConVarString(g_hForceVersusMode, tempValue, sizeof(tempValue));
	CheckCase(tempValue, false);
	SetConVarString(g_hForceVersusMode, tempValue);
	GetConVarString(g_hForceVersusMode, g_sForceVersusMode, sizeof(g_sForceVersusMode));
	
	GetConVarString(g_hForceScavengeMode, tempValue, sizeof(tempValue));
	CheckCase(tempValue, false);
	SetConVarString(g_hForceScavengeMode, tempValue);
	GetConVarString(g_hForceScavengeMode, g_sForceScavengeMode, sizeof(g_sForceScavengeMode));
	
	GetConVarString(g_hForceSurvivalMode, tempValue, sizeof(tempValue));
	CheckCase(tempValue, false);
	SetConVarString(g_hForceSurvivalMode, tempValue);
	GetConVarString(g_hForceSurvivalMode, g_sForceSurvivalMode, sizeof(g_sForceSurvivalMode));
	
	GetConVarString(g_hForceEasy, tempValue, sizeof(tempValue));
	CheckCase(tempValue, true);
	SetConVarString(g_hForceEasy, tempValue);
	GetConVarString(g_hForceEasy, g_sForceEasy, sizeof(g_sForceEasy));
	
	GetConVarString(g_hForceNormal, tempValue, sizeof(tempValue));
	CheckCase(tempValue, true);
	SetConVarString(g_hForceNormal, tempValue);
	GetConVarString(g_hForceNormal, g_sForceNormal, sizeof(g_sForceNormal));
	
	GetConVarString(g_hForceHard, tempValue, sizeof(tempValue));
	CheckCase(tempValue, true);
	SetConVarString(g_hForceHard, tempValue);
	GetConVarString(g_hForceHard, g_sForceHard, sizeof(g_sForceHard));
	
	GetConVarString(g_hForceImpossible, tempValue, sizeof(tempValue));
	CheckCase(tempValue, true);
	SetConVarString(g_hForceImpossible, tempValue);
	GetConVarString(g_hForceImpossible, g_sForceImpossible, sizeof(g_sForceImpossible));
	
	HookConVarChange(g_hForceCoopMode, ConVarChange_ForceCoopMode);
	HookConVarChange(g_hForceVersusMode, ConVarChange_ForceVersusMode);
	HookConVarChange(g_hForceScavengeMode, ConVarChange_ForceScavengeMode);
	HookConVarChange(g_hForceSurvivalMode, ConVarChange_ForceSurvivalMode);
	HookConVarChange(g_hForceEasy, ConVarChange_ForceEasy);
	HookConVarChange(g_hForceNormal, ConVarChange_ForceNormal);
	HookConVarChange(g_hForceHard, ConVarChange_ForceHard);
	HookConVarChange(g_hForceImpossible, ConVarChange_ForceImpossible);
	
	HookConVarChange(g_hMapVoteEnable, ConVarChange_MapVoteEnable);
	g_bMapVoteEnable = GetConVarBool(g_hMapVoteEnable);
	HookConVarChange(g_hEndVoteEnable, ConVarChange_EndVoteEnable);
	g_bEndVoteEnable = GetConVarBool(g_hEndVoteEnable);
	HookConVarChange(g_hMapVoteTime, ConVarChange_MapVoteTime);
	g_MapVoteTime = GetConVarInt(g_hMapVoteTime);
	HookConVarChange(g_hMapChangeTime, ConVarChange_MapChangeTime);
	g_fMapChangeTime = GetConVarFloat(g_hMapChangeTime);
	
	// MapList is 32 chars
	new arraySize = ByteCountToCells(33);
	g_aMapList = CreateArray(arraySize);
	// MapName is 64 chars
	arraySize = ByteCountToCells(65);
	g_aMapName = CreateArray(arraySize);
	// Modes are 1 char - 1 or 0 (true/false)
	arraySize = ByteCountToCells(2);
	g_aMapModeCoop = CreateArray(arraySize);
	g_aMapModeVersus = CreateArray(arraySize);
	g_aMapModeScavenge = CreateArray(arraySize);
	g_aMapModeSurvival = CreateArray(arraySize);
	
	new mapFile = ReadMapFile();		// return 1 for good, 0 for bad
	if (mapFile == 0)
	{
		SetConVarBool(g_hMapVoteEnable, false);
		UnhookConVarChange(g_hMapVoteEnable, ConVarChange_MapVoteEnable);
		UnhookConVarChange(g_hEndVoteEnable, ConVarChange_EndVoteEnable);
		ClearArray(g_aMapList);
		ClearArray(g_aMapName);
		ClearArray(g_aMapModeCoop);
		ClearArray(g_aMapModeVersus);
		ClearArray(g_aMapModeScavenge);
		ClearArray(g_aMapModeSurvival);
		DebugPrintToAll("[OnPluginStart] Error reading from mapvote.txt. Disabling feature.");
	}
}

public OnMapStart()
{
	DebugPrintToAll("[OnMapStart] Begin..");
	ExecuteGameModeConfig(false);
	//GameModeCheck();
	
	if (g_bMapVoteEnable)
	{
		if (g_bEndVoteEnable)
			endMapVote = false;
		isFirstRound = true;
		isMapVote = false;
		g_hMapMenu = BuildMapMenu();
	}
}

public OnMapEnd()
{
	DebugPrintToAll("[OnMapEnd] Begin..");
	if (g_hMapMenu != INVALID_HANDLE)
	{
		CloseHandle(g_hMapMenu);
		g_hMapMenu = INVALID_HANDLE;
	}
}

public OnClientDisconnect(client)
{
	if (!g_bMapVoteEnable) return;
/*
	// Noone left on server (at least noone that isn't currently connecting)
	if (GetClientCount(true) <= 0)
	{
		DoMapChange(true, "\0");
	}
}

DoMapChange(bool:emptyServer, String:map[])
{
	if (!g_bEndVoteEnable) return;
	
	// this can be used to "warm-restart" a server after everyone leaves.
	if (emptyServer)
	{
		if (StrEqual(next_mission_force, "none") == true)
			map = next_mission_def;
		else
			map = next_mission_force;
	}
	
	ServerCommand("changelevel %s", map);
*/
}

public Action:OnRoundStartPostNav(Handle:event, const String:name[], bool:dontBroadcast)
{
	DebugPrintToAll("[OnRoundStartPostNav] Begin..");
	ForceGameModes();
	ForceDifficulty();
	
	if (g_bMapVoteEnable)
	{
		isMapVote = false;
	}
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bMapVoteEnable) return;
	if (!g_bEndVoteEnable) return;
	
	DebugPrintToAll("[RoundEnd] Begin..");
	if (g_hMapMenu == INVALID_HANDLE)
	{
		DebugPrintToAll("[RoundEnd] No mapvote.txt file means no menu. Aborting vote..");
		return;
	}
	
	if (!isFirstRound)	// How does this work in scavenge?
	{
		endMapVote = true;
		//DoVoteMenu();
	}
	
	isFirstRound = false;
}

public ConVarChange_GameMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] GameMode Changed.. oldValue: %s, newValue: %s", oldValue, newValue);
	// Make sure the gamemode is formatted correctly (so all future string comparisons
	// don't have to worry about case. GameMode is all lower..
	new String:tempValue[24] = "\0";
	new String:tempMode[24] = "\0";
	GetConVarString(g_hGameMode, tempMode, sizeof(tempMode));
	StrCat(String:tempValue, sizeof(tempValue), String:newValue);
	TrimString(tempValue);
	CheckCase(tempValue, false);
	
	if (!(StrEqual(tempMode, tempValue, true)))
		SetConVarString(g_hGameMode, tempValue);
	GetConVarString(g_hGameMode, g_sGameMode, sizeof(g_sGameMode));
	
	/* fixing broken code.. will clean up later once its working again
	if (g_bForceMode)
	{
		if (GameMode == GM_COOP)
		{
			if ((strlen(g_sForceCoopMode) == 0) || (StrEqual(g_sForceCoopMode, g_sGameMode)))
				return;
		}
		else if (GameMode == GM_VERSUS)
		{
			if ((strlen(g_sForceVersusMode) == 0) || (StrEqual(g_sForceVersusMode, g_sGameMode)))
				return;
		}
		else if (GameMode == GM_SCAVENGE)
		{
			if ((strlen(g_sForceScavengeMode) == 0) || (StrEqual(g_sForceScavengeMode, g_sGameMode)))
				return;
		}
		else if (GameMode == GM_SURVIVAL)
		{
			if ((strlen(g_sForceSurvivalMode) == 0) || (StrEqual(g_sForceSurvivalMode, g_sGameMode)))
				return;
		}
		
		DebugPrintToAll("[ConVar] Forcing GameMode Change.");
		ForceGameModes();
	} else {
		if (!(StrEqual(oldValue, tempValue, false)))
			ExecuteGameModeConfig(false);
	}
	*/
	
	if (strcmp(oldValue, tempValue) != 0)
		ExecuteGameModeConfig(false);
	
	if (!g_bForceMode)
		return;
	
	if ((g_bForceCoop) && (StrEqual(g_sForceCoopMode, g_sGameMode)))
		return;
	if ((g_bForceVersus) && (StrEqual(g_sForceVersusMode, g_sGameMode)))
		return;
	if ((g_bForceScavenge) && (StrEqual(g_sForceScavengeMode, g_sGameMode)))
		return;
	if ((g_bForceSurvival) && (StrEqual(g_sForceSurvivalMode, g_sGameMode)))
		return;
	
	DebugPrintToAll("[ConVar] Forcing GameMode Change.");
	ForceGameModes();
}

public ConVarChange_Difficulty(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] Difficulty Changed..");
	// Make sure the difficulty is formatted correctly (so all future string comparisons
	// don't have to worry about case. Difficulty is Upper first letter, lower every other..
	new String:tempValue[24] = "\0";
	new String:tempDif[24] = "\0";
	GetConVarString(g_hDifficulty, tempDif, sizeof(tempDif));
	StrCat(String:tempValue, sizeof(tempValue), String:newValue);
	TrimString(tempValue);
	CheckCase(tempValue, true);
	
	if (!(StrEqual(tempDif, tempValue, true)))
		SetConVarString(g_hDifficulty, tempValue);
	GetConVarString(g_hDifficulty, g_sDifficulty, sizeof(g_sDifficulty));
	
	if (!(StrEqual(oldValue, tempValue, false)))
		ExecuteGameModeConfig(true);
	
	if (!g_bForceDifficulty)
		return;
	
	if (!g_bDifficultyCheck)
	{
		g_bDifficultyCheck = true;
		DebugPrintToAll("[ConVar] Old GameMode: %s, New GameMode: %s..", oldValue, newValue);
		DebugPrintToAll("[ConVar] Forcing Difficulty.");
		ForceDifficulty();
	} else {
		g_bDifficultyCheck = false;
		DebugPrintToAll("[ConVar] Difficulty OK.");
	}
}

public ConVarChange_ForceMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceMode Changed..");
	g_bForceMode = GetConVarBool(g_hForceMode);
	
	if (!g_bForceMode)
		return;
	
	/* More clean up...
	if (GameMode == GM_COOP)
	{
		if ((strlen(g_sForceCoopMode) == 0) || (StrEqual(g_sForceCoopMode, g_sGameMode)))
			return;
	}
	else if (GameMode == GM_VERSUS)
	{
		if ((strlen(g_sForceVersusMode) == 0) || (StrEqual(g_sForceVersusMode, g_sGameMode)))
			return;
	}
	else if (GameMode == GM_SCAVENGE)
	{
		if ((strlen(g_sForceScavengeMode) == 0) || (StrEqual(g_sForceScavengeMode, g_sGameMode)))
			return;
	}
	else if (GameMode == GM_SURVIVAL)
	{
		if ((strlen(g_sForceSurvivalMode) == 0) || (StrEqual(g_sForceSurvivalMode, g_sGameMode)))
			return;
	}
	*/
	
	if ((g_bForceCoop) && (StrEqual(g_sForceCoopMode, g_sGameMode)))
		return;
	if ((g_bForceVersus) && (StrEqual(g_sForceVersusMode, g_sGameMode)))
		return;
	if ((g_bForceScavenge) && (StrEqual(g_sForceScavengeMode, g_sGameMode)))
		return;
	if ((g_bForceSurvival) && (StrEqual(g_sForceSurvivalMode, g_sGameMode)))
		return;
	
	DebugPrintToAll("[ConVar] Forcing GameMode Change.");
	ForceGameModes();
}

public ConVarChange_ForceDifficulty(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceDifficulty Changed..");
	g_bForceDifficulty = GetConVarBool(g_hForceDifficulty);
	
	DebugPrintToAll("[ConVar] Check GameMode..");
	GameModeCheck();
	
	if (!g_bForceDifficulty)
	{
		if (StrEqual(g_sDifficulty, difficulties[DIF_NORMAL]))
			return;
	}
	
	if (!g_bDifficultyCheck)
	{
		g_bDifficultyCheck = true;
		if (StrEqual(g_sDifficulty, difficulties[DIF_EASY]))
		{
			if (StrEqual(g_sForceEasy, g_sDifficulty))
				return;
			else
				DebugPrintToAll("[ConVar] Difficulty is Easy, but shouldn't be..");
		}
		if (StrEqual(g_sDifficulty, difficulties[DIF_NORMAL]))
		{
			if (g_bForceDifficulty)
			{
				if (StrEqual(g_sForceNormal, g_sDifficulty))
					return;
				else
					DebugPrintToAll("[ConVar] Difficulty is Normal, but shouldn't be..");
		/*
			Versus, Scavenge, Survival games all run on Normal w/o an override in place.
			This will reset that state if needed.
		*/
			} else {
				if (GameMode == GM_COOP)
					return;
				else
					DebugPrintToAll("[ConVar] Difficulty is not Normal, but should be..");
			}
		}
		if (StrEqual(g_sDifficulty, difficulties[DIF_HARD]))
		{
			if (StrEqual(g_sForceHard, g_sDifficulty))
				return;
			else
				DebugPrintToAll("[ConVar] Difficulty is Hard, but Shouldn't be..");
		}
		if (StrEqual(g_sDifficulty, difficulties[DIF_IMPOSSIBLE]))
		{
			if (StrEqual(g_sForceImpossible, g_sDifficulty))
				return;
			else
				DebugPrintToAll("[ConVar] Difficulty is Impossible, but Shouldn't be..");
		}
		DebugPrintToAll("[ConVar] Forcing Difficulty Change.");
		ForceDifficulty();
	} else {
		g_bDifficultyCheck = false;
		DebugPrintToAll("[ConVar] Difficulty OK.");
	}
}

public ConVarChange_ForceCoop(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceCoop Changed..");
	g_bForceCoop = GetConVarBool(g_hForceCoop);
	
	if (!g_bForceMode)
		return;
	if (!g_bForceCoop)
		return;
	
	// if the gamemode is already what it should be then skip the rest
	if (StrEqual(g_sForceCoopMode, g_sGameMode))
		return;
	
	DebugPrintToAll("[ConVar] Forcing GameMode Change.");
	ForceGameModes();
}

public ConVarChange_ForceVersus(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceVersus Changed..");
	g_bForceVersus = GetConVarBool(g_hForceVersus);
	
	if (!g_bForceMode)
		return;
	if (!g_bForceVersus)
		return;
	
	// if the gamemode is already what it should be then skip the rest
	if (StrEqual(g_sForceVersusMode, g_sGameMode))
		return;
	
	DebugPrintToAll("[ConVar] Forcing GameMode Change.");
	ForceGameModes();
}

public ConVarChange_ForceScavenge(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceScavenge Changed.");
	g_bForceScavenge = GetConVarBool(g_hForceScavenge);
	
	if (!g_bForceMode)
		return;
	if (!g_bForceScavenge)
		return;
	
	// if the gamemode is already what it should be then skip the rest
	if (StrEqual(g_sForceScavengeMode, g_sGameMode))
		return;
	
	DebugPrintToAll("[ConVar] Forcing GameMode.");
	ForceGameModes();
}

public ConVarChange_ForceSurvival(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceSurvival Changed..");
	g_bForceSurvival = GetConVarBool(g_hForceSurvival);
	
	if (!g_bForceMode)
		return;
	if (!g_bForceSurvival)
		return;
	
	// if the gamemode is already what it should be then skip the rest
	if (StrEqual(g_sForceSurvivalMode, g_sGameMode))
		return;
	
	DebugPrintToAll("[ConVar] Forcing GameMode Change.");
	ForceGameModes();
}

public ConVarChange_ForceCoopMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceCoopMode Changed..");
	GetConVarString(g_hForceCoopMode, g_sForceCoopMode, sizeof(g_sForceCoopMode));
	
	if (!g_bForceMode)
		return;
	
	if (GameMode == GM_COOP)
	{
		if (!g_bForceCoop)
			return;
		
		if (strlen(g_sForceCoopMode) == 0)
			return;
		
		// if the gamemode is already what it should be then skip the rest
		if (StrEqual(g_sForceCoopMode, g_sGameMode))
			return;
		
		DebugPrintToAll("[ConVar] Forcing GameMode Change.");
		ForceGameModes();
	} else {
		DebugPrintToAll("[ConVar] ForceCoopMode changed, but GameMode isn't coop. Nothing happening.");
		return;
	}
}

public ConVarChange_ForceVersusMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceVersusMode Changed..");
	GetConVarString(g_hForceVersusMode, g_sForceVersusMode, sizeof(g_sForceVersusMode));
	
	if (!g_bForceMode)
		return;
	
	if (GameMode == GM_VERSUS)
	{
		if (!g_bForceVersus)
			return;
		
		if (strlen(g_sForceVersusMode) == 0)
			return;
		
		// if the gamemode is already what it should be then skip the rest
		if (StrEqual(g_sForceVersusMode, g_sGameMode))
			return;
		
		// if not forcing difficulties, make sure its Normal.. at least for modes that need Normal.
		DebugPrintToAll("[ConVar] Checking ForceDifficulty and reset if needed..");
		if (g_bForceDifficulty)
		{
			if (StrEqual(g_sDifficulty, g_sForceNormal))
				return;
		} else {
			// If forcing the game into coop, skip changing the difficulty to normal.
			DebugPrintToAll("[ConVar] ForceVersusMode check against Coop gametypes..");
			new bool:isMode = false;
			for (new index=0; index < coopCount; index++)
			{
				if (StrEqual(g_sForceVersusMode, coop[index]))
				{
					isMode = true;
					break;
				}
			}
			if (isMode)
				return;
			
			if (!(StrEqual(g_sDifficulty, difficulties[DIF_NORMAL])))
			{
				DebugPrintToAll("[ConVar] ForceVersusMode is not Coop and ForceDifficulty is off, changing Difficulty to Normal.");
				SetConVarString(g_hDifficulty, difficulties[DIF_NORMAL]);
			}
			DebugPrintToAll("[ConVar] ForceDifficulty check complete.");
		}
		
		DebugPrintToAll("[ConVar] Forcing GameMode Change.");
		ForceGameModes();
	} else {
		DebugPrintToAll("[ConVar] ForceVersusMode changed, but GameMode isn't versus. Nothing happening.");
		return;
	}
}

public ConVarChange_ForceScavengeMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceScavengeMode Changed..");
	GetConVarString(g_hForceScavengeMode, g_sForceScavengeMode, sizeof(g_sForceScavengeMode));
	
	if (!g_bForceMode)
		return;
	
	if (GameMode == GM_SCAVENGE)
	{
		if (!g_bForceScavenge)
			return;
		
		if (strlen(g_sForceScavengeMode) == 0)
			return;
		
		// if the gamemode is already what it should be then skip the rest
		if (StrEqual(g_sForceScavengeMode, g_sGameMode))
			return;
		
		// if not forcing difficulties, make sure its Normal.. at least for modes that need Normal.
		DebugPrintToAll("[ConVar] Checking ForceDifficulty and reset if needed..");
		if (g_bForceDifficulty)
		{
			if (StrEqual(g_sDifficulty, g_sForceNormal))
				return;
		} else {
			// If forcing the game into coop, skip changing the difficulty to normal.
			DebugPrintToAll("[ConVar] ForceScavengeMode check against Coop gametypes..");
			new bool:isMode = false;
			for (new index=0; index < coopCount; index++)
			{
				if (StrEqual(g_sForceScavengeMode, coop[index]))
				{
					isMode = true;
					break;
				}
			}
			if (isMode)
				return;
			
			if (!(StrEqual(g_sDifficulty, difficulties[DIF_NORMAL])))
			{
				DebugPrintToAll("[ConVar] ForceScavengeMode is not Coop and ForceDifficulty is off, changing Difficulty to Normal.");
				SetConVarString(g_hDifficulty, difficulties[DIF_NORMAL]);
			}
			DebugPrintToAll("[ConVar] ForceDifficulty check complete.");
		}
		
		DebugPrintToAll("[ConVar] Forcing GameMode Change.");
		ForceGameModes();
	} else {
		DebugPrintToAll("[ConVar] ForceScavengeMode changed, but GameMode isn't scavenge. Nothing happening.");
		return;
	}
}

public ConVarChange_ForceSurvivalMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceSurvivalMode Changed..");
	GetConVarString(g_hForceSurvivalMode, g_sForceSurvivalMode, sizeof(g_sForceSurvivalMode));
	
	if (!g_bForceMode)
		return;
	
	if (GameMode == GM_SURVIVAL)
	{
		if (!g_bForceSurvival)
			return;
		
		if (strlen(g_sForceSurvivalMode) == 0)
			return;
		
		// if the gamemode is already what it should be then skip the rest
		if (StrEqual(g_sForceSurvivalMode, g_sGameMode))
			return;
		
		// if not forcing difficulties, make sure its Normal.. at least for modes that need Normal.
		DebugPrintToAll("[ConVar] Checking ForceDifficulty and reset if needed..");
		if (g_bForceDifficulty)
		{
			if (StrEqual(g_sDifficulty, g_sForceNormal))
				return;
		} else {
			// If forcing the game into coop, skip changing the difficulty to normal.
			DebugPrintToAll("[ConVar] ForceSurvivaleMode check against Coop gametypes..");
			new bool:isMode = false;
			for (new index=0; index < coopCount; index++)
			{
				if (StrEqual(g_sForceSurvivalMode, coop[index]))
				{
					isMode = true;
					break;
				}
			}
			if (isMode)
				return;
			
			if (!(StrEqual(g_sDifficulty, difficulties[DIF_NORMAL])))
			{
				DebugPrintToAll("[ConVar] ForceSurvivalMode is not Coop and ForceDifficulty is off, changing Difficulty to Normal.");
				SetConVarString(g_hDifficulty, difficulties[DIF_NORMAL]);
			}
			DebugPrintToAll("[ConVar] ForceDifficulty check complete.");
		}
		
		DebugPrintToAll("[ConVar] Forcing GameMode Change.");
		ForceGameModes();
	} else {
		DebugPrintToAll("[ConVar] ForceSurvivalMode changed, but GameMode isn't survival. Nothing happening.");
		return;
	}
}

public ConVarChange_ForceEasy(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceEasy Changed..");
	GetConVarString(g_hForceEasy, g_sForceEasy, sizeof(g_sForceEasy));
	
	// Not forcing, so it doesn't matter..
	if (!g_bForceDifficulty)
		return;
	// Currently not Easy, so it doesn't matter..
	if (!(StrEqual(g_sDifficulty, difficulties[DIF_EASY])))
		return;
	// Not forcing Easy, so it doesn't matter..
	if (strlen(g_sForceEasy) == 0)
		return;
	
	// Forcing Easy.. to current so it doesn't matter..
	if (StrEqual(g_sForceEasy, g_sDifficulty))
		return;
	
	DebugPrintToAll("[ConVar] Forcing Difficulty Change.");
	ForceDifficulty();
}

public ConVarChange_ForceNormal(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceNormal Changed..");
	GetConVarString(g_hForceNormal, g_sForceNormal, sizeof(g_sForceNormal));
	
	if (!g_bForceDifficulty)
		return;
	if (!(StrEqual(g_sDifficulty, difficulties[DIF_NORMAL])))
		return;
	if (strlen(g_sForceNormal) == 0)
		return;
	
	if (StrEqual(g_sForceNormal, g_sDifficulty))
		return;
	
	DebugPrintToAll("[ConVar] Forcing Difficulty Change.");
	ForceDifficulty();
}

public ConVarChange_ForceHard(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceHard Changed..");
	GetConVarString(g_hForceHard, g_sForceHard, sizeof(g_sForceHard));
	
	if (!g_bForceDifficulty)
		return;
	if (!(StrEqual(g_sDifficulty, difficulties[DIF_HARD])))
		return;
	if (strlen(g_sForceHard) == 0)
		return;
	
	if (StrEqual(g_sForceHard, g_sDifficulty))
		return;
	
	DebugPrintToAll("[ConVar] Forcing Difficulty Change.");
	ForceDifficulty();
}

public ConVarChange_ForceImpossible(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAll("[ConVar] ForceImpossible Changed..");
	GetConVarString(g_hForceImpossible, g_sForceImpossible, sizeof(g_sForceImpossible));
	
	if (!g_bForceDifficulty)
		return;
	if (!(StrEqual(g_sDifficulty, difficulties[DIF_IMPOSSIBLE])))
		return;
	if (strlen(g_sForceImpossible) == 0)
		return;
	
	if (StrEqual(g_sForceImpossible, g_sDifficulty))
		return;
	
	DebugPrintToAll("[ConVar] Forcing Difficulty Change.");
	ForceDifficulty();
}

public ConVarChange_MapVoteEnable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bMapVoteEnable = GetConVarBool(g_hMapVoteEnable);
	
	if (g_bMapVoteEnable)
		DebugPrintToAll("[ConVar] MapVoteEnable is TRUE, requires the plugin to be reloaded.");
	else
	{
		DebugPrintToAll("[ConVar] MapVoteEnable is FALSE, entire feature will not be available again until plugin is reloaded.");
		UnhookConVarChange(g_hMapVoteEnable, ConVarChange_MapVoteEnable);
		UnhookConVarChange(g_hEndVoteEnable, ConVarChange_EndVoteEnable);
		ClearArray(g_aMapList);
		ClearArray(g_aMapName);
		ClearArray(g_aMapModeCoop);
		ClearArray(g_aMapModeVersus);
		ClearArray(g_aMapModeScavenge);
		ClearArray(g_aMapModeSurvival);
		if (g_hMapMenu != INVALID_HANDLE)
		{
			CloseHandle(g_hMapMenu);
			g_hMapMenu = INVALID_HANDLE;
		}
	}
}

public ConVarChange_EndVoteEnable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!g_bMapVoteEnable)
		return;
	
	g_bEndVoteEnable = GetConVarBool(g_hEndVoteEnable);
}

public ConVarChange_MapVoteTime(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!g_bMapVoteEnable)
		return;
	
	g_MapVoteTime = GetConVarInt(g_hMapVoteTime);
}

public ConVarChange_MapChangeTime(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!g_bMapVoteEnable)
		return;
	
	g_fMapChangeTime = GetConVarFloat(g_hMapChangeTime);
}

ForceGameModes()
{
	DebugPrintToAll("[ForceGameModes] Begin..");
	if (!g_bForceMode)
		return;
	if (!g_bForceCoop && !g_bForceVersus && !g_bForceScavenge && !g_bForceSurvival)
		return;
	
	DebugPrintToAll("[ForceGameModes] Check GameMode..");
	GameModeCheck();
	switch (GameMode)
	{
		case GM_UNKNOWN:
			SetFailState("[GameMode] Could not detect GameMode.");
		case GM_COOP:
		{
			DebugPrintToAll("[ForceGameModes] Coop mode detected..");
			if (strlen(g_sForceCoopMode) == 0)
				return;
			
			DebugPrintToAll("[ForceGameModes] Coop mode replacement found..");
			if (!(StrEqual(g_sForceCoopMode, g_sGameMode)))
			{
				DebugPrintToAll("[ForceGameModes] Forcing Coop Change.");
				//SetConVarString(g_hGameMode, g_sForceCoopMode);
				ReloadMap(g_sForceCoopMode);
			}
			else
				DebugPrintToAll("[ForceGameModes] Coop mode replacement invalid!");
		}
		case GM_VERSUS:
		{
			DebugPrintToAll("[ForceGameModes] Versus mode detected..");
			if (strlen(g_sForceVersusMode) == 0)
				return;
			
			DebugPrintToAll("[ForceGameModes] Versus mode replacement found..");
			if (!(StrEqual(g_sForceVersusMode, g_sGameMode)))
			{
				DebugPrintToAll("[ForceGameModes] Forcing Versus Change.");
				//SetConVarString(g_hGameMode, g_sForceVersusMode);
				ReloadMap(g_sForceVersusMode);
			}
			else
				DebugPrintToAll("[ForceGameModes] Versus mode replacement invalid!");
		}
		case GM_SCAVENGE:
		{
			DebugPrintToAll("[ForceGameModes] Scavenge mode detected..");
			if (strlen(g_sForceSurvivalMode) == 0)
				return;
			
			DebugPrintToAll("[ForceGameModes] Scavenge mode replacement found..");
			if (!(StrEqual(g_sForceScavengeMode, g_sGameMode)))
			{
				DebugPrintToAll("[ForceGameModes] Forcing Scavenge Change.");
				//SetConVarString(g_hGameMode, g_sForceScavengeMode);
				ReloadMap(g_sForceScavengeMode);
			}
		}
		case GM_SURVIVAL:
		{
			DebugPrintToAll("[ForceGameModes] Survival mode detected..");
			if (strlen(g_sForceScavengeMode) == 0)
				return;
			
			DebugPrintToAll("[ForceGameModes] Survival mode replacement found..");
			if (!(StrEqual(g_sForceSurvivalMode, g_sGameMode)))
			{
				DebugPrintToAll("[ForceGameModes] Forcing Survival Change.");
				//SetConVarString(g_hGameMode, g_sForceSurvivalMode);
				ReloadMap(g_sForceSurvivalMode);
			}
		}
	}
}

ReloadMap(String:mode[])
{
	DebugPrintToAll("[Reload] Reloading the map..");
	decl String:map[MAP_SIZE];
	GetCurrentMap(map, sizeof(map));
	isReload = true;
	SetConVarString(g_hGameMode, mode);
	ServerCommand("changelevel %s", map);
}

ForceDifficulty()
{
	DebugPrintToAll("[ForceDifficulty] Begin..");
	if (!g_bForceDifficulty)
		return;
	
	if (StrEqual(g_sDifficulty, difficulties[0]))
	{
		DebugPrintToAll("[ForceDifficulty] Easy GameMode Detected..");
		if (!strlen(g_sForceEasy))
			return;
		else
		{
			DebugPrintToAll("[ForceDifficulty] Easy GameMode Override Detected..");
			if (StrEqual(g_sForceEasy, g_sDifficulty))
			{
				DebugPrintToAll("[ForceDifficulty] Easy GameMode Not Changed (either bad override, or empty).");
				return;
			} else {
				SetConVarString(g_hDifficulty, g_sForceEasy);
				DebugPrintToAll("[ForceDifficulty] Forcing Easy Change.");
			}
		}
	}
	else if (StrEqual(g_sDifficulty, difficulties[1]))
	{
		DebugPrintToAll("[ForceDifficulty] Normal GameMode Detected..");
		if (!strlen(g_sForceNormal))
			return;
		else
		{
			DebugPrintToAll("[ForceDifficulty] Normal GameMode Override Detected..");
			if (StrEqual(g_sForceNormal, g_sDifficulty))
			{
				DebugPrintToAll("[ForceDifficulty] Normal GameMode Not Changed (either bad override, or empty).");
				return;
			} else {
				SetConVarString(g_hDifficulty, g_sForceNormal);
				DebugPrintToAll("[ForceDifficulty] Forcing Normal Change.");
			}
		}
	}
	else if (StrEqual(g_sDifficulty, difficulties[2]))
	{
		DebugPrintToAll("[ForceDifficulty] Hard GameMode Detected..");
		if (!strlen(g_sForceHard))
			return;
		else
		{
			DebugPrintToAll("[ForceDifficulty] Hard GameMode Override Detected..");
			if (StrEqual(g_sForceHard, g_sDifficulty))
			{
				DebugPrintToAll("[ForceDifficulty] Hard GameMode Not Changed (either bad override, or empty).");
				return;
			} else {
				SetConVarString(g_hDifficulty, g_sForceHard);
				DebugPrintToAll("[ForceDifficulty] Forcing Hard Change.");
			}
			
		}
	}
	else if (StrEqual(g_sDifficulty, difficulties[3]))
	{
		DebugPrintToAll("[ForceDifficulty] Impossible GameMode Detected..");
		if (!strlen(g_sForceImpossible))
			return;
		else
		{
			DebugPrintToAll("[ForceDifficulty] Impossible GameMode Override Detected..");
			if (StrEqual(g_sForceImpossible, g_sDifficulty))
			{
				DebugPrintToAll("[ForceDifficulty] Impossible GameMode Not Changed (either bad override, or empty).");
				return;
			} else {
				SetConVarString(g_hDifficulty, g_sForceImpossible);
				DebugPrintToAll("[ForceDifficulty] Forcing Impossible Change.");
			}
			
		}
	}
	else
		SetFailState("[GameMode] Unknown Difficulty.");
}

ExecuteGameModeConfig(bool:CheckDifficulty)
{
	// If we're only changing the Difficulty, we won't exec any configs
	// if there isn't a difficulty based config. EG: if !(coop_Easy.cfg) do_nothing;
	
	DebugPrintToAll("[ExecuteGameModeConfig] Begin..");
	decl String:sConfigName[PLATFORM_MAX_PATH] = "\0";
	decl String:sConfigNameD[PLATFORM_MAX_PATH] = "\0";
	
	decl String:sGameMode[16] = "\0";
	GetConVarString(g_hGameMode, sGameMode, sizeof(sGameMode));
	
	decl String:sGameDifficulty[16] = "\0";
	GetConVarString(g_hDifficulty, sGameDifficulty, sizeof(sGameDifficulty));
	
	if (!CheckDifficulty)
	{
		StrCat(String:sConfigName, sizeof(sConfigName), sGameMode);
		TrimString(sConfigName);
	}
	
	StrCat(String:sConfigNameD, sizeof(sConfigName), sGameMode);
	StrCat(String:sConfigNameD, sizeof(sConfigName), Temp3);
	StrCat(String:sConfigNameD, sizeof(sConfigName), sGameDifficulty);
	TrimString(sConfigNameD);
	
	// the location of the config folder that exec looks for
	decl String:filePath[PLATFORM_MAX_PATH] = "\0";
	decl String:filePathD[PLATFORM_MAX_PATH] = "\0";
	
	if (!CheckDifficulty)
	{
		StrCat(String:filePath, sizeof(filePath), String:Temp1);
		StrCat(String:filePath, sizeof(filePath), sConfigName);
		StrCat(String:filePath, sizeof(filePath), String:Temp2);
		TrimString(filePath);
	}
	StrCat(String:filePathD, sizeof(filePathD), String:Temp1);
	StrCat(String:filePathD, sizeof(filePathD), sConfigNameD);
	StrCat(String:filePathD, sizeof(filePathD), String:Temp2);
	TrimString(filePathD);
	
	if (FileExists(filePathD))
		ServerCommand("exec %s", sConfigNameD);
	else
	{
		if (!CheckDifficulty)
		{
			if (FileExists(filePath))
				ServerCommand("exec %s", sConfigName);
			else
				return;		// no config file - will probably expand later
		}
	}
}

Handle:BuildMapMenu()
{
	if (!g_bMapVoteEnable) return INVALID_HANDLE;
	
	new mapIndex = GetArraySize(g_aMapList);
	if (mapIndex < 1)
	{
		DebugPrintToAll("[BuildMapMenu] There are no maps in the array, possible mapvote.txt error.");
		return INVALID_HANDLE;
	}
	DebugPrintToAll("[BuildMapMenu] Begin building the menu..");
	
	new Handle:menu = INVALID_HANDLE;
	if (endMapVote)
	{
		menu = CreateMenu(Menu_VoteMap);
		
		if ((GameMode == GM_COOP) || (GameMode == GM_VERSUS))
			SetMenuTitle(menu, "Vote for a Campaign to play next:");
		else
			SetMenuTitle(menu, "Vote for a map to play next:");
		//SetVoteResultCallback(menu, Handle_VoteResults);
		SetMenuExitButton(menu, false);
	} else {
		menu = CreateMenu(Menu_ChangeMap);
		
		if ((GameMode == GM_COOP) || (GameMode == GM_VERSUS))
			SetMenuTitle(menu, "Select a Campaign:");
		else
			SetMenuTitle(menu, "Select a map:");
		SetMenuExitButton(menu, true);
	}
	
	DebugPrintToAll("[BuildMapMenu] Begin reading the arrays..");
	new String:Map[MAP_SIZE];
	new String:MapName[MAP_NAME_SIZE];
	new menuItems = 0;
	
	for (new i=0; i<mapIndex; i++)
	{
		new isMode = 0;
		Map = "\0";
		MapName = "\0";
		
		if (GameMode == GM_COOP)
			isMode = GetArrayCell(g_aMapModeCoop, i, 0, false);
		else if (GameMode == GM_VERSUS)
			isMode = GetArrayCell(g_aMapModeVersus, i);
		else if (GameMode == GM_SCAVENGE)
			isMode = GetArrayCell(g_aMapModeScavenge, i);
		else if (GameMode == GM_SURVIVAL)
			isMode = GetArrayCell(g_aMapModeSurvival, i);
		
		DebugPrintToAll("[BuildMapMenu] Index: %i (of %i), isMode: %i", i, mapIndex-1, isMode);
		if (isMode != 0)
		{
			GetArrayString(g_aMapList, i, Map, sizeof(Map));
			GetArrayString(g_aMapName, i, MapName, sizeof(MapName));
			
			AddMenuItem(menu, Map, MapName);
			menuItems++;
			DebugPrintToAll("[BuildMapMenu] Adding Map: '%s', MapName: '%s', # Menu Entries: %i.", Map, MapName, menuItems);
		} else
			DebugPrintToAll("[BuildMapMenu] Array entry: %i is not correct GameMode 'isMode' (%i). Skipping it..", i, isMode);
	}
	
	DebugPrintToAll("[BuildMapMenu] Menu has %i entries. Menu Completed.", menuItems);
	return menu;
}

ReadMapFile()
{
	DebugPrintToAll("[ReadMapFile] Begin building the arrays..");
	new Handle:file = OpenFile("mapvote.txt", "rt");
	if (file == INVALID_HANDLE)
	{
		DebugPrintToAll("[ReadMapFile] Unable to find file mapvote.txt. aborting..");
		return 0;
	}
	
	new String:buffer[255];
	new String:Map[MAP_SIZE];
	new String:MapName[MAP_NAME_SIZE];
	new String:MapMode[12];
	new index = -1;
	
	DebugPrintToAll("[ReadMapFile] Begin reading mapvote.txt..");
	while (!IsEndOfFile(file) && ReadFileLine(file, buffer, sizeof(buffer)))
	{
		TrimString(buffer);
		DebugPrintToAll("[ReadMapFile] Read line: '%s'", buffer);
		
		// Skip comment lines and blank lines
		if (buffer[0] == '\0' || buffer[0] == ';' || (buffer[0] == '/' && buffer[1] == '/')) 
		{
			DebugPrintToAll("[ReadMapFile] Just read a comment line. Skipping to next line..");
			continue;
		}
		
		// Skip any line that is incorrectly formated (has to start with the mapname, which has to start with a letter)
		if (!IsCharAlpha(buffer[0]))
		{
			DebugPrintToAll("[ReadMapFile] Read an invalid map. aborting line..");
			continue;
		}
		
		// Read the line, and if something is missing skip this line..
		new old_pos = 0;
		new pos = BreakString(String:buffer[old_pos], String:Map, sizeof(Map));
		if (!IsMapValid(Map))
		{
			DebugPrintToAll("[ReadMapFile] Invalid map in file: '%s'.", Map);
			continue;
		}
		
		// We have a valid map.. now process it
		index++;
		PushArrayString(g_aMapList, String:Map);
		
		DebugPrintToAll("[ReadMapFile] Map: %s, pos: %i, old_pos: %i, index: %i", Map, pos, old_pos, index);
		
		if (pos == -1)
		{
			PushArrayString(g_aMapName, String:Map);
			PushArrayCell(g_aMapModeCoop, 1);
			PushArrayCell(g_aMapModeVersus, 1);
			PushArrayCell(g_aMapModeScavenge, 1);
			PushArrayCell(g_aMapModeSurvival, 1);
			DebugPrintToAll("[ReadMapFile] Map added to array.. Map: '%s', MapName '%s'.", Map, Map);
			continue;
		}
		
		old_pos += pos;
		pos = BreakString(String:buffer[old_pos], String:MapName, sizeof(MapName));
		PushArrayString(g_aMapName, MapName);
		
		DebugPrintToAll("[ReadMapFile] Map: '%s', MapName: '%s', pos: %i, old_pos: %i", Map, MapName, pos, old_pos);
		
		if (pos == -1)
		{
			PushArrayCell(g_aMapModeCoop, 1);
			PushArrayCell(g_aMapModeVersus, 1);
			PushArrayCell(g_aMapModeScavenge, 1);
			PushArrayCell(g_aMapModeSurvival, 1);
			DebugPrintToAll("[ReadMapFile] Map added to array on all MapModes.. Map: '%s', MapName '%s'.", Map, MapName);
			continue;
		}
		DebugPrintToAll("[ReadMapFile] MapName = '%s'. Finding MapModes..", MapName);
		
		// Get the rest of the line.. which is all the valid game modes.
		PushArrayCell(g_aMapModeCoop, 0);
		PushArrayCell(g_aMapModeVersus, 0);
		PushArrayCell(g_aMapModeScavenge, 0);
		PushArrayCell(g_aMapModeSurvival, 0);
		new len = strlen(buffer);
		new modes = 0;
		
		old_pos -= 1;	// need to fix it.. maybe because of the " " around MapName?
		for (new i=pos; i<=len; i++)
		{
			DebugPrintToAll("[ReadMapFile] Map: '%s', pos: %i, old_pos: %i, len: %i, modes: %i", Map, pos, old_pos, len, modes);
			
			if (modes == 3)
			{
				DebugPrintToAll("[ReadMapFile] Line not finished, yet there cannot be any more MapModes (Total: %i). aborting..", modes+1);
				break;
			}
			old_pos += pos;
			pos = BreakString(String:buffer[old_pos], String:MapMode, sizeof(MapMode));
			
			DebugPrintToAll("[ReadMapFile] Check current MapMode against list..");
			if (StrEqual(MapMode, "coop", false))
				SetArrayCell(g_aMapModeCoop, index, 1);
			else if (StrEqual(MapMode, "versus", false))
				SetArrayCell(g_aMapModeVersus, index, 1);
			else if (StrEqual(MapMode, "survival", false))
				SetArrayCell(g_aMapModeScavenge, index, 1);
			else if (StrEqual(MapMode, "scavenge", false))
				SetArrayCell(g_aMapModeSurvival, index, 1);
			else
			{
				DebugPrintToAll("[ReadMapFile] Invalid MapMode = '%s'. Ignoring it..", MapMode);
				MapMode = "\0";
				break;
			}
			modes++;
			
			if (pos == -1)
			{
				DebugPrintToAll("[ReadMapFile] MapMode = '%s', # modes: %i. No more MapModes..", MapMode, modes);
				break;
			} else {
				i = old_pos + pos;
			}
			DebugPrintToAll("[ReadMapFile] MapMode = '%s', # modes: %i. Reading next MapMode..", MapMode, modes);
		}
		
		DebugPrintToAll("[ReadMapFile] Line completed, read next (if there is one)..");
	}
	CloseHandle(file);
	
	// Make sure all the Arrays are correct
	new mapIndexList = GetArraySize(g_aMapList);
	new mapIndexName = GetArraySize(g_aMapName);
	new mapIndexCoop = GetArraySize(g_aMapModeCoop);
	new mapIndexVersus = GetArraySize(g_aMapModeVersus);
	new mapIndexScavenge = GetArraySize(g_aMapModeScavenge);
	new mapIndexSurvival = GetArraySize(g_aMapModeSurvival);
	DebugPrintToAll("[ReadMapFile] Array Sizes MapList: %i, MapName: %i, ModeCoop: %i, Versus: %i, Scavenge: %i, Survival: %i", mapIndexList, mapIndexName, mapIndexCoop, mapIndexVersus, mapIndexScavenge, mapIndexSurvival);
	
	if (!(mapIndexList == mapIndexName) && !(mapIndexList == mapIndexCoop) && !(mapIndexList == mapIndexVersus)
		&& !(mapIndexList == mapIndexScavenge) && !(mapIndexList == mapIndexSurvival))
	{
		DebugPrintToAll("[BuildMapMenu] Array indexes are not the same size. Error reading from file.");
		return 0;
	}
	
	DebugPrintToAll("[ReadMapFile] Map file read and arrays built.");
	return 1;
}

public Menu_ChangeMap(Handle:menu, MenuAction:action, param1, param2)
/*
	MenuAction_Start		MenuAction_Display					MenuAction_Cancel
		nothing					param1 = client						param1 = client
								param2 = MenuPanel Handle			param2 = reason
	MenuAction_Select											MenuAction_End
		param1 = client												param1 = reason
		param2 = selection											param2 = reason from MenuAction_Cancel if above is MenuEnd_Cancelled
	
*/
{
	DebugPrintToAll("[MenuChangeMap] Begin..");
	
	if (action == MenuAction_Select)
	{
		DebugPrintToAll("[MenuChangeMap] MenuAction_Select..");
		DebugPrintToAll("[MenuChangeMap] client(%i) '%N', choice: %i", param1, param1, param2);
		
		new String:map[MAP_SIZE];
		new bool:found = GetMenuItem(menu, param2, map, sizeof(map));
		
		PrintToConsole(param1, "You selected: %d (%s)", param2, found ? map : "INVALID");
		if (found)
		{
			new String:mapname[MAP_NAME_SIZE] = "\0";
			new index = FindStringInArray(g_aMapList, map);
			if (index != -1)
				GetArrayString(g_aMapName, index, mapname, sizeof(mapname));
			else
				StrCat(String:mapname[0], sizeof(mapname), map);
			DebugPrintToAll("[MenuChangeMap] Selection made: %i, Selection info: '%s' (%s)", param2, mapname, map);
			
			if (isMapVote)
			{
				DebugPrintToAll("[MenuChangeMap] Selection: %i (%s) chosen, creating vote menu for it..", param2, map);
				PrintToChatAll("%N requested a map change vote to: '%s'", param1, mapname);
				isMapVote = false;
				
				DoVoteForMapMenu(map, param1);
			} else {	// Admin ChangeMap command
				DebugPrintToAll("[MenuChangeMap] Selection: %i (%s) chosen, executing changelevel after %0.1f seconds..", param2, map, g_fMapChangeTime);
				PrintToChatAll("An Admin is changing the map to: '%s'", mapname);
				PrintToChatAll("Map change in 5 seconds..");
				
				new Handle:pack;
				WritePackString(pack, map);
				CreateDataTimer(g_fMapChangeTime, Timer_ChangeMap, pack);
			}
		} else
			DebugPrintToAll("[MenuChangeMap] Selection: %i is INVALID..", param2);
	}
	/*	Don't close it because we need it for any future votes..
	else if ((action == MenuAction_Cancel) || (action == MenuAction_End))
		CloseHandle(menu);
	*/
}

public Menu_VoteMap(Handle:menu, MenuAction:action, param1, param2)
/*
	MenuAction_VoteStart	MenuAction_VoteEnd							MenuAction_DrawItem
		nothing					param1 = winner								param1 = client
								skipped if SetVoteResultCallback used		param2 = selection
	MenuAction_VoteCancel												MenuAction_DisplayItem
		param1 = reason								use RedrawMenuItem()->	param1 = client
																			param2 = selection
*/
{
	DebugPrintToAll("[MenuVoteMap] Begin..");
	
	if (action == MenuAction_VoteStart)
	{
		DebugPrintToAll("[MenuVoteMap] MenuAction_VoteStart..");
	}
	else if (action == MenuAction_VoteEnd)
	{
		DebugPrintToAll("[MenuVoteMap] MenuAction_VoteEnd..");
		DebugPrintToAll("[MenuVoteMap] Winner: %i", param1);
		
		if (param1 == 0)	// YES
		{
			decl String:map[MAP_SIZE];
			new bool:found = GetMenuItem(menu, param1, map, sizeof(map));
			
			if (found)
			{
				new String:mapname[MAP_NAME_SIZE] = "\0";
				new index = FindStringInArray(g_aMapList, map);
				if (index != -1)
					GetArrayString(g_aMapName, index, mapname, sizeof(mapname));
				else
					StrCat(String:mapname[0], sizeof(mapname), map);
			
				DebugPrintToAll("[MenuChangeMap] Vote Result: %i, Selection info: '%s' (%s)", param1, mapname, map);
				PrintToChatAll("Vote Successful!  Changing map to: '%s'", mapname);
				PrintToChatAll("Map change in 5 seconds..");
				
				new Handle:pack = CreateDataPack();
				WritePackString(Handle:pack, String:map);
				CreateDataTimer(g_fMapChangeTime, Timer_ChangeMap, pack);
			} else
				DebugPrintToAll("[MenuVoteeMap] Selection: %i is INVALID..", param2);
		} else {			// NO or ???
			PrintToChatAll("Vote Failed! Continue as you were.");
		}
	}
	else if (action == MenuAction_VoteCancel)
	{
		// If we receive 0 votes, pick at random.
		if (param1 == VoteCancel_NoVotes)
			{
				PrintToChatAll("Vote Failed! Keeping current map.");
			}
			else
			{
				// We were actually cancelled. Guess we do nothing.
			}
	}
	/*	Don't close it because we need it for any future votes..
	else if ((action == MenuAction_Cancel) || (action == MenuAction_End))
		CloseHandle(menu);
	*/
	DebugPrintToAll("[MenuVoteMap] Menu Completed.");
}

public Action:Timer_ChangeMap(Handle:timer, Handle:pack)
{
	DebugPrintToAll("[TimerChangeMap] Timer elapsed, begin action..");
	PrintToChatAll("[Map] Changing map now..");
	
	new String:map[MAP_SIZE];
	
	ResetPack(pack);
	ReadPackString(pack, map, sizeof(map));
	
	DebugPrintToAll("[TimerChangeMap] Executing command: changelevel %s", map);
	ServerCommand("changelevel %s", map);
}

DoVoteForMapMenu(const String:map[MAP_SIZE], any:client)
{
	DebugPrintToAll("[Vote_YN_Menu] Begin..");
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] %t", "Vote already in Progress");
		DebugPrintToAll("[Vote_YN_Menu] Vote in progress, aborting..");
		return;
	}
	
	// Get the friendly map name for the vote menu
	new String:mapname[MAP_NAME_SIZE] = "\0";
	new index = FindStringInArray(g_aMapList, map);
	if (index != -1)
		GetArrayString(g_aMapName, index, mapname, sizeof(mapname));
	else
		StrCat(String:mapname[0], sizeof(mapname), map);
	
	new Handle:voteMenu = CreateMenu(Menu_VoteMap);
	
	if ((GameMode == GM_COOP) || (GameMode == GM_VERSUS))
		SetMenuTitle(voteMenu, "Do you want to change the campaign to: %s?", mapname);
	else
		SetMenuTitle(voteMenu, "Do you want to change map to: %s?", mapname);
	AddMenuItem(voteMenu, map, "Yes");
	AddMenuItem(voteMenu, "no", "No");
	SetMenuExitButton(voteMenu, false);
	
	DebugPrintToAll("[Vote_YN_Menu] Y/N Vote on '%s' (%s) begining, results in %i seconds.", mapname, map, g_MapVoteTime);
	
	// Fix for SourceMod bug(?) - server will crash VoteMenuToAll if there is only 1 human client (wonder what happens with 0 fake clients).
	// Secondary Fix.. this will allow votes to pass with bots.
	// Since bots don't vote, they can skew results (3 bots, 1 human = FAIL)
	new clientTotal = GetRealClientCount(true);
	new clients[MAXPLAYERS+1];
	clients = GetRealClients(true);
	
	VoteMenu(voteMenu, clients, clientTotal, g_MapVoteTime);
	DebugPrintToAll("[Vote_YN_Menu] Menu created, and sent to everyone.");
}
/*
DoVoteMenu()
{
	if (IsVoteInProgress())
		return;
	
	//new Handle:voteMenu = CreateMenu(Menu_VoteMap);
	
	VoteMenuToAll(g_hMapMenu, g_MapVoteTime);
}
*/
public Action:Command_ChangeMap(client, args)
{
	if (!g_bMapVoteEnable) return Plugin_Continue;
	
	DebugPrintToAll("[CmdChangeMap] Begin..");
	if (g_hMapMenu == INVALID_HANDLE)
	{
		PrintToConsole(client, "The mapvote.txt file was not found! (cannot generate menu)");
		DebugPrintToAll("[CmdChangeMap] No mapvote.txt file means no menu. aborting command..");
		return Plugin_Handled;
	}	
	
	// This ends up pointing to Menu_ChangeMap
	isMapVote = false;
	DisplayMenu(g_hMapMenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public Action:Command_MapVote(client, args)
{
	if (!g_bMapVoteEnable) return Plugin_Continue;
	
	DebugPrintToAll("[CmdMapVote] Begin..");
	if (g_hMapMenu == INVALID_HANDLE)
	{
		PrintToConsole(client, "The mapvote.txt file was not found! (cannot generate menu)");
		DebugPrintToAll("[CmdMapVote] No mapvote.txt file means no menu. aborting command..");
		return Plugin_Handled;
	}	
	
	isMapVote = true;
	DisplayMenu(g_hMapMenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public Action:Command_CancelVote(client, args)
{
	if (!g_bMapVoteEnable) return Plugin_Continue;
	
	DebugPrintToAll("[CmdCancelVote] Begin..");
	
	CancelVote();
	isMapVote = false;
	
	return Plugin_Handled;
}

GameModeCheck()
{
	DebugPrintToAll("[GameModeCheck] Begin..");
	
	GameMode = GM_UNKNOWN;
	new index;
	
	for (index=0; index < survivalCount; index++)
	{
		DebugPrintToAll("[GameModeCheck] Survival index = %i, GameMode = %i..", index, GameMode);
		if (StrEqual(g_sGameMode, survival[index]))
		{
			GameMode = GM_SURVIVAL;
			break;
		}
	}
	if (!GameMode)
	{
		for (index=0; index < scavengeCount; index++)
		{
			DebugPrintToAll("[GameModeCheck] Scavenge index = %i, GameMode = %i..", index, GameMode);
			if (StrEqual(g_sGameMode, scavenge[index]))
			{
				GameMode = GM_SCAVENGE;
				break;
			}
		}
	}
	if (!GameMode)
	{
		for (index=0; index < versusCount; index++)
		{
			DebugPrintToAll("[GameModeCheck] Versus index = %i, GameMode = %i..", index, GameMode);
			if (StrEqual(g_sGameMode, versus[index]))
			{
				GameMode = GM_VERSUS;
				break;
			}
		}
	}
	if (!GameMode)
	{
		for (index=0; index < coopCount; index++)
		{
			DebugPrintToAll("[GameModeCheck] Coop index = %i, GameMode = %i..", index, GameMode);
			if (StrEqual(g_sGameMode, coop[index]))
			{
				GameMode = GM_COOP;
				break;
			}
		}
	}
	if (!GameMode)
		SetFailState("[GameMode] Could not detect Game Mode.");
	
	DebugPrintToAll("[GameModeCheck] GameMode = %i.. Completed.", GameMode);
}

CheckCase(String:string1[24], bool:IsDifficulty)
{
	DebugPrintToAll("[CheckCase] Begin checking..");
	TrimString(string1);
	if (!strlen(string1))
	{
		DebugPrintToAll("[CheckCase] Nothing to check, returning..");
		return;
	}
	
	DebugPrintToAll("[CheckCase] Before changing anything: string1 = %s ..", string1);
	new i=0;
	if (IsCharAlpha(string1[0]))
	{
		if (IsDifficulty)
		{
			DebugPrintToAll("[CheckCase] Checking Difficulty string..");
			string1[0] = CharToUpper(string1[0]);
		} else {
			DebugPrintToAll("[CheckCase] Checking GameMode string..");
			string1[0] = CharToLower(string1[0]);
		}
	}
	DebugPrintToAll("[CheckCase] After first letter check: string1 = %s ..", string1);
	for (i=1; i < sizeof(string1); i++)
	{
		DebugPrintToAll("[CheckCase] Checking letter: %s", string1[i]);
		if (i >= strlen(string1))
		{
			DebugPrintToAll("[CheckCase] End of string.");
			break;
		}
		if (IsCharSpace(string1[i]))
			SetFailState("[CheckCase] White Spaces not allowed in GameMode or Difficulty.");
		else if (IsCharAlpha(string1[i]))
		{
			if (IsCharUpper(string1[i]))
				string1[i] = CharToLower(string1[i]);
		} else {
			if (!IsCharNumeric(string1[i]))
				SetFailState("[CheckCase] Invalid character in GameMode or Difficulty.");
		}
	}
	DebugPrintToAll("[CheckCase] After checking all letters: string1 = %s ..", string1);
	
	new bool:isValid = false;
	if (IsDifficulty)
	{
		for (i=0; i<difficultyCount; i++)
		{
			if (StrEqual(string1, difficulties[i]))
			{
				isValid = true;
				break;
			}
		}
	} else {
		new bool:isDone = false;
		for (i=0; i<survivalCount; i++)
		{
			if (StrEqual(string1, survival[i]))
			{
				isValid = true;
				isDone = true;
				break;
			}
		}
		if (!isDone)
		{
			for (i=0; i<scavengeCount; i++)
			{
				if (StrEqual(string1, scavenge[i]))
				{
					isValid = true;
					isDone = true;
					break;
				}
			}
		}
		if (!isDone)
		{
			for (i=0; i<versusCount; i++)
			{
				if (StrEqual(string1, versus[i]))
				{
					isValid = true;
					isDone = true;
					break;
				}
			}
		}
		if (!isDone)
		{
			for (i=0; i<coopCount; i++)
			{
				if (StrEqual(string1, coop[i]))
				{
					isValid = true;
					break;
				}
			}
		}
	}
	
	if (isValid)
		return;
	else
		SetFailState("[CheckCase] Invalid GameMode or Difficulty specified.");
}

stock GetRealClientCount(bool:inGameOnly = true)
{
	new clients = 0;
	
	for (new i=1; i<=MaxClients; i++)
	{
		if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i))
			clients++;
	}
	return clients;
}

stock GetRealClients(bool:inGameOnly = true)
{
	new clientindex = 0;
	new clients[MAXPLAYERS+1];
	
	for (new i=1; i<=MaxClients; i++)
	{
		if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i))
		{
			clients[clientindex] = i;
			clientindex++;
		}
	}
	return clients;
}

stock DebugPrintToAll(const String:format[], any:...)
{
	#if TEST_DEBUG	|| TEST_DEBUG_LOG
	decl String:buffer[250];
	
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
