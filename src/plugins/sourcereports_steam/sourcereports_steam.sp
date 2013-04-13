#pragma semicolon 1

//////////////////////////////
//		DEFINITIONS			//
//////////////////////////////

#define PLUGIN_NAME "SourceReports - Steam backend"
#define PLUGIN_AUTHOR "Zephyrus"
#define PLUGIN_DESCRIPTION "Steam backend for SourceReports."
#define PLUGIN_VERSION "0.1"
#define PLUGIN_URL ""

//////////////////////////////
//			INCLUDES		//
//////////////////////////////

#include <sourcemod>
#include <sdktools>
#include <steamreports>
#include <sourcereports>

#include <zephstocks>

//////////////////////////////////
//		GLOBAL VARIABLES		//
//////////////////////////////////

new g_cvarUsername = -1;
new g_cvarPassword = -1;

//////////////////////////////////
//		PLUGIN DEFINITION		//
//////////////////////////////////

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

//////////////////////////////
//		PLUGIN FORWARDS		//
//////////////////////////////

public OnPluginStart()
{
	g_cvarUsername = RegisterConVar("sm_sourcereports_steam_username", "", "Username of the Steam account that should be logged in.", TYPE_STRING);
	g_cvarPassword = RegisterConVar("sm_sourcereports_steam_password", "", "Password of the Steam account that should be logged in.", TYPE_STRING);

	AutoExecConfig();

	SourceReports_AddListener("steam", SteamReports_Listener);
}

public OnPluginEnd()
{
	SourceReports_RemoveListener();
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("GetUserMessageType");
}

public OnConfigsExecuted()
{
	if(g_eCvars[g_cvarUsername][sCache][0] != 0 && g_eCvars[g_cvarPassword][sCache][0] != 0 && SteamReports_IsLoggedIn() == kLoggedOff)
	{
		SteamReports_Login(g_eCvars[g_cvarUsername][sCache], g_eCvars[g_cvarPassword][sCache]);
		CreateTimer(1.0, Timer_IsLoggedIn, TIMER_REPEAT);
	}
}

//////////////////////////////////
//			TIMERS	 			//
//////////////////////////////////

public Action:Timer_IsLoggedIn(Handle:client, any:data)
{
	new EAccountState:m_eState = SteamReports_IsLoggedIn();
	if(m_eState == kLoggedOn)
	{
		new Handle:m_hRecipients = SourceReports_GetRecipients();
		if(m_hRecipients != INVALID_HANDLE)
		{
			decl String:m_szSteamID[256];
			for(new i=0;i<GetArraySize(m_hRecipients);++i)
			{
				GetArrayString(m_hRecipients, i, STRING(m_szSteamID));
				SteamReports_AddFriend(m_szSteamID);
			}
		}
		return Plugin_Stop;
	} else if(m_eState == kLoggedOff)
		return Plugin_Stop;
	return Plugin_Continue;
}

//////////////////////////////////
//			LISTENER	 		//
//////////////////////////////////

public SteamReports_Listener(String:reporting_player[], String:reported_player[], Handle:receivers, String:message[])
{
	if(receivers == INVALID_HANDLE)
		return;

	decl String:m_szSteamID[256];
	for(new i=0;i<GetArraySize(receivers);++i)
	{
		GetArrayString(receivers, i, STRING(m_szSteamID));
		SteamReports_AddFriend(m_szSteamID);
		SteamReports_SendMessage(m_szSteamID, message);
	}
}