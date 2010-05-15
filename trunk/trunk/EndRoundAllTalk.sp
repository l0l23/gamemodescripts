/*
 * This is basically the RoundAllTalk plugin with the start round stuff removed
 * it didn't work properly as it was, and its not worth fixing since I never used it.
 *test
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION 				"1.2"
#define ALLTALKMSG_TAG			"\x03[AllTalk]\x01"

new Handle:g_hAllTalkCvar;
new Handle:g_hTagsCvar;
new Handle:g_hEnable;
new Handle:g_hOverride;
new Handle:g_hUseSounds;
new Handle:g_hEndAllTalk;
new Handle:g_hEndAllTalk_Msg;
new Handle:g_hEndAllTalk_Time;
new Handle:g_hEndAllTalk_Sound;
new Handle:g_hStartAllTalk_Msg;
new Handle:g_hStartAllTalk_Sound;
new Float:g_fEndAllTalk_Time = 1.5;
new bool:g_bPluginChangedAllTalk = false;
new bool:g_bAdminChangedAllTalk = false;
new bool:isFirstRound;

public Plugin:myinfo = 
{
	name = "End-Round All-Talk",
	author = "Mr. Zero & Dirka_Dirka",
	description = "Enables All talk when the round ends.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=111666"
}

public OnPluginStart()
{
	g_hAllTalkCvar 			= FindConVar("sv_alltalk");
	g_hTagsCvar 			= FindConVar("sv_tags");
	g_hEnable				= CreateConVar("l4d_rat_enable","1","Sets whether the plugin is active or not.",FCVAR_PLUGIN);
	g_hOverride				= CreateConVar("l4d_rat_override","0","If an admin enables the all talk cvar (or another plugin), this plugin will not change the value unless permissions to override is given or value is changed back to false again.",FCVAR_PLUGIN);
	g_hUseSounds			= CreateConVar("l4d_rat_usesounds","1","Sets whether the plugin is using sounds or not (sounds are defined in the script).",FCVAR_PLUGIN);
	
	g_hEndAllTalk 			= CreateConVar("l4d_rat_endalltalk"			,"1","Toggles all talk on upon the end round event or after amount of time after the event.",FCVAR_PLUGIN);
	g_hEndAllTalk_Msg		= CreateConVar("l4d_rat_endalltalk_msg"		,"All-Talk Disabled!","Message to print to chat upon all talk ends.",FCVAR_PLUGIN);
	g_hEndAllTalk_Time 		= CreateConVar("l4d_rat_endalltalk_time"	,"1.5","Toggles all talk on after this amount of time upon the end round event (does nothing if endalltalk is false).",FCVAR_PLUGIN);
	g_hEndAllTalk_Sound		= CreateConVar("l4d_rat_endalltalk_sound"	,"ui/pickup_misc42.wav","Sound file to play upon all talk ends, relative to the sound folder.",FCVAR_PLUGIN);
	
	g_hStartAllTalk_Msg		= CreateConVar("l4d_rat_startalltalk_msg"	,"All-Talk Enabled!","Message to print to chat upon all talk starts.",FCVAR_PLUGIN);
	g_hStartAllTalk_Sound	= CreateConVar("l4d_rat_startalltalk_sound" ,"ui/menu_enter05.wav","Sound file to play upon all talk starts, relative to the sound folder.",FCVAR_PLUGIN);
	
	CreateConVar("l4d_rat_version",PLUGIN_VERSION,"Round All Talk Version",FCVAR_PLUGIN|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	AutoExecConfig(true,"RoundAllTalk");
	
	HookConVarChange(g_hAllTalkCvar,CvarChanged_AllTalk);
	HookConVarChange(g_hOverride,CvarChanged_AllTalk);
	HookConVarChange(g_hEndAllTalk_Time,CvarChanged_EndAllTalkTime);
	
	HookEvent("round_end",Event_RoundEnd);
	HookEvent("round_start",Event_RoundStart);
	HookEvent("player_left_start_area",Event_PlayerLeftStartArea);
	
	SetConVarFlags(g_hAllTalkCvar,(GetConVarFlags(g_hAllTalkCvar) & ~FCVAR_NOTIFY));
	SetConVarFlags(g_hTagsCvar,(GetConVarFlags(g_hTagsCvar) & ~FCVAR_NOTIFY));
}

public OnConfigsExecuted()
{
	decl String:sSound[128];

	GetConVarString(g_hStartAllTalk_Sound, sSound, 128);
	PrecacheSound(sSound);

	GetConVarString(g_hEndAllTalk_Sound, sSound, 128);
	PrecacheSound(sSound);
}

public OnPluginEnd()
{
	SetConVarFlags(g_hAllTalkCvar,(GetConVarFlags(g_hAllTalkCvar) & FCVAR_NOTIFY));
	SetConVarFlags(g_hTagsCvar,(GetConVarFlags(g_hTagsCvar) & FCVAR_NOTIFY));
}

public CvarChanged_AllTalk(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(g_bPluginChangedAllTalk)
	{
		g_bPluginChangedAllTalk = false;
		return;
	}
	
	if(GetConVarBool(g_hAllTalkCvar) && !GetConVarBool(g_hOverride))
	{
		g_bAdminChangedAllTalk = true;
	}
	else
	{
		g_bAdminChangedAllTalk = false;
	}
}

public CvarChanged_EndAllTalkTime(Handle:convar, const String:oldValue[], const String:newValue[]){g_fEndAllTalk_Time = StringToFloat(newValue);}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{	
	if(!GetConVarBool(g_hEndAllTalk)) { return; }

	if(g_fEndAllTalk_Time > 0.0)
	{
		CreateTimer(g_fEndAllTalk_Time,Timer_RoundEnd,INVALID_HANDLE,TIMER_FLAG_NO_MAPCHANGE);
		return;
	}
	else { SetAllTalk(true); }
}

public OnMapStart()
{
	isFirstRound = true;
	SetAllTalk(false);
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	SetAllTalk(false);
}

public Event_PlayerLeftStartArea(Handle:event, const String:name[], bool:dontBroadcast)
{
	SetAllTalk(false);
}

public Action:Timer_RoundEnd(Handle:timer){SetAllTalk(true);}

SetAllTalk(bool:enabled)
{
	decl String:sMsg[128];
	
	// If admin or another plugin have changed the all talk cvar or not enabled
	if(g_bAdminChangedAllTalk || !GetConVarBool(g_hEnable))
	{
		return;
	}

	// Else if all talk enables and is not already enabled
	else if(enabled && !GetConVarBool(g_hAllTalkCvar))
	{
		if (isFirstRound) {
			isFirstRound = false;
			
			if(GetConVarBool(g_hUseSounds))
			{
				decl String:sSoundFile[128];
				GetConVarString(g_hStartAllTalk_Sound,sSoundFile,128);
				EmitSoundToAll(sSoundFile);
			}
			GetConVarString(g_hStartAllTalk_Msg,sMsg,128);
		}
		else { return; }
	}

	// Else if all talk disables and is not already disabled
	else if(!enabled && GetConVarBool(g_hAllTalkCvar))
	{
		if(GetConVarBool(g_hUseSounds))
		{
			decl String:sSoundFile[128];
			GetConVarString(g_hEndAllTalk_Sound,sSoundFile,128);
			EmitSoundToAll(sSoundFile);
		}
		GetConVarString(g_hEndAllTalk_Msg,sMsg,128);
	}

	// else all talk state isn't changing
	else { return; }
	
	PrintToChatAll("%s %s",ALLTALKMSG_TAG,sMsg);
	g_bPluginChangedAllTalk = true;
	SetConVarBool(g_hAllTalkCvar,enabled);
}