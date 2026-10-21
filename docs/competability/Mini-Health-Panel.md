# Mini Health Panel

- **Mod id:** `MiniHealthPanel`
- **Workshop id:** `2866258937` (v1.6.1.42 in its `42/` folder, versionMin 42.13, author Speedy Von Gofast; the root folder is the old B41 v1.5)
- **Status:** supported since 2026-10-21. Built and tested offline (`tests/mini_health_spec.lua`); our API check over its Lua finds one unknown method, `ModOptions:loadFile`, which it guards itself. **Not yet in a game client.**

## How we are compatible

**A companion panel, no wraps.** The mod keeps one global panel, `mhpHandle` (an ISPanel created when the first local player is created). We read it, never change it, and dock our own small "EHR Status" panel beside it. It wraps none of our patch points. Without the mod, `Client/MiniHealth.lua` does nothing.

**Ties** (`UI/MiniHealth.lua` model, `Client/MiniHealth.lua` panel, client side):

| Tie | What happens |
|---|---|
| Docking | Right of its wound figure, or left when that would leave the screen; follows its position, visibility and fade (alpha). |
| Four rows | Blood, infected wounds, sepsis and the worst illness, from our mirror with the same knowledge rules as the EHR Monitor: blood needs the Medical Monitor Watch (else `?`), stages need First Aid (else `?`), nothing active shows `--`. |
| Multiplayer | Works in MP too (v0.9's companion was single player only), because it reads the mirror. |
| Guard | Every read of the host is a logged `pcall`; if it does not look as expected the panel switches itself off for the session. A new game in the same session gets a new panel. |

13 new texts in all nine languages (`UI_EHR_Mini_*`; the translations are machine translated).

## Not done / open

- Needs a game client: docking, dragging, fading and the screen-edge flip; that the host's `alpha` and `getPlayer` behave as read from its code.
- Split screen: Mini Health Panel itself serves only the first local player, so the companion does too.
