# Extensive Health Rework Evolved (the original) and Extensive Health Rework B42 (its predecessor)

- **Mod ids:** `ExtensiveHealthReworkEvolved` (Frozen_Heart, v0.9) and `EHR` (Hunter)
- **Workshop ids:** `3726328119` and `3638633196` (the predecessor is not downloaded here)
- **Status:** **cannot be enabled together with Extensive Health Redone, by design.** Prevented in the mod screen and logged if it happens anyway (`tests/compat_spec.lua`); the mod screen was not run in a game client.

## Why they cannot share a game

Redone keeps the original's identity on purpose, so a save can switch over: the item module `ExtensiveHealth` and every item id, and the sandbox namespace `ExtensiveHealthRework.*` with its option names. Two health mods would own the same items and options, and both would write the same vanilla stats, blood and Knox state.

## How it is enforced

- **`mod.info`:** `incompatible=` lists both ids in both spellings (`\ExtensiveHealthReworkEvolved`, `\EHR`, `ExtensiveHealthReworkEvolved`, `EHR`), which the game's mod selector reads and refuses.
- **Runtime:** `Server/Main.checkOriginals` logs an error naming the original when it is active (a server's mod list or a hand-edited save can still enable both).

## Switching a save over

Redone imports the permanent part of the original's player data once (blood type, disease and journal knowledge, flyers, radio, immunity score, Knox gene-therapy and Patient Zero flags) and resets everything active (illnesses, treatments, wound infections, blood loss, cooldowns). It removes the old `EHR_*` keys and never imports twice. Item ids and sandbox values carry over unchanged. Offline check against 8 real saves: `tests/real_saves_spec.lua`; to try a save: `tools/prepare-migration-save.sh`.
