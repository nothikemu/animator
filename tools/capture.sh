#!/usr/bin/env bash
# Renders a game scenario (or any scene) to a PNG under a virtual display (software GL/Vulkan).
#   tools/capture.sh <scenario> <out.png> [extra args...]
#   tools/capture.sh menu <out.png>            # the title screen
#   tools/capture.sh <scenario> <out.png> --ui=journal   # open a panel before the shot
set -e
cd "$(dirname "$0")/.."
SCEN="$1"; OUT="$2"; shift 2
if [ "$SCEN" = "menu" ]; then
  TARGET="--scene=res://scenes/main_menu.tscn"
else
  TARGET="--scenario=$SCEN"
fi
timeout 240 xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1280x720 -- "$TARGET" --capture="$OUT" "$@" 2>&1 | grep -v -E "ALSA|audio_driver|All audio drivers|at: (init_output|initialize)|status < 0|^\s*$" | tail -15
