# Research Log

Sources consulted before and during development, and what each one changed.
Primary/official sources were preferred. Several sites (unrealengine.com,
wikipedia.org, godotengine.org) were blocked by the build environment's egress
policy; in those cases the official Godot manual was read from its source
repository and design sources were consulted through search summaries.

## Engine: Godot 4.7.2-stable (latest stable at project start, Aug 2026 build)

| Source | Used for | Finding → Decision |
|---|---|---|
| Godot manual source, `godotengine/godot-docs@stable` (commit 6d86d7c, Aug 2026) — `tutorials/migrating/upgrading_to_godot_4.6.rst`, `…4.7.rst` | Catching changes since my prior knowledge | `.tscn` no longer writes `load_steps`; glow default blend is now **Screen** with lower intensity; new projects default to `canvas_items`/`expand` stretch; keyboard/mouse device IDs are now `InputEvent.DEVICE_ID_KEYBOARD/MOUSE` (never compare device to 0); typed-return overrides must explicitly return. All honoured in code. |
| `tutorials/rendering/renderers.rst` (feature matrix) | Renderer choice | Compatibility lacks DOF, 2D HDR, volumetric fog, FXAA. Forward+/Mobile support DOF + glow. → **Forward+** default, Mobile as the "Low" fallback; every look-critical effect has a renderer-agnostic fallback (screen-space tilt-shift shader) so Compatibility still works. |
| `classes/class_spritebase3d.rst`, `class_cameraattributespractical.rst` | HD-2D sprites & tilt-shift | `Sprite3D` supports billboard, `shaded`, alpha-cut, nearest filtering; `CameraAttributesPractical` gives near/far DOF blur. Validated in a spike under lavapipe. |
| `tutorials/shaders/shader_reference/spatial_shader.rst` (light built-ins) | Toon/rim lighting for sprites | `light()` exposes `LIGHT`, `LIGHT_COLOR`, `ATTENUATION`, `VIEW`, `DIFFUSE_LIGHT` → custom banded diffuse + back-light rim in the character shader. |
| `classes/class_audiostreamsynchronized.rst`, `class_audiostreaminteractive.rst`, `class_audiostreamplaybackinteractive.rst` | Adaptive music | `AudioStreamSynchronized` plays stems sample-locked with per-stream volume (`set_sync_stream_volume`) → native **vertical layering**. Cue changes use a two-player crossfade (simpler and more controllable than a transition table for this scope). |
| `tutorials/io/saving_games.rst`, `classes/class_configfile.rst` | Save system | Manual recommends JSON dictionaries for game state and `ConfigFile` for settings. Loading `Resource` files from `user://` can execute embedded scripts, so saves are **JSON only**, versioned, written atomically (temp file + rename) with a rolling backup. |
| `tutorials/inputs/controllers_gamepads_joysticks.rst`, `classes/class_inputmap.rst` | Input abstraction & remapping | All gameplay reads named actions; runtime remap via `InputMap.action_erase_events/action_add_event`, persisted to `ConfigFile`. Keyboard + gamepad bindings defined together from day one. |
| `tutorials/i18n/internationalizing_games.rst` | Localization | UI strings go through `tr()` with keys; dialogue lines carry stable IDs in data files so they can be swapped per locale. |
| `classes/class_astargrid2d.rst` | NPC navigation | Native grid A* fits a cell-based world; (4.6 change) paths from solid points return empty → callers handle it. |
| `--doctool` dump of the 4.7.2 binary (1076 classes) | API ground truth | Used to confirm signatures for the exact engine build instead of relying on memory. |
| Spike tests run in this container (Xvfb + Mesa llvmpipe, OpenGL 4.5 and Vulkan 1.4 lavapipe) | Feasibility | Forward+ renders 3D pixel-textured terrain + billboard sprite + 3 shadowed omni lights + DOF + glow + fog correctly; global shader uniform cutaway (`discard` past `cut_z`) works with a side-on camera. → Architecture confirmed. |

## Visual direction

| Source | Finding → Decision |
|---|---|
| Unreal Engine developer spotlight on *Octopath Traveler* / Acquire (via search summary; site blocked) and HD-2D coverage | HD-2D is **3D environments + 2D pixel sprites**, sold by dynamic lighting, depth of field, tilt-shift, volumetric fog; originated from studying PS1-era 2D-on-3D games. The sequel used a tilt-shift camera with a wide FOV that flattens the view while keeping depth. → Build a real 3D diorama with pixel textures and billboard pixel sprites instead of faking depth in 2D. Our identity diverges deliberately: underground (no sky), bioluminescent/lantern lighting, and the cutaway cross-section view — which is only natural because the world is genuinely 3D. |
| Pixel-art craft conventions (hue-shifted ramps, selective outlining) | 3-tone ramps per material with shadows shifted toward violet and highlights toward warm; outlines tinted from the adjacent fill rather than pure black. |

## Systems design

| Source | Principle extracted (the *why*) | How it is used here |
|---|---|---|
| *Behind the design of Oxygen Not Included* and *Layering challenges in Klei's survival sim* (Game Developer) | A broad but *simple* simulation reads as a complex living world; predictable behaviours let players manipulate them; "if you feel you discovered it on your own, that's the Holy Grail"; "tutorials are not fun". | Gas/water/heat use a handful of legible rules (heavy sinks, light rises, water falls then spreads). Teach through problems (the dry well) instead of tutorial text. |
| ONI one-substance-per-tile rule (search summary) | Discrete rule makes gas legible but produces pressure-lock edge cases players fight with. | We store *mixtures* per cell (simpler to make smooth and readable) with explicit buoyancy per species. Our grid is tiny (a single cross-section), so legibility beats fidelity. |
| W-Shadow "Simple Fluid Simulation With Cellular Automata"; DwarfCorp water write-up; Tom Forsyth "Cellular Automata for Physical Modelling" | Water: fall down, then spread sideways, upward only when compressed; store pressure as ~2% compressible excess mass; double-buffer to avoid directional bias. | Water CA follows this exactly (max mass 1.0, compress 0.02), double-buffered. |
| RimWorld storyteller analyses (Tynan Sylvester's design) | Events are "cards dealt" by a director that reads colony state; stories cascade through interconnected systems. | Event Director chooses events whose *conditions* match state (pollution, water level, relationships, day) with cooldowns and intensity pacing — never pure random. |
| Left 4 Dead AI Director (Michael Booth, GDC 2009 coverage) | Track an *intensity* estimate; alternate build-up, peak, relax; unpredictability prevents both exhaustion and boredom. | Director keeps a tension value; after a crisis it enforces a calm window (cozy pacing) before allowing another. |
| Elan Ruskin, *AI-driven Dynamic Dialog through Fuzzy Pattern Matching* (GDC 2012) | Query thousands of world facts against rules; **the most specific matching rule wins**; less specific rules are fallbacks; writers add special cases without code. | Dialogue/bark selection: each line has criteria; score = number of satisfied criteria + priority; highest wins; "once" lines remember they were used. |
| Greg Kasavin on *Hades* dialogue (GDC 2021 coverage, GameSpot) | A bucket of conversations filtered by game-state conditions, weighted by importance: evergreen < specific < essential story beats. | Three priority tiers in our rule system: `ambient`, `reactive`, `story`. |
| Emily Short, *Beyond Branching: Quality-Based, Salience-Based and Waypoint Narrative Structures* (2016) | Storylets gated by qualities let many small arcs slot together; salience picks the most relevant. | NPC events and quest stages are storylets gated by world "facts" (qualities). |
| Stardew Valley design analyses (incl. Barone on "natural, relaxed pace") | Daily loop with clear goals + immediate feedback → flow and "one more day"; schedules make residents feel real; long-term mystery sits behind short-term goals. | Day rhythm without stamina bars; schedule-driven NPCs; a mystery (Station 7) behind the farm loop. We avoid its *specifics* (energy bar, inherited farm, seasons-as-calendar). |
| Undertale analyses (NPCs remembering actions; choices change dialogue and outcome) | The emotional force comes from **specific** acknowledgement of what *you* did, not from a morality meter. | NPC memories reference concrete deeds ("you vented the burner onto my moss"); no karma bar; reputations are per-person and multi-dimensional. |
| Spelunky / Brogue / Shattered Planet generation discussions | Hand-made pieces + procedural stitching under hard rules (connectivity, critical path) make generated levels feel designed. | The Reach: cavern graph with a guaranteed critical path to the Trunk chamber, biome assigned by depth/heat/moisture rules, one authored "ruin vignette" per tier. |
| Adaptive music practice (vertical layering vs. horizontal resequencing; Winifred Phillips GDC 2021 hybrid approach) | Stems must be standalone and combinable, start on one timeline, intensity changes gain rather than restarting. | Every cue is rendered as synchronized stems; the Music Director only moves stem gains and crossfades between cues on bar boundaries. |
| Jan Willem Nijman, *The Art of Screenshake* (2013); Swink, *Game Feel*; Jonasson & Purho, *Juice It or Lose It* (2012) | Redundant feedback (sound + motion + particles + camera) on each action makes control feel tactile; but restraint matters. | Every verb (till, water, place, repair, harvest) gets sound + sprite squash + particles + tiny camera nudge; shake is opt-out and capped. |
| Relationship-system surveys (trust/respect/familiarity models) | Separate axes let characters like you without trusting you. | Six hidden axes: trust, respect, affection, resentment, fear, shared history. |
