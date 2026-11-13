#!/usr/bin/env python3
"""Export the single-threaded Godot Web preset into a chosen directory.

Requires Godot and its matching Web release export template. Does not publish.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]


def run_godot(command: list[str]) -> None:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end="")
    if result.returncode != 0 or re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:)", result.stdout):
        raise SystemExit("Godot reported an import/export error; output is not validated")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot executable")
    parser.add_argument("--output", type=Path, default=ROOT / "builds" / "web")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    run_godot([args.godot, "--headless", "--editor", "--path", str(ROOT), "--import"])
    run_godot([args.godot, "--headless", "--path", str(ROOT), "--export-release", "Web", str(output / "index.html")])
    required = ("index.html", "index.js", "index.wasm", "index.pck")
    for name in required:
        path = output / name
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"Missing or empty export file: {path}")
    with (output / "index.wasm").open("rb") as engine:
        if engine.read(8) != b"\0asm\x01\0\0\0":
            raise SystemExit("Exported index.wasm has an invalid WebAssembly header")
    for path in sorted(output.iterdir()):
        if path.is_file():
            print(f"{path.name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
