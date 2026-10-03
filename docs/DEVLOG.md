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
