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
	g_cvarUsername = RegisterConVar("sm_sourcereports_steam_username", "focus591", "Username of the Steam account that should be logged in.", TYPE_STRING);
	g_cvarPassword = RegisterConVar("sm_sourcereports_steam_password", "iddqdiddqd", "Password of the Steam account that should be logged in.", TYPE_STRING);

	RegConsoleCmd("sm_sourcereports_reload", Command_Reload);

	SourceReports_AddListener("steam", SteamReports_Listener);
}

public OnPluginEnd()
{
	SourceReports_RemoveListener();
}

public OnConfigsExecuted()
{
	if(g_eCvars[g_cvarUsername][sCache][0] != 0 && g_eCvars[g_cvarPassword][sCache][0] != 0 && !SteamReports_IsLoggedIn())
		SteamReports_Login(g_eCvars[g_cvarUsername][sCache], g_eCvars[g_cvarPassword][sCache]);
}

//////////////////////////////////
//			COMMANDS	 		//
//////////////////////////////////

public Action:Command_Reload(client, args)
{
	if(client != 0)
		return Plugin_Continue;

	if(SteamReports_IsLoggedIn())
		SteamReports_Logout();
	SteamReports_Login(g_eCvars[g_cvarUsername][sCache], g_eCvars[g_cvarPassword][sCache]);

	return Plugin_Handled;
}

//////////////////////////////////
//			LISTENER	 		//
//////////////////////////////////

public SteamReports_Listener(client, String:reported_player[], Handle:receivers, String:message[])
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