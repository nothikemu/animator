# Bellows

*Build a life inside a living machine — and find out who else is still breathing down there.*

Bellows (working title; formerly "Project Underground") is a cozy engineering-life game made
in **Godot 4.7**. Your line snaps at the bottom of a shaft and you land in **Wick**, a lamp-lit
settlement built on top of a dead pumping station. You grow crops in the dark, look
under the town through a surveyor's **plumb-glass** at the pipes, wires, water, gas and heat
that keep it alive, and get to know five residents who remember what you do.

This repository holds the first chapter as a playable vertical slice. It runs from
the dry well on your first morning to the moment the Trunk valve opens and something knocks
back.

| | |
|---|---|
| **Life** | Glowbeets, moss, sulfur ferns, emberroot and bellcaps, each with its own light, water, heat and air needs. You sell at the Exchange, cook at the Lantern House, and give gifts to people who remember them. |
| **Engineering** | The cut view: a live cross-section with water you can watch fall, gases that sink or rise by weight, heat that conducts through rock, pipes that leak, wires that burn out, and machines that tell you in plain words why they're unhappy. |
| **Consequence** | No karma bar. Residents hold six relationship axes and individual memories. Gossip spreads at dusk, deeds are noticed by the people who care about them, and the Quietlight bloom is as bright as the air you've left the town. |

## Running it

```sh
godot --path .                      # title screen
godot --path . -- --dev             # with the dev overlay (F3) and console (F1)
```

The project uses Forward+ (Mobile and Compatibility fall back gracefully). It needs Godot 4.7
or newer; the first launch imports the generated assets.

### Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Interact, talk | E | A |
| Use tool | F / left click | X / RT |
| Cycle tool | Q | LB / RB |
| Cycle seed | Right click | LT |
| Plumb-glass (cut view) | C | Back |
| Pack · Journal · Map | Tab · J · M | Y · D-up · D-down |
| Pause | Esc | Start |
| **In the cut view:** tools | 1–7, Q | LB / RB |
| Place / drag pipe and wire | Left click (hold) | A (hold) |
| Overlay · Build menu | V · B | D-right · D-left |
| Pause time · Speed | P · T | L3 · R3 |

Every binding can be remapped in **Settings → Controls**, separately for keyboard and pad.

## Repository layout

```
assets/      generated textures, audio and fonts (OFL licences included)
data/        all game content as JSON: items, crops, machines, recipes, markets, biomes,
             NPC sheets, dialogue, quest threads, director events, lore, maps
docs/        design, architecture, systems reference, content guide, research log,
             risk register, devlog
scenes/      boot, title, game and test scenes (kept tiny; structure is built in code)
shaders/     terrain (with the cut), pixel sprites, water, cross-section fields, conduits
src/         GDScript, grouped by concern (autoload, sim, world, actors, camera,
             engineering, social, economy, ui, save, debug)
tests/       headless test runner and suites
tools/       Python generators for every asset (art, audio, maps) and the capture script
```

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn               # everything
godot --headless --path . res://tests/test_runner.tscn -- --only=story
```

The 96 tests cover:
- simulation conservation and behaviour
- networks, machines, crops and the economy
- saves (round trip, migration, corruption fallback)
- procgen connectivity
- a content linter over every dialogue rule, effect, thread and event
- every panel opening cleanly, and every sound the code asks for existing
- a smoke test that boots the real game and drives every interactable, tool, cavern,
  conversation and cut-view inspection
- a full-arc playthrough from the dry well to the knock

## Regenerating assets

All art and audio are generated. Nothing is drawn or recorded by hand, and nothing is
taken from other games.

```sh
python3 tools/art/tiles.py && python3 tools/art/props.py && python3 tools/art/chars.py \
  && python3 tools/art/icons.py && python3 tools/art/machines.py
python3 tools/maps/build_maps.py
python3 tools/audio/make_sfx.py && python3 tools/audio/make_music.py && python3 tools/audio/make_ambience.py
godot --headless --path . --import
```

The art tools need Python 3 with Pillow, and the audio tools need numpy, scipy and ffmpeg
(with libvorbis).

## Screenshots and test scenes

```sh
tools/capture.sh menu out.png                    # title screen
tools/capture.sh cut_demo:power out.png          # the cut view with a powered circuit
tools/capture.sh midgame out.png --ui=journal    # any panel over a day-3 world
godot --path . -- --scene=res://scenes/test/audio_test.tscn    # audition every sound
godot --path . -- --scene=res://scenes/test/stress_test.tscn   # sim + render bench
```

The scenarios live in `src/debug/scenarios.gd`:
- `wick_day`, `wick_night`, `commons`, `lake`, `opening`
- `cut[:overlay[:tool[:machine]]]`, `cut_demo`, `cut_exit`
- `midgame`, `talk:<npc>`, `quietlight`, `tremor`, `harvest`, `trunk`
- `reach:<id>`, `pos:x:z`

## Documentation

- [Design](docs/DESIGN.md): pillars, the world, characters, the loop, the MVP contract and its critique.
- [Architecture](docs/ARCHITECTURE.md): runtime structure, state, data and rendering.
- [Systems](docs/SYSTEMS.md): simulation rules, machines, saves, procgen, audio and shaders, in depth.
- [Content guide](docs/CONTENT_GUIDE.md): adding items, crops, machines, people, dialogue, quests and events.
- [Research log](docs/RESEARCH_LOG.md), [Risks](docs/RISKS.md), [Devlog](docs/DEVLOG.md).

## Credits

Design, code, pixel art, music and sound were generated for this project.

The fonts are [Pixelify Sans](https://github.com/eifetx/Pixelify-Sans) and
[Atkinson Hyperlegible](https://brailleinstitute.org/freefont), both under the SIL Open Font
License (copies in `assets/fonts/`). The engine is [Godot](https://godotengine.org) (MIT).
