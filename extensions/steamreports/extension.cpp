#include "extension.h"

SourceReports g_SourceReports;
SMEXT_LINK(&g_SourceReports);

CreateInterfaceFn g_pSteamFactory = 0;
GetCallbackFn g_pGetCallback = 0;
FreeLastCallbackFn g_pFreeLastCallback = 0;

HSteamPipe g_hPipe;
HSteamUser g_hUser;

IClientEngine *g_pSteamClient = 0;
IClientUser *g_pClientUser = 0;
IClientFriends *g_pClientFriends = 0;

volatile bool g_bLoginThreadRunning = false;

sp_nativeinfo_t g_Natives[] = 
{
	{"SteamReports_Login",			SteamReports_Login},
	{"SteamReports_Logout",			SteamReports_Logout},
	{"SteamReports_IsLoggedIn",		SteamReports_IsLoggedIn},
	{"SteamReports_SendMessage",	SteamReports_SendMessage},
	{"SteamReports_AddFriend",		SteamReports_AddFriend},
	{NULL,							NULL}
};

bool SourceReports::SDK_OnLoad(char * error, size_t maxlength, bool late)
{
	if(!GetSteamFactory())
	{
		snprintf(error, maxlength, "Failed to get Steam factory.");
		return false;
	}

	if(!GetSteamClient())
	{
		snprintf(error, maxlength, "Failed to get Steam client.");
		return false;
	}

	if(!CreateLocalUser())
	{
		snprintf(error, maxlength, "Failed to get local user.");
		return false;
	}

	if(!GetSteamInterfaces())
	{
		snprintf(error, maxlength, "Failed to get necessary Steam interfaces.");
		return false;
	}

	sharesys->AddNatives(myself, g_Natives);
	sharesys->RegisterLibrary(myself, "steamreports");

	return true;
}

void SourceReports::SDK_OnUnload()
{
	if(g_hUser && g_hPipe)
		g_pSteamClient->ReleaseUser(g_hPipe, g_hUser);
}

bool SourceReports::GetSteamFactory()
{
	LIB_POINTER m_pSteamclient = LIB_LOAD(g_szSteamLibrary);
	if(m_pSteamclient == 0)
		return false;
	g_pSteamFactory = reinterpret_cast<CreateInterfaceFn>(LIB_SYMBOL(m_pSteamclient, "CreateInterface"));
	if(g_pSteamFactory == 0)
		return false;
	g_pGetCallback = reinterpret_cast<GetCallbackFn>(LIB_SYMBOL(m_pSteamclient, "Steam_BGetCallback"));
	if(g_pGetCallback == 0)
		return false;
	g_pFreeLastCallback = reinterpret_cast<FreeLastCallbackFn>(LIB_SYMBOL(m_pSteamclient, "Steam_FreeLastCallback"));
	if(g_pFreeLastCallback == 0)
		return false;
	return true;
}

bool SourceReports::GetSteamClient()
{
	g_pSteamClient = reinterpret_cast<IClientEngine*>(g_pSteamFactory(CLIENTENGINE_INTERFACE_VERSION, 0));
	if(g_pSteamClient == 0)
		return false;
	return true;
}

bool SourceReports::CreateLocalUser()
{
	printf("**********************************************************************\n");
	printf("* [SourceReports] The upcoming lines are NORMAL, please ignore them. *\n");
	printf("**********************************************************************\n");
	g_hUser = g_pSteamClient->CreateLocalUser(&g_hPipe, k_EAccountTypeIndividual);
	printf("**********************************************************************\n");
	if(g_hUser == 0 || g_hPipe == 0)
		return false;
	return true;
}

bool SourceReports::GetSteamInterfaces()
{
	g_pClientUser = reinterpret_cast<IClientUser*>(g_pSteamClient->GetIClientUser(g_hUser, g_hPipe, CLIENTUSER_INTERFACE_VERSION));
	if(g_pClientUser == 0)
		return false;
	g_pClientFriends = reinterpret_cast<IClientFriends*>(g_pSteamClient->GetIClientFriends(g_hUser, g_hPipe, CLIENTFRIENDS_INTERFACE_VERSION));
	if(g_pClientFriends == 0)
		return false;
	return true;
}

void SourceReports::DoThreadedLogin(char * username, char * password)
{
	g_pClientUser->LogOnWithPassword(false, username, password);
#if defined _WIN32
	DWORD m_dwThreadID;
	CreateThread(NULL, 0, SourceReports_LoginThread, 0, 0, &m_dwThreadID);
#elif defined _LINUX
	pthread_t m_pThread;
	pthread_create(&m_pThread, NULL, &SourceReports_LoginThread, NULL);
#endif
}

#if defined _WIN32
DWORD WINAPI SourceReports_LoginThread(LPVOID lpParam)
#elif defined _LINUX
void * SourceReports_LoginThread(void * stack)
#endif
{
	g_bLoginThreadRunning = true;
	time_t m_iTimeout = time(0)+30;
	CallbackMsg_t m_eCallback;
	while(time(0) < m_iTimeout)
	{
		if(g_pGetCallback(g_hPipe, &m_eCallback))
		{
			g_pFreeLastCallback(g_hPipe);
			if(m_eCallback.m_iCallback == SteamServersConnected_t::k_iCallback)
			{
				g_pSM->LogMessage(myself, "Successfully logged in as %s\n", g_pClientFriends->GetPersonaName());
				g_pClientUser->SetSelfAsPrimaryChatDestination();
				g_pClientFriends->SetPersonaState(k_EPersonaStateOnline);
				break;
			}
			else if(m_eCallback.m_iCallback == SteamServerConnectFailure_t::k_iCallback)
			{
				g_pSM->LogError(myself, "Logging in to the specified account failed.");
				break;
			}
		}
#if defined _WIN32
		Sleep(10);
#elif defined _LINUX
		usleep(10);
#endif
	}
	g_bLoginThreadRunning = false;
	return 0;
}

static cell_t SteamReports_Login(IPluginContext *pContext, const cell_t *params)
{
	if(g_bLoginThreadRunning)
		return pContext->ThrowNativeError("An account is being logged in.");
	if(g_pClientUser->BLoggedOn())
		return pContext->ThrowNativeError("An account is already logged in.");

	char * m_szUsername;
	char * m_szPassword;
	pContext->LocalToString(params[1], &m_szUsername);
	pContext->LocalToString(params[2], &m_szPassword);

	g_SourceReports.DoThreadedLogin(m_szUsername, m_szPassword);

	return 0;
}

static cell_t SteamReports_Logout(IPluginContext *pContext, const cell_t *params)
{
	if(g_bLoginThreadRunning)
		return pContext->ThrowNativeError("An account is being logged in.");
	if(!g_pClientUser->BLoggedOn())
		return pContext->ThrowNativeError("There isn't any accounts logged in.");

	g_pClientUser->LogOff();

	return 0;
}

static cell_t SteamReports_IsLoggedIn(IPluginContext *pContext, const cell_t *params)
{
	if(g_bLoginThreadRunning)
		return pContext->ThrowNativeError("An account is being logged in.");

	return g_pClientUser->BLoggedOn();
}

static cell_t SteamReports_SendMessage(IPluginContext *pContext, const cell_t *params)
{
	if(g_bLoginThreadRunning)
		return pContext->ThrowNativeError("An account is being logged in.");
	if(!g_pClientUser->BLoggedOn())
		return pContext->ThrowNativeError("There isn't any accounts logged in.");

	char * m_szSteamID;
	char * m_szMessage;
	pContext->LocalToString(params[1], &m_szSteamID);
	pContext->LocalToString(params[2], &m_szMessage);

	uint64 m_iCommunityID = 76561197960265728ULL + 2*atoi(m_szSteamID+10) + (m_szSteamID[8]-48);
	CSteamID m_hSteamID(m_iCommunityID);

	if(g_pClientFriends->GetFriendPersonaState(m_hSteamID) != k_EPersonaStateOffline)
	{
		g_pClientFriends->SendMsgToFriend(m_hSteamID, k_EChatEntryTypeChatMsg, m_szMessage, strlen(m_szMessage)+1);
		return 1;
	}

	return 0;
}

static cell_t SteamReports_AddFriend(IPluginContext *pContext, const cell_t *params)
{
	if(g_bLoginThreadRunning)
		return pContext->ThrowNativeError("An account is being logged in.");
	if(!g_pClientUser->BLoggedOn())
		return pContext->ThrowNativeError("There isn't any accounts logged in.");

	char * m_szSteamID;
	pContext->LocalToString(params[1], &m_szSteamID);

	uint64 m_iCommunityID = 76561197960265728ULL + 2*atoi(m_szSteamID+10) + (m_szSteamID[8]-48);
	CSteamID m_hSteamID(m_iCommunityID);

	if(g_pClientFriends->GetFriendRelationship(m_hSteamID) != k_EFriendRelationshipFriend)
		return g_pClientFriends->AddFriend(m_hSteamID);

	return 0;
}