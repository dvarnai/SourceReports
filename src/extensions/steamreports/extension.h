#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include "smsdk_ext.h"

#define STEAMWORKS_CLIENT_INTERFACES
#include "IClientFriends.h"
#include <Steamworks.h>

typedef bool (*GetCallbackFn)(HSteamPipe hSteamPipe, CallbackMsg_t *pCallbackMsg);
typedef void (*FreeLastCallbackFn)(HSteamPipe hSteamPipe);

#if defined _WIN32
#include <Windows.h>

#define LIB_LOAD(x) GetModuleHandle(x)
#define LIB_SYMBOL(x, y) GetProcAddress(x, y)
#define LIB_POINTER HMODULE

const char g_szSteamLibrary[] = "steamclient.dll";
#elif defined _LINUX
#include <stdlib.h>
#include <pthread.h>
#include <dlfcn.h>

#define LIB_LOAD(x) dlopen(x, RTLD_LAZY)
#define LIB_SYMBOL(x, y) dlsym(x, y)
#define LIB_POINTER void *

const char g_szSteamLibrary[] = "steamclient.so";
#endif

#if defined _WIN32
DWORD WINAPI SourceReports_LoginThread(LPVOID lpParam);
#elif defined _LINUX
void * SourceReports_LoginThread(void * stack);
#endif

static cell_t SteamReports_Login(IPluginContext *pContext, const cell_t *params);
static cell_t SteamReports_Logout(IPluginContext *pContext, const cell_t *params);
static cell_t SteamReports_IsLoggedIn(IPluginContext *pContext, const cell_t *params);
static cell_t SteamReports_SendMessage(IPluginContext *pContext, const cell_t *params);
static cell_t SteamReports_AddFriend(IPluginContext *pContext, const cell_t *params);

class SourceReports : public SDKExtension
{
public:
	virtual bool SDK_OnLoad(char * error, size_t maxlength, bool late);
	virtual void SDK_OnUnload();
public:
	bool GetSteamFactory();
	bool GetSteamClient();
	bool CreateLocalUser();
	bool GetSteamInterfaces();
	void DoThreadedLogin(char * username, char * password);
};

#endif
