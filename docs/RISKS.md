# Risk Register

Scored 1–5 for probability (P) and impact (I). Re-ranked as development proceeds.

## Technical risks

| # | Risk | P | I | Mitigation | Status |
|---|---|---|---|---|---|
| T1 | **No GPU in the build container**: visuals can only be verified under software rendering (llvmpipe/lavapipe) | 5 | 4 | Capture pipeline under Xvfb; validate Forward+ *and* Compatibility; avoid effects that only look right on hardware | Closed — every visual milestone reviewed from Xvfb captures (Forward+ under lavapipe) |
| T2 | **All art must be authored by code** (no image generator available). Risk of "programmer art" | 5 | 5 | Strict palette; hand-designed ASCII pixel maps for characters (deliberate authorship, not noise); a small number of highly polished assets reused; visual review after every milestone | Mitigated — palette-locked generators for tiles, props, characters, machines, icons; reviewed and recoloured after each capture pass |
| T3 | **All music/SFX must be synthesised**. Risk of generic chiptune | 4 | 4 | Custom synth with physical-model plucks, FM brass, convolution cave reverb, breathing harmonium; a distinctive harmonic language rather than more instruments | Mitigated — original score (6 cues, 21 stems), 75 effects, voices, ambience; numeric checks for levels and loop seams (no listening possible in the build container) |
| T4 | GDScript performance of the grid sim | 2 | 3 | Small grid (48×24), 4 Hz, packed arrays, profiled in stress scene | Closed — 2.3 ms/step under a 137-machine stress load after optimisation |
| T5 | Cut transition looks like a glitch rather than a reveal | 3 | 5 | Dedicated iteration: dissolve with noise + falling earth particles + strata wipe + camera ease; screenshot sequence review | Closed — mid-transition and exit captured and fixed (stretched faces, sunk props) |
| T6 | Billboard sprites look flat/wrong under 3D lighting | 3 | 4 | Custom sprite shader (banded diffuse, rim light), blob shadows, fixed-Y billboards | Closed |
| T7 | Save corruption / version drift | 2 | 5 | Atomic writes, backups, versioned migrations, clamping, round-trip tests | Closed — tested |
| T8 | Scene files hand-written without the editor drift from the 4.7 format | 3 | 2 | Keep `.tscn` minimal; build structure in code where procedural; import check in CI script | Closed — scenes are 1-node shells |
| T9 | Procedural Reach produces unreachable or boring caves | 3 | 4 | Graph-first generation with a guaranteed critical path; flood-fill connectivity check + carving; seed sweep tests | Closed — tested |
| T10 | Light count explodes (glowroots everywhere) | 3 | 3 | Emissive materials + glow for most plants; real `OmniLight3D` only for key sources; per-preset caps | Mitigated — self-lit layer, emissive-first |
| T11 | Input/UI focus breaks with gamepad | 3 | 3 | Focus-based UI from day one; test navigation via synthetic input events | Mitigated — focus on open, per-device prompts; untested on real hardware |
| T12 | Audio sync drift between stems | 1 | 3 | `AudioStreamSynchronized` (sample-locked); identical stem lengths enforced by the renderer | Closed — tested |

## Design risks

| # | Risk | P | I | Mitigation |
|---|---|---|---|---|
| D1 | **Too complicated**: fields + networks + crops + people at once | 4 | 5 | Progressive disclosure (water → power → gas → heat); plain-language status; overlays; residents explain *consequences*, not mechanics |
| D2 | **Too derivative** of the three reference games | 3 | 5 | Originality test each milestone (see DESIGN §1, §13); the cut, crops-as-instruments and deed memory are the identity |
| D3 | **Too cozy** (no tension) | 2 | 3 | The Breath, tremor, leaks, NPC conflict; Director tension pacing |
| D4 | **Too industrial** (spreadsheet) | 3 | 4 | No numbers in relationship UI; economy explained in words; small machine count |
| D5 | **Too slow** opening | 3 | 5 | First cut within ~6 minutes; no exposition before the first problem |
| D6 | **Too grindy** | 2 | 4 | Low recipe costs; short days; no stamina; automation as reward |
| D7 | **Too shallow** (systems don't actually interact) | 3 | 5 | Every crop/machine has at least one cross-system hook (DESIGN §5); integration tests assert the chains (Burner → sour → fern/moss/Hesper) |
| D8 | **Writing becomes generic or corny** | 3 | 4 | Writing pass with a banned-phrases list; each line must be in a character's voice and refer to something concrete |
| D9 | Scope creep vs. polish | 4 | 5 | MVP table is the contract; features cut before quality is lowered |

## Highest-risk systems (designed around first)
1. Art pipeline (T2) → build the sprite authoring tool and palette **before** content.
2. The cut (T5) → prototype early in the first playable, iterate visually.
3. System legibility (D1) → status reasons and overlays are part of the first engineering build, not polish.

## Remaining risks after the vertical slice

| # | Risk | Note |
|---|---|---|
| R1 | Audio has never been heard by a human | Levels, lengths and seams are checked numerically; a listening pass on real speakers is the first thing to do with the build |
| R2 | Pad and Steam Deck feel | Focus paths and pad bindings exist; they've only been exercised through tests and synthetic events |
| R3 | Balance of the first two days | The cistern drain, prices and crank power are tuned by test, not by playing for hours; watch first-time players |
| R4 | Real-GPU look | Captures come from a software renderer; DOF, glow and SSAO need a look on real hardware |
