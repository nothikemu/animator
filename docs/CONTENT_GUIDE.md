# Content Guide

Almost everything in Bellows is data. This guide shows how to add each kind of content
and which test tells you you've broken something. After any change, run:

```sh
godot --headless --path . res://tests/test_runner.tscn
```

`Content` (src/autoload/content.gd) validates references at startup: unknown items, crops,
machines and NPCs are logged with the file and key. The **story** suite lints every
condition and effect in dialogue, threads and events. The **audio** suite checks that every
sound the code asks for exists.

---

## The rule language (used everywhere)

Conditions are arrays of clause strings. **All** of them must hold, and the number of clauses
is the rule's specificity (used to pick dialogue).

```
[!]kind[:arg][op value]          ops: >= <= != = > <
```

| Kind | Example | Means |
|---|---|---|
| `flag` | `flag:well_fixed`, `flag:ql_bloom=bright` | Truthy flag, or flag equals value |
| `met` | `met:barnaby` | The player has met them |
| `trust` `respect` `affection` `resentment` `fear` `shared` | `trust:barnaby>=10` | Relationship axis (−100..100) |
| `mem` | `mem:hesper:sealed_fissure` | The NPC remembers that memory |
| `mood` | `mood:mags=worried` | Current mood |
| `thread` | `thread:station7>=2` | Quest stage |
| `item` · `money` · `tool` | `item:glowbeet>=3`, `money>=30`, `tool:glass` | Inventory |
| `deed` | `deed:harvested>=1` | Running total of a deed kind |
| `day` `hour` `minute` | `day>=4` | Clock |
| `phase` `breath` `place` `view` `weekday` | `phase:hush\|night` | Membership (`\|` = or) |
| `lore` · `discovered` · `recipe` | `lore:tier1`, `discovered:places:undercroft` | Discoveries |
| `market_day` · `talked` · `gifted` · `seen_places` | `seen_places>=2` | Misc |
| World facts | `pollution>0.15`, `cistern<0.35`, `running.burner`, `machine.pump>=1`, `planted>=3`, `well_flowing`, `fissure_sealed`, `power>40`, `leaks>=3`, `air_sour_hesper>0.1` | From `Sim.fact()` |

**Effects** are strings too:

| Effect | Example |
|---|---|
| Flags | `flag:x`, `flag:x=3`, `!flag:x` |
| Items and money | `give:seal_gum*2`, `take:glowbeet`, `money+30`, `money-30` |
| Knowledge | `learn:schematic_turbine` (sets the unlock flag; recipes also go in the journal) |
| Tools | `tool:glass` |
| Quests and events | `thread:power=1`, `event:knock` |
| Relationships | `trust:barnaby+5`, `affection:hesper-3` (daily caps apply only to deeds) |
| Memory | `mem:npc:id:importance[:sentiment][:lasting]` |
| Deeds | `deed:helped_barnaby+1` (fans out to every NPC who values it) |
| Feedback | `toast:...`, `caption:...`, `notice:npc:text`, `discover:lore:id`, `met:npc` |

---

## Items (`data/items.json`)

```json
"ember_resin": {"name": "Ember Resin", "desc": "...", "category": "material", "value": 8,
  "stack": 99, "icon": "ember_resin", "uses": ["fuel"], "fuel_minutes": 240}
```

Set `"food": true` for anything Mags cooks or a market applies food quality to. Icons come from
`tools/art/icons.py`. Add a 16×16 pixel map there and regenerate. Any icon that's missing falls
back to a warning sign, so the game never shows a blank.

## Crops (`data/crops.json`)

```json
"glowbeet": {"name": "Glowbeet", "seed": "glowbeet_seed", "days": 3,
  "ranges": {"light": [0.35, 1.0], "moisture": [0.45, 0.92], "temp": [16, 30], "sour": [0.0, 0.12]},
  "yield": {"glowbeet": [2, 4]}, "seed_return": [0, 1], "light_when_mature": 0.35,
  "thirst": 0.7, "tint": "glow", "sprite": "crop_glowbeet"}
```

Growth runs every 10 in-game minutes and multiplies the factor for each range. The plain-language
crop line names the worst factor ("too dark", "the air is fouled"). `light_when_mature` makes
the crop a light source. That's how glowbeets light their neighbours. Sprites have four growth
stages (`tools/art/props.py`). The **crops** suite covers growth and yield.

## Machines (`data/machines.json`)

A machine is a bag of components. One generic evaluator runs all of them.

| Component | Shape | Does |
|---|---|---|
| `power` | `{"produce": 40}` / `{"consume": 15}` | Joins its wire network |
| `battery` | `{"capacity": 900, "rate": 30}` | Stores surplus |
| `crank` | `{"power": 20, "minutes": 30}` | Power while hand-cranked |
| `turbine` | `{"per_flow": 700, "max": 14}` | Power from water falling through its cells |
| `fuel` | `{"items": {"glowbeet": 90}, "capacity": 10}` | Burns items for minutes |
| `pump` | `{"rate": 0.6, "manual": false}` | Pulls water from its cells into the pipe |
| `intake` / `outlet` | `{"rate": 1.0}` | Pipe ends |
| `water_use` | `0.03` | Consumes water from the pipe |
| `well`, `tank` | `{"capacity": ...}` | Stores water |
| `sprinkle` | `{"radius": 2}` | Wets surface soil |
| `scrub` | `{"sour": 0.03, "radius": 2}` | Cleans gas around it |
| `filter` | `{"item": "filter_pad", "minutes": 720}` | Consumable for scrubbers |
| `waste`, `compost` | | Output buffers you empty |
| `fan` | `{"dir": [0, -1]}` | Pushes gas |
| `heat`, `heat_move`, `emit_gas` | | Changes the fields |
| `light` | `{"color": "amber", "energy": 1.6, "grow": 0.55}` | Lights cells and crops |
| `requires` | `{"governor_coil": 1}` | Parts to install before it runs (story machines) |

Other keys:
- `size`, plus `placement`: one of `floor`, `water`, `surface`, `ceiling` or `any`.
- `cost`, plus `unlock`: either `start` or a schematic flag.
- `waterproof`, `needs_air`, `max_temp`, `dirty`, `noise`, `fixed`.

Each machine also needs a sprite strip in `tools/art/machines.py`, with five frames: idle,
active ×3 and broken. Statuses come from `MachineWorld.STATUS_PRIORITY`, and each one maps to
a sentence in `src/ui/inspect.gd`. The **machines** and **engineering** suites cover these.

## Recipes, markets, biomes

- **Recipes** (`recipes.json`): `inputs`, `output {item|machine, n}`, `station`, optional `unlock` flag.
  Something must teach every unlock: a dialogue `learn:`, a schematic, or a thread effect.
- **Markets** (`markets.json`) list:
  - `buys` and `sells`;
  - `targets` (the stock level at which price equals the item's value; scarcity moves it
    within 0.5–2×);
  - `schematics`, each with its own `when` rule.
- **Biomes** (`biomes.json`): lighting, fog, ambience bed (must exist in `assets/audio/ambience`),
  music cue, temperature, hazard.

## People (`data/npcs/<id>.json`)

A resident sheet has the following fields:
- `name`, `short`, `title`, `home`, `sprite`, `portrait`, `color`.
- `voice {timbre, pitch, rate}`: the timbre needs `assets/audio/sfx/voice_<timbre>.ogg`.
- `profile`: personality, history, goals, fears, contradiction, problem. This is writing
  guidance, and isn't shown to the player.
- `values`: deed value → axis changes, e.g. `"pollution": {"affection": -3}`. This is how
  people notice things you never told them.
- `likes`, `loves`, `dislikes`: used for gifts.
- `tolerance`: the air a person will go indoors to avoid.
- `schedule`: blocks of `{from, to, at, do, why, when?}`.
  - The **last** matching block wins, so conditional overrides go at the end.
  - `at` is a named point in the area map. `do` is one of `work`, `crank`, `tend`, `cook`,
    `inspect`, `sleep`, `sit`, `rounds`, etc.
- `unknown`: how they're referred to before you've met.

Deed kinds map to values in `Society.DEED_VALUES`. To make a new action matter to people, emit
`GameState.add_deed("kind", amount)` and add the kind there. Character sheets are layered
ASCII pixel maps in `tools/art/chars.py`.

## Dialogue (`data/dialogue/<npc>.json`)

```json
{"lines": [
  {"id": "b_sour", "tier": "reactive", "when": ["pollution>0.15"], "text": "You can taste it in the lane."},
  {"id": "b_wren", "tier": "story", "once": true, "when": ["flag:took_crew_tag"], "convo": "wren", "priority": 20},
  {"id": "o_amb", "tier": "ambient", "text": "Buying or selling?", "open": "shop:exchange"},
  {"id": "b_bark1", "tier": "bark", "text": "Mind the pipe-heads."}
 ],
 "convos": {"wren": [
  {"say": "Where did you get that.", "emote": "surprised"},
  {"choice": [{"text": "You saved Wick.", "do": ["trust:barnaby+4"], "goto": "saved"}, ...]},
  {"label": "saved"}, {"say": "...", "who": "narrator"},
  {"do": ["event:knock"]}, {"if": ["flag:x"], "goto": "end"}, {"open": "shop:exchange"}
 ]}}
```

- **Picking a line**: tier weight (story 300, reactive 200, ambient 100) + 5 × specificity +
  `priority`, minus 60 if already heard today. `once` lines are used up for good. Barks play
  when the player walks by.
- **Node types**:
  - `say` (with optional `emote`: happy, sad, surprised or annoyed; and `who`: the NPC,
    `player` or `narrator`);
  - `choice` (each option can have `when`, `do` and `goto`);
  - `do`, `if`/`goto`, `label`, `open` (a panel to show when the conversation ends).
- **Text tokens**: `{player}`, `{name:npc}`, `{price:market:item}`, `{trend:market:item}`,
  `{time}`, `{day}`, `{item:id}`, and `{key:action}` (the player's current binding for an action).
- **Voice**: one opinion per line, concrete nouns, no exposition dumps. Barnaby says it once.
  Odile counts. Hesper talks to the moss. Mags gets it slightly wrong. Grist… pauses.

## Quest threads (`data/threads.json`)

```json
"power": {"title": "Feeding the Cistern", "priority": 9, "start": ["flag:b_thanked_well"],
  "stages": [
    {"note": "...", "advance": ["machine.pump>=1"]},
    {"note": "...", "advance": ["running.pump"]},
    {"note": "...", "done": true, "on_enter": ["deed:water_restored+2", "flag:cistern_fed"]}]}
```

Threads are checked every in-game minute. Notes are written as the player's own shorthand, and
`branch` jumps to a stage when its condition holds. The **story** suite walks the first day, and
**full_arc** plays the chapter through to the end.

## Director events (`data/events.json`)

```json
"tremor": {"when": ["thread:station7>=2", "day>=4", "phase:wake|bloom"], "once": true,
  "chance": 1.0, "intensity": 3, "shake": 1.0, "hook": "tremor", "toast": "...", "caption": "...",
  "effects": ["mem:barnaby:tremor:3:-0.2"]}
```

The Director runs once an hour:
- It only considers eligible cards, so cards fire on conditions, not pure chance.
- It respects `cooldown` (in days).
- After intensity ≥ 2 it holds a calm window, so crises don't stack.

`hook` calls `Director._hook_<name>()` for events that reshape the world (the Tremor,
Quietlight, the valve). Cards marked `manual` fire only from an `event:` effect.

## Lore (`data/lore.json`)

`{title, where, text}`. Lore is discovered by reading ruin pages in the Reach (ids `tier1`–`tier3`
and `trunk`), by inspecting relics in the cut (`relic_<type>`), or through effects. It appears
under **Journal → Found**. Each entry should answer one question and raise another.

## Maps

- **Wick** and its Undercroft are authored in `tools/maps/build_maps.py`, which writes
  `data/wick_map.json` and `data/undercroft_wick.json`. That covers heights, materials, props,
  points, pipes, machines, water, springs, vents, gas pockets, the fissure and relics.
- **The Reach** is generated from the world seed by `src/world/reach_gen.gd` (see
  [SYSTEMS.md](SYSTEMS.md)).
