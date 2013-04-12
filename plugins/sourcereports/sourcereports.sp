#pragma semicolon 1

//////////////////////////////
//		DEFINITIONS			//
//////////////////////////////

#define PLUGIN_NAME "SourceReports"
#define PLUGIN_AUTHOR "Zephyrus"
#define PLUGIN_DESCRIPTION "An extensible player reporting API."
#define PLUGIN_VERSION "0.1"
#define PLUGIN_URL ""

#define MAX_LISTENERS 32
#define MAX_REASONS 64

//////////////////////////////
//			INCLUDES		//
//////////////////////////////

#include <sourcemod>
#include <sdktools>
#include <sourcereports>

#include <zephstocks>

//////////////////////////////
//			ENUMS			//
//////////////////////////////

enum Listener
{
	String:szIdentifier[64],
	Handle:hPlugin,
	Report:fnListener,
}

//////////////////////////////////
//		GLOBAL VARIABLES		//
//////////////////////////////////

new g_cvarCooldown = -1;
new g_cvarListenMagic = -1;
new g_cvarListenPort = -1;
new g_cvarMasterIP = -1;
new g_cvarMasterPort = -1;

new g_eListeners[MAX_LISTENERS][Listener];

new g_iListeners = 0;
new g_iReasons = 0;

new String:g_szReasons[MAX_REASONS][256];

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
	g_cvarCooldown = RegisterConVar("sm_sourcereports_cooldown", "60", "Cooldown in seconds between two reports from the same person.", TYPE_INT);
	g_cvarListenMagic = RegisterConVar("sm_sourcereports_listen_magic", "", "Magic code for the packets. In case this is a master server, make sure to set a code for security purposes.", TYPE_STRING);
	g_cvarListenPort = RegisterConVar("sm_sourcereports_listen_port", "", "Port to listen on to make this a master server for the reports.", TYPE_INT);
	g_cvarMasterIP = RegisterConVar("sm_sourcereports_master_ip", "", "IP of the master server. If master IP and port are set, this server will only act as a relay for the reports.", TYPE_STRING);
	g_cvarMasterPort = RegisterConVar("sm_sourcereports_master_ip", "", "Port of the master server. If master IP and port are set, this server will only act as a relay for the reports.", TYPE_STRING);

	LoadReasons();
	LoadRecipientsKV();

	LoadTranslations("sourcereports.phrases");

	RegConsoleCmd("sm_report", Command_Report);
	RegConsoleCmd("sm_calladmin", Command_Report);
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("SocketIsConnected");
	MarkNativeAsOptional("SocketCreate");
	MarkNativeAsOptional("SocketBind");
	MarkNativeAsOptional("SocketConnect");
	MarkNativeAsOptional("SocketDisconnect");
	MarkNativeAsOptional("SocketListen");
	MarkNativeAsOptional("SocketSend");
	MarkNativeAsOptional("SocketSendTo");
	MarkNativeAsOptional("SocketSetOption");
	MarkNativeAsOptional("SocketSetReceiveCallback");
	MarkNativeAsOptional("SocketSetSendqueueEmptyCallback");
	MarkNativeAsOptional("SocketSetDisconnectCallback");
	MarkNativeAsOptional("SocketSetErrorCallback");
	MarkNativeAsOptional("SocketSetArg");
	MarkNativeAsOptional("SocketGetHostName");

	CreateNative("SourceReports_AddListener", Native_AddListener);
	CreateNative("SourceReports_RemoveListener", Native_RemoveListener);

	return APLRes_Success;
} 

public OnConfigsExecuted()
{
}

//////////////////////////////
//			NATIVES			//
//////////////////////////////

public Native_AddListener(Handle:plugin, numParams)
{
	if(g_iListeners == MAX_LISTENERS)
		return false;
		
	decl String:m_szIdentifier[64];
	GetNativeString(1, STRING(m_szIdentifier));

	new m_iIdx = -1;
	for(new i=0;i<MAX_LISTENERS;++i)
		if(strcmp(g_eListeners[i][szIdentifier], m_szIdentifier)==0)
		{
			m_iIdx = i;
			break;
		}
	if(m_iIdx == -1)
		for(new i=0;i<MAX_LISTENERS;++i)
			if(g_eListeners[i][hPlugin] == INVALID_HANDLE)
			{
				m_iIdx = i;
				break;
			}

	g_eListeners[m_iIdx][hPlugin] = plugin;
	g_eListeners[m_iIdx][fnListener] = Report:GetNativeCell(2);
	strcopy(g_eListeners[m_iIdx][szIdentifier], 64, m_szIdentifier);

	++g_iListeners;

	return true;
}

public Native_RemoveListener(Handle:plugin, numParams)
{		
	decl String:m_szIdentifier[64];
	GetNativeString(1, STRING(m_szIdentifier));

	new m_iIdx = -1;
	for(new i=0;i<MAX_LISTENERS;++i)
		if(strcmp(g_eListeners[i][szIdentifier], m_szIdentifier)==0)
		{
			m_iIdx = i;
			break;
		}

	if(m_iIdx == -1)
		return false;

	g_eListeners[m_iIdx][hPlugin] = INVALID_HANDLE;
	g_eListeners[m_iIdx][fnListener] = Report:0;
	g_eListeners[m_iIdx][szIdentifier][0] = 0;

	--g_iListeners;

	return true;
}
//////////////////////////////////
//			COMMANDS	 		//
//////////////////////////////////

public Action:Command_Report(client, args)
{
	decl String:m_szSteamID[64];
	decl String:m_szMessage[256];

	GetCmdArg(1, m_szSteamID, 64);
	GetCmdArg(2, STRING(m_szMessage));

	new Handle:m_hSteamIDs = CreateArray(256);
	PushArrayString(m_hSteamIDs, m_szSteamID);

	Call_StartFunction(g_eListeners[0][hPlugin], g_eListeners[0][fnListener]);
	Call_PushCell(client);
	Call_PushCell(client);
	Call_PushCell(m_hSteamIDs);
	Call_PushString(m_szMessage);
	Call_Finish();

	CloseHandle(m_hSteamIDs);

	return Plugin_Handled;
}

//////////////////////////////////
//			HELPERS		 		//
//////////////////////////////////

public LoadReasons()
{
	decl String:m_szFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, STRING(m_szFile), "configs/sourcereports/reasons.txt");
	new Handle:m_hFile = OpenFile(m_szFile, "r");
	
	while(ReadFileLine(m_hFile, g_szReasons[g_iReasons], sizeof(g_szReasons[])))
		TrimString(g_szReasons[g_iReasons++]);

	CloseHandle(m_hFile);
}

public LoadRecipientsKV()
{

}