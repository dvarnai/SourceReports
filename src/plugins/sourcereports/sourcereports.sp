#pragma semicolon 1

//////////////////////////////
//		DEFINITIONS			//
//////////////////////////////

#define PLUGIN_NAME "SourceReports"
#define PLUGIN_AUTHOR "Zephyrus"
#define PLUGIN_DESCRIPTION "An extensible player reporting API."
#define PLUGIN_VERSION "0.1"
#define PLUGIN_URL ""

#define CHAT_TAG "[SourceReports] "

#define MAX_LISTENERS 32
#define MAX_REASONS 64

//////////////////////////////
//			INCLUDES		//
//////////////////////////////

#include <sourcemod>
#include <sdktools>
#include <sourcereports>

#include <zephstocks>

#if defined REQUIRE_EXTESIONS
#undef REQUIRE_EXTESIONS
#endif
#include <socket>

//////////////////////////////
//			ENUMS			//
//////////////////////////////

enum Listener
{
	String:szIdentifier[64],
	Handle:hPlugin,
	Report:fnListener,
	Handle:hRecipients,
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
new g_iCooldown[MAXPLAYERS+1] = {0,...};

new String:g_szSelection[MAXPLAYERS+1][96];
new String:g_szReasons[MAX_REASONS][256];
new String:g_szServerIP[32];

new Handle:g_hListenSocket = INVALID_HANDLE;
new Handle:g_hRelaySocket = INVALID_HANDLE;

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
	g_cvarListenMagic = RegisterConVar("sm_sourcereports_magic", "", "Magic code for the packets. In case this is a master or relay server it must be set and should be matching on both servers.", TYPE_STRING);
	g_cvarListenPort = RegisterConVar("sm_sourcereports_listen_port", "0", "Port to listen on to make this a master server for the reports.", TYPE_INT);
	g_cvarMasterIP = RegisterConVar("sm_sourcereports_master_ip", "", "IP of the master server. If master IP and port are set, this server will only act as a relay for the reports.", TYPE_STRING);
	g_cvarMasterPort = RegisterConVar("sm_sourcereports_master_port", "", "Port of the master server. If master IP and port are set, this server will only act as a relay for the reports.", TYPE_INT);
	AutoExecConfig();

	new Handle:m_hHostIP = FindConVar("hostip");
	new Handle:m_hHostPort = FindConVar("hostport");
	if(m_hHostIP == INVALID_HANDLE || m_hHostPort == INVALID_HANDLE)
		SetFailState("Failed to determine server ip and port.");
	new m_iServerPort = GetConVarInt(m_hHostPort);
	new m_iServerIP = GetConVarInt(m_hHostIP);
	Format(STRING(g_szServerIP), "%d.%d.%d.%d:%d", m_iServerIP >>> 24 & 255, m_iServerIP >>> 16 & 255, m_iServerIP >>> 8 & 255, m_iServerIP & 255, m_iServerPort);

	LoadReasons();

	LoadTranslations("sourcereports.phrases");

	RegConsoleCmd("sm_report", Command_Report);
	RegConsoleCmd("sm_calladmin", Command_Report);
}

public OnPluginEnd()
{
	if(g_hListenSocket != INVALID_HANDLE)
		CloseHandle(g_hListenSocket);
	if(g_hRelaySocket != INVALID_HANDLE)
		CloseHandle(g_hRelaySocket);
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("GetUserMessageType");
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
	CreateNative("SourceReports_GetRecipients", Native_GetRecipients);

	return APLRes_Success;
} 

public OnConfigsExecuted()
{
	if(GetExtensionFileStatus("socket.ext")!=1)
		return;

	if(g_eCvars[g_cvarListenPort][aCache] != 0 && g_eCvars[g_cvarListenMagic][sCache][0] != 0)
	{
		if(g_hListenSocket == INVALID_HANDLE)
			SetupMasterSocket();
	}
	else if(g_eCvars[g_cvarMasterIP][sCache][0] != 0 && g_eCvars[g_cvarMasterPort][aCache] != 0)
		if(g_hRelaySocket == INVALID_HANDLE)
			SetupRelaySocket();
}

//////////////////////////////
//		CLIENT FORWARDS		//
//////////////////////////////

public OnClientConnected(client)
{
	g_iCooldown[client] = 0;
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

	LoadRecipientsKV();

	return true;
}

public Native_RemoveListener(Handle:plugin, numParams)
{		
	new m_iIdx = -1;
	for(new i=0;i<MAX_LISTENERS;++i)
		if(g_eListeners[i][hPlugin] == plugin)
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

public Native_GetRecipients(Handle:plugin, numParams)
{
	new m_iIdx = -1;
	for(new i=0;i<MAX_LISTENERS;++i)
		if(g_eListeners[i][hPlugin] == plugin)
		{
			m_iIdx = i;
			break;
		}

	if(m_iIdx == -1)
		return 0;

	return _:g_eListeners[m_iIdx][hRecipients];
}

//////////////////////////////////
//			COMMANDS	 		//
//////////////////////////////////

public Action:Command_Report(client, args)
{
	if(g_iCooldown[client] > GetTime())
	{
		Chat(client, "%t", "Cooldown Active");
		return Plugin_Handled;
	}

	if(GetClientCount() == 1)
	{
		Chat(client, "%t", "Noone to report");
		return Plugin_Handled;
	}

	DisplayPlayerSelection(client);

	return Plugin_Handled;
}

//////////////////////////////
//			MENUS			//
//////////////////////////////

public DisplayPlayerSelection(client)
{
	new Handle:m_hMenu = CreateMenu(MenuHandler_PlayerSelection);
	SetMenuTitle(m_hMenu, "%t", "Player Selection Title");

	new String:m_szData[96];
	LoopIngamePlayers(i)
		if(client != i)
		{
			// In case the player leaves we save his name and SteamID
			GetClientAuthString(i, STRING(m_szData));
			new m_iLength = strlen(m_szData);
			m_szData[m_iLength] = ',';
			GetClientName(i, m_szData[m_iLength+1], sizeof(m_szData)-m_iLength+1);
			AddMenuItem(m_hMenu, m_szData, m_szData[m_iLength+1]);
		}

	DisplayMenu(m_hMenu, client, 0);
}

public DisplayReasonSelection(client)
{
	new Handle:m_hMenu = CreateMenu(MenuHandler_ReasonSelection);
	SetMenuTitle(m_hMenu, "%t", "Reason Selection Title");
	SetMenuExitBackButton(m_hMenu, true);

	for(new i=0;i<g_iReasons;++i)
		AddMenuItem(m_hMenu, g_szReasons[i], g_szReasons[i]);

	DisplayMenu(m_hMenu, client, 0);
}

public MenuHandler_PlayerSelection(Handle:menu, MenuAction:action, client, param2)
{
	if (action == MenuAction_End)
		CloseHandle(menu);
	else if (action == MenuAction_Select)
	{
		GetMenuItem(menu, param2, g_szSelection[client], sizeof(g_szSelection[]));
		DisplayReasonSelection(client);
	}
}

public MenuHandler_ReasonSelection(Handle:menu, MenuAction:action, client, param2)
{
	if (action == MenuAction_End)
		CloseHandle(menu);
	else if (action == MenuAction_Select)
	{		
		decl String:m_szTargetName[64];
		decl String:m_szTargetSteamID[32];
		decl String:m_szReason[256];
		GetMenuItem(menu, param2, STRING(m_szReason));
		new m_iIdx = FindCharInString(g_szSelection[client], ',');
		g_szSelection[client][m_iIdx] = 0;
		strcopy(STRING(m_szTargetSteamID), g_szSelection[client]);
		strcopy(STRING(m_szTargetName), g_szSelection[client][m_iIdx+1]);

		new String:m_szSteamID[32];
		decl String:m_szName[64];
		GetClientAuthString(client, STRING(m_szSteamID));
		GetClientName(client, STRING(m_szName));

		ReportPlayer(m_szName, m_szSteamID, m_szTargetName, m_szTargetSteamID, m_szReason, g_szServerIP);

		g_iCooldown[client] = GetTime()+g_eCvars[g_cvarCooldown][aCache];
		Chat(client, "%t", "Reported Player", m_szTargetName);
	}
	else if(action==MenuAction_Cancel)
		if (param2 == MenuCancel_ExitBack)
			DisplayPlayerSelection(client);
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
	decl String:m_szFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, STRING(m_szFile), "configs/sourcereports/recipients.txt");
	new Handle:m_hKV = CreateKeyValues("Recipients");
	FileToKeyValues(m_hKV, m_szFile);
	if(!KvGotoFirstSubKey(m_hKV))
		return 0;
	
	decl String:m_szIdentifier[64];
	decl String:m_szIdx[11];
	decl String:m_szRecipient[256];

	new m_iIdx = 1;
	new m_iListenerIdx = -1;
	new m_iRecipients = 0;
	do
	{
		m_iIdx = 1;
		KvGetSectionName(m_hKV, STRING(m_szIdentifier));
		for(new i=0;i<MAX_LISTENERS;++i)
			if(strcmp(g_eListeners[i][szIdentifier], m_szIdentifier)==0)
			{
				m_iListenerIdx = i;
				break;
			}
		if(m_iListenerIdx == -1)
			continue;

		if(g_eListeners[m_iListenerIdx][hRecipients] != INVALID_HANDLE)
			CloseHandle(g_eListeners[m_iListenerIdx][hRecipients]);
		g_eListeners[m_iListenerIdx][hRecipients] = CreateArray(256);

		m_szRecipient[0] = 1;
		while(m_szRecipient[0] != 0)
		{
			IntToString(m_iIdx++, STRING(m_szIdx));
			KvGetString(m_hKV, m_szIdx, STRING(m_szRecipient));
			if(m_szRecipient[0] == 0)
				break;
			PushArrayString(g_eListeners[m_iListenerIdx][hRecipients], m_szRecipient);
			++m_iRecipients;
		}
	} while (KvGotoNextKey(m_hKV));

	CloseHandle(m_hKV);

	return m_iRecipients;
}

public ReportPlayer(String:name[], String:steamid[], String:targetname[], String:targetsteamid[], String:reason[], String:ip[])
{
	if(g_hRelaySocket == INVALID_HANDLE)
	{
		decl String:m_szMessage[2048];
		Format(STRING(m_szMessage), "%t", "Report Message", targetname, targetsteamid, name, steamid, reason, ip);

		for(new i=0;i<MAX_LISTENERS;++i)
		{
			if(g_eListeners[i][hPlugin] == INVALID_HANDLE)
				continue;
			Call_StartFunction(g_eListeners[i][hPlugin], g_eListeners[i][fnListener]);
			Call_PushString(steamid);
			Call_PushString(targetsteamid);
			Call_PushCell(g_eListeners[i][hRecipients]);
			Call_PushString(m_szMessage);
			Call_Finish();
		}
	}
	else
	{
		new m_iLength = strlen(g_eCvars[g_cvarListenMagic][sCache])+480+7;
		new String:m_szPacket[m_iLength];
		new m_iIdx = 0;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, g_eCvars[g_cvarListenMagic][sCache])+1;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, ip)+1;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, name)+1;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, steamid)+1;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, targetname)+1;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, targetsteamid)+1;
		m_iIdx += strcopy(m_szPacket[m_iIdx], m_iLength-m_iIdx, reason)+1;
		SocketSend(g_hRelaySocket, m_szPacket, m_iIdx);
	}
}

//////////////////////////////
//			SOCKETS			//
//////////////////////////////

//////////////////////////////
//			MASTER			//
//////////////////////////////

public SetupMasterSocket()
{
	new Handle:m_hHostIP = FindConVar("hostip");
	new m_iServerIP = GetConVarInt(m_hHostIP);

	decl String:m_szServerIP[32];
	Format(STRING(m_szServerIP), "%d.%d.%d.%d", m_iServerIP >>> 24 & 255, m_iServerIP >>> 16 & 255, m_iServerIP >>> 8 & 255, m_iServerIP & 255);

	g_hListenSocket = SocketCreate(SOCKET_TCP, Master_SocketError);
	if(!SocketBind(g_hListenSocket, m_szServerIP, g_eCvars[g_cvarListenPort][aCache]))
	{
		LogError("[SourceReports] Failed to bind socket to %s:%d", m_szServerIP, g_eCvars[g_cvarListenPort][aCache]);
		CloseHandle(g_hListenSocket);
		return;
	}

	SocketListen(g_hListenSocket, Master_SocketIncoming);

	LogMessage("[SourceReports] Listening on %s:%d", m_szServerIP, g_eCvars[g_cvarListenPort][aCache]);
}

public Master_SocketIncoming(Handle:socket, Handle:newSocket, String:remoteIP[], remotePort, any:arg)
{
	SocketSetReceiveCallback(newSocket, Master_ChildSocketReceive);
	SocketSetDisconnectCallback(newSocket, Master_ChildSocketDisconnected);
	SocketSetErrorCallback(newSocket, Master_ChildSocketError);
}

public Master_ChildSocketReceive(Handle:socket, String:receiveData[], const dataSize, any:hFile)
{
	new m_iMagicLength = strlen(g_eCvars[g_cvarListenMagic][sCache]);
	if(dataSize < m_iMagicLength)
		return;
	if(strncmp(receiveData, g_eCvars[g_cvarListenMagic][sCache], m_iMagicLength)!=0)
		return;

	decl String:m_szRemoteIP[32];
	decl String:m_szTargetName[64];
	decl String:m_szTargetSteamID[32];
	decl String:m_szName[64];
	decl String:m_szSteamID[32];
	decl String:m_szReason[256];

	new m_iTerminators = 0;
	for(new i=m_iMagicLength;i<dataSize;++i)
		if(receiveData[i]==0)
			++m_iTerminators;

	if(m_iTerminators != 7)
		return;

	new m_iIdx = m_iMagicLength+1;

	strcopy(STRING(m_szRemoteIP), receiveData[m_iIdx]);
	m_iIdx += strlen(receiveData[m_iIdx])+1;
	strcopy(STRING(m_szName), receiveData[m_iIdx]);
	m_iIdx += strlen(receiveData[m_iIdx])+1;
	strcopy(STRING(m_szSteamID), receiveData[m_iIdx]);
	m_iIdx += strlen(receiveData[m_iIdx])+1;
	strcopy(STRING(m_szTargetName), receiveData[m_iIdx]);
	m_iIdx += strlen(receiveData[m_iIdx])+1;
	strcopy(STRING(m_szTargetSteamID), receiveData[m_iIdx]);
	m_iIdx += strlen(receiveData[m_iIdx])+1;
	strcopy(STRING(m_szReason), receiveData[m_iIdx]);
	m_iIdx += strlen(receiveData[m_iIdx])+1;

	ReportPlayer(m_szName, m_szSteamID, m_szTargetName, m_szTargetSteamID, m_szReason, m_szRemoteIP);
}

public Master_ChildSocketDisconnected(Handle:socket, any:hFile)
{
	CloseHandle(socket);
}

public Master_ChildSocketError(Handle:socket, const errorType, const errorNum, any:ary)
{
	LogError("[SourceReports] Relay server socket error %d (errno %d)", errorType, errorNum);
	CloseHandle(socket);
}

public Master_SocketError(Handle:socket, const errorType, const errorNum, any:data)
{
	LogError("[SourceReports] Master socket error %d (errno %d)", errorType, errorNum);
	g_hListenSocket = INVALID_HANDLE;
	CloseHandle(socket);
}

//////////////////////////////
//			RELAY			//
//////////////////////////////

public SetupRelaySocket()
{
	g_hRelaySocket = SocketCreate(SOCKET_TCP, Relay_SocketError);
	SocketConnect(g_hRelaySocket, Relay_SocketConnected, Relay_SocketReceive, Relay_SocketDisconnected, g_eCvars[g_cvarMasterIP][sCache], g_eCvars[g_cvarMasterPort][aCache]);
}

public Relay_SocketConnected(Handle:socket, any:data)
{
	LogMessage("[SourceReports] Relaying reports to %s:%d", g_eCvars[g_cvarMasterIP][sCache], g_eCvars[g_cvarMasterPort][aCache]);
}

public Relay_SocketReceive(Handle:socket, String:receiveData[], const dataSize, any:data)
{
}

public Relay_SocketDisconnected(Handle:socket, any:data)
{
	LogMessage("[SourceReports] Stopped relaying reports.");
	g_hRelaySocket = INVALID_HANDLE;
	CloseHandle(socket);

	CreateTimer(30.0, Relay_Reconnect, TIMER_REPEAT);
}

public Relay_SocketError(Handle:socket, const errorType, const errorNum, any:data)
{
	LogError("[SourceReports] Relay socket error %d (errno %d)", errorType, errorNum);
	g_hRelaySocket = INVALID_HANDLE;
	CloseHandle(socket);

	CreateTimer(30.0, Relay_Reconnect, TIMER_REPEAT);
}

public Action:Relay_Reconnect(Handle:timer, any:data)
{
	if(g_eCvars[g_cvarMasterIP][sCache][0] != 0 && g_eCvars[g_cvarMasterPort][aCache] != 0)
		if(g_hRelaySocket == INVALID_HANDLE)
			SetupRelaySocket();
	return Plugin_Stop;
}