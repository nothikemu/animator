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
  and ruins, but they lack set pieces; the Trunk chamber deserves a hand-built room.
* **Audio is unheard.** It's composed and checked, but nobody has listened. Expect the mix to
  need a pass.
* **Controller play** is designed for but unproven on hardware.
* **Balance** is tuned by tests. The cistern drain, crank output and prices need real sessions.

Next, in order: a listening pass; a hand-built Trunk chamber; harvest feel; a first-hour
playtest with three people who've never seen it, watching where they stop reading.
