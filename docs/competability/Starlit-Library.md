# Starlit Library

- **Mod id:** `StarlitLibrary`
- **Workshop id:** `3378285185` (v42-1.4.3 in its `42/` folder; a library other mods depend on, for example Repairable Windows, so it is often enabled without the player choosing it)
- **Status:** conflict found and fixed 2026-10-21 (`tests/client_spec.lua`, "lets a library swap DoTooltip on the item's metatable"). Found by reading its code. **Not yet in a game client.**

## How we are compatible

**The clash.** Both mods wrap `ISToolTipInv.render`. Starlit's wrap reads `getmetatable(self.item).__index` and then indexes the result (and swaps `DoTooltip` on it while it renders). For items that get our extra tooltip lines, we put a Lua stand-in in `panel.item`, and its metatable's `__index` was a function, so Starlit's wrap would have errored on every frame while an EHR or tweaked item was hovered.

**The fix** (`Client/ItemTooltip.lua`): the stand-in's metatable `__index` is now a table that forwards every key to the real item. Whatever Starlit writes there lands on that throw-away table and never reaches the item class. Our wrap is the outermost and puts the real item back afterwards.

**What players see:** an EHR item shows vanilla's tooltip plus our lines. Starlit's own tooltip changes apply to other items, not to ours (inferred from the code).
