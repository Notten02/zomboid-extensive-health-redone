# Assets and credits

Extensive Health Redone is a rewrite. Its **code** is new and MIT-licensed (see `LICENSE`). Its **content** comes from
the two mods it continues. That content is credited to their authors below and is **not** relicensed under MIT.

## Origin

| Mod | Author | Workshop | Mod ID |
|---|---|---|---|
| Extensive Health Rework Evolved (v0.9) | Frozen_Heart | [3726328119](https://steamcommunity.com/sharedfiles/filedetails/?id=3726328119) | `ExtensiveHealthReworkEvolved` |
| Extensive Health Rework B42 | Hunter | [3638633196](https://steamcommunity.com/sharedfiles/filedetails/?id=3638633196) | `EHR` |

Everything below was copied from Extensive Health Rework Evolved v0.9, which grew out of Hunter's mod. The files don't
record which author made which asset, so both authors are credited for all of them.

## Permission

Both authors publicly opened their mods for others to continue. Their Workshop pages are archived verbatim in
`docs/original-author-guides/`:

- **Frozen_Heart** (`workshop-description.md`): *"Feel free to modify, fix, edit, whatever. I don't own these mods, the
  community does."* They also recommend rebuilding the mod from scratch, which is what this project does.
- **Hunter** (`predecessor-workshop-description.md`): *"i decided to open this mod up for other modders to continue
  working on and improve"*. Hunter also points users to Frozen_Heart's version.

## What was reused

| Content | Location in this repo | Count |
|---|---|---|
| Textures (item icons, disease and moodle icons, UI tabs, minigame art) | `Contents/mods/ExtensiveHealthRedone/common/media/textures/` | 178 |
| Sounds (coughs, sneezes, delirium audio) | `common/media/sound/` | 23 |
| 3D models | `common/media/models_X/EHR/` | 3 |
| Trait icons | `common/media/ui/Traits/` | 2 |
| Item, recipe, sound, trait, profession and watch scripts | `42/media/scripts/` | 11 files |
| Sandbox options | `42/media/sandbox-options.txt` | |
| Trait and profession registrations | `42/media/registries.lua` | |
| Translations (9 languages) | `42/media/lua/shared/Translate/` | 54 files |

## Changes made on import

- **Dropped** superseded or duplicate textures: the six `EHR_Tab_*(OLD).png`, `Item_AlbendazoleInjectionOLD.png`,
  `Item_EpinephrineOLD.png`, `Item_PainkillersOLD.png` and `Item_Item_HomemadeCoughSyrup.png`.
- **Dropped** `spider-web-cobweb-icon-spiderweb-border-vector-36034555..png`. Nothing referenced it, and its file name
  suggests a stock-image download whose licence we can't confirm.
- **Not imported:** `EHR_VanillaOverrides.txt`. It redefined seven vanilla items wholesale. The rewrite adjusts those
  items property by property at load time instead.
- **Not imported:** the original's Lua code (rewritten from scratch) and its stale root-level `media/` folder.
- **Missing models fixed:**
  - Seven `model` definitions pointed at an `EHR/InjectorBase` mesh and texture that never shipped. They were removed.
    The 11 items that used them now have no 3D model and fall back to their inventory icon, like the mod's other
    syringes and IV bags. The items are `CorticosteroidInjection`, `TetanusAntitoxin`, `TetanusImmunoglobulin`,
    `AlbendazoleInjection`, `IVAntibiotics`, `IVMetronidazole`, `IVAmphotericin`, `IVCiprofloxacin`, `IVVancomycin`,
    `GeneTherapyKit` and `ImmunoboosterShot`.
  - 25 flyer and guide items used the vanilla model `Magazine_Ground`, which no longer exists in 42.21. The disease
    flyers and `MedicalWildPlants` now use vanilla `Flier1`; the two recipe guides use vanilla `Magazine`.
- **Item icons made 32×32**, the canvas vanilla uses for item icons in its texture packs:
  - The ten `Item_BloodBag*.png` icons and `Item_SalineBag.png` were 189 to 1254 px wide (up to 6 MB each). They were
    trimmed and fitted into 32×32.
  - 68 other icons were not square (e.g. 32×27, 32×67, 65×54). Those that fit were padded with transparency, unscaled.
    Those larger than 32 px on a side were trimmed and fitted into 32×32.
  - The original art remains in the original mod (`42/media/textures/`) if a larger export is ever needed.
- **Translations re-keyed:** the original keyed 792 UI lines by a hash of their English text (`UI_EHR_Line_<hash>`).
  `tools/translations/rekey-ui-lines.lua` renamed them to readable `UI_EHR_Text_<Words>` keys in all 9 languages. It
  dropped 18 entries that were code fragments rather than text and 2 stale debug lines. For two lines with no English
  entry, it took the English from the original's source code.
- Line endings normalised to LF. Item IDs, the `ExtensiveHealth` module name and sandbox option names are unchanged so
  that saves and server configs carry over.
