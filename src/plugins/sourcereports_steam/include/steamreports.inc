#if defined _steamreports_included
	#endinput
#endif
#define _steamreports_included

enum EAccountState
{
	kLoggedOff = 0,
	kLoggingOn,
	kLoggedOn,
}

native SteamReports_Login(String:username[], String:password[]);
native SteamReports_Logout();
native EAccountState:SteamReports_IsLoggedIn();
native bool:SteamReports_SendMessage(String:steamid[], String:message[]);
native bool:SteamReports_AddFriend(String:steamid[]);

public Extension:__ext_steamreports =
{
	name = "SourceReports - Steam backend",
	file = "steamreports.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};