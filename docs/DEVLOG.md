# Development Log

Concise record of decisions, problems, solutions and discoveries.

## 2026-10-03 — Day 0: research and direction
* **Environment:** empty repository; no engine installed. Downloaded Godot 4.7.2-stable (latest
  stable). Installed Mesa Vulkan (lavapipe) so both Forward+ and Compatibility can be rendered under
  Xvfb for screenshots. godotengine.org is blocked; the official manual was read from
  `godotengine/godot-docs@stable`.
* **Decision: true HD-2D (3D diorama) instead of 2D.** Research confirmed HD-2D is 3D environments with
  2D pixel sprites. More importantly, the required "camera moves through the earth into a
  cross-section" transition is only *physically* coherent if the world is 3D. A spike rendered
  pixel-textured terrain, a billboard sprite, three shadowed omni lights, DOF, glow and fog, then
  cut the world with a global shader uniform and viewed it side-on. Both worked.
* **Decision: name.** "Project Underground" → **BELLOWS** (the inhabitants' name for the Deep's
  breathing machine). Settlement: **Wick**, built on Respiratory Station 7.
* **Decision: JSON content over `.tres`.** Content is authored without the editor GUI, must diff
  cleanly, must be validated in tests, and must be localisable. Typed wrapper classes give the
  same safety as custom Resources.
* **Decision: gas as mixtures.** One-substance-per-tile is legible but brittle; per-species
  buoyancy over mixtures gives smoother visuals and simpler code on a 48×24 slice.
* **Decision: no health bar.** Hazards use a breath meter that only appears in bad air; blacking
  out creates a memory instead of a game over.

## 2026-10-03 — First render
* **Art pipeline**: `tools/art/px.py` (palette ramps with hue-shifted shading, periodic noise,
  ordered dither, selective outlines), `tiles.py` (98-tile atlas), `props.py` (40 sprites),
  `chars.py` (paper-doll characters: player, Barnaby).
* **Bug: whole sprites glowing.** Emission maps lit entire silhouettes. Cause: Godot's texture
  importer *Fix Alpha Border* (on by default) copies neighbouring opaque RGB into transparent
  texels; the shader used `emit.rgb` without alpha. Fix: `EMISSION = e.rgb * e.a`. Found by
  bisecting in the new visual test scene (unshaded vs. default light vs. custom light).
* **Engine fact verified**: in Forward+ a custom `light()` writes `DIFFUSE_LIGHT` which the
  engine multiplies by albedo afterwards; rim light goes to `SPECULAR_LIGHT` to keep its colour.
* **Readability**: underground scenes were unreadably dark. Added a weak, cool, shadowed
  directional "cavern fill" (the ceiling's bioluminescence) and raised ambient; emissive plants
  and lamps sit on render layer 2 and their own lights skip that layer (no self-washout); the
  player's headlamp skips the player sprite, a tiny fill light lights only the player.

## 2026-10-03 — The cut
* **Cross-section as an object, not a UI.** The Undercroft is a one-cell-thick slab whose face
  lies on the cut plane, so when the ground in front falls away the town above is still standing
  on it. Cavities get back walls, corner AO and inner faces; at a slight downward tilt they read
  as holes rather than paint.
* **Bug: green curtains during the cut.** Terrain faces that straddle the cut line had one edge
  sunk 14 m and one edge not, stretching into walls of moss. Fix: recompute the sink factor per
  fragment from the *unsunk* position and dissolve with the cell. Sprites got the same treatment
  later after a capture showed sunk glowroots at the bottom of the slab.
* **Pipes in front.** First capture: no pipes visible — they were behind the slab face. Conduits
  now sit just in front of it (ONI's choice, for the same legibility reason).
* **The gas overlay** started as wisps with more opacity; it read as mud. The normal view keeps
  wisps; the overlay is an exact per-cell reading with a one-pixel rim so cells can be counted.
* **The station pump had a face.** Two gauges over a sight light read as eyes and a mouth. Made
  the gauges unequal and moved the light to a vertical sight glass.

## 2026-10-03 — Words
* Wrote the chapter: five voices, nine threads, eleven director cards, a dozen lore fragments,
  and the valve finale with two endings that both end at the knock.
* **Content linter as a test.** Every condition kind, effect kind, item, machine, thread,
  event, label and speaker in the data is checked. It passed first time, so to prove it bites, a
  line with a misspelled effect (`trsut:`) and condition (`runing.`) was planted: the suite failed
  naming both, and the line was removed.
* **Full-arc test.** Playing the chapter through real systems found a progression hole: Station 7
  needs seal gum and nothing taught it. Barnaby now teaches it. It also showed a crank placed
  in the Sink floods — correct, and now part of the test.

## 2026-10-03 — Faces and sounds
* Title screen over a drifting Wick at Hush; one panel host for everything; settings that apply
  and save instantly, including per-device remapping.
* **Ligature bug.** Pixelify Sans' `fi` ligature rendered "first" as "Arst". Ligatures off.
* **Audio from nothing.** numpy/scipy synthesis: resonator banks for pipes and the knock, FM for
  bells, filtered noise for soil and water, formant syllables for voices; six cues of
  synchronised stems with reverb tails wrapped into the loop start. Balanced by RMS, checked for
  seams numerically — there are no speakers in a build container.

## 2026-10-03 — Performance and polish
* Stress bench: 137 machines, gas everywhere. Field step 4.7 ms → 2.3 ms by hoisting packed
  arrays into typed locals and unrolling species (identical results; the test suite itself got
  twice as fast).
* Quietlight made visible (lamps out via a `lamp_level` global, glow swells, lampmoths rise);
  muted the lime moss; Barnaby's eye glints went from cyan to cream so the moss in his helmet
  crack reads as the only living cyan on him; more light in waking hours.

## 2026-10-03 — Bugs a player would have hit
* **Three crops crashed the farm.** Moss, fern and emberroot named sprites that didn't exist;
  only glowbeets had ever been planted in a capture. Found by a harvest scenario, fixed in data,
  and the farm view now falls back with a warning.
* **The key pickup was invisible.** The governor coil lived in a resource with no sprite, and
  unsprited resources are skipped. Now a glowing Station 7 spares crate beside Wren's camp
  (bedroll, tin cup, her work lamp still lit).
* **A smoke test** now boots the real game and drives every interactable, tool, cavern (with a
  sprite check for every resource), conversation (both extremes of every choice) and cut-view
  inspection. Both bugs above would have failed it.
* **The Reach** hid the player behind 8 m walls. Cavern rock is now drawn as a low dark
  plateau: you look into the cave, diorama style.
* **Critters**: lampmoths and rock-lice, so the ecology the dialogue talks about is visible.
* **Progression holes.** A new test asks, for every machine and recipe unlock, "who teaches
  this?" Six had no answer (sprinkler, fan, compost vat, heat cell, lamp lens, spore mash). Each
  now has a teacher in a conversation where the topic fits. Another asks "where does it come
  from?" for the Station's parts: seal gum was only teachable in a conversation that could
  expire before the Tremor, and ember resin only grew on a crop that needs a burner's heat.
  Seal gum is now stocked at the Exchange and re-taught with the coil; Ember caverns hold resin.

## Critique of the vertical slice
What works:
* The cut is the identity. The moment the lane's ground drops and the camera swings down to the
  town standing on its own plumbing is the thing nobody else does.
* Systems talk to each other in ways the player can see: the burner's sour air sinks into the
  plots, Hesper goes indoors, the Quietlight bloom dims, Mags' stew "tastes of pennies".
* Barnaby's arc lands on a mechanical object (the valve) and a sound (the knock), not on a cutscene.

What doesn't yet:
* **The opening hour is light on farming feel.** Tilling and watering work, but there's no
  satisfying harvest animation beyond a pop and a toast; crops need more visual growth stages.
* **The Reach is functional rather than memorable.** Procedural caverns connect and carry ore
  and ruins; the Trunk chamber now has Wren's camp, but the other tiers lack set pieces.
* **Audio is unheard.** It's composed and checked, but nobody has listened. Expect the mix to
  need a pass.
* **Controller play** is designed for but unproven on hardware.
* **Balance** is tuned by tests. The cistern drain, crank output and prices need real sessions.

Next, in order: a listening pass; set pieces for each Reach tier; harvest feel; a first-hour
playtest with three people who've never seen it, watching where they stop reading.

## Browser build
The game now runs in a browser tab, so it can be played without installing anything.
* **Renderer.** Desktop stays on Forward+; the Web uses Compatibility (WebGL 2). Audio uses the
  Stream playback path on the Web because the default Sample path can't play the layered music.
* **Invisible town.** The first browser run drew nothing but the sky. Unset per-instance shader
  uniforms read as 0 under WebGL, not their declared defaults, so `fade = 0` discarded every
  fragment and `tint = 0` would have blacked out every sprite. The terrain and sprite shaders now
  treat an exact zero as "never set". No real value hits it: roof fades bottom out at 0.08 and
  sprites hide below 0.01.
* **Data.** The JSON content isn't a Godot resource, so the export preset includes `*.json`.
* **Hosting limits.** The engine is 40 MB, and some hosts cap files at 15 MB and serve only
  standard web types. The packager gzips the engine and the pack and ships them as base64 text;
  a fetch shim in the launch page decodes, inflates and hands Godot its `index.wasm` and
  `index.pck`, and drives the download gauge. Checked in Chromium (SwiftShader) from launcher to
  the grotto's first line, including under a strict CSP that allows only `wasm-unsafe-eval`.
* **Not checked yet:** Firefox and Safari, a real GPU, and save persistence in a sandboxed
  frame (Godot falls back to memory-only saves when IndexedDB is unavailable).

## 2026-10-08 — The whole story, and playing it to the end
* **Chapters Two to Four** are written (see STORY.md): the pipe telegraph, two town meetings,
  the Primary Lift, Sallow and the Lower Stations, Wren, Pell and Tolley, the Knappers' ways,
  and the Heart. Four endings and a Topside coda, an epilogue card per person, and the endless
  Unmapped after.
* **Replay.** A notice board of seeded daily requests in each resident's voice; five origins;
  echoes (residents half-remember endings from earlier runs); the Almanac on the title screen.
* **The Bellows** was a striped red box. It is now pleated leather under brass lids, a brick
  spine with a gauge, a crown of pipes and a row of dials, and its bellows rise and fall: a
  shallow half-minute breath while it idles, a deep one every eight seconds once restarted.
* **An autopilot found four real bugs.** `test_story_arc` plays from the knock to each ending
  by talking to whoever has something to say and doing what the notes ask. It found:
  - a thread stage with two `on_enter` keys. JSON keeps the last, so `o_trade_sent` was never
    set: no down-river medicine, and Everything Breathing could not be reached. A new test now
    scans every data file for repeated keys;
  - the lift winch hint said "thirty power", but one wire carries sixty and the Station pump
    already takes fifty-five. The note and Barnaby now say it needs a wire of its own;
  - Everything Breathing only needed Wren not dead yet, so pulling the lever fast beat her
    clock. It now needs her cured, and the epilogue covers her still being ill;
  - if Wren died after Barnaby reached her, he had no scene and the epilogue gave the quiet
    table a second cup. He has one now ("I was there. At the end."), and the card is right.
* **Pacing, honestly.** Handed the goods, the autopilot gets from the knock to the lever in
  seven to nine in-game days. The design's eight hours assumes the gathering, crafting, farming
  and travel the autopilot skips. That figure is still an estimate until someone plays it.

