/**
 * vim: set ts=4 :
 * =============================================================================
 * Nominations Extended
 * Allows players to nominate maps for Mapchooser
 *
 * Nominations Extended (C)2012-2013 Powerlord (Ross Bemrose)
 * SourceMod (C)2004-2007 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include <sourcemod>
#include <mapchooser>
#include "include/mapchooser_extended"
#pragma newdecls required
#pragma semicolon 1

#define MCE_VERSION "1.31.0"

public Plugin myinfo = {
	name = "Map Nominations Extended",
	author = "Powerlord, JoinedSenses and AlliedModders LLC",
	description = "Provides Map Nominations",
	version = MCE_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
};

ConVar g_Cvar_ExcludeOld = null;
ConVar g_Cvar_ExcludeCurrent = null;

ArrayList g_MapList = null;
Menu g_MapMenu = null;
int g_mapFileSerial = -1;

#define MAPSTATUS_ENABLED (1<<0)
#define MAPSTATUS_DISABLED (1<<1)
#define MAPSTATUS_EXCLUDE_CURRENT (1<<2)
#define MAPSTATUS_EXCLUDE_PREVIOUS (1<<3)
#define MAPSTATUS_EXCLUDE_NOMINATED (1<<4)

StringMap g_mapTrie;

// Nominations Extended Convars
ConVar g_Cvar_MarkCustomMaps = null;

public void OnPluginStart() {
	LoadTranslations("common.phrases");
	LoadTranslations("nominations.phrases");
	// for Next Map phrase
	LoadTranslations("basetriggers.phrases");
	LoadTranslations("mapchooser_extended.phrases");

	g_MapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	g_Cvar_ExcludeOld = CreateConVar("sm_nominate_excludeold", "1", "Specifies if the current map should be excluded from the Nominations list", 0, true, 0.00, true, 1.0);
	g_Cvar_ExcludeCurrent = CreateConVar("sm_nominate_excludecurrent", "1", "Specifies if the MapChooser excluded maps should also be excluded from Nominations", 0, true, 0.00, true, 1.0);

	RegConsoleCmd("sm_nominate", Command_Nominate);
	RegConsoleCmd("sm_nom", Command_Nominate);

	RegAdminCmd("sm_nominate_addmap", Command_Addmap, ADMFLAG_CHANGEMAP, "sm_nominate_addmap <mapname> - Forces a map to be on the next mapvote.");

	// Nominations Extended cvars
	CreateConVar("ne_version", MCE_VERSION, "Nominations Extended Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);


	g_mapTrie = new StringMap();
}

public void OnAllPluginsLoaded() {
	// This is an MCE cvar... this plugin requires MCE to be loaded.  Granted, this plugin SHOULD have an MCE dependency.
	g_Cvar_MarkCustomMaps = FindConVar("mce_markcustommaps");
}

public void OnConfigsExecuted() {
	if (ReadMapList(g_MapList, g_mapFileSerial, "nominations", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) == null) {
		if (g_mapFileSerial == -1) {
			SetFailState("Unable to create a valid map list.");
		}
	}

	BuildMapMenu();
}

public void OnNominationRemoved(const char[] map, int owner) {
	int status;

	/* Is the map in our list? */
	if (!g_mapTrie.GetValue(map, status)) {
		return;
	}

	/* Was the map disabled due to being nominated */
	if ((status & MAPSTATUS_EXCLUDE_NOMINATED) != MAPSTATUS_EXCLUDE_NOMINATED) {
		return;
	}

	g_mapTrie.SetValue(map, MAPSTATUS_ENABLED);
}

public Action Command_Addmap(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "\x01[\x03NE\x01] Usage: sm_nominate_addmap <mapname>");
		return Plugin_Handled;
	}

	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));


	int status;
	if (!g_mapTrie.GetValue(mapname, status)) {
		ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map was not found", mapname);
		return Plugin_Handled;
	}

	NominateResult result = NominateMap(mapname, true, 0);

	if (result > Nominate_Replaced) {
		/* We assume already in vote is the casue because the maplist does a Map Validity check and we forced, so it can't be full */
		ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map Already In Vote", mapname);

		return Plugin_Handled;
	}


	g_mapTrie.SetValue(mapname, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);


	ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map Inserted", mapname);
	LogAction(client, -1, "\"%L\" inserted map \"%s\".", client, mapname);

	return Plugin_Handled;
}

public Action Command_Nominate(int client, int args) {
	if (!client || !IsNominateAllowed(client)) {
		return Plugin_Handled;
	}

	if (args == 0) {
		DisplayMapMenu(client);
		return Plugin_Handled;
	}

	char mapName[PLATFORM_MAX_PATH];
	char mapResult[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapName, sizeof(mapName));

	if (0 < strlen(mapName) < 3) {
		ReplyToCommand(client, "\x01[\x03NE\x01] Please specify more than 2 characters");
		return Plugin_Handled;
	}

	ArrayList results = new ArrayList();
	int matches = FindMatchingMaps(g_MapList, results, mapName);

	if (matches <= 0) {
		ReplyToCommand(client, "\x01[\x03NE\x01] No nomination match");
	}

	else if (matches > 1) {
		// Display results to the client and end
		Menu menu = new Menu(MapList_MenuHandler);
		menu.SetTitle("Select map");
		
		for (int i = 0; i < results.Length; i++) {
			g_MapList.GetString(results.Get(i), mapResult, sizeof(mapResult));
			menu.AddItem(mapResult, mapResult);
		}

		menu.Display(client, MENU_TIME_FOREVER);
		ReplyToCommand(client, "\x01[\x03NE\x01] Found multiple matches");
	}
		// One result
	else if (matches == 1) {
		// Get the result and nominate it
		g_MapList.GetString(results.Get(0), mapResult, sizeof(mapResult));
		AttemptNominate(client, mapResult);
	}

	delete results;

	return Plugin_Handled;
}

void AttemptNominate(int client, const char[] mapName) {
	char unused[96];
	int status;
	if (FindMap(mapName, unused, sizeof(unused)) == FindMap_NotFound) {
		ReplyToCommand(client, "\x01[\x03NE\x01] Map was not found", mapName);
		return;
	}
	if (!g_mapTrie.GetValue(mapName, status)) {
		ReplyToCommand(client,"\x01[\x03NE\x01] Map %s is not in the mapcycle.", mapName);
		return;
	}

	if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED) {
		if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT) {
			ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Can't Nominate Current Map");
		}

		if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS) {
			ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map in Exclude List");
		}

		if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED) {
			ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map Already Nominated");
		}

		return;
	}

	NominateResult result = NominateMap(mapName, false, client);

	if (result > Nominate_Replaced) {
		if (result == Nominate_AlreadyInVote) {
			ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map Already In Vote", mapName);
		}
		else {
			ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Map Already Nominated");
		}

		return;
	}

	/* Map was nominated! - Disable the menu item and update the trie */

	g_mapTrie.SetValue(mapName, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	PrintToChatAll("\x01[\x03NE\x01] %t", "Map Nominated", name, mapName);
	LogMessage("%s nominated %s", name, mapName);
}

void DisplayMapMenu(int client) {
	g_MapMenu.SetTitle("%T", "Nominate Title", client);
	g_MapMenu.Display(client, MENU_TIME_FOREVER);
}	

void BuildMapMenu() {
	delete g_MapMenu;

	g_mapTrie.Clear();

	g_MapMenu = new Menu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);

	char map[PLATFORM_MAX_PATH];

	ArrayList excludeMaps = null;
	char currentMap[32];

	if (g_Cvar_ExcludeOld.BoolValue) {
		excludeMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		GetExcludeMapList(excludeMaps);
	}

	if (g_Cvar_ExcludeCurrent.BoolValue) {
		GetCurrentMap(currentMap, sizeof(currentMap));
	}


	for (int i = 0; i < g_MapList.Length; i++) {
		int status = MAPSTATUS_ENABLED;

		g_MapList.GetString(i, map, sizeof(map));

		if (g_Cvar_ExcludeCurrent.BoolValue) {
			if (StrEqual(map, currentMap)) {
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_CURRENT;
			}
		}

		/* Dont bother with this check if the current map check passed */
		if (g_Cvar_ExcludeOld.BoolValue && status == MAPSTATUS_ENABLED) {
			if (excludeMaps.FindString(map) != -1) {
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_PREVIOUS;
			}
		}

		g_MapMenu.AddItem(map, map);
		g_mapTrie.SetValue(map, status);
	}

	g_MapMenu.ExitButton = true;

	if (excludeMaps != null) {
		delete excludeMaps;
	}
}

int MapList_MenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char mapName[96];
			// Get the map name and attempt to nominate it
			menu.GetItem(param2, mapName, sizeof(mapName));
			AttemptNominate(param1, mapName);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack){
				// Return to previous menu if selection == exitback
				DisplayMapMenu(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

public int Handler_MapSelectMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char map[PLATFORM_MAX_PATH];
			char name[MAX_NAME_LENGTH];
			menu.GetItem(param2, map, sizeof(map));

			GetClientName(param1, name, MAX_NAME_LENGTH);

			NominateResult result = NominateMap(map, false, param1);

			/* Don't need to check for InvalidMap because the menu did that already */
			if (result == Nominate_AlreadyInVote) {
				PrintToChat(param1, "\x01[\x03NE\x01] %t", "Map Already Nominated");
				return 0;
			}
			else if (result == Nominate_VoteFull) {
				PrintToChat(param1, "\x01[\x03NE\x01] %t", "Max Nominations");
				return 0;
			}

			g_mapTrie.SetValue(map, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

			if (result == Nominate_Replaced) {
				PrintToChatAll("\x01[\x03NE\x01] %t", "Map Nomination Changed", name, map);
				return 0;
			}

			PrintToChatAll("\x01[\x03NE\x01] %t", "Map Nominated", name, map);
			LogMessage("%s nominated %s", name, map);
		}

		case MenuAction_DrawItem: {
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));

			int status;

			if (!g_mapTrie.GetValue(map, status)) {
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return ITEMDRAW_DEFAULT;
			}

			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED) {
				return ITEMDRAW_DISABLED;
			}

			return ITEMDRAW_DEFAULT;

		}

		case MenuAction_DisplayItem: {
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));

			int mark = g_Cvar_MarkCustomMaps.IntValue;
			bool official;

			int status;

			if (!g_mapTrie.GetValue(map, status)) {
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return 0;
			}

			char buffer[100];
			char display[150];

			if (mark) {
				official = IsMapOfficial(map);
			}

			if (mark && !official) {
				switch (mark) {
					case 1: {
						Format(buffer, sizeof(buffer), "%T", "Custom Marked", param1, map);
					}

					case 2: {
						Format(buffer, sizeof(buffer), "%T", "Custom", param1, map);
					}
				}
			}
			else {
				strcopy(buffer, sizeof(buffer), map);
			}

			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED) {
				if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT) {
					Format(display, sizeof(display), "%s (%T)", buffer, "Current Map", param1);
					return RedrawMenuItem(display);
				}

				if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS) {
					Format(display, sizeof(display), "%s (%T)", buffer, "Recently Played", param1);
					return RedrawMenuItem(display);
				}

				if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED) {
					Format(display, sizeof(display), "%s (%T)", buffer, "Nominated", param1);
					return RedrawMenuItem(display);
				}
			}

			if (mark && !official) {
				return RedrawMenuItem(buffer);
			}

			return 0;
		}
	}

	return 0;
}

stock bool IsNominateAllowed(int client) {
	CanNominateResult result = CanNominate();

	switch(result) {
		case CanNominate_No_VoteInProgress: {
			ReplyToCommand(client, "\x01[\x03ME\x01] %t", "Nextmap Voting Started");
			return false;
		}

		case CanNominate_No_VoteComplete: {
			char map[PLATFORM_MAX_PATH];
			GetNextMap(map, sizeof(map));
			ReplyToCommand(client, "\x01[\x03NE\x01] %t", "Next Map", map);
			return false;
		}

		case CanNominate_No_VoteFull: {
			ReplyToCommand(client, "\x01[\x03ME\x01] %t", "Max Nominations");
			return false;
		}
	}

	return true;
}

int FindMatchingMaps(ArrayList mapList, ArrayList results, const char[] input){
	int map_count = mapList.Length;

	if (!map_count) {
		return -1;
	}

	int matches = 0;
	char map[PLATFORM_MAX_PATH];

	for (int i = 0; i < map_count; i++) {
		mapList.GetString(i, map, sizeof(map));
		if (StrContains(map, input, false) != -1) {
			results.Push(i);
			matches++;

			if (matches >= 14) {
				break;
			}
		}
	}

	return matches;
}