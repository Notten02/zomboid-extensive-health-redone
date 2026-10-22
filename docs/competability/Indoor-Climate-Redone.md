# Indoor Climate Redone

- **Mod id:** `IndoorClimateRedone` (Workshop id not known yet: not published). A rewrite of Indoor Climate (EHR
  Addon) by Frozen_Heart, mod id `IndoorClimateLiteB42`, Workshop id `3772549209` (v0.12.2), the same author as the
  original Extensive Health Rework Evolved.
- **Status:** supported. Built and tested offline (`tests/temperature_spec.lua`); Indoor Climate Redone keeps the
  original's API names and sample fields, which were checked in both mods' source. **Not yet seen in a game client**
  (the cold meter should stop building in a heated house).

## How we are compatible

**Read-only, public API.** We call `isActive`, `getRoomDescriptor` and `getTemperatureSample` of the global
`IndoorClimateLite` and read `source`, `active`, `indoors`, `roomKey` and `airC` of the sample. Every call sits behind
one logged `pcall` (`Game/IndoorClimate.lua`), so a changed API costs the feature, not the game. Without the mod, or
with it switched off, everything says "nothing" and vanilla's air is used. Indoor Climate Redone needs nothing from us.

**Ties** (`Game/IndoorClimate.lua`, `Server/IndoorClimate.lua`):

| Tie | What happens |
|---|---|
| Room air feeds the meters | Inside a room the mod simulates, its air temperature replaces vanilla's in `facts.env.airC`, so the cold meter, the heat meter and heat-stroke cooling see heated houses, cold rooms and hot attics. Vanilla's reading is kept as `nativeAirC`. Body temperature stays vanilla's (the mod's warmth reaches it through its own heat sources). |
| Single player and multiplayer | The server reads the player's sample through the public API. Indoor Climate Redone simulates rooms on the dedicated server, so the server has the real value; no client report is needed or trusted. |
| The original Indoor Climate (EHR Addon) | It uses the same API, so it still works in single player. It computes samples only on the client, so on a dedicated server we get none and use vanilla's air. Use Indoor Climate Redone instead; the two cannot be enabled together. |
