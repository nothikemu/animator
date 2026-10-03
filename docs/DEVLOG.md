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
