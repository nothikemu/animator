#!/usr/bin/env bash
# Renders a game scenario to a PNG under a virtual display (software GL/Vulkan).
#   tools/capture.sh <scenario> <out.png> [extra args...]
set -e
cd "$(dirname "$0")/.."
SCEN="$1"; OUT="$2"; shift 2
timeout 240 xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1280x720 res://scenes/game.tscn -- --scenario="$SCEN" --capture="$OUT" "$@" 2>&1 | grep -v -E "ALSA|audio_driver|All audio drivers|at: (init_output|initialize)|^\s*$" | tail -15
