# Real Room Temperature 2.0

- **Mod id:** `RealRoomHeat`
- **Workshop id:** `3741066319` (`Real Room Temperature 2.0 - B42 SP&MP`, sandbox page `RRH2`)
- **Status:** supported since 2026-11-19. Its code was read (`shared/RRH2/RRH2ColdRetention.lua`, `RRH2BodyNativeAdapter.lua`, `client/RRH2/RRH2BodyCold.lua`, `RRH2BodyHeat.lua`, `server/RRH2/RRH2BodyServer.lua`, `RRH2BodyServerInput.lua`; [its cold retention hook](https://github.com/just3r/real-room-temperature-docs#lua-cold-retention-hook)), and we are tested offline against stand-ins for those globals (`tests/real_room_temperature_spec.lua`). **Not yet tried in a game.**

## Without the Body Temperature Rework

With **`RRH2.BodyTempRework`** off (its default), nothing changes for us. RRT's heaters warm the body through vanilla's heat sources. After the power shutoff, vanilla's own indoor cold still brings our cold stages and hypothermia.

## With it on

**The clash.** The rework lets RRT model cold rooms and vehicle cabins itself: it writes the thermoregulator's core and `Stats` TEMPERATURE together. Before every write it requires the two to agree within 4e-6. If anything else changed TEMPERATURE in between, it stops with `preexisting_core_stat_disagreement`:

- **Single player:** the fault is saved in the character (`RRH2BodySimulation.faultLatched`) and the cold model stays off for that character. Only its Heating Info panel resets it, in RRT Debug Mode.
- **Dedicated server:** the cold model stays off until the player moves to another room.

We write TEMPERATURE every tick while we hold a fever, the Warming Pack or the effect of hot or frozen food (`Server/Temperature`, `StatWriter.holdTemperature`). Eating hot soup in a cold house was enough to break RRT.

**What we do now** (`Game/RealRoomTemperature.lua`, `Server/RealRoomTemperature.lua`), only while RRT is enabled and its rework is on:

| | |
|---|---|
| **No writes while RRT owns the body** | The hold skips the player while RRT's cold model owns the body. In single player that is from the moment its lease starts until it is given back (`RealRoomHeat2.BodyCold.blocks`). On a dedicated server, RRT admits without checking first, so we also stay out as soon as its route for the player is the cold model (`BodyServerInput.resolve` → `lua_cold_trajectory`), and while it still holds or cleans up a generation (`BodyServer.snapshot`). If RRT's API is missing or fails, we take the body as owned: not writing is always safe. |
| **Warming Pack and hot food as cold retention** | Our provider in RRT's registry (`registerColdRetentionProvider("ExtensiveHealthRedone", …)`) returns the share of the heat lost to colder air that is kept in: **0.6** while a Warming Pack is active, and up to **0.5** from hot food (at its 0.6 °C maximum), fading with it. RRT uses the highest provider. `BodyTemperatureEnabled = false` turns both off, as it does without RRT. |
| **Fever and frozen food wait** | Neither can be expressed as retention. While RRT owns the body, the fever keeps running in our state (it rises and breaks on its own clock), but TEMPERATURE isn't raised, so the exam and vanilla's own fever effects don't see it (the Monitor marks it, see below). The disease's other symptoms go on as usual. When RRT lets go (you leave the cold room, the room warms up, time is sped up or you sleep), the hold sets TEMPERATURE straight to the fever as it is by then; a fever that broke meanwhile never shows. Frozen food does nothing while RRT owns the body, and its effect (15 to 60 minutes) usually runs out before RRT lets go. |

**Once a hold is running, RRT waits (single player).** Before it starts its cold model, RRT waits as long as TEMPERATURE and the core disagree, and leaves the body to vanilla meanwhile. A fever or warming that we are already holding therefore keeps RRT's cold model out until the hold ends. A dedicated server has no such wait, so there the hold always yields.

**Telling a hidden fever.** Without a TEMPERATURE to read, a player still learns about the fever three ways (`Body/FeverFeel`, which reads our fever, not the body's temperature):

- the EHR Monitor marks the body temperature *feverish* while we keep a fever, and keeps showing the body's real reading, so the cold stays visible too;
- the Monitor's **Check for fever** button (`Actions/CheckFever`, server command `temperature.checkFever`) has the character feel their forehead and say how warm they feel. A fever the body is 0.5 °C or more below feels like chills;
- the character remarks on the fever when it comes on, now and then while it lasts (chills while it is hidden), and when it breaks, following `DialogueFrequency`.

**What you'll see:** an unheated house cools the character through RRT's model. Our cold stages and hypothermia follow, because they read TEMPERATURE. A hot meal or a Warming Pack slows that cooling instead of setting a temperature. A fever caught in a cold room raises TEMPERATURE when you leave or sleep, unless it started before RRT's cold model took over; until then the Monitor, the check and the character's remarks show it.

**Extensive Food Rework** needs nothing of its own: it never writes body temperature, and hot meals go through our food temperature.

## Limits

- The "owns" check reads RRT internals that are not part of its public API (`BodyCold.blocks`, `BodyServerInput.resolve`, `BodyServer.snapshot`). If a later RRT version renames them, we stop writing whenever the rework is on and log one warning: fevers then don't raise TEMPERATURE indoors, but nothing faults.
- On a dedicated server, a fever doesn't raise TEMPERATURE in a room RRT models as cold, for as long as you stay there.
- The retention values (0.6 and 0.5) are a first guess, not tuned in a game.
- Take a Bath and Shower writes TEMPERATURE too. RRT handles that itself and it doesn't involve us.
- **Not yet seen:** any of this in a running game. To check: rework on, cold room, eat hot soup and catch a fever. Heating Info must show no latched fault, and our cold stages and hypothermia must follow.
