#if defined _sourcereports_included
	#endinput
#endif
#define _sourcereports_included

funcenum Report
{
	public(client, String:reported_player[], Handle:receivers, String:message[])
}

native SourceReports_AddListener(String:identifier[], Report:listener);
native SourceReports_RemoveListener();

public SharedPlugin:_pl_sourcereports = 
{
	name = "SourceReports",
	file = "sourcereports.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};