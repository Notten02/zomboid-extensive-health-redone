# Lifestyle: Hobbies

- **Mod id:** `LifestyleHobbies`
- **Workshop id:** `3403870858` (v0.4.0.3, author Angry)
- **Status:** **not supported, blocked.** `mod.info` lists it as incompatible (both id spellings) since 2026-11-02, so
  the game's mod screen won't enable it together with ours. Found in a single-player game on 42.21: the health state
  stopped being saved about an hour of game time after every load.

## Why it clashes

Lifestyle copies the player's whole modData and writes it back, which replaces our state table with a copy.

- **Theirs:** `client/ZLSUpdate.lua` calls `sendClientCommand(character, "LS", "SavePlayerData",
  {character:getModData()})` on a game-time timer (sandbox `LS.ModdataUpdate`; with its default and a `DayLength`
  setting of 4 to 6 it falls back to once per game hour). The handler, `server/LSservercommands.lua`, writes every key back:
  `for k, v in pairs(data) do playerData[k] = v end`. A client command's arguments arrive as a copy, so every table in
  the player's modData is replaced by a snapshot, `ExtensiveHealthRedone` included. The sandbox option has no "off".
- **Ours:** the server loads the state table from `modData.ExtensiveHealthRedone` once, when the player is attached
  (`Server/PlayerState`), and keeps simulating that table. After Lifestyle's first update the game saves the snapshot
  instead, and every later update copies the stale snapshot again. Everything after the first hourly update is lost
  on the next load: conditions, timers, medication, immunity, and add-on sections such as Extensive Food Redone's
  meal journal and reserves.
- **Multiplayer** is worse: the client sends its own copy of the modData, so the server's state is overwritten with
  whatever the client holds.

## What was removed

Until 2026-11-02 Lifestyle was supported as an optional mod. All of it is gone:

- the recovery pace from its hygiene, shower, sitting comfort and yoga readings (`Lifestyle/Pace`,
  `Server/Lifestyle`, `Client/Lifestyle`, `Game/Lifestyle`), and its use in `Conditions/Engine`;
- a Lifestyle shower counting as bathing for the heat and cold meters (`Diseases/Weather/Meters`);
- the `bladder` client effect, through which dysentery and furosemide raised its bathroom need, and the anti-diarrheal's
  `bathroomNeed` relief;
- the tub animations and positions in the heat-stroke cold bath, which now always uses the plain crouch
  (`Client/ColdBath`).

Saves that ran with it keep a stale `effects.bladder` field; nothing reads it.
