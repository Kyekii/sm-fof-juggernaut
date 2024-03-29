/*
* Juggernaut Mode, a custom gamemode for Fistful of Frags
* Started 21 Dec 2021
* 
* Created by Kyeki, with (most) code from CrimsonTautology's Fistful of Zombies mode
* https://github.com/CrimsonTautology/sm-fistful-of-zombies
*
* GPL-3.0
*/

#include <sourcemod>
#include <steamworks>
#include <sdktools>
#include <sdkhooks>
#include <entity>
#include <smlib/clients>
#include <smlib/teams>
#include <smlib/entities>
#include <smlib/weapons>

#define TEAM_HUMAN 2
#define INFO_PLAYER_HUMAN "info_player_vigilante"
#define ON_NO_HUMAN_ALIVE "OnNoVigAlive"
#define INPUT_HUMAN_VICTORY "InputVigVictory"
#define TEAM_JUGGERNAUT 3 
#define INFO_PLAYER_JUGGERNAUT "info_player_desperado"
#define ON_NO_JUGGERNAUT_ALIVE "OnNoDespAlive"
#define INPUT_JUGGERNAUT_VICTORY "InputDespVictory"
// these teams are the default Teamplay teams, changing the juggernaut to a bandido is only cosmetic (and funny)

ConVar g_RoundTimeCvar;
ConVar g_isEnabledCvar;
ConVar g_CfgCvar;
ConVar g_ScaleDamage;
ConVar g_ScaleOverride;
ConVar g_MedicRatio;
ConVar g_JuggernautSpeed;
ConVar g_JuggernautRage;
ConVar g_JuggernautPicker;
ConVar g_BeaconTime;

Handle h_DeathBeacon;

ConVar g_TeambalanceAllowedCvar;
ConVar g_TeamsUnbalanceLimitCvar;
ConVar g_AutoteambalanceCvar;

KeyValues g_GearPrimaryTable;
int g_GearPrimaryTotalWeight;
KeyValues g_GearSecondaryTable;
int g_GearSecondaryTotalWeight;
KeyValues g_JuggernautPrimaryTable;
int g_JuggernautPrimaryTotalWeight;
KeyValues g_JuggernautSecondaryTable;
int g_JuggernautSecondaryTotalWeight;
KeyValues g_LootTable;
int g_LootTotalWeight;

bool JuggernautBeacon = false;
int AlreadyJuggernaut[MAXPLAYERS+1] = {0, ...};
Handle JuggernautPicks;
Handle MedicPicks;
int AlreadyJuggernautIndex = 0;
int CurrentJuggernautId;
int DeathTime;

bool InGrace = false;

bool g_AutoSetGameDescription = false;
int g_VigilanteModelIndex;
int g_BandidoModelIndex;

int g_BeamSprite = -1;
int g_HaloSprite = -1;

int g_TeamplayEntity = INVALID_ENT_REFERENCE;

public Plugin myinfo =
{
	name = "Juggernaut",
	author = "Kyeki",
	description = "Juggernaut gamemode for Fistful of Frags",
	version = "1.13",
	url = "https://github.com/Kyekii/sm-fof-juggernaut"
};

public void OnPluginStart()
{
	g_isEnabledCvar = CreateConVar("jm_enabled", "1", "Whether Juggernaut Mode is on or not.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_BeaconTime = CreateConVar("jm_beacontime", "30", "Time it takes from the round starts until the Juggernaut's beacon is enabled.", FCVAR_NOTIFY, true, 0.0); 
	g_CfgCvar = CreateConVar("jm_config", "configs/juggernaut_cfg.txt", "Location of the Juggernaut config file.", 0);
	g_MedicRatio = CreateConVar("jm_medics", "0.50", "Percentage of players on the human side that will receive whiskey along with their weapons.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_JuggernautRage = CreateConVar("jm_rage", "1", "Whether the Juggernaut's speed will scale with health.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_JuggernautPicker = CreateConVar("jm_random", "0", "Whether the chosen Juggernaut is pure random, or randomly permutated. (everyone gets to be Juggernaut at least once)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_ScaleDamage = CreateConVar("jm_ratio_dynamic", "1.0", "Turns on or off scaling damage reduction for the Juggernaut based on player count.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_ScaleOverride = CreateConVar("jm_ratio_override", "0.25", "Static rate of the Juggernaut's damage reduction if jm_ratio_dynamic is set to 0.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_RoundTimeCvar = CreateConVar("jm_round_time", "180", "How many seconds are in a round.", FCVAR_NOTIFY, true, 0.0);
	g_JuggernautSpeed = CreateConVar("jm_speed", "150.0", "Movement speed, in Hammer units/second, that the Juggernaut will spawn with.", FCVAR_NOTIFY, true, 0.0, false);
	
	RegAdminCmd("jm_reload", Command_Reload, ADMFLAG_CONFIG, "Force a reload of the Juggernaut config file.");
	RegAdminCmd("jm_dump", Command_Dump, ADMFLAG_CONFIG, "Dump the Juggernaut array and other miscellaneous debug information.");
	
	g_TeambalanceAllowedCvar = FindConVar("fof_sv_teambalance_allowed");
	g_TeamsUnbalanceLimitCvar = FindConVar("mp_teams_unbalance_limit");
	g_AutoteambalanceCvar = FindConVar("mp_autoteambalance");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_activate", Event_Announce);
	HookEvent("player_spawn", Event_Spawn);
	HookEvent("player_death", Event_Death);
	
	AddNormalSoundHook(SoundReplace);

	JuggernautPicks = CreateArray(1, 0);
	MedicPicks = CreateArray(1, 0);
}

Action Command_Reload(int caller, int args)
{
	InitializeJuggernautMode();
	return Plugin_Handled;
}

Action Command_Dump(int caller, int args)
{
	PrintToServer("[JUGGERNAUT DUMP - %.3f] Started dump", GetGameTime());
	if (GetArraySize(MedicPicks) != 0)
	{
		for (new p = 0; p <= GetArraySize(MedicPicks)-1; p++)
		{
			if (IsClientInGame(GetArrayCell(MedicPicks, p)) && GetArrayCell(MedicPicks, p) != 0)
			{
				PrintToServer("[JUGGERNAUT DUMP - %.3f] Non-Medic survivors: %i - %N", GetGameTime(), p, GetArrayCell(MedicPicks, p));
			}
			else continue;
		}
	}

	int juggernaut = GetClientOfUserId(CurrentJuggernautId)
	if (juggernaut != 0)
	{
		PrintToServer("[JUGGERNAUT DUMP - %.3f] Current juggernaut: %i - %N", GetGameTime(), juggernaut, juggernaut);
	}

	for (new i = 0; i <= MaxClients; i++)
	{
		int tmp = GetClientOfUserId(AlreadyJuggernaut[i]);
		if (AlreadyJuggernaut[i] == 0 || tmp == 0)
		{
			continue;
		}
		else (IsClientInGame(tmp))
		{
			PrintToServer("[JUGGERNAUT DUMP - %.3f] AlreadyJuggernautIndex %i, AlreadyJuggernaut: id %i, client index %i - %N", GetGameTime(), i, AlreadyJuggernaut[i], tmp, tmp);
		}
	}
	return Plugin_Handled;
} 

public Action:Hook_PreThinkPost(int client)
{
	if (IsClientInGame(client) && isJuggernaut(client) && isEnabled())
    {
		float slowdown = GetConVarFloat(g_JuggernautSpeed);
		float interval = (235.0 - slowdown) / 75
		if ((GetClientHealth(client) < 100) && (GetConVarBool(g_JuggernautRage)))
		{
			slowdown = slowdown + interval * (100 - GetClientHealth(client));
			if (GetClientHealth(client) <= 25)
			{
				slowdown = 235.0
			}
		}
		SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", slowdown);
    }
}

Action Hook_OnWeaponCanUse(int client, int weapon)
{
	if (isJuggernaut(client) && isEnabled())
	{
		char item[32];
		GetEntityClassname(weapon, item, sizeof(item));
		if (StrEqual(item, "weapon_whiskey"))
		{
			PrintToChat(client, "The juggernaut can't use whiskey!");
		}
		// melee increases run speed and would not be the most fair as juggernaut
		if (StrEqual(item, "weapon_axe") || StrEqual(item, "weapon_machete") || StrEqual(item, "weapon_knife"))
		{
			PrintToChat(client, "The juggernaut can't use melee weapons!");
		}
	}
	return Plugin_Continue;
}

public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if (isEnabled() && isJuggernaut(victim)) 
	{
		int players = GetClientCount(false);	
		float ratio = 0.25
		if (players > 1 && GetConVarBool(g_ScaleDamage) == true)
		{
			ratio = ratio - float(players) * 0.02
			if (ratio <= 0.05)
			{
				ratio = 0.05
			}
		}

		if (GetConVarBool(g_ScaleDamage) != true)
		{
			ratio = GetConVarFloat(g_ScaleOverride);
		}

		if (damagetype != (1 << 14)) // juggernauts take full damage from drowning (insta-kill water hazards like on robertlee)
		{
			damage = damage * ratio; 
		}
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

Action SoundReplace(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if ((0 < entity <= MaxClients) && isEnabled())
	{
		if (isJuggernaut(entity))
		{
			if (StrContains(sample, "npc/mexican") != -1 || StrContains(sample, "player/voice") != -1)
			{
				Format(sample, sizeof(sample), "npc/mexican/andale-0%i.wav", GetRandomInt(1, 7));
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

Action Timer_Repeat(Handle timer)
{
	if (!isEnabled()) return Plugin_Continue;
	if (g_AutoSetGameDescription)
	{
		SetGameDescription("Juggernaut");
		g_AutoSetGameDescription = false;
	}
	RoundEndCheck();
	if (Team_GetClientCount(TEAM_JUGGERNAUT, CLIENTFILTER_ALIVE) > 1)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == TEAM_JUGGERNAUT)
			{
				if (GetClientUserId(i) != CurrentJuggernautId)
				{
					ChangeClientTeam(i, TEAM_HUMAN);
				}
			}
		}
	} 
	return Plugin_Handled;
}

Action Timer_GiveWhiskey(Handle timer, int client)
{
	if (!IsClientInGame(client)) return Plugin_Stop;
	GivePlayerItem(client, "weapon_whiskey");
	return Plugin_Handled;
}

Action Timer_Grace(Handle timer)
{
	InGrace = false;	
	return Plugin_Handled;
}

Action Timer_Disclaimer(Handle timer, int iuserid)
{
	int client = GetClientOfUserId(iuserid);
	if (client > 0 && IsClientInGame(client))
	{
        PrintToChat(client, "\x04/*\x07FFDA00 This server is running \x07FF0000Juggernaut,\x07FFDA00 a custom gamemode by \x07BF00FFKyeki.\x04 */");
	}
	return Plugin_Handled;
}

Action Timer_Freeze(Handle timer, float speed) // this shouldn't be required, but force switching teams after the player spawns unfreezes players
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue", speed);
		}
	}
	return Plugin_Continue;
}

Action Timer_Beacon(Handle timer)
{
	int client = GetClientOfUserId(CurrentJuggernautId);
	if (JuggernautBeacon == false || client == 0) return Plugin_Stop;

	// the following code is from the SourceMod beacon command. It's possible to just use ServerCmd, but this implementation doesn't spam the chat.
	float origin[3];
	int redColor[4] = {255, 75, 75, 255};
	
	GetClientAbsOrigin(client, origin);
	origin[2] += 10;
	TE_SetupBeamRingPoint(origin, 10.0, 250.0, g_BeamSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, redColor, 10, 0);
	TE_SendToAll();
	
	GetClientEyePosition(client, origin);
	EmitAmbientSound("common/buy_tick.wav", origin, client, SNDLEVEL_RAIDSIREN); 
	
	return Plugin_Handled;
}

Action Timer_DeathBeacon(Handle timer)
{
	if (!isEnabled() || JuggernautBeacon == true || GetClientOfUserId(CurrentJuggernautId == 0)) return Plugin_Continue;

	int time = GetConVarInt(g_BeaconTime);
	if (DeathTime < time)
	{
		DeathTime++;
	}

	if (DeathTime == time)
	{
		JuggernautBeacon = true;
		CreateTimer(1.0, Timer_Beacon, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		PrintToChatAll("%i seconds has passed without deaths. The Juggernaut's beacon has been enabled!", time);
	}
	return Plugin_Handled;
}

Action Timer_GivePrimaryWeapon(Handle timer, int userid)
{
	if (!isEnabled()) return Plugin_Handled;
	
	int client = GetClientOfUserId(userid);
	char weapon[32];
	
	if (isHuman(client))
	{
		GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight, weapon, sizeof(weapon));
		GivePlayerItem(client, weapon);
	}
	
	else if (isJuggernaut(client))
	{
		GetRandomValueFromTable(g_JuggernautPrimaryTable, g_JuggernautPrimaryTotalWeight, weapon, sizeof(weapon));
		GivePlayerItem(client, weapon);
	}
	return Plugin_Handled;
}

// having two functions that do basically the same thing sucks, but SourceMod seemingly doesn't let you pass more than 1 variable to timers :(
Action Timer_GiveSecondaryWeapon(Handle timer, int userid) 
{
	if (!isEnabled()) return Plugin_Handled;
	
	int client = GetClientOfUserId(userid);
	char weapon[32];

	if (isHuman(client))
	{
		GetRandomValueFromTable(g_GearSecondaryTable, g_GearSecondaryTotalWeight, weapon, sizeof(weapon));
		GivePlayerItem(client, weapon);
	}
	else if (isJuggernaut(client))
	{
		GetRandomValueFromTable(g_JuggernautSecondaryTable, g_JuggernautSecondaryTotalWeight, weapon, sizeof(weapon));
		GivePlayerItem(client, weapon);
	}
	return Plugin_Handled;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;

	InGrace = true;
	DeathTime = 0;
	if (h_DeathBeacon != INVALID_HANDLE)
	{
		CloseHandle(h_DeathBeacon)
		h_DeathBeacon = INVALID_HANDLE;
	}
}

void Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;

	DeathTime = 0;
	if (JuggernautBeacon == true)
	{
		JuggernautBeacon = false;
		SetEntityRenderColor(GetClientOfUserId(CurrentJuggernautId), 255, 255, 255, 255);
		PrintToChatAll("The Juggernaut's beacon has been disabled.");
	}
}

void Event_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!InGrace && isEnabled() && GetEventInt(event, "userid") != CurrentJuggernautId) // idk why this was needed, since Timer_Repeat should stop people from being on the wrong team, but this was needed too
	{
		SDKHooks_TakeDamage(client, client, client, 999.0);
		ChangeClientTeam(client, TEAM_HUMAN);
	}
}

void Event_Announce(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;
	CreateTimer(3.0, Timer_Disclaimer, GetEventInt(event, "userid"), TIMER_FLAG_NO_MAPCHANGE);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;

	if (h_DeathBeacon != INVALID_HANDLE) // shouldn't be necessary, but the round doesn't properly "end" and CloseHandle in Event_RoundEnd if all players leave the server
	{
		CloseHandle(h_DeathBeacon)
		h_DeathBeacon = INVALID_HANDLE;
	}

	DeathTime = 0;
	InGrace = true;
	PickJuggernaut();
	
	for (new i = 1; i <= GetClientCount(); i++) 
	{
		if (IsClientInGame(i))
		{
			int userid = GetClientUserId(i);
			SetEntityRenderColor(i, 255, 255, 255, 255);
			CreateTimer(0.2, Timer_GiveSecondaryWeapon, userid, TIMER_FLAG_NO_MAPCHANGE);
			CreateTimer(0.4, Timer_GivePrimaryWeapon, userid, TIMER_FLAG_NO_MAPCHANGE);
			
			if (isHuman(i))
			{
				Entity_SetModelIndex(i, g_VigilanteModelIndex);
				PrintCenterText(i, "You are a human!");
			}
			if (isJuggernaut(i))
			{
				char tmp[PLATFORM_MAX_PATH];
				Entity_SetModelIndex(i, g_BandidoModelIndex);
				Format(tmp, sizeof(tmp), "npc/mexican/andale-0%i.wav", GetRandomInt(1, 7));
				EmitSoundToAll(tmp, i, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEPITCH, SNDVOL_NORMAL); 
				PrintCenterText(i, "You are the Juggernaut!");
			}
		}
	}

	PickMedics();
	ConvertWhiskey(g_LootTable, g_LootTotalWeight);
	
	CreateTimer(0.1, Timer_Freeze, 0.0, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(5.0, Timer_Freeze, 1.0, TIMER_FLAG_NO_MAPCHANGE);

	g_TeambalanceAllowedCvar.SetInt(0, false, false);
	g_TeamsUnbalanceLimitCvar.SetInt(0, false, false);
	g_AutoteambalanceCvar.SetInt(0, false, false);

	Entity_KillAllByClassName("fof_crate");
	Entity_KillAllByClassName("fof_crate_low");
	Entity_KillAllByClassName("fof_crate_med");
	Entity_KillAllByClassName("fof_buyzone");
	
	JuggernautBeacon = false;

	h_DeathBeacon = CreateTimer(1.0, Timer_DeathBeacon, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(2.0, Timer_Grace, .flags = TIMER_FLAG_NO_MAPCHANGE);
}

void InitializeJuggernautMode()
{
	char file[PLATFORM_MAX_PATH];
	g_CfgCvar.GetString(file, sizeof(file));

	KeyValues config = LoadConfigFile(file);

	// clear tables if they exist, and build new weight tables. then delete config keyvalue once we're done
	delete g_LootTable;
	g_LootTable = BuildWeightTable(config, "loot", g_LootTotalWeight);
	delete g_GearPrimaryTable;
	g_GearPrimaryTable = BuildWeightTable(config, "gear_primary", g_GearPrimaryTotalWeight);
	delete g_GearSecondaryTable;
	g_GearSecondaryTable = BuildWeightTable(config, "gear_secondary", g_GearSecondaryTotalWeight);
	delete g_JuggernautPrimaryTable;
	g_JuggernautPrimaryTable = BuildWeightTable(config, "juggernaut_primary", g_JuggernautPrimaryTotalWeight);
	delete g_JuggernautSecondaryTable;
	g_JuggernautSecondaryTable = BuildWeightTable(config, "juggernaut_secondary", g_JuggernautSecondaryTotalWeight);
	delete config;
}

KeyValues LoadConfigFile(const char[] file)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), file);

	KeyValues config = new KeyValues("juggernaut_mode");
	if (!config.ImportFromFile(path))
	{
		LogError("Could not read Juggernaut config file \"%s\"", file);
		SetFailState("Could not read Juggernaut config file \"%s\"", file);
		return null;
	}
	return config;
}

KeyValues BuildWeightTable(KeyValues config, const char[] name, int& total_weight)
{
	char key[128];
	int weight;
	KeyValues table = new KeyValues(name);
	total_weight = 0;

	config.Rewind();

	if (config.JumpToKey(name))
	{
		table.Import(config);
		config.GotoFirstSubKey();
		do
		{
			config.GetSectionName(key, sizeof(key));
			weight = config.GetNum("weight", 0);
			if (weight > 0)
			{
				total_weight += weight;
			}
		}
		while (config.GotoNextKey());
	}
	else
	{
		LogError("A valid \"%s\" key was not defined", name);
		SetFailState("A valid \"%s\" key was not defined", name);
	}
	PrintToServer("BuildWeightTable %s end total_weight: %d", name, total_weight);
	return table;
}

bool GetRandomValueFromTable(KeyValues table, int total_weight, char[] value, int length)
{
	int weight;
	int rand = GetRandomInt(0, total_weight - 1);
	
	table.Rewind();
	table.GotoFirstSubKey();
	do
	{
		table.GetSectionName(value, length);
		weight = table.GetNum("weight", 0);
		if (weight <= 0) continue;

		if (rand < weight)
		{
			return true;
		}
		rand -= weight;
	}
	while(table.GotoNextKey());

	return false;
}

void ConvertWhiskey(KeyValues loot_table, int loot_total_weight)
{
	char loot[128];
	int whiskey = INVALID_ENT_REFERENCE;
	int horse = INVALID_ENT_REFERENCE;
	int converted = INVALID_ENT_REFERENCE;
	float origin[3], angles[3];

	while ((whiskey = FindEntityByClassname(whiskey, "item_whiskey")) != INVALID_ENT_REFERENCE)
	{
		Entity_GetAbsOrigin(whiskey, origin);
		Entity_GetAbsAngles(whiskey, angles);
		Entity_Kill(whiskey);

		GetRandomValueFromTable(loot_table, loot_total_weight, loot, sizeof(loot));
		if (StrEqual(loot, "nothing", false)) continue;

		converted = Weapon_Create(loot, origin, angles);
		Entity_AddEFlags(converted, EFL_NO_GAME_PHYSICS_SIMULATION | EFL_DONTBLOCKLOS);
	}

	while ((horse = FindEntityByClassname(horse, "fof_horse")) != INVALID_ENT_REFERENCE)
	{
		Entity_Kill(horse);
	}
}

int SpawnTeamplayEntity()
{
	char tmp[128];
	int ent = FindEntityByClassname(INVALID_ENT_REFERENCE, "fof_teamplay");
	
	if (!IsValidEntity(ent)) // if not loaded into tp_ map that has existing fof_teamplay, make one
	{
		ent = CreateEntityByName("fof_teamplay");
		DispatchKeyValue(ent, "targetname", "tpjuggernaut");
	}

	if (IsValidEntity(ent))
	{
		DispatchKeyValue(ent, "RoundBased", "1");
		DispatchKeyValue(ent, "RespawnSystem", "1");

		Format(tmp, sizeof(tmp), "!self,RoundTime,%d,0,-1", GetRoundTime());
		DispatchKeyValue(ent, "OnNewRound", tmp);
		DispatchKeyValue(ent, "OnNewRound", "!self,ExtraTime,15,0.1,-1");
		
		Format(tmp, sizeof(tmp), "!self,ExtraTime,%d,0,-1", 15);
		DispatchKeyValue(ent, "OnTimerEnd", tmp);

		Format(tmp, sizeof(tmp), "!self,%s,,0,-1", INPUT_JUGGERNAUT_VICTORY);
		DispatchKeyValue(ent, "OnRoundTimeEnd", tmp);
		DispatchKeyValue(ent, ON_NO_JUGGERNAUT_ALIVE, INPUT_HUMAN_VICTORY);
		Format(tmp, sizeof(tmp), "!self,%s,,0,-1", INPUT_JUGGERNAUT_VICTORY);
		DispatchKeyValue(ent, ON_NO_HUMAN_ALIVE, tmp);

		DispatchSpawn(ent);
		ActivateEntity(ent);
	}
	return ent; 
}

// FoF's server browser looks at gamemode to determine which server listing to put it under, so this is required. If it doesn't matter to you, this can be removed and SteamWorks would no longer be required.
bool SetGameDescription(const char[] description) 
{
    return SteamWorks_SetGameDescription(description);
}

public GetRoundTime()
{
	return g_RoundTimeCvar.IntValue;
}

public isEnabled()
{
	return g_isEnabledCvar.BoolValue;
}

bool isHuman(int client)
{
	if (client == 0) return false;
	return GetClientTeam(client) == TEAM_HUMAN;
}

bool isJuggernaut(int client)
{
	if (client == 0) return false;
	return GetClientTeam(client) == TEAM_JUGGERNAUT;
}

void PickMedics()
{
	int HumanCount = Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE);
	float MedicCount = GetConVarFloat(g_MedicRatio) * HumanCount;
	RoundToCeil(MedicCount);
	
	for (new p = 1; p <= MedicCount; p++)
	{
		int randomindex = GetRandomInt(0, GetArraySize(MedicPicks)-1)
		int random = GetArrayCell(MedicPicks, randomindex)
		if (IsClientInGame(random))
		{
			RemoveFromArray(MedicPicks, randomindex)
			PrintToServer("[JUGGERNAUT - %.3f] PickMedics random: %i - %N", GetGameTime(), random, random);
			PrintCenterText(random, "You are a medic - heal your teammates!");
			CreateTimer(0.5, Timer_GiveWhiskey, random, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void ClearJuggernauts()
{
	AlreadyJuggernautIndex = 0;
	for (new i = 0; i < MAXPLAYERS+1; i++)
	{
		AlreadyJuggernaut[i] = 0;
	}
}

public CheckJuggernaut(int client)
{
	if (!IsClientInGame(client) || !IsClientConnected(client)) return 1;
	int clientid = GetClientUserId(client);
	for (new i = 0; i < MAXPLAYERS+1; i++)
	{
		if (AlreadyJuggernaut[i] != clientid) continue;
		if (AlreadyJuggernaut[i] == clientid) return 1;
	}
	return 0;
}

void PickJuggernaut()
{
	int chosen = 1, client_count, random;

	if (GetArraySize(JuggernautPicks) == 1)
	{
		ClearJuggernauts();
		PrintToServer("[JUGGERNAUT - %.3f] Clearing juggernaut array", GetGameTime());
	}

	ClearArray(JuggernautPicks);
	ClearArray(MedicPicks);
	for (new i = 1; i <= MaxClients; i++)  // building list of players in the server that not only exist, but were not already picked for juggernaut previously
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			PushArrayCell(MedicPicks, i)
			if ((!CheckJuggernaut(i) && GetConVarBool(g_JuggernautPicker) == false) || GetConVarBool(g_JuggernautPicker) == true) 
			{
				PushArrayCell(JuggernautPicks, i);
			}		
			ChangeClientTeam(i, TEAM_HUMAN);
			client_count++;
		}
		else continue;
	}
	// this code uses a dynamic array JuggernautPicks to narrow down the possible juggernaut. 
	random = GetRandomInt(0, GetArraySize(JuggernautPicks)-1);
	chosen = GetArrayCell(JuggernautPicks, random);
	RemoveFromArray(MedicPicks, FindValueInArray(MedicPicks, chosen)); // necessary later on, so the juggernaut does not end up being a medic
	PrintToServer("[JUGGERNAUT - %.3f] Juggernaut is %i - %N", GetGameTime(), chosen, chosen);

	if (GetTeamClientCount(TEAM_JUGGERNAUT) != 0) // this check might be superfluous, but it stopped multiple juggernauts from happening 
	{
		for (new i = 1; i <= client_count; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				ChangeClientTeam(i, TEAM_HUMAN);
			}
		}
	}

	ChangeClientTeam(chosen, TEAM_JUGGERNAUT);
	if (GetConVarBool(g_JuggernautPicker) == false)
	{
		CurrentJuggernautId = GetClientUserId(chosen);
		PrintToServer("[JUGGERNAUT - %.3f] Logging playerid %i in AlreadyJuggernautIndex %i", GetGameTime(), CurrentJuggernautId, AlreadyJuggernautIndex);
		AlreadyJuggernaut[AlreadyJuggernautIndex] = CurrentJuggernautId;
		AlreadyJuggernautIndex++

		for (new p = 0; p <= AlreadyJuggernautIndex; p++) // clearing AlreadyJuggernaut array of any players that left the server
   		{
			if (AlreadyJuggernaut[p] == 0) continue;
			if (GetClientOfUserId(AlreadyJuggernaut[p]) == 0)
   	    	{
				PrintToServer("[JUGGERNAUT - %.3f] Clearing invalid userid, index %i", GetGameTime(), p)
				AlreadyJuggernaut[p] = 0;
			}
		}
	}
}

void ConvertSpawns()
{
	int count = GetRandomInt(0, 1);
	int spawn = INVALID_ENT_REFERENCE;
	int converted = INVALID_ENT_REFERENCE;
	float origin[3], angles[3];

	while ((spawn = FindEntityByClassname(spawn, "info_player_fof")) != INVALID_ENT_REFERENCE)
	{
		Entity_GetAbsOrigin(spawn, origin);
		Entity_GetAbsAngles(spawn, angles);
		Entity_Kill(spawn);

		converted = count % 2 == 0
		? Entity_Create(INFO_PLAYER_HUMAN) : Entity_Create(INFO_PLAYER_JUGGERNAUT);
		if (IsValidEntity(converted))
		{
			Entity_SetAbsOrigin(converted, origin);
			Entity_SetAbsAngles(converted, angles);
			DispatchKeyValue(converted, "StartDisabled", "0");
			DispatchSpawn(converted);
			ActivateEntity(converted);
		}
		count++;
	}
}

public void OnMapStart()
{
	if (!isEnabled()) return;
	
	char tmp[PLATFORM_MAX_PATH];
	InGrace = true;

	// precache gamemode materials
	g_VigilanteModelIndex = PrecacheModel("models/playermodels/player1.mdl");
	g_BandidoModelIndex = PrecacheModel("models/playermodels/bandito.mdl");
	g_BeamSprite = PrecacheModel("sprites/laser.vmt");
	g_HaloSprite = PrecacheModel("sprites/halo01.vmt");
	PrecacheSound("common/buy_tick", true);

	ClearJuggernauts();

	for (int i = 1; i <= 7; i++)
	{
		Format(tmp, sizeof(tmp), "npc/mexican/andale-0%i", i);
		PrecacheSound(tmp, true);
	}
	
	g_TeamplayEntity = SpawnTeamplayEntity();
	ConvertSpawns();
	g_AutoSetGameDescription = true;
}

public void RoundEndCheck() // sometimes the teamplay entity won't end the round, so this manual check is needed
{
	if (!isEnabled() || GetClientCount(false) < 2) return;
	if (Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE) == 0)
	{
		AcceptEntityInput(g_TeamplayEntity, INPUT_JUGGERNAUT_VICTORY);
	}
	else if (Team_GetClientCount(TEAM_JUGGERNAUT, CLIENTFILTER_ALIVE) == 0)
	{
		AcceptEntityInput(g_TeamplayEntity, INPUT_HUMAN_VICTORY);
		
	}
	return;
}

public void OnClientPutInServer(int client)
{
	if (!isEnabled()) return;

	SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	SDKHook(client, SDKHook_PreThinkPost, Hook_PreThinkPost);
}

public void OnConfigsExecuted()
{
	if (!isEnabled()) return;

	g_TeambalanceAllowedCvar.SetInt(0, false, false);
	g_TeamsUnbalanceLimitCvar.SetInt(0, false, false);
	g_AutoteambalanceCvar.SetInt(0, false, false);
	SetGameDescription("Juggernaut");
	InitializeJuggernautMode();
}
