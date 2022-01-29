# sm-fof-juggernaut
Juggernaut gamemode for Fistful of Frags

![gif](https://thumbs.gfycat.com/InfamousEllipticalEarwig-size_restricted.gif)

## Requirements
* [SourceMod](https://www.sourcemod.net/) version 1.10 or later
* [SteamWorks extension](https://users.alliedmods.net/~kyles/builds/SteamWorks/) (to change server's gamemode in server browser)

## Installation
Be sure you have properly installed SourceMod and that your server is functioning with it enabled. If you are unsure on how to install SourceMod or custom plugins, refer to the [AlliedModders wiki page](https://wiki.alliedmods.net/Installing_SourceMod) for more detail.

To install, extract the latest release in your SourceMod's addons folder. If compiling manually, be sure to include both SteamWorks and smlib in your scripting/include folder.

Once installed, edit the following server.cfg's cvars so that Teamplay mode is enabled: fof_sv_currentmode 2, mp_teamplay 1, fof_sv_maxteams 2. Be **ABSOLUTELY** certain to change mapcycle_tp.txt to the maps you want your server to run for this mode. All maps except Teamplay maps are supported. Once this is done, the plugin is ready to be used. 

## Server Settings
This gamemode can support up to 24 players (Teamplay mode's max), but for balance reasons, it should be kept to 20 players or less.

### Variables
| Variable | Accepts | Range | Default | Description |
| --- | --- | --- | --- | --- |
| `jm_enabled` | boolean | 0-1 | 1 | Whether Juggernaut Mode is on or not. |
| `jm_config` | string | path | configs/juggernaut_cfg.txt | Location of the Juggernaut config file, relative to addons/sourcemod. |
| `jm_medics` | float | 0-1 | 0.50 | Percentage of players on the human side that will receive whiskey along with their weapons. |
| `jm_rage` | bool | 0-1 | 1 | Whether the Juggernaut's speed will scale with health. |
| `jm_random` | bool | 0-1 | 0 | Whether the chosen Juggernaut is pure random, or randomly permutated. (everyone gets to be Juggernaut at least once) 1 = pure random. |
| `jm_ratio_dynamic` | bool | 0-1 | 1 | Turns on or off scaling damage reduction for the Juggernaut based on player count. | 
| `jm_ratio_override` | float | 0-1 | 0.25 | Static rate of the Juggernaut's damage reduction if jm_ratio_dynamic is set to 0. | 
| `jm_round_time` | int | 0-999 | 120 | How many seconds humans have to live in a round. | 
| `jm_speed` | float | 0-999 | 150.0 | Movement speed, in Hammer units/second, that the Juggernaut will start with. |

### Commands (admin only)

| Command | Description |
| --- | --- 
| `jm_reload` | Force a reload of the Juggernaut config file. |

## License
[GNU General Public License v3.0](https://choosealicense.com/licenses/gpl-3.0/)

## Credits
This gamemode is derived from [CrimsonTautology's Fistful of Zombies mode,](https://github.com/CrimsonTautology/sm-fistful-of-zombie) which is licensed under GPL-3.0.

Special thanks to the following players for playtesting, discovering bugs, and offering feedback:  
Spunty  
general disarray  
Flaydin  
sid3windr  
Ziginox  
Chitch  
Wolfgang V2.35  
Nimrod Hempel  
Judge Uchiha  
yami  
Scamper9  
Dooge  
tadtakker  
