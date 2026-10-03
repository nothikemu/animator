# Systems Reference

How each system works and why it's built that way. For data formats see
[CONTENT_GUIDE.md](CONTENT_GUIDE.md); for the runtime layout see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. Time

`Clock` runs at 0.7 real seconds per in-game minute, so a full day is about 14 minutes awake.

| Phase | Hours | Notes |
|---|---|---|
| Wake | 06–12 | |
| Bloom | 12–18 | Glowroots at their brightest |
| Dimming | 18–22 | |
| Hush | 22–02 | Lamps on |
| Night | 02– | Exhaustion at 02:00 |

Exhaustion is not a game over: you wake at home, and if you collapsed outside, Barnaby
remembers that he carried you.

The Breath runs on a three-day cycle (day % 3):
- **Exhale**: vents push ×2.5.
- **Inhale**: vents draw ×0.3.
- **Market day**: the third day (day % 3 == 2).

Time pauses for dialogue, panels and the console. The cut view has its own pause and speed
controls (×1/×2/×4). Each of these takes a named pause reason, so they never fight.

## 2. The Undercroft field simulation (`src/sim/uc_grid.gd`)

The Undercroft is a 48×24 cross-section, one cell = 1 m, with row 10 as the surface. Each cell
has:
- a material;
- four gas species amounts (fresh, stale, sour, damp);
- water mass, temperature, soil moisture;
- last step's water flow (used for foam and turbines).

It steps three times per in-game minute in this order: **water → displacement → gas → heat
→ moisture → sources**.

- **Water** uses a compressible-mass cellular automaton. Water falls, spreads sideways,
  rises only under pressure (MAX_COMPRESS 0.02) and is double-buffered. Springs add water,
  drains remove it.
- **Displacement**: water entering a cell pushes that cell's gas into open neighbours.
- **Gas** has four parts:
  1. Pairwise diffusion: vertical mixing ×0.5, so gases layer.
  2. Settling: heavy species (stale ×1.45, sour ×2.1) drift down, and light damp air (×0.55)
     drifts up, each trading places with fresh air so pressure holds.
  3. Convection: a denser mixture over a lighter one swaps a share, and heat travels with it,
     which makes plumes rise. Hot air is lighter (an ideal-gas scale around 18 °C).
  4. The top row exchanges with the open cavern.
- **Heat** conducts by material (metal 0.45 … felt 0.005) and is buffered by capacity. Water
  raises an air cell's capacity, and ember cells are fixed hot sources.
- **Moisture**: soil soaks from neighbouring pools, spreads slowly and evaporates at the surface.
  The farm plots read the surface row.

Every exchange is pairwise, so gas and water are conserved except at explicit sources and
sinks. The **grid** suite checks that, along with stratification, rising plumes and bounds.

**Performance.** With 137 machines and gas in every open cell, a field step costs ~2.3 ms
(water 0.18, gas 1.1, heat 0.5, moisture 0.36). The hot loops hoist each species' packed array
into typed locals (packed arrays are shared by reference), unroll the four species, and
precompute an open-cell mask and per-cell conductivity. That halved the cost from 4.7 ms.
Frames run at most 3 catch-up steps. Re-measure with `scenes/test/stress_test.tscn`.

## 3. Machines and networks (`src/sim/machine_world.gd`)

Machines are data-driven bundles of components (see the content guide), evaluated once per
in-game minute in four passes:

1. **Environment and potentials**: broken, off, flooded (unless waterproof), too hot, choking,
   missing parts; what each producer *could* make and each consumer wants.
2. **Power networks**: connected components of the wire layer, merged through any machine that
   touches two runs. Supply and demand balance, batteries absorb and release. A run carrying
   more than 60 units overloads, and after 6 minutes overloaded a wire burns out.
3. **Water networks**: the pipe layer. Pumps and intakes draw from their cells, capped at 3
   units a minute per network. Consumers, tanks, wells and outlets receive. Cracked segments
   leak a share of everything that passes into their cell.
4. **Apply**: emit gas, heat, light, moisture, scrubbing and fans into the grid. Each machine
   then picks the highest-priority reason from
   `broken > off > flooded > not_connected > no_power > overloaded > no_fuel > needs_filter > output_full > no_water > dry > too_hot > choking > incomplete > idle > ok`.
   Every reason has one plain sentence (`Inspect.STATUS_TEXT`), and the inspect panel adds
   lines in words ("Getting most of what it needs in power"), never numbers.

Story machines (the well, the mains, Station 7) are `fixed`. Station 7 `requires` a governor
coil and four seal gum before it will run.

## 4. Crops (`src/sim/crop_logic.gd`)

Each environmental factor (light, moisture, temperature, sour air) scores 0..1 against the
crop's ideal range, with soft shoulders outside it. Growth per tick = days⁻¹ × the product of
the factors. Health falls while the worst factor is below 0.25 and slowly recovers otherwise;
at zero the crop dies. Light comes from glowroots, lamps, the player's headlamp and mature
glowbeets. Harvested yield scales with health, and pollination (from the lampmoth swarm
event) adds 25%.

Crops act as instruments. Sulfur ferns eat sour air. Moss scrubs and its fibre makes filter
pads. Emberroot needs the burner's heat. Bellcaps want darkness. Glowbeets light their
neighbours.

## 5. People (`src/autoload/society.gd`, `src/social/`)

- **Relationships and memory**:
  - Six hidden axes per resident: trust, respect, affection, resentment, fear and shared
    history.
  - Memories carry importance and sentiment. Their importance fades ×0.82 a day, and they're
    forgotten below 0.6 unless marked lasting. Resentment and fear soften 3% a day; shared
    history never fades.
  - `NpcSocial.describe()` turns the axes into a phrase for the journal. There is no karma
    meter and no visible number anywhere.
- **Deeds**: the player's actions raise deeds (`repaired`, `built_dirty`, `pollution`,
  `leaked_water`, `sold_food`…). Each resident's `values` decide which axes a deed moves, capped
  at 8 per axis per value per day. A strong change shows a quiet "Hesper noticed."
- **Gossip**: at 18:45 memories spread through the Lantern House. Mags is the hub, and her
  version is slightly wrong.
- **Schedules**: the last matching block wins, conditions included. NPCs route on an A* grid,
  go indoors when the air at their door is beyond their `tolerance`, and remember a blocked
  route.
- **Dialogue**: the most specific matching rule wins (tier + specificity + priority − repeat
  penalty). Conversations are small node graphs.

## 6. Economy (`src/economy/market.gd`, `src/autoload/economy.gd`)

Each market holds per-item stock with a target level. Price = value × scarcity (stock against
target, bounded 0.5–2×) × modifiers × food quality. Food grown in sour air sells for up to 50%
less at the Lantern House. Stock relaxes 35% toward its target each day. When Grist hasn't
visited for more than four days, the Exchange's glowglass and thermal ore cost ×1.4. Schematics
are rule-gated purchases that set unlock flags.

## 7. Director (`src/autoload/director.gd`)

Hourly, the Director picks one eligible card by weight, then rolls its `chance`.
- **Tension**: intensity adds tension, which decays 0.1 an hour and 1.5 a day. While tension
  is above 1, crisis cards (intensity ≥ 2) can't fire.
- **Hooks**:
  - `tremor`: opens the fissure, adds sour gas, cracks three pipes, and opens the sealed Trunk
    passage while collapsing a shortcut.
  - `quietlight`: decides the bloom from the town's air and whose side you took.
  - `exhale_surge`, `moth_swarm`, `valve_turn` and `knock`.

## 8. The Reach (`src/world/reach_gen.gd`)

The Reach is deterministic from the world seed.

**Graph**:
- Three depth tiers, each node named from biome word lists.
- Biome follows depth, heat and moisture, with at least one Blackstone node (tier 1) and one
  Ember node (tier 2).
- The Trunk chamber sits on the deepest tier behind a `sealed` edge that the Tremor opens.
- One `collapsible` shortcut closes when the Tremor hits.

**Caverns**:
- Cellular-automaton rock, then protected critical paths between the hub, every exit and the
  ruin.
- A flood-fill `_ensure_connected` safety net carves any pocket that still ends up isolated.
- Resource nodes are placed by biome. Each tier has one ruin vignette with a lore page. The
  Trunk ruin holds the governor coil and Wren's note.

Mined nodes are saved as deltas per area, never by regenerating differently. The **reachgen**
suite sweeps seeds for determinism and connectivity.

## 9. Saves (`src/autoload/saves.gd`, `src/save/save_codec.gd`)

`{"format": "bellows-save", "version": 2, "meta": {...}, "sections": {world, clock, sim, society, economy, threads, director, dialogue}}`.

- Writes are atomic: write to `*.tmp`, keep the previous file as `*.bak`, then rename. A
  corrupt slot falls back to its backup and says so ("recovered").
- Version 1 saves migrate step by step. Saves from a newer version are refused with a
  readable message.
- Every loaded value is clamped and sanitised (grid arrays are size-checked; RNG states are
  stored as strings so 64-bit values survive JSON).
- Slot 0 is the autosave, taken on sleep and at the ending. Slots 1–3 are manual.
- The **save** suite covers round trips, migration, corruption, truncation and future versions.

## 10. Rendering

- **Diorama**: Wick is a real 3D model (1 m cells, 16 texels/m, nearest filtering) viewed
  through a 30° FOV camera pitched −46° from 24 m, with tilt-shift depth of field and a
  critically damped follow. Characters and props are pixel-art billboards
  (`pixel_sprite.gdshader`):
  - fixed-Y billboarding;
  - banded diffuse lighting, with the rim light written to `SPECULAR_LIGHT` so it keeps its
    colour;
  - emission weighted by alpha, because the importer's alpha-border fix fills the RGB of
    transparent texels.
- **Light and self-lit layers**:
  - Glowroots and lamps sit on render layer 2 and their lights skip it, so they don't
    wash themselves out.
  - The player's headlamp skips the player; a tiny fill light lights only the player.
  - A faint, cool cavern-fill directional light keeps the diorama legible.
- **Global shader uniforms**: `world_time`, `glow_level` (time of day, and Quietlight's
  bloom), `lamp_level` (Quietlight), `pollution` (colour grading and fog), `wind`,
  `cut_z`, `cut_amount`.
- **The cut** (`src/engineering/`): the ground with z > `cut_z` sinks by k² × 14 m and
  dissolves per fragment.
  - The sink factor k is recomputed per fragment from the unsunk position, so faces that
    straddle the cut line dissolve with their cell instead of stretching. Props dither away
    on the same factor.
  - The camera swings on a quadratic curve that pulls back and drops, with its view
    blended between the endpoints' exact framings and a look-at point. A thin strata band
    passes the lens at ground level.
- **Cross-section** (`undercroft_view.gd`):
  - a one-cell-thick slab with strata tiles on its face;
  - cavities with back walls, corner occlusion and inner faces, so they have depth;
  - field planes driven by per-step data textures (`uc_fields.gdshader`):
    - water filled per cell with a moving surface line and foam where it flows;
    - gas as domain-warped wisps, or an exact per-cell reading in the gas overlay;
    - a heat colour map with contour bands, so it never relies on colour alone;
  - conduits as per-network meshes whose instance uniform `flow` drives travelling pulses,
    with damaged segments throbbing red.
- **Performance knobs**: quality presets (shadows, DOF, glow, SSAO, particles, render scale).
  The debug overlay shows draw calls and frame time.

## 11. Audio

Everything is synthesised offline by `tools/audio/` (numpy and scipy; OGG Vorbis via ffmpeg).

- **Music**: six cues: menu, wick, hush, reach, cut and station.
  - Each cue is 3–4 stems of identical length, rendered with reverb tails wrapped into the
    loop start so the seams are continuous.
  - Played through `AudioStreamSynchronized` (sample-locked). Stem gains glide toward a
    target vector from `game._update_music()`: the counter-melody at Bloom, a quieter pulse at
    night, the melody ducked in dialogue, the alarm stem during an open Tremor crisis, the
    knock stem after the finale, and glass only during Quietlight.
  - Bad air closes the Music bus's low-pass and adds drive.
  - The harmony is original: D minor town theme, F lydian Hush, phrygian Reach drone, a
    mechanical D-minor cut groove, and a D major finale that restates the town theme.
- **Effects**: 75 files with variants. Physical-ish models: resonator banks for pipes and
  knocks, filtered noise for soil and water, FM for bells and plucks.
- **Voices**: one formant-shaped syllable per timbre, pitched per character as text types out.
- **Ambience**: four 32-second beds with crossfaded seams and sparse seeded events (drips,
  knapping, crackles, groans).

## 12. Input and accessibility

Named actions only, with keyboard/mouse and gamepad bindings defined together and remappable
per device. The UI follows the last device used: prompts show the right glyph names, and pads
get focus navigation.

Accessibility options:
- text size (0.75–1.75×);
- a readable font (Atkinson Hyperlegible);
- high-contrast panels;
- captions for story sounds;
- text speed;
- screen shake on/off and strength;
- flash strength (0 disables).

Status is always stated in words as well as colour, and overlays carry legends.
