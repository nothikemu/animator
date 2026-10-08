#!/usr/bin/env python3
"""Turn Godot's Web export (build/web) into a folder (build/webpub) that a static host with
strict limits can serve: our own launch page, and the engine and game pack shipped as base64
text of their gzip, split into parts where needed (no file over 16 MB, only standard web types). The page's fetch shim turns
them back into index.wasm and index.pck. The build is single-threaded, so no special server
headers (COOP/COEP) are needed."""

import base64
import gzip
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "build" / "web"
OUT = ROOT / "build" / "webpub"
HERE = Path(__file__).resolve().parent
COPY = ["index.js", "index.audio.worklet.js", "index.audio.position.worklet.js"]
PACK = {"index.wasm": "application/wasm", "index.pck": "application/octet-stream"}
TEXT_LIMIT = 16_000_000


def pack(name: str) -> dict:
	"""Write <name>.txt (base64 of gzip, 76-char lines) and describe it for the page. Text over
	the limit is cut at line boundaries into <name>.0.txt, <name>.1.txt, ... (each line is a
	whole number of base64 groups, so the page can simply join the parts before decoding)."""
	raw = (SRC / name).read_bytes()
	text = base64.encodebytes(gzip.compress(raw, compresslevel=9, mtime=0))
	if len(text) <= TEXT_LIMIT:
		dest = OUT / f"{name}.txt"
		dest.write_bytes(text)
		return {"parts": [dest.name], "type": PACK[name], "size": len(text)}
	line = 77  # 76 base64 characters and a newline
	per = (TEXT_LIMIT // line) * line
	parts = []
	for i, at in enumerate(range(0, len(text), per)):
		dest = OUT / f"{name}.{i}.txt"
		dest.write_bytes(text[at:at + per])
		parts.append(dest.name)
	return {"parts": parts, "type": PACK[name], "size": len(text)}


def main() -> int:
	shell = (SRC / "index.html").read_text(encoding="utf-8")
	m = re.search(r"const GODOT_CONFIG = (\{.*?\});", shell)
	if not m:
		print("GODOT_CONFIG not found in build/web/index.html; export first.", file=sys.stderr)
		return 1
	config = json.loads(m.group(1))
	config["ensureCrossOriginIsolationHeaders"] = False  # no service worker; nothreads needs no COOP/COEP

	if OUT.exists():
		shutil.rmtree(OUT)
	OUT.mkdir(parents=True)

	packed = {name: pack(name) for name in PACK}
	for name in COPY:
		shutil.copy2(SRC / name, OUT / name)
	shutil.copy2(HERE / "wick.jpg", OUT / "wick.jpg")

	page = (HERE / "launcher.html").read_text(encoding="utf-8")
	page = re.sub(r"/\*GODOT_CONFIG\*/.*?/\*END\*/", lambda _: json.dumps(config, separators=(",", ":")), page)
	page = re.sub(r"/\*PACKED\*/.*?/\*END\*/", lambda _: json.dumps(packed, separators=(",", ":")), page)

	# artifact.html is the bare page for hosts that wrap it in their own document skeleton;
	# index.html is the same page as a complete document, for any ordinary static host.
	(OUT / "artifact.html").write_text(page, encoding="utf-8")
	(OUT / "index.html").write_text(
		'<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
		'<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
		'<style>body { margin: 0; }</style>\n</head>\n<body>\n' + page + '\n</body>\n</html>\n',
		encoding="utf-8",
	)

	for p in sorted(OUT.iterdir()):
		print(f"{p.stat().st_size:>12,}  {p.name}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
