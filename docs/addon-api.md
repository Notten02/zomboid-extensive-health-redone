# Add-on API

Extension points for mods that build on Extensive Health Redone. An add-on requires `ExtensiveHealthRedone` in its
`mod.info` and talks to EHR only through these: it never wraps vanilla methods itself, never writes stats or body parts,
and never writes into EHR's data tables.

The rules that bind EHR's own code bind an add-on too (see "Code layout" in the README):

- The server owns all state. Systems describe what they want through the aggregators on the player context
  (`p.stats`, `p.body`, `p.fx`, `p.mods`, `p.perks`); only the writers touch the game.
- Prefix everything that shares a namespace with EHR: condition ids, section names, server message names
  (`Client.on` keeps one handler per name), command names, moodle names, patch point and listener names.
- Register at load, from the side named below. Shared registrations must run on MP clients too, because the client
  builds the Monitor, tooltips and moodles from the same tables.

## State and simulation

| What | Call | Side | Notes |
|---|---|---|---|
| A state section | `Schema.registerSection(name, { defaults, version, migrations, exam, resetOnHeal })` (`Core/Schema`) | shared | Saved in the player's modData with EHR's state and synced to the owning client like EHR's sections. The section's own version lives in its field `v`; `migrations[from](section)` upgrades it. A section saved by a newer add-on version leaves the state untouched, as EHR's own schema does. `exam = true` copies it into the exam window's model, `resetOnHeal = true` resets it on an admin's full heal (a reset always does). |
| A simulation system | `Runtime.sim:add({ name, order, update(p, dt) })` (`Server/Runtime`) | server | Order guide in `Systems.lua`. Run before 200 to scale blood recovery in the same step. |
| A command | `Runtime.registry:register(name, spec)` | server | `Core/CommandRegistry` lists the argument and access checks. |
| A scheduled job | `Runtime.scheduler:every(name, minutes, fn, opts)` | server | |
| Facts from the game | `Facts.extend(name, fn(player, facts))` (`Server/Facts`) | server | Body part facts include the healing timers: `scratchTime`, `cutTime`, `deepTime`, `burnTime`, `fractureTime` and `fracture`. |
| Rate multipliers | `p.mods:scale(key, source, factor)` (`Core/Modifiers`) | in a system | Lowest factor per key wins. Keys EHR reads: `bloodRegen` (order 200), `immunityRise` (order 395). |
| Strength and Fitness loss | `p.perks:drain(perk, source, xpPerHour)` (`Core/PerkAggregator`) | in a system | Highest drain per perk wins. `Server/PerkWriter` applies it the way vanilla's own passive-skill decay does: negative XP, then a level lost below the level's XP. |
| Admin full heal | `FullHeal.onHeal(fn(p, mode))` (`Admin/FullHeal`) | shared | Runs after a heal or reset changed the state. Every condition ends on a heal, so reset what drives yours here. |

## Conditions and knowledge

| What | Call | Side | Notes |
|---|---|---|---|
| A condition | `Registration.register(id, def)` (`Conditions/Registration`) | shared | The fields `Conditions/Engine` lists, plus `alert = false` (no Medical Alert moodle), `pressure = false` or `"half"` (disease pressure on the immune system), `strand` and `display = { icon, category, lethal, unknownName, unknownDesc, handbook, lockedDesc }` (`lockedDesc`: the text of a locked handbook entry, how to unlock it). Set `master = false` and `xp = false` unless the condition is a disease. |
| Sandbox options of your own | `"Namespace.Option"` wherever EHR reads an option for you (`enabledOption`, `speedOption`, `audioOption`, `option`) | | `Env.sandbox` reads `SandboxVars.Namespace.Option`. |
| A knowledge strand | `Knowledge.registerStrand(id, rule(state, def, firstAid, level))` (`Conditions/Knowledge`) | shared | A condition with `def.strand` is judged only by the strand's rule: an EHR doctor or First Aid 8 does not name it. The rule returns `{ name, stage, progress }`. |
| Learning a strand | `Learn.strand(p, id, level, nameKey)` (`Knowledge/Learn`) | in a system or `Runtime.applyNow` | Raise-only; saved in `state.knowledge.strands`, so the exam sees the doctor's level. |

## Medication

| What | Call | Side | Notes |
|---|---|---|---|
| A medication | `MedData.register(fullType, entry)` (`Medication/Data`) | shared | The entry format is at the top of `Medication/Data`. `course = true` runs the doses as a course (interval, waste, abandon) without curing anything. |
| React to a dose | `Doses.onDose(fn(p, med, outcome))` (`Medication/Doses`) | shared | Called for every dose that counted, in the same step. |
| A drug interaction | `Interactions.register(id, { a, b, line, effect, weakens })` (`Medication/Interactions`) | shared | `a` and `b` are medication categories. `effect(p)` runs once when both become active; `weakens = { category, factor }` scales the relief of that category's doses while both are active (activated charcoal halves antibiotics this way). |

## Body and effects

| What | Call | Notes |
|---|---|---|
| Slower wound closing | `p.body:woundSpeed(part, source, factor)` | Scratch, cut, deep wound and burn timers fall at `factor` of vanilla's pace. Lowest factor wins. |
| Slower fracture healing | `p.body:fractureSpeed(part, source, factor)` | The same for the fracture timer. |
| A wound opening again | `p.body:reopen(part, source, kind)` | `kind`: `"scratch"`, `"cut"` or `"deep"`; never carries Knox. |
| Slower HP healing | `p.body:healFactor(part, source, factor)` | Lowest factor wins. |
| Night blindness | `p.fx:nightVision(source, level)` | 0-1, highest wins. The client darkens and blurs the view only where the character's square is dark. |
| Unsteady aim | `p.fx:aim(source, multiplier)` | Ranged weapon hit chance multiplier, lowest wins. |
| A stagger | `p.client("stagger")` | A stumble that doesn't knock the character down. |
| A sound | `Noise.register(kind, def)` (`Server/Noise`, server), then `p.noise(kind)` | The `Data/Noise` fields. |

## Game hooks

| What | Call | Side | Notes |
|---|---|---|---|
| A vanilla patch point | `Patches.define({ name, path, side, named })` (`Game/Patches`) | as `side` | Same fields as `Data/PatchPoints`. Then `Patches.on(name, listener)`. A point defined after the first install is installed at once. Check `Data/PatchPoints` first: a method is wrapped once, by whoever defines it. |
| What was drunk | `Patches.on("drinkFluidUpdateEat", listener)` | server | Every sip, also of a drink stopped part way. `action.consumedRatio` before and after the call gives the sip as a share of the container. |
| What was eaten | `Food.onBite({ name, describe(item, action), bite(p, data, portion) })` (`Server/Food`) | server | `describe` runs before vanilla eats the item; `bite` runs in the same step as the food-borne risks. `portion` is a share of the item's base hunger. |
| No stale-food risk | `Risk.exemptStale(name, exempt(food))` (`Diseases/Food/Risk`) | shared, at load | `exempt` returns true when a stale bite carries no food-poisoning risk for being stale (the food description in `Diseases/Food/Risk`, with `heat` and `frozen`). Rotten, burnt and uncooked food keep their risks. Without a registered rule, stale food always counts. |
| An item script change | `ItemTweaks.add(tweak)` (`Game/ItemTweaks`) | shared, at load | The `Core/ItemTweaks` format. Two mods changing the same item property fail at boot. |

## UI

| What | Call | Side | Notes |
|---|---|---|---|
| A character window tab | `CharacterWindow.addTab({ id, name, create, visible, order })` (`Client/CharacterWindow`) | client | After EHR's tabs. `toggle(playerNum, id)` and `open(playerNum, id)` take its id; the view's `markStale()` runs after each sync of the player's mirror. |
| A condition's Monitor row | `def.monitorRow(row, c, known, input)` on the condition definition | shared | Called after EHR built the row: set `description`, `progress`, `progressText`, `status` and their colours (the `UI/Monitor` row fields; the description wraps to two lines), for example the progress of a driven condition, which has no timers. `known` is what the reader knows; the exam calls it with the doctor's knowledge. A failure leaves the row as EHR built it (`Monitor.rowErrors`). |
| Monitor rows | `Monitor.addRowProvider(name, fn(input) -> rows, order)` (`UI/Monitor`) | shared | Rows that aren't conditions. The exam builds the same model with the doctor's knowledge, so gate on `input.state.knowledge` and read only sections registered with `exam = true`. |
| A moodle | `Moodles.register(id, { name, icon, compute(section, player) -> level, title, desc })` (`Client/Moodles`) | client | A bad moodle, levels 1-4, through MoodleFramework when it is active. |
| A sleep refusal line | `Sleep.registerReason(source, key)` (`Client/Sleep`) | client | For a source of `p.fx:noSleep`. |
| Item tooltip lines | `ItemTooltip.addProvider(fn(item, player) -> lines)` (`Client/ItemTooltip`) | client | |
| Mirrored state | `Client.section(player, name)`, `Client.onChange(fn)`, `Client.on(command, fn)` (`Client/Client`) | client | |
| Log lines | `Env.logger(tag, "[YourMod] ")` (`Game/Env`) | any | Follows EHR's DebugMode level. |

## Testing an add-on

`tests/support/sim.lua` builds a player context for pure systems, and `tests/support/fake_game.lua` runs EHR's server
and client wiring offline. From an add-on's repository, with EHR checked out next to it:

- add EHR's `shared/` folder and its `tests/` folder to the busted `lpath`;
- `require("support/sim")` for pure systems;
- `FakeGame.install({ root = "../extensive-health-redone/" })` for wiring tests, then `game.sandboxFor(namespace)`,
  `game.addEvent(name)` and `game.addPerk(name)` for what the add-on needs.

`tests/addon_api_spec.lua` and `tests/wiring_addon_spec.lua` use every extension point above.
