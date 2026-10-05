#!/usr/bin/env bash
# Export the browser build and package it for static hosting.
#   tools/build_web.sh            -> build/webpub/ (serve it with any static server)
# Needs Godot 4.7 with the Web export templates installed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
python3 tools/web/package.py
echo "Try it: python3 -m http.server -d build/webpub 8000  ->  http://localhost:8000"
