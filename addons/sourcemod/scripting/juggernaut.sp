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

ConVar g_TeambalanceAllowedCvar;
ConVar g_TeamsUnbalanceLimitCvar;
ConVar g_AutoteambalanceCvar;
ConVar g_PermaDeath;

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

bool AlreadyMedic[MAXPLAYERS+1] = {false, ...};
int AlreadyJuggernaut[MAXPLAYERS+1] = {0, ...};
int AlreadyJuggernautIndex = 0;
int DisconnectCount;

bool GameLive = false;

bool g_AutoSetGameDescription = false;
int g_VigilanteModelIndex;
int g_BandidoModelIndex;
int CurrentJuggernautId;
int g_TeamplayEntity = INVALID_ENT_REFERENCE;

public Plugin myinfo =
{
	name = "Juggernaut",
	author = "Kyeki",
	description = "Juggernaut gamemode for Fistful of Frags",
	version = "1.0",
	url = "https://github.com/Kyekii/sm-fof-juggernaut"
};

public void OnPluginStart()
{
	g_isEnabledCvar = CreateConVar("jm_enabled", "1", "Whether Juggernaut Mode is on or not.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CfgCvar = CreateConVar("jm_config", "configs/juggernaut_cfg.txt", "Location of the Juggernaut config file.", 0);
	g_MedicRatio = CreateConVar("jm_medics", "0.50", "Percentage of players on the human side that will receive whiskey along with their weapons.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_JuggernautRage = CreateConVar("jm_rage", "1", "Whether the Juggernaut's speed will scale with health.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_JuggernautPicker = CreateConVar("jm_random", "0", "Whether the chosen Juggernaut is pure random, or randomly permutated. (everyone gets to be Juggernaut at least once)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_ScaleDamage = CreateConVar("jm_ratio_dynamic", "1.0", "Turns on or off scaling damage reduction for the Juggernaut based on player count.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_ScaleOverride = CreateConVar("jm_ratio_override", "0.25", "Static rate of the Juggernaut's damage reduction if jm_ratio_dynamic is set to 0.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_RoundTimeCvar = CreateConVar("jm_round_time", "180", "How many seconds are in a round.", FCVAR_NOTIFY, true, 0.0);
	g_JuggernautSpeed = CreateConVar("jm_speed", "150.0", "Movement speed, in Hammer units/second, that the Juggernaut will spawn with.", FCVAR_NOTIFY, true, 0.0, false);
	
	RegAdminCmd("jm_reload", Command_Reload, ADMFLAG_CONFIG, "Force a reload of the Juggernaut config file.");
	
	g_TeambalanceAllowedCvar = FindConVar("fof_sv_teambalance_allowed");
	g_TeamsUnbalanceLimitCvar = FindConVar("mp_teams_unbalance_limit");
	g_AutoteambalanceCvar = FindConVar("mp_autoteambalance");
	g_PermaDeath = FindConVar("fof_sv_force_spect");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_activate", Event_Announce);
	HookEvent("player_disconnect", Event_Disconnect);
	
	AddNormalSoundHook(SoundReplace);
	
	GameLive = false;
}

void Event_Disconnect(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;
	if (!GameLive) return;
		
	DisconnectCount++; // this is to ensure that any players that leave during warmup aren't counted as part of the disconnect count
}

void Event_Announce(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;
	int iuserid = GetEventInt(event, "userid");
	CreateTimer(5.0, Timer_Disclaimer, iuserid, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_GivePrimaryWeapon(Handle timer, int userid)
{
	if (!isEnabled()) return Plugin_Handled;
	
	int client = GetClientOfUserId(userid);
	char weapon[32];
	char tmp[64];
	
	if (isHuman(client))
	{
		GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight, weapon, sizeof(weapon));
		GivePlayerItem(client, weapon);
		Format(tmp, sizeof(tmp), "use %s", weapon);
		ClientCommand(client, tmp);
	}
	
	else if (isJuggernaut(client))
	{
		GetRandomValueFromTable(g_JuggernautPrimaryTable, g_JuggernautPrimaryTotalWeight, weapon, sizeof(weapon));
		GivePlayerItem(client, weapon);
		Format(tmp, sizeof(tmp), "use %s", weapon);
		ClientCommand(client, tmp);
	}
	return Plugin_Handled;
}

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

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!isEnabled()) return;
	
	GameLive = true;
	if (GetConVarBool(g_JuggernautPicker) == false)
	{
		PickJuggernaut();
	}
	else
	{
		PickJuggernaut_Legacy();
	}
	
	for (new i = 1; i <= GetClientCount(); i++) 
	{
		if (IsClientInGame(i))
		{
			int userid = GetClientUserId(i);
			SetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue", 0.0);
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
	
	g_TeambalanceAllowedCvar.SetInt(0, false, false);
	g_TeamsUnbalanceLimitCvar.SetInt(0, false, false);
	g_AutoteambalanceCvar.SetInt(0, false, false);
	g_PermaDeath.SetInt(1, false, false);

	Entity_KillAllByClassName("fof_crate");
	Entity_KillAllByClassName("fof_crate_low");
	Entity_KillAllByClassName("fof_crate_med");
	Entity_KillAllByClassName("fof_buyzone");
	CreateTimer(2.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

Action Command_Reload(int caller, int args)
{
	InitializeJuggernautMode();
	return Plugin_Handled;
}

void InitializeJuggernautMode()
{
	char file[PLATFORM_MAX_PATH];
	g_CfgCvar.GetString(file, sizeof(file));

	KeyValues config = LoadConfigFile(file);

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
	int count = 0;
	int whiskey = INVALID_ENT_REFERENCE;
	int converted = INVALID_ENT_REFERENCE;
	float origin[3], angles[3];

	while((whiskey = FindEntityByClassname(whiskey, "item_whiskey")) != INVALID_ENT_REFERENCE)
	{
		Entity_GetAbsOrigin(whiskey, origin);
		Entity_GetAbsAngles(whiskey, angles);
		Entity_Kill(whiskey);

		GetRandomValueFromTable(loot_table, loot_total_weight, loot, sizeof(loot));
		if (StrEqual(loot, "nothing", false)) continue;

		converted = Weapon_Create(loot, origin, angles);
		Entity_AddEFlags(converted, EFL_NO_GAME_PHYSICS_SIMULATION | EFL_DONTBLOCKLOS);

		count++;
	}
}

int SpawnTeamplayEntity()
{
	char tmp[128];
	int ent = FindEntityByClassname(INVALID_ENT_REFERENCE, "fof_teamplay");
	
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
	}

	else if (!IsValidEntity(ent))
	{
		ent = CreateEntityByName("fof_teamplay");
		DispatchKeyValue(ent, "targetname", "tpjuggernaut");

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
	return GetClientTeam(client) == TEAM_HUMAN;
}

bool isJuggernaut(int client)
{
	return GetClientTeam(client) == TEAM_JUGGERNAUT;
}

Action Timer_GiveWhiskey(Handle timer, int client)
{
	if (!IsClientInGame(client)) return;
	GivePlayerItem(client, "weapon_whiskey");
}

void PickMedics()
{
	int HumanCount = Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE);
	int PlayerCount = GetClientCount(false);
	float MedicCount = GetConVarFloat(g_MedicRatio) * HumanCount;
	RoundToCeil(MedicCount);
	int JuggernautClient = GetClientOfUserId(CurrentJuggernautId);
	
	for (new p = 0; p < MAXPLAYERS+1; p++)
	{
		AlreadyMedic[p] = false;
	}
	
	for (new p = 1; p <= MedicCount; p++)
	{
		int random = GetRandomInt(1, PlayerCount);
		
		if (IsClientInGame(random))
		{ 
			while (((AlreadyMedic[random] == true)) || (random == JuggernautClient) || (!IsClientInGame(random)))
			{
				random = GetRandomInt(1, PlayerCount);	
				int overflow;
				overflow++
				if (overflow > 64) break;
			}
			PrintToServer("[JUGGERNAUT - %.3f] PickMedics random: %i - %N", GetGameTime(), random, random);
			PrintCenterText(random, "You are a medic - heal your teammates!");
			CreateTimer(0.3, Timer_GiveWhiskey, random, TIMER_FLAG_NO_MAPCHANGE);
			AlreadyMedic[random] = true;
		}
	}
}

Action:Timer_Disclaimer(Handle timer, int iuserid)
{
	int client = GetClientOfUserId(iuserid);
	if (client > 0 && IsClientInGame(client))
	{
        PrintToChat(client, "\x04/*\x07FFDA00 This server is running \x07FF0000Juggernaut,\x07FFDA00 a custom gamemode by \x07BF00FFKyeki.\x04 */");
	}
	return;
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
}

public void ClearJuggernauts()
{
	AlreadyJuggernautIndex = 0;
	DisconnectCount = 0;
	for (new i = 0; i < MAXPLAYERS+1; i++)
	{
		AlreadyJuggernaut[i] = 0;
	}
}

public CheckJuggernaut(int client)
{
	if (!IsClientConnected(client)) return 1;
	int clientid = GetClientUserId(client);
	for (new i = 0; i < MAXPLAYERS+1; i++)
	{
		if (AlreadyJuggernaut[i] != clientid) continue;
		if (AlreadyJuggernaut[i] == clientid) return 1;
	}
	return 0;
}

void PickJuggernaut_Legacy()
{
	int clients[MAXPLAYERS+1];
	int chosen = 1, i, client_count; 

	ClearJuggernauts();
	for (i = 1; i <= MaxClients; i++)  
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			ChangeClientTeam(i, TEAM_HUMAN);
			clients[client_count] = i;
			client_count++;
		}
		else continue;
	}
	
	chosen = GetRandomInt(1, client_count);  
	while (!IsClientInGame(chosen))
	{
		PrintToServer("[JUGGERNAUT - %.3f] Rerolling juggernaut", GetGameTime());
		chosen = GetRandomInt(1, client_count);  
	}
	
	if (GetTeamClientCount(TEAM_JUGGERNAUT) != 0)
	{
		for (i = 1; i <= client_count; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				ChangeClientTeam(i, TEAM_HUMAN);
			}
		}
	}
	
	PrintToServer("[JUGGERNAUT - %.3f] Moving juggernaut to team", GetGameTime());
	CreateTimer(0.1, Timer_Freeze, 0.0, TIMER_FLAG_NO_MAPCHANGE);
	ChangeClientTeam(chosen, TEAM_JUGGERNAUT);
	CreateTimer(5.0, Timer_Freeze, 1.0, TIMER_FLAG_NO_MAPCHANGE);
	CurrentJuggernautId = GetClientUserId(chosen);
}

void PickJuggernaut()
{
	int clients[MAXPLAYERS+1];
	int chosen = 1, i, client_count; 
	int overflow = 0;

	for (i = 1; i <= MaxClients; i++)  
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			ChangeClientTeam(i, TEAM_HUMAN);
			clients[client_count] = i;
			client_count++;
		}
		else continue;
	}

	chosen = GetRandomInt(1, MaxClients); 
	while ((CheckJuggernaut(chosen) == 1) || !IsClientInGame(chosen))
	{
		PrintToServer("[JUGGERNAUT - %.3f] Rerolling juggernaut", GetGameTime());
		chosen = GetRandomInt(1, MaxClients);
	}
	
	PrintToServer("[JUGGERNAUT - %.3f] Juggernaut is %i - %N", GetGameTime(), chosen, chosen);
	if (GetTeamClientCount(TEAM_JUGGERNAUT) != 0) // this might be superfluous, but it stopped multiple juggernauts from happening 
	{
		for (i = 1; i <= client_count; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				ChangeClientTeam(i, TEAM_HUMAN);
			}
		}
	}
	CreateTimer(0.1, Timer_Freeze, 0.0, TIMER_FLAG_NO_MAPCHANGE);
	ChangeClientTeam(chosen, TEAM_JUGGERNAUT);
	CreateTimer(5.0, Timer_Freeze, 1.0, TIMER_FLAG_NO_MAPCHANGE);
	CurrentJuggernautId = GetClientUserId(chosen);
	PrintToServer("[JUGGERNAUT - %.3f] JuggernautArrayIndex: %i", GetGameTime(), AlreadyJuggernautIndex);
	
	AlreadyJuggernaut[AlreadyJuggernautIndex] = CurrentJuggernautId;
	AlreadyJuggernautIndex++
	
	PrintToServer("[JUGGERNAUT - %.3f] Logging playerid %i", GetGameTime(), CurrentJuggernautId);
		
	for (new p = 0; p < MAXPLAYERS+1; p++)
	{
		if (AlreadyJuggernaut[p] == 0) continue;
			
		overflow++;
		if (overflow - DisconnectCount >= client_count || AlreadyJuggernautIndex - DisconnectCount <= 0)
		{
			ClearJuggernauts();
			PrintToServer("[JUGGERNAUT - %.3f] Clearing juggernaut array", GetGameTime());
			break;
		}
	}
}

void ConvertSpawns()
{
	int count = GetRandomInt(0, 1);
	int spawn = INVALID_ENT_REFERENCE;
	int converted = INVALID_ENT_REFERENCE;
	float origin[3], angles[3];

	while((spawn = FindEntityByClassname(spawn, "info_player_fof")) != INVALID_ENT_REFERENCE)
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
	
	char tmp[256];
	
	ClearJuggernauts();
	//precache gamemode materials
	g_VigilanteModelIndex = PrecacheModel("models/playermodels/player1.mdl");
	g_BandidoModelIndex = PrecacheModel("models/playermodels/bandito.mdl");
	
	for (int i = 1; i <= 7; i++)
	{
		Format(tmp, sizeof(tmp), "npc/mexican/andale-0%i", i);
		PrecacheSound(tmp, true);
	}
	
	g_TeamplayEntity = SpawnTeamplayEntity();
	ConvertSpawns();
	g_AutoSetGameDescription = true;
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
	return Plugin_Handled;
}

public void RoundEndCheck() // sometimes the teamplay entity won't end the round, so this manual check is needed
{
	if (!isEnabled()) return;
	if (GetClientCount(false) < 2) return;
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


Action SoundReplace(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (!isEnabled) return Plugin_Handled;
	if (0 < entity <= MaxClients)
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

Action Hook_OnWeaponCanUse(int client, int weapon)
{
	if (!isEnabled()) return Plugin_Continue;
	
	if (isJuggernaut(client))
	{
		char item[32];
		GetEntityClassname(weapon, item, sizeof(item));
		if (StrEqual(item, "weapon_whiskey"))
		{
			PrintToChat(client, "The juggernaut can't use whiskey!");
			return Plugin_Handled;
		}
		// melee increases run speed/would not be the most fair as juggernaut
		if (StrEqual(item, "weapon_axe") || StrEqual(item, "weapon_machete") || StrEqual(item, "weapon_knife"))
		{
			PrintToChat(client, "The juggernaut can't use melee weapons!");
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	if (!isEnabled()) return;

	SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	SDKHook(client, SDKHook_PreThinkPost, Hook_PreThinkPost);
}

public Action:Hook_PreThinkPost(int client)
{
	if (!isEnabled()) return;
	if (IsClientInGame(client) && isJuggernaut(client))
    {
		float slowdown = GetConVarFloat(g_JuggernautSpeed);
		float interval = (235.0 - slowdown) / 75
		if (GetClientHealth(client) < 100 && GetConVarBool(g_JuggernautRage))
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
		else if (GetConVarBool(g_ScaleDamage) != true)
		{
			ratio = GetConVarFloat(g_ScaleOverride);
		}
		
		if (damagetype != (1 << 14)) // juggernauts take full damage from drowning (insta-kill water hazards)
		{
			damage = damage * ratio; 
		}
		return Plugin_Changed;
	}
	else
	{
		return Plugin_Continue;
	}
}

public void OnConfigsExecuted()
{
	if (!isEnabled()) return;

	SetGameDescription("Juggernaut");
	g_TeambalanceAllowedCvar.SetInt(0, false, false);
	g_TeamsUnbalanceLimitCvar.SetInt(0, false, false);
	g_AutoteambalanceCvar.SetInt(0, false, false);
	InitializeJuggernautMode();
}
