# Extensive Health Redone

A from-scratch rewrite of **Extensive Health Rework Evolved** (by Frozen_Heart, which grew out of Hunter's
**Extensive Health Rework B42**) for Project Zomboid **Build 42.21**. It adds diseases, blood and transfusion, medication
courses, an immune system and medical knowledge, and is multiplayer-safe with the server in charge of all health state.

Gameplay matches the original; the code does not.

- **Blood and wounds:** blood volume and types, transfusion, bleeding, wound infection, sepsis, cellulitis, tetanus and
  the stitch minigame.
- **Diseases:** food-borne, weather, corpse, scabies, concussion, mental and Knox, with the Knox items.
- **Medication:** courses, overdose, side effects, interactions and utility drugs.
- **Immunity and temperature:** the immune system, body temperature and fevers, Indoor Climate Redone room air,
  food temperature.
- **UI:** the EHR Monitor and Immune System tabs, the handbook, hotkeys, tooltips, moodles (MoodleFramework) and the
  Medical Monitor Watch.
- **World content:** loot, flyers and knowledge, the radio, crafting, two search minigames, professions and traits.
- **Multiplayer and admin:** examining and treating other players with consent, server-side actions and admin commands.
- **Compatibility:** Lifestyle: Hobbies, Indoor Climate Redone, MoodleFramework and others (see `docs/competability/` and
  `docs/incompetable/`), and a one-time importer for the original mod's saves.

## Compatibility with the original

- Mod ID `ExtensiveHealthRedone`. It cannot be enabled together with the original (`ExtensiveHealthReworkEvolved`) or
  its predecessor (`EHR`).
- The item module `ExtensiveHealth`, every item ID and every sandbox option name are kept, so existing saves and server
  configs carry over. On first load, long-term character data (blood type, disease knowledge, immunity, Knox
  gene-therapy and Patient Zero flags) is imported, and active illnesses and treatments are reset.

## Installing, running the tests, building art

**Players:** subscribe on the
[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3824731938), enable *Extensive Health Redone*
in the mod list, and disable the original. Needs Build 42.21 or newer. Optional:
MoodleFramework, Indoor Climate Redone, Lifestyle: Hobbies.

**From source:** `tools/deploy-dev.sh` copies `Contents/` into `~/Zomboid/Workshop/ExtensiveHealthRedone/` (the game
loads local mods from there, not through a symlink); enable the mod in the game's mod list. Run it again after each
change.

**Tests:** `tools/test.sh` (needs Lua 5.1 and busted, see Development below).

**Art:** `python3 tools/make-release-art.py` (needs Python 3 and Pillow) regenerates `42/icon.png` (256x256),
`42/poster.png` (512x512) and `preview.png` (256x256, the Workshop thumbnail; the in-game uploader insists on exactly
that size). The art is original: a blood drop with a pulse line.

**Source and bug reports:** the issue tracker of this repository (include `console.txt`).

## Repository layout

```
Contents/mods/ExtensiveHealthRedone/   the mod (the repo root is the Workshop item folder)
  42/mod.info                          mod metadata
  42/icon.png, 42/poster.png           mod list icon and poster (tools/make-release-art.py)
  42/media/                            versioned content: scripts, sandbox options, Lua, translations
  common/media/                        version-independent assets: textures, sounds, models, UI icons
tests/                                 busted specs (offline, never shipped)
tests/e2e/                             dev-only test mods for multiplayer end-to-end runs (never shipped)
tools/                                 dev scripts (tools/lib: helpers shared by tools and tests)
preview.png                            Workshop thumbnail (256x256), copied next to Contents/ when uploading
docs/addon-api.md                      extension points for mods that build on this one
docs/original-author-guides/           the original author's guides: the behaviour spec
docs/guides/                           player guides reworked from those, matching what Redone does today
docs/competability/, docs/incompetable/   one note per other mod we work with, or clash with
```

## Code layout

Project Zomboid resolves `require` and loads Lua files by path relative to `media/lua/<side>/`, shared by vanilla and
every mod: two files with the same relative path replace each other. All our code therefore sits in a folder named
after the mod, and every `require` uses the full path.

```
42/media/lua/shared/ExtensiveHealthRedone/          require "ExtensiveHealthRedone/Core/ItemTweaks"
  Core/, Data/         pure framework code and data tables: no game API, time and RNG passed in
  Blood/, Body/, Wounds/, Conditions/, Immunity/, Medication/, ...   pure feature rules; Systems.lua lists every
                                         simulation system
  Diseases/<Group>/                      disease groups (Food, Weather, Corpse, Scabies, Concussion, Mind, Knox,
                                         Shared); each Group.lua brings its conditions and systems
  Game/                shared code that touches the game (event hooks, script items); runs in every Lua VM
42/media/lua/client/ExtensiveHealthRedone/Client/
42/media/lua/server/ExtensiveHealthRedone/Server/
```

- The `Client/` and `Server/` subfolders keep relative paths unique across sides.
- `server/` is not server-only: MP clients load it too, after `OnGameBoot`. Guard server logic with `isServer()` and
  `isClient()` where it matters.
- Modules return a table and create no globals.
- `tests/layout_spec.lua` enforces these rules: the folders, no game API in pure shared code, no globals, and the two
  single writers below.

### How the framework fits together

The server (or the single-player game, which runs the same code) owns all health state. Clients mirror it and send
intents.

- **State:** one versioned table per player in modData (`Core/Schema`), upgraded through a migration chain. Timers
  store remaining time (`Core/Timers`), and only online players are simulated, so nothing advances while a player is
  offline.
- **Time:** `Core/Scheduler` runs jobs on game time; `Server/Main` drives it from `OnTick`. There are no per-feature
  tick handlers.
- **Simulation:** features add systems to `Runtime.sim` (`Core/Simulation`). Each system gets plain tables and
  describes the vanilla stat changes it wants through `Core/StatAggregator`, and the body part changes (health,
  healing caps, pain, the infected-wound flag, death) through `Core/BodyAggregator`. `Server/StatWriter` and
  `Server/BodyWriter` are the only code that writes them (enforced by `tests/layout_spec.lua`). Systems read the body
  as plain facts (`Server/Facts`), and ask `p.treatment` what medication does.
- **Client effects:** what only the owning client can do (speech, a blackout's sleep, a fall, the low-blood speed
  penalty, refusing food with lockjaw) lives in `Client/Effects`, driven by server messages or the mirrored state.
- **Commands:** every client-to-server message is declared in `Runtime.registry` (`Core/CommandRegistry`), with
  argument types, permission, sandbox `DebugMode`, rate limit, proximity, consent and item ownership checked before
  the handler runs. Permissions map to B42 role capabilities (`Game/Permissions`), never to role names.
- **Sync:** `Core/StateStore` tracks dirty sections; changed sections go to the client as deltas (`Core/Sync`), and
  a full snapshot is sent only when a client asks (on join or a stale mirror). `Game/Transport` uses the network in
  MP and direct calls in single player.
- **Vanilla patches:** each wrapped vanilla method is one entry in `Data/PatchPoints.lua`; features attach listeners
  through `Game/Patches`. Listeners observe; the only two that change an outcome (`intercept`) are the stitch
  minigame and the tetanus lockjaw.
- **Debug:** with sandbox `DebugMode` (and the medical-cheat capability in MP), G opens a debug window.

**Changing items we don't own** (vanilla or other mods) never redefines the whole item in a script file. Each change
is one `{ item, property, value, reason }` entry in `shared/ExtensiveHealthRedone/Data/ItemTweaks.lua`. At
`OnGameBoot`, it is applied with `Item:DoParam`, and each item property may appear once.

## Development

Requirements (Arch / CachyOS): `pacman -S lua51 lua51-busted lua-language-server`.
Lua 5.1 is used rather than LuaJIT because it is closer to Kahlua, the game's Lua VM.

| Task | Command |
|---|---|
| Run the checks and tests | `tools/test.sh` |
| Download PZ type stubs for LuaLS | `tools/fetch-umbrella.sh` (into `.cache/`, not committed) |
| Type-check with LuaLS | `lua-language-server --check=.` (run `tools/fetch-umbrella.sh` first) |
| Load the working copy in game | `tools/deploy-dev.sh` (copies `Contents/` into `~/Zomboid/Workshop/`; run again after each change) |

`tests/support/fake_game.lua` stands in for the game API, so `tests/wiring_spec.lua` can run the server and client
wiring end to end in single-player mode. It is not a game: anything it doesn't fake fails loudly.

`tests/e2e/` holds dev-only test mods for a real dedicated server with game clients (the `pz-mp-e2e` bench, which
keeps its server and clients in `.cache/pz-e2e/`). Each mod requires the bench's `PZE2EHarness` and this mod.
`EHRExamTreatE2E` checks that a doctor treats a remote patient from the exam window (issue #3). It needs two clients
(`admin` the doctor, `player2` the patient), standing together (`teleport "player2" "admin"` on the server console),
and a world without zombies, since attacks cancel the treatment.

`tools/test.sh` first runs `tools/check-kahlua.lua`, which rejects Lua the game can't run: anything that fails
`luac5.1 -p` (goto, `//`, bitwise operators) and uses of `io`, `os`, `debug`, `load` and 5.2+ library functions.
Beyond that, keep to the Kahlua-safe subset: never rely on `pairs` order.

Then `tools/check-api.lua` checks that every method the mod calls (`obj:name(...)`) still exists in the game API,
against the Umbrella stubs (`tools/fetch-umbrella.sh`). The fake game can't catch a vanilla rename, because it fakes our
assumptions: 42.21 renamed `IsoGridSquare:Is` to `:has`, and only the game noticed. Without the stubs the check is
skipped with a warning.

## Credits and licence

- Original design, content and assets: **Frozen_Heart** and **Hunter**. Both opened their mods to the community;
  details in `ASSETS.md`.
- Code: MIT (`LICENSE`). Reused assets are not covered by the MIT licence; see `ASSETS.md`.
