# Technical Architecture

Engine: **Godot 4.7.2-stable**, GDScript with static typing throughout.
Renderer: **Forward+** (default), **Mobile** for the Low preset; Compatibility supported with
reduced effects (DOF falls back to a screen-space tilt-shift pass).

## 1. Principles
1. **Simulation is plain data + pure functions.** Every simulation module is a `RefCounted`
   class with no scene-tree dependency, so it runs in headless tests.
2. **Presentation observes, never owns, state.** Visual nodes read from `GameState`/sim objects
   and listen to `Events`; they can be rebuilt at any time from state, which is what makes
   save/load and area streaming trivial.
3. **Content is data.** Items, crops, machines, recipes, NPCs, schedules, dialogue, quests, events,
   biomes and the Wick map are JSON in `data/`. Adding a crop or machine means adding data, plus an
   optional sprite. Code never switches on a content ID.
4. **Fixed-rate simulation, variable-rate rendering.** Each system ticks at the rate it needs.
5. **Fail soft.** Invalid data or state is clamped and logged with context; it never crashes the game
   or corrupts a save.

## 2. Directory layout
```
project.godot
assets/            generated textures, audio, fonts (+ licences)
data/              JSON content (see §5)
shaders/           .gdshader files
scenes/            .tscn (boot, menu, game, ui, test scenes)
src/
  autoload/        singletons (thin orchestration)
  sim/             pure simulation (grid, networks, machines, crops, rng)
  world/           area maps, terrain/prop builders, Reach generator, area streaming
  actors/          player, NPCs, pixel sprites
  camera/          camera rig (explore, cut transition, dialogue framing, shake)
  engineering/     cross-section view, build tool, overlays, inspection
  social/          relationships, memory, dialogue rule matcher, schedules
  economy/         markets
  ui/              HUD, dialogue box, panels (pack, workbench, shops, board, journal, map,
                   lore, pause, saves), settings tabs, title screen, theme
  save/            codec + migrations (save_codec.gd)
  debug/           dev overlay + console, scenarios, visual/audio/stress test scenes
  game.gd          the game scene: areas, actors, camera, story sequences, adaptive music
  game_flow.gd     new game / continue / quit to title (one reset path for everything)
tests/             headless test runner + suites
tools/             Python content generators (art, audio, fonts) and capture scripts
docs/
```

## 3. Runtime structure

### 3.1 Autoloads (load order)
| Autoload | Responsibility |
|---|---|
| `Log` | Structured logging (`Log.info/warn/error(ctx, msg)`), ring buffer for the debug overlay |
| `Events` | Global signal bus (deeds, sim changes, UI requests) |
| `Content` | Loads and validates `data/`, exposes typed lookups |
| `Settings` | `user://settings.cfg`, input remapping, applies graphics/audio/accessibility |
| `GameState` | The single save-able state root (see §4) |
| `Clock` | In-game time, speed (pause/1×/3×), hour/day signals |
| `Sim` | Owns Undercroft grid + networks + machines + crops; fixed-rate scheduling |
| `Society` | Relationships, memories, gossip, moods |
| `Economy` | Market stocks and prices |
| `Threads` | Quest/thread stages |
| `Director` | Event cards, tension pacing |
| `Dialogue` | Rule matching + conversation runner |
| `Audio` | Music director (stems), ambience, pooled SFX, voice blips |
| `Saves` | Slots, atomic writes, backups, migration |
| `Dev` | Debug overlay + console (only with `--dev` or in debug builds) |

### 3.2 Game scene
```
Game (game.gd)
├─ AreaHost            current area (Wick or a Reach cavern), streamed one at a time
│  ├─ Terrain chunks   ArrayMesh per 16×16 chunk, atlas texture, AO in vertex colour
│  ├─ Props            generated box/billboard prefabs
│  ├─ Actors           Player, NPCs (PixelSprite3D)
│  ├─ Lights / FX
│  └─ Undercroft       (Wick only) cross-section geometry, machines, conduits, gas/water planes
├─ CameraRig → Camera3D (+ CameraAttributesPractical for DOF)
├─ WorldEnvironment    per-area preset, blended by pollution and time of day
├─ PostFX (CanvasLayer) final grade: vignette, grade, grain, tilt-shift fallback, strata wipe
├─ HUD (CanvasLayer)
└─ Overlay menus (CanvasLayer)
```

### 3.3 Update frequencies
| System | Rate | Driver |
|---|---|---|
| Rendering, camera, sprite animation | every frame | `_process` |
| Player/NPC movement & grid collision | 60 Hz | `_physics_process` |
| Undercroft fields (gas, water, heat, moisture) | 4 Hz × time speed (max 4 substeps/frame) | `Sim` accumulator |
| Networks + machines | 1 Hz × time speed | `Sim` |
| Crops | every in-game 10 minutes | `Clock.minute_tick` |
| NPC schedule decisions | on in-game minute change | `Clock` |
| Event Director | every in-game hour | `Clock.hour_changed` |
| Gossip, economy relaxation, memory decay | daily (at Dimming / on sleep) | `Clock` |

## 4. State model (`GameState`)
```
world:     seed, version, day, minute, breath_phase, flags{}, facts{}
player:    name, area, pos, facing, tools[], active_tool, breath, money
inventory: slots[{id, n}]
farm:      plots[{cell, crop, growth, health, water, planted_day}]
undercroft: grid arrays (materials, gas×4, water, temp, moisture), conduits, machines[]
areas:     reach graph (from seed) + per-area deltas (mined nodes, opened passages)
npcs:      {id: {axes{}, memories[], mood, met, gifts_today, schedule_override}}
economy:   {market: {item: stock}}
threads:   {id: stage}
history:   deed counters
discovered: places, recipes, lore, people
```
Everything that is not derivable from the seed lives here. Visual nodes are rebuilt from it.

## 5. Content data (`data/`)
| File | Defines |
|---|---|
| `items.json` | id, name, description, category, value, icon, stack, uses |
| `crops.json` | growth days, condition ranges, yields, emissions (light, gas scrub) |
| `machines.json` | size, cost, ports, consumption, production, emissions, operating ranges, sprite |
| `recipes.json` | inputs, output, station, unlock condition |
| `npcs/*.json` | profile, values, tolerances, schedule blocks, gifts, motif, voice |
| `dialogue/*.json` | rules (criteria, priority, once) and conversations (nodes, choices, effects) |
| `threads.json` | quest threads and their stages |
| `events.json` | director cards (conditions, weight, cooldown, intensity, effects) |
| `biomes.json` | Reach biome rules (depth/heat/moisture), palettes, resources, creatures, ambience |
| `wick_map.json` | hand-authored settlement height/material grids + props + NPC homes |
| `undercroft_wick.json` | hand-authored cross-section base layout |

Validation runs at boot and in tests (missing keys, unknown references); errors name the file and key.

## 6. Simulation details
* **Grid (`src/sim/uc_grid.gd`)**: `PackedFloat32Array` per field, index = `y*w + x`. Gas step:
  pairwise diffusion (double-buffered) → species buoyancy swaps against `fresh` → water displacement
  → top-row exchange with cavern ambient. Mass of each species is conserved except at explicit
  sources/sinks; tests assert conservation.
* **Water**: W-Shadow compressible CA (`MAX_MASS=1`, `COMPRESS=0.02`), double-buffered.
* **Heat**: explicit diffusion with per-material conductivity, clamped to [−20, 400] °C.
* **Networks (`src/sim/network.gd`)**: conduits are sparse dictionaries per layer (`pipe`, `wire`);
  components found by flood-fill and cached until a conduit/machine changes. Solve order per tick:
  producers → storage → consumers by priority; each machine gets a satisfaction ratio and status.
* **Machines (`src/sim/machine_logic.gd`)**: one generic evaluator driven by `machines.json`.
* **Determinism**: every generator derives its own `RandomNumberGenerator` from
  `hash([world_seed, "subsystem", index])`. Saves store the seed plus deltas, so reloading never
  regenerates differently.

## 7. Rendering
* **Terrain**: cells are 1 m. Heights in 0.5 m steps. Top + exposed side faces, atlas UVs (16 px/m),
  per-vertex AO from neighbour heights, nearest filtering with mipmaps.
* **Sprites (`PixelSprite3D`)**: `MeshInstance3D` + `QuadMesh` + `shaders/pixel_sprite.gdshader`
  (Y-axis billboard in the vertex shader, frame selection, alpha scissor, banded diffuse + rim light in
  `light()`, flash/tint). Blob shadows on the ground instead of billboard shadow casting.
* **The cut**: global shader uniforms `cut_z`, `cut_amount`. Terrain/prop shaders dissolve
  fragments in front of the cut; the Undercroft geometry is built exactly on the cut plane.
* **Post**: Environment (filmic tonemap, glow, fog, adjustments) + a final CanvasLayer grade shader.
* **Quality presets** (Low/Medium/High/Ultra) control: shadows, DOF, glow, SSAO, volumetric fog,
  particles amount, 3D render scale, MSAA.

## 8. Audio
* Music, ambience and SFX are rendered offline by `tools/audio/` (numpy synthesis, convolution
  reverb with a synthetic cave IR) into OGG Vorbis; loops are cut to exact bar lengths.
* Buses: `Master → {Music, Ambience, SFX, UI, Voice}`; Music bus has a low-pass + distortion used by
  the crisis state.
* The `Audio` autoload: two players (A/B) holding `AudioStreamSynchronized` cues; stem gains glide
  toward a target vector that `game._update_music()` derives from state (place, phase, view,
  dialogue, crisis, Quietlight, the finale); cue changes crossfade over 3 s. See SYSTEMS.md §11.

## 9. Save system
* JSON, `user://saves/slot_{n}.json`, written to `*.tmp` then renamed; the previous file kept as
  `*.bak`. Header: `{format, version, meta{name, day, place, playtime, saved_at}}`.
* `SaveCodec.migrate()` upgrades older versions step by step; unknown future versions are refused
  with a readable message instead of being loaded.
* All values are clamped and validated on load; a corrupt slot falls back to its backup.
* Never loads `Resource` files from `user://` (avoids embedded-script execution).

## 10. Input
Named actions only (`move_*`, `interact`, `context`, `inventory`, `tool_next`, `tool_prev`,
`confirm`, `cancel`, `menu`, `primary`, `secondary`, `cut_view`, `journal`, `map`, `time_pause`,
`time_speed`, `overlay_next`, `build_menu`…). Defaults define keyboard/mouse **and** gamepad bindings together.
Remaps persist in `settings.cfg`. UI uses focus navigation, so mouse, keyboard and gamepad all work.

## 11. Testing
`godot --headless --path . res://tests/test_runner.tscn` runs every suite in `tests/suites/` and
exits with a non-zero code on failure. Suites cover: worldgen determinism, grid conservation (gas,
water), heat bounds, network solving (supply/demand/overload/leak), machine status reasons, crop
growth factors, save round-trip + migration + corruption fallback, NPC schedule transitions,
relationship/memory decay, dialogue rule specificity, economy bounds, content validation, and a
scripted full-arc playthrough.

## 12. Tooling
* `tools/art/*.py`: pixel-art generators (palette-locked tiles, prop textures, character sheets
  authored as layered ASCII pixel maps with per-frame transforms, UI icons).
* `tools/audio/*.py`: synthesiser, instruments, sequencer, cues, SFX, ambience.
* `tools/capture.sh`: runs the game (or the title screen) under Xvfb with `--capture` and a scenario
  to produce screenshots for visual review; `--ui=<panel>` opens a panel first.
* `tools/maps/build_maps.py`: the authored Wick map and its Undercroft.
