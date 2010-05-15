/*
 *	L4D AFK Manager
 *	Version: PLUGIN_VERSION
 *
 *	Original Concept by Matthias Vance and his plugin found here:
 *		http://forums.alliedmods.net/showthread.php?t=115020
 *
 *	Version History:
 *		1.4 -		Complete re-write of almost the entire plugin.
 *					Added of Game Mode checks to determine 4 player and 8 player games.
 *					- This allows for improved team switching with chat commands instead of a menu.
 *					- While this is a tad more then is needed, it is what I use in other plugins as well.
 *					Reworked the !team menu to reduce (remove?) crashes and weird behavior.
 *					Addition of mins/maxes on pretty much every cvar.
 *					Most (if not all) of the content that anyone would want to tweak is found up top now.
 *					Added extended kick time to those who deliberately idle (!afk) instead of just afk'ing or crashing.
 *					- This lets people take a short break for nature or what not.
 *					Added detection of the game being paused via the Pause plugin (might try and find a better way)..
 *					Added detection of end game events so as to not prematurely exit.
 *					- Previous versions would auto spec everyone during the credits and then quickly R.T.L. (without sb_all_bot_team 1).
 *		1.4.1 -		Fixed a few bugs with the team menu.. it was possible to join a team that was full.
 *					Fixed event detection to disable during round ends (derr forgot the hooks).
 *		1.4.2 -		Added Scavenge as a seperate gameMode from versus (I use the same detection in other plugins, keeping consistant only).
 *		1.4.3 -		Worked on the new join code, fix a bug, create a bug, fix a bug.. and so on.
 *
 */
 
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

/* left4dead.inc */
#define L4D_TEAM_UNASSIGNED		0
#define L4D_TEAM_SPECTATOR		1
#define L4D_TEAM_SURVIVOR		2
#define L4D_TEAM_INFECTED		3

#define PLUGIN_VERSION	"1.4.3"
#define TAG				"\x03[AFK]\x01 "
#define MIN_TIMER		30.0
#define MIN_KICK		10.0
#define TIMER_MSG		5.0		// How often to display messages (about joining team and getting kicked)
#define MAX_TEAM_SIZE	4		// Change this for > 8 player servers.

public Plugin:myinfo = {
	name = "[L4D(2)] AFK Manager",
	author = "Dirka_Dirka",
	description = "Determines if someone has gone AFK (crashed) and removes them from the game.",
	version = PLUGIN_VERSION,
	url = ""
};

new Handle:g_hGameMode		=	INVALID_HANDLE;
new String:g_sGameMode[24]	=	"\0";
new GameMode	=	0;
				// 1 = coop, realism, mutation3 (Bleed Out), mutation9 (Last Gnome on Earth)
				// 2 = versus, teamversus, mutation12 (Realism Versus)
				// 3 = scavenge, teamscavenge, mutation13 (Follow the Liter - Linear Scavenge)
				// 4 = survival
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

new Handle:g_hEnabled			=	INVALID_HANDLE;
new Handle:g_hImmuneFlag		=	INVALID_HANDLE;
new Handle:g_hMessageLevel		=	INVALID_HANDLE;
new Handle:g_hAdvertiseInterval	=	INVALID_HANDLE;
new Handle:g_hAdvertiseTimer	=	INVALID_HANDLE;
new Handle:g_hAFKCheckTimer		=	INVALID_HANDLE;
new Handle:g_hTimeToSpec		=	INVALID_HANDLE;
new Handle:g_hTimeToKick		=	INVALID_HANDLE;
new Handle:g_hTimeLeftInterval	=	INVALID_HANDLE;
new Handle:g_hTimerJoinMessage	=	INVALID_HANDLE;
new Handle:g_hIdleTimeMultiple	=	INVALID_HANDLE;

new bool:g_bEnabled	=	true;
new bool:g_bActive	=	true;

new Float:g_fIdleTimeMultiple	=	1.0;
new Float:g_fTimeToSpec			=	MIN_KICK;
new Float:g_fTimeToKick			=	MIN_KICK;
new Float:g_fAdvertiseInterval	=	MIN_TIMER;
new Float:g_fTimeLeftInterval	=	TIMER_MSG;
new Float:g_fTimerJoinMessage	=	TIMER_MSG;

new g_iMessageLevel		=	0;

new String:immuneFlagChar[] = "z";
new AdminFlag:immuneFlag = Admin_Root;

new String:ads[][] = {
	"Use \x04!afk\x01 if you plan to go AFK (you will be kicked if gone too long).",
	"Use \x04!team\x01 to join a team by menu.",
	"Use \x04!teams\x01 to join the survivors and \x04!teami\x01 to join the infected."
};
new adCount = 3;	// Number of ads above
new adIndex = 0;

/* Is the Pause Plugin running and the game is paused? */
new bool:g_bGamePaused = false;

new Float:specTime[MAXPLAYERS+1];
new Float:afkTime[MAXPLAYERS+1];
new bool:isIdle[MAXPLAYERS+1];

new Float:checkInterval = 2.0;

new Float:lastMessage[MAXPLAYERS+1];

new Float:clientPos[MAXPLAYERS+1][3];
new Float:clientAngles[MAXPLAYERS+1][3];

new Handle:hSetHumanSpec, Handle:hTakeOverBot;

public OnPluginStart() {
	CreateConVar("l4d_afkmanager_version", PLUGIN_VERSION, "[L4D(2)] AFK Manager", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	SetConVarString(FindConVar("l4d_afkmanager_version"), PLUGIN_VERSION);
	
	g_hEnabled = CreateConVar("l4d_afkmanager_enable", "1", "Enable this plugin, spectates and then kicks AFKers/crashers.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hImmuneFlag = CreateConVar("l4d_afk_immuneflag", immuneFlagChar, "Admins with this flag have kick immunity.", FCVAR_NOTIFY|FCVAR_PLUGIN);
	g_hMessageLevel = CreateConVar("l4d_afk_messages", "2", "Control spec/kick messages. (0 = disable, 1 = spec, 2 = kick, 3 = spec + kick)", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 3.0);
	g_hAdvertiseInterval = CreateConVar("l4d_afk_adinterval", "180.0", "Interval in which the plugin will advertise the !afk command. (0 = disabled, otherwise MIN_TIMER = 30 seconds)", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 1200.0);
	g_hTimeToSpec = CreateConVar("l4d_afk_spectime", "30.0", "AFK time after which you will be moved to the Spectator team. (0 = disabled, otherwise MIN_KICK = 10 seconds)", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 300.0);
	g_hTimeToKick = CreateConVar("l4d_afk_kicktime", "90.0", "AFK time after which you will be kicked.. counted AFTER l4d_afk_spectime. (0 = disabled, otherwise MIN_KICK = 10 seconds)", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 0.0, true, 300.0);
	g_hTimerJoinMessage = CreateConVar("l4d_afk_joinmsgtime", "5.0", "Time between messages telling you how to rejoin your team.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 1.0, true, 30.0);
	g_hTimeLeftInterval = CreateConVar("l4d_afk_warningtime", "5.0", "Time between messages telling you when your getting kicked.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 1.0, true, 30.0);
	g_hIdleTimeMultiple = CreateConVar("l4d_afk_idlemulti", "2.0", "Value to multiply l4d_afk_kicktime with for idlers (volunteer afkers). They then get l4d_afk_idlemulti * l4d_afk_kicktime seconds to spectate.", FCVAR_NOTIFY|FCVAR_PLUGIN, true, 1.0, true, 6.0);
	
	HookConVarChange(g_hEnabled, ConVarChanged_Enable);
	g_bEnabled = GetConVarBool(g_hEnabled);
	HookConVarChange(g_hMessageLevel, ConVarChanged_Messages);
	g_iMessageLevel = GetConVarInt(g_hMessageLevel);
	HookConVarChange(g_hAdvertiseInterval, ConVarChange_AdvertiseInterval);
	g_fAdvertiseInterval = GetConVarFloat(g_hAdvertiseInterval);
	HookConVarChange(g_hTimeToSpec, ConVarChanged_TimeToSpec);
	g_fTimeToSpec = GetConVarFloat(g_hTimeToSpec);
	HookConVarChange(g_hTimeToKick, ConVarChanged_TimeToKick);
	g_fTimeToKick = GetConVarFloat(g_hTimeToKick);
	HookConVarChange(g_hTimerJoinMessage, ConVarChanged_TimerJoinMessage);
	g_fTimerJoinMessage = GetConVarFloat(g_hTimerJoinMessage);
	HookConVarChange(g_hTimeLeftInterval, ConVarChanged_TimeLeftInterval);
	g_fTimeLeftInterval = GetConVarFloat(g_hTimeLeftInterval);
	HookConVarChange(g_hIdleTimeMultiple, ConVarChanged_IdleTimeMultiple);
	g_fIdleTimeMultiple = GetConVarFloat(g_hIdleTimeMultiple);
	
	HookConVarChange(g_hImmuneFlag, ConVarChanged_ImmuneFlag);
	
	g_hGameMode = FindConVar("mp_gamemode");
	HookConVarChange(g_hGameMode, ConVarChanged_GameMode);
	GetConVarString(g_hGameMode, g_sGameMode, sizeof(g_sGameMode));
	
	AutoExecConfig(true, "l4d_afkmanager");
	new Handle:hConfig = LoadGameConfigFile("l4d_afkmanager");
//	if (hConfig == INVALID_HANDLE)
//		SetFailState("[AFK Manager] Could not load l4d_afkmanager gamedata.");
	
	// SetHumanSpec
	StartPrepSDKCall(SDKCall_Player);
	if (PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "SetHumanSpec"))
	{
		PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
		hSetHumanSpec = EndPrepSDKCall();
	}
	if (hSetHumanSpec == INVALID_HANDLE)
		SetFailState("[AFK Manager] SetHumanSpec not found.");

	// TakeOverBot
	StartPrepSDKCall(SDKCall_Player);
	if (PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "TakeOverBot"))
	{
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
		hTakeOverBot = EndPrepSDKCall();
	}
	if (hTakeOverBot == INVALID_HANDLE)
		SetFailState("[AFK Manager] TakeOverBot not found.");
	
	if (g_fAdvertiseInterval)
	{
		if (g_fAdvertiseInterval < MIN_TIMER)
		{
			g_fAdvertiseInterval = MIN_TIMER;
			SetConVarFloat(g_hAdvertiseInterval, g_fAdvertiseInterval);
		}
		if (g_hAdvertiseTimer != INVALID_HANDLE)
			CloseHandle(g_hAdvertiseTimer);
		g_hAdvertiseTimer = CreateTimer(g_fAdvertiseInterval, timer_Advertise, _, TIMER_REPEAT);
	}
	if (g_fTimeToSpec)
	{
		if (g_fTimeToSpec < MIN_KICK)
		{
			g_fTimeToSpec = MIN_KICK;
			SetConVarFloat(g_hTimeToSpec, g_fTimeToSpec);
		}
	}
	if (g_fTimeToKick)
	{
		if (g_fTimeToKick < MIN_KICK)
		{
			g_fTimeToKick = MIN_KICK;
			SetConVarFloat(g_hTimeToKick, g_fTimeToKick);
		}
	}
	if (g_fTimeToSpec || g_fTimeToKick)
	{
		if (g_hAFKCheckTimer != INVALID_HANDLE)
			CloseHandle(g_hAFKCheckTimer);
		g_hAFKCheckTimer = CreateTimer(checkInterval, timer_Check, _, TIMER_REPEAT);
	}
	
	RegConsoleCmd("sm_afk", cmd_Idle, "Go AFK (Spectator team).");
	RegConsoleCmd("sm_team", cmd_Team, "Change team.");
	RegConsoleCmd("sm_teami", cmd_TeamI, "Goto Infected team.");
	RegConsoleCmd("sm_teams", cmd_TeamS, "Goto Survivor team.");
	
	HookEvent("round_start_post_nav", OnRoundStartPostNav);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("finale_win", Event_FinalWin);
	HookEvent("mission_lost", Event_MissionLost);
}

public OnConfigsExecuted()
{
	// This is called after OnMapStart() and OnAutoConfigsBuffered() -- in that order.
	// Best place to initialize based on ConVar data
	
	if (!g_bEnabled) return;
	
	// Plugin Compatability: L4D2 Pause
	if ((FindConVar("l4d2pause_enabled") != INVALID_HANDLE) && (GetConVarInt(FindConVar("l4d2pause_enabled")) == 1))
	{
		g_bGamePaused = true;
	} else {
		g_bGamePaused = false;
	}
}

public OnMapStart()
{
	if (!g_bEnabled) return;
	
	g_bActive = true;
	
	for (new i=1; i <= MaxClients; i++)
		isIdle[i] = false;
}

public Action:OnRoundStartPostNav(Handle:event, const String:name[], bool:dontBroadcast)
{
	GameModeCheck();
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{	
	if (!g_bEnabled) return;
	
	g_bActive = true;
	
	for (new i=1; i <= MaxClients; i++)
		isIdle[i] = false;
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{	
	if (!g_bEnabled) return;
	
	g_bActive = false;
}

public Action:Event_FinalWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return;
	
	g_bActive = false;
}

public Action:Event_MissionLost(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled) return;
	
	g_bActive = false;
}

public ConVarChanged_Enable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bEnabled = GetConVarBool(g_hEnabled);
	
	if (g_bEnabled)					// Plugin enabled, turn on (reset) timers if needed..
	{
		if (g_fAdvertiseInterval)
		{
			if (g_hAdvertiseTimer != INVALID_HANDLE)
				CloseHandle(g_hAdvertiseTimer);
			g_hAdvertiseTimer = CreateTimer(g_fAdvertiseInterval, timer_Advertise, _, TIMER_REPEAT);
		}
		if (g_fTimeToSpec || g_fTimeToKick)
		{
			if (g_hAFKCheckTimer != INVALID_HANDLE)
				CloseHandle(g_hAFKCheckTimer);
			g_hAFKCheckTimer = CreateTimer(checkInterval, timer_Check, _, TIMER_REPEAT);
		}
	} else {						// Plugin disabled, turn off timers..
		if (g_hAdvertiseTimer != INVALID_HANDLE)
		{
			CloseHandle(g_hAdvertiseTimer);
			g_hAdvertiseTimer = INVALID_HANDLE;
		}
		if (g_hAFKCheckTimer != INVALID_HANDLE)
		{
			CloseHandle(g_hAFKCheckTimer);
			g_hAFKCheckTimer = INVALID_HANDLE;
		}
	}
}

public ConVarChanged_ImmuneFlag(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// I think I can improve this.. will come back to it later.
	if(strlen(newValue) != 1) {
		PrintToServer("[AFK Manager] Invalid flag value (%s).", newValue);
		SetConVarString(convar, oldValue);
		return;
	}
	if(!FindFlagByChar(newValue[0], immuneFlag)) {
		PrintToServer("[AFK Manager] Invalid flag value (%s).", newValue);
		SetConVarString(convar, oldValue);
		return;
	}
}

public ConVarChanged_Messages(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_iMessageLevel = GetConVarInt(g_hMessageLevel);
}

public ConVarChange_AdvertiseInterval(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_fAdvertiseInterval = GetConVarFloat(g_hAdvertiseInterval);
	
	if (!g_fAdvertiseInterval)		// No Advertising.. close the timer if it exists.
	{
		if (g_hAdvertiseTimer != INVALID_HANDLE)
		{
			CloseHandle(g_hAdvertiseTimer);
			g_hAdvertiseTimer = INVALID_HANDLE;
		}
	}
	else							// Advertising enabled..
	{
		if (g_fAdvertiseInterval < MIN_TIMER)		// Timer setting too short, fix time
		{
			g_fAdvertiseInterval = MIN_TIMER;
			SetConVarFloat(g_hAdvertiseInterval, g_fAdvertiseInterval);
		}
		if (g_hAdvertiseTimer != INVALID_HANDLE)	// Timer already exists, kill it
		{
			CloseHandle(g_hAdvertiseTimer);
		}
		g_hAdvertiseTimer = CreateTimer(g_fAdvertiseInterval, timer_Advertise, _, TIMER_REPEAT);
	}
}

public ConVarChanged_TimeToSpec(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_fTimeToSpec = GetConVarFloat(g_hTimeToSpec);
	
	if (g_fTimeToSpec)
	{
		if (g_fTimeToSpec < MIN_KICK)
		{
			g_fTimeToSpec = MIN_KICK;
			SetConVarFloat(g_hTimeToSpec, g_fTimeToSpec);
		}
	}
}

public ConVarChanged_TimeToKick(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_fTimeToKick = GetConVarFloat(g_hTimeToKick);
	
	if (g_fTimeToKick)
	{
		if (g_fTimeToKick < MIN_KICK)
		{
			g_fTimeToKick = MIN_KICK;
			SetConVarFloat(g_hTimeToKick, g_fTimeToKick);
		}
	}
}

public ConVarChanged_TimerJoinMessage(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_fTimerJoinMessage = GetConVarFloat(g_hTimerJoinMessage);
}

public ConVarChanged_TimeLeftInterval(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_fTimeLeftInterval = GetConVarFloat(g_hTimeLeftInterval);
}

public  ConVarChanged_IdleTimeMultiple(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_fIdleTimeMultiple = GetConVarFloat(g_hIdleTimeMultiple);
}

public  ConVarChanged_GameMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	GetConVarString(g_hGameMode, g_sGameMode, sizeof(g_sGameMode));
	
	GameModeCheck();
}

public Action:cmd_Team(client, argCount)
{
	new Handle:menu = CreateMenu(menu_Team);

	isIdle[client] = false;

	if ((GameMode == 1) || (GameMode == 4))
	{
		if (GetClientTeam(client) == L4D_TEAM_SPECTATOR)
		{
			SetMenuTitle(menu, "Choose your team:");
			AddMenuItem(menu, "2", "Survivors");
			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, 0);
		}
		else if (GetClientTeam(client) == L4D_TEAM_SURVIVOR)
		{
			SetMenuTitle(menu, "Choose your team:");
			AddMenuItem(menu, "1", "Spectators");
			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, 0);
		}
	} else {
		if (GetClientTeam(client) == L4D_TEAM_SPECTATOR)
		{
			SetMenuTitle(menu, "Choose your team:");
			AddMenuItem(menu, "2", "Survivors");
			AddMenuItem(menu, "3", "Infected");
			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, 0);
		}
		else if (GetClientTeam(client) == L4D_TEAM_SURVIVOR)
		{
			SetMenuTitle(menu, "Choose your team:");
			AddMenuItem(menu, "1", "Spectators");
			AddMenuItem(menu, "3", "Infected");
			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, 0);
		}
		else if (GetClientTeam(client) == L4D_TEAM_INFECTED)
		{
			SetMenuTitle(menu, "Choose your team:");
			AddMenuItem(menu, "1", "Spectators");
			AddMenuItem(menu, "2", "Survivors");
			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, 0);
		}
	}
	return Plugin_Handled;
}

public findHumans(team)
{
	new humans = 0;
	for (new client=1; client<=MaxClients; client++)
	{
		if (!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
			continue;
		humans++;
	}
	PrintToChatAll("[Debug] Team: %i, Number of Humans: %i", team, humans);
	return humans;
}

public menu_Team(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			new String:info[32];
			if(GetMenuItem(menu, param2, info, sizeof(info)))
			{
				new team = StringToInt(info);
				new bot;
				switch(team)
				{
					case L4D_TEAM_SPECTATOR:
					{
						ChangeClientTeam(param1, L4D_TEAM_SPECTATOR);
						specTime[param1] = 0.0;
					}
					case L4D_TEAM_SURVIVOR:
					{
						bot = MAX_TEAM_SIZE - findHumans(L4D_TEAM_SURVIVOR);
						if (bot == 0)
							PrintToChat(param1, "\x03[AFK Manager]\x01 That team is full.");
						else
						{
							SDKCall(hSetHumanSpec, bot, param1);
							SDKCall(hTakeOverBot, param1, true);
							isIdle[param1] = false;
							afkTime[param1] = 0.0;
						}
					}
					case L4D_TEAM_INFECTED:
					{
						bot = MAX_TEAM_SIZE - findHumans(L4D_TEAM_INFECTED);
						if (bot == 0)
							PrintToChat(param1, "%sYou cannot join that team, it is full already.", TAG);
						else
						{
							ChangeClientTeam(param1, L4D_TEAM_INFECTED);
							isIdle[param1] = false;
							afkTime[param1] = 0.0;
						}
					}
				}
			}
		}
		case MenuAction_End:
			CloseHandle(menu);
	}
}

public Action:Event_PlayerTeam(Handle:event, const String:eventName[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new team = GetEventInt(event, "team");
	
	switch(team)
	{
		case L4D_TEAM_SPECTATOR:
		{
			specTime[client] = 0.0;
		}
		case L4D_TEAM_SURVIVOR, L4D_TEAM_INFECTED:
		{
			afkTime[client] = 0.0;
			isIdle[client] = false;
		}
	}
	if (GetEventBool(event, "disconnected"))
	{
		clientPos[client] = Float:{ 0.0, 0.0, 0.0 };
		clientAngles[client] = Float:{ 0.0, 0.0, 0.0 };
		isIdle[client] = false;
	}
}

public Action:cmd_Idle(client, argCount)
{
	if (GetClientTeam(client) != L4D_TEAM_SPECTATOR)
	{
		ChangeClientTeam(client, L4D_TEAM_SPECTATOR);
		isIdle[client] = true;
	} else {
		PrintToChat(client, "%sYou are already spectating!", TAG);
	}
	return Plugin_Handled;
}

public Action:cmd_TeamS(client, argCount)
{
	if (!IsClientInGame(client)) return Plugin_Handled;
	if (!IsClientConnected(client)) return Plugin_Handled;
	if (IsFakeClient(client)) return Plugin_Handled;
	
	new bot = MAX_TEAM_SIZE - findHumans(L4D_TEAM_SURVIVOR);
	PrintToChat(client, "[Debug] bot slots open: %i", bot);
	if (!bot)
	{
		PrintToChat(client, "%sYou cannot join that team, it is full already.", TAG);
		return Plugin_Handled;
	}
	
	if (GetClientTeam(client) == L4D_TEAM_SURVIVOR)
	{
		PrintToChat(client, "%sYou are already on that team!", TAG);
		return Plugin_Handled;
	} else {
		SDKCall(hSetHumanSpec, bot, client);
		SDKCall(hTakeOverBot, client, true);
		isIdle[client] = false;
		afkTime[client] = 0.0;
	}
	return Plugin_Continue;
}

public Action:cmd_TeamI(client, argCount)
{
	if (!IsClientInGame(client)) return Plugin_Handled;
	if (!IsClientConnected(client)) return Plugin_Handled;
	if (IsFakeClient(client)) return Plugin_Handled;
	
	if ((GameMode != 2) || (GameMode !=3))
	{
		PrintToChat(client, "%sYou cannot join that team, it is not valid.", TAG);
		return Plugin_Handled;
	}
	
	new bot = MAX_TEAM_SIZE - findHumans(L4D_TEAM_INFECTED);
	if (!bot)
	{
		if (GetClientTeam(client) != L4D_TEAM_INFECTED)
			PrintToChat(client, "%sYou cannot join that team, it is full already.", TAG);
		else
			PrintToChat(client, "%sYou are already on that team!", TAG);
		
		return Plugin_Handled;
	}
	
	if (GetClientTime(client) != L4D_TEAM_INFECTED)
	{
		ChangeClientTeam(client, L4D_TEAM_INFECTED);
		isIdle[client] = false;
		afkTime[client] = 0.0;
	} else {
		PrintToChat(client, "%sYou are already on that team!", TAG);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:timer_Check(Handle:timer)
{
	if (!g_bEnabled) return Plugin_Handled;	// This should actually probably kill the timer
	if (!g_bActive) return Plugin_Handled;
	
	if ((FindConVar("l4d2pause_enabled") != INVALID_HANDLE) && (GetConVarInt(FindConVar("l4d2pause_enabled")) == 1))
	{
		g_bGamePaused = true;
	} else {
		g_bGamePaused = false;
	}
	if (g_bGamePaused) return Plugin_Handled;
	
	new Float:currentPos[3];
	new Float:currentAngles[3];
	
	new team;
	new bool:isAFK = false;
	new AdminId:id = INVALID_ADMIN_ID;
	new client, index;
	
	for (client = 1; client <= MaxClients; client++)
	{
		if (!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
			continue;
		
		team = GetClientTeam(client);
		
		if (team == L4D_TEAM_SPECTATOR)
		{
			id = GetUserAdmin(client);
			if (id != INVALID_ADMIN_ID && GetAdminFlag(id, immuneFlag))
			{
				if (GetClientTime(client) - lastMessage[client] >= g_fTimerJoinMessage)
				{
					PrintToChat(client, "%sSay \x04!team\x01 to choose a team.", TAG);
					lastMessage[client] = GetClientTime(client);
				}
				continue;
			}
			
			specTime[client] += checkInterval;
			if (((specTime[client] >= g_fTimeToKick) && !isIdle[client]) || ((specTime[client] >= (g_fIdleTimeMultiple * g_fTimeToKick)) && isIdle[client]))
			{
				KickClient(client, "%sYou were AFK for too long.. \x04Goodbye\x01!", TAG);
				if (g_iMessageLevel >= 2)
					PrintToChatAll("%sPlayer: \x04%N\x01 was kicked for being AFK too long.", TAG, client);
				
				continue;
			}
			
			if (((GetClientTime(client) - lastMessage[client]) >= g_fTimeLeftInterval) || ((GetClientTime(client) - lastMessage[client]) >= g_fTimerJoinMessage))
			{
				if ((GetClientTime(client) - lastMessage[client]) >= g_fTimeLeftInterval)
				{
					if (isIdle[client])
						PrintToChat(client, "%sYou can spectate for \x05%d\x01 more seconds before you will be kicked.", TAG, RoundToFloor((g_fIdleTimeMultiple * g_fTimeToKick) - specTime[client]));
					else
						PrintToChat(client, "%sYou can spectate for \x05%d\x01 more seconds before you will be kicked.", TAG, RoundToFloor(g_fTimeToKick - specTime[client]));
				}
				if ((GetClientTime(client) - lastMessage[client]) >= g_fTimerJoinMessage)
				{
					PrintToChat(client, "%sSay \x04!team\x01 to choose a team.", TAG);
				}
				lastMessage[client] = GetClientTime(client);
			}
		}
		else if (IsPlayerAlive(client) && (team == L4D_TEAM_SURVIVOR || team == L4D_TEAM_INFECTED))
		{
			GetClientAbsOrigin(client, currentPos);
			GetClientAbsAngles(client, currentAngles);
			
			isAFK = true;								// Assume everyone is afk and verify
			for (index = 0; index < 3; index++)
			{
				if (currentPos[index] != clientPos[client][index])			// Did the player move?
				{
					isAFK = false;
					isIdle[client] = false;
					break;
				}
				if (currentAngles[index] != clientAngles[client][index])	// Did the player look around?
				{
					isAFK = false;
					isIdle[client] = false;
					break;
				}
			}
			
			if (isAFK)
			{
				afkTime[client] += checkInterval;
				if (afkTime[client] >= g_fTimeToSpec)
				{
					ChangeClientTeam(client, L4D_TEAM_SPECTATOR);
					if (g_iMessageLevel == 1 || g_iMessageLevel == 3)
						PrintToChatAll("%sPlayer \x04%N\x01 was moved to the Spectator team.", TAG, client);
				}
			} else {
				afkTime[client] = 0.0;
			}
			
			for (index = 0; index < 3; index++)
			{
				clientPos[client][index] = currentPos[index];
				clientAngles[client][index] = currentAngles[index];
			}
		}
	}
	
	return Plugin_Continue;
}

public Action:timer_Advertise(Handle:timer)
{
	PrintToChatAll("%s%s", TAG, ads[adIndex++]);
	if(adIndex >= adCount) adIndex = 0;
	return Plugin_Continue;
}

GameModeCheck()
{
	
	GameMode = 0;
	new index;
	
	for (index=0; index < survivalCount; index++)
	{
		if (StrEqual(g_sGameMode, survival[index], false))
		{
			GameMode = 4;
			break;
		}
	}
	if (!GameMode)
	{
		for (index=0; index < scavengeCount; index++)
		{
			if (StrEqual(g_sGameMode, scavenge[index], false))
			{
				GameMode = 3;
				break;
			}
		}
	}
	if (!GameMode)
	{
		for (index=0; index < versusCount; index++)
		{
			if (StrEqual(g_sGameMode, versus[index], false))
			{
				GameMode = 2;
				break;
			}
		}
	}
	if (!GameMode)
	{
		for (index=0; index < coopCount; index++)
		{
			if (StrEqual(g_sGameMode, coop[index], false))
			{
				GameMode = 1;
				break;
			}
		}
	}
	if (!GameMode)
		SetFailState("[AFK Manager] Could detect Game Mode.");
}