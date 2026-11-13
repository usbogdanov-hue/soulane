#!/usr/bin/env python3
"""Prepare a freshly exported Godot build in the existing private Site checkout.

This packages local files only. It never requests credentials or publishes.
Run export_web.py from the same clean source commit before this command.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[1]
SITE_ID = "appgprj_6af6ec80bdec8191849423a2099135ac"
MAX_ASSET_BYTES = 25 * 1024 * 1024
GAME_PATHS = ("scripts", "data", "scenes", "project.godot")
ADAPTER = r'''/* Decode the explicit gzip asset before Godot receives WASM bytes. */
(() => {
  'use strict';
  const nativeFetch = globalThis.fetch.bind(globalThis);
  const wasmURL = new URL('index.wasm', document.baseURI);
  const decodedSize = __DECODED_SIZE__;
  globalThis.fetch = async function (input, init) {
    const requestedURL = new URL(input instanceof Request ? input.url : String(input), document.baseURI);
    if (requestedURL.origin !== wasmURL.origin || requestedURL.pathname !== wasmURL.pathname) {
      return nativeFetch(input, init);
    }
    if (typeof DecompressionStream !== 'function') {
      throw new Error('Для загрузки игры нужен современный браузер с поддержкой DecompressionStream.');
    }
    requestedURL.pathname += '.gz';
    const response = await nativeFetch(requestedURL.href, init);
    if (!response.ok) return response;
    if (!response.body) throw new Error('Не удалось загрузить движок игры. Обновите страницу.');
    const headers = new Headers(response.headers);
    headers.delete('Content-Encoding');
    headers.set('Content-Type', 'application/wasm');
    headers.set('Content-Length', String(decodedSize));
    return new Response(response.body.pipeThrough(new DecompressionStream('gzip')), {
      status: response.status,
      statusText: response.statusText,
      headers
    });
  };
})();
'''


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".suleyn-", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def source_version() -> str:
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    name = re.search(r'^config/name="([^"]+)"', project, re.MULTILINE)
    version = re.search(r"\bv\d+(?:\.\d+)+", name.group(1)) if name else None
    return version.group(0) if version else "dev"


def prepare(export_dir: Path, site_dir: Path, version: str) -> dict:
    export_dir, site_dir = export_dir.resolve(), site_dir.resolve()
    if not export_dir.is_dir() or not site_dir.is_dir():
        raise ValueError("Both export and existing Site directories must exist")
    if export_dir == site_dir or site_dir in export_dir.parents or export_dir in site_dir.parents:
        raise ValueError("Export and Site directories must be separate, not nested")
    if site_dir == ROOT or site_dir in ROOT.parents or ROOT in site_dir.parents:
        raise ValueError("Site output must not replace the game repository or its parent")
    manifest_path = site_dir / ".openai" / "hosting.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    if manifest.get("project_id") != SITE_ID or manifest.get("static", {}).get("directory") != "dist":
        raise ValueError("The checkout is not the expected private Site with static directory dist")
    dist = site_dir / "dist"
    game = dist / "game"
    if dist.is_symlink() or game.is_symlink() or not dist.is_dir():
        raise ValueError("Site dist/game must be an ordinary generated directory")
    if game.exists() and not game.is_dir():
        raise ValueError("Existing dist/game is not a directory")
    index_path, source_path = dist / "index.html", site_dir / "source.json"
    if index_path.is_symlink() or source_path.is_symlink():
        raise ValueError("Site index and source metadata must not be symlinks")
    index_before = index_path.read_bytes()
    source_before = source_path.read_bytes() if source_path.exists() else None
    current_commit = git("rev-parse", "HEAD")
    if git("diff", "HEAD", "--name-only", "--", *GAME_PATHS):
        raise ValueError("Tracked game sources are dirty; commit before exporting")
    untracked = git("ls-files", "--others", "--exclude-standard", "--", *GAME_PATHS)
    if any(not name.endswith(".gd.uid") for name in untracked.splitlines()):
        raise ValueError("Untracked game sources exist; commit before exporting")
    stamp = json.loads((export_dir / ".suleyn-export.json").read_text(encoding="utf-8"))
    if stamp.get("source_commit") != current_commit:
        raise ValueError("Raw export belongs to another source commit; export the current HEAD again")
    wasm = (export_dir / "index.wasm").read_bytes()
    pck = (export_dir / "index.pck").read_bytes()
    if wasm[:8] != b"\0asm\x01\0\0\0" or not pck:
        raise ValueError("Missing or invalid WebAssembly/PCK output")
    if stamp.get("wasm_sha256") != digest(wasm) or stamp.get("pck_sha256") != digest(pck):
        raise ValueError("Raw engine or game package does not match its export stamp")
    if not stamp.get("engine_version"):
        raise ValueError("Export stamp is missing the actual Godot version")
    for name in ("index.html", "index.js"):
        if not (export_dir / name).is_file() or not (export_dir / name).stat().st_size:
            raise ValueError(f"Missing or empty raw export file: {name}")
    label = f"{version} · {current_commit[:8]}"
    pattern = r'(?P<open><span\b[^>]*\sid=(?P<q>[\"\x27])build-label(?P=q)[^>]*>).*?(?P<close></span>)'
    index, count = re.subn(pattern, lambda m: m["open"] + html.escape(label) + m["close"],
                           index_before.decode("utf-8"), count=1, flags=re.DOTALL)
    if count != 1:
        raise ValueError('Site launcher must contain <span id="build-label"> before packaging')

    def update_iframe(match: re.Match) -> str:
        url = urlsplit(html.unescape(match["url"]))
        query = dict(parse_qsl(url.query, keep_blank_values=True))
        query["build"] = current_commit[:12]
        value = urlunsplit((url.scheme, url.netloc, url.path, urlencode(query), url.fragment))
        return match["prefix"] + html.escape(value, quote=True) + match["quote"]

    iframe_pattern = r'(?P<prefix><iframe\b[^>]*\ssrc=(?P<quote>[\"\x27]))(?P<url>game/index\.html(?:\?[^\"\x27]*)?)(?P=quote)'
    index = re.sub(iframe_pattern, update_iframe, index, count=1)
    metadata = {
        "project": "Сулэйн", "version": version,
        "source_repository": "https://github.com/usbogdanov-hue/soulane",
        "source_commit": current_commit,
        "engine": "Godot " + str(stamp["engine_version"]),
        "export": "Web, single-threaded, WebGL 2",
        "wasm_uncompressed_bytes": len(wasm), "wasm_sha256": digest(wasm),
    }
    compressed = gzip.compress(wasm, mtime=0)
    if digest(gzip.decompress(compressed)) != metadata["wasm_sha256"]:
        raise ValueError("Gzip round-trip changed the original engine bytes")
    metadata["wasm_gzip_sha256"] = digest(compressed)
    with tempfile.TemporaryDirectory(prefix=".prepare-web-", dir=site_dir) as temporary:
        temporary = Path(temporary)
        staged = temporary / "game"
        staged.mkdir()
        for item in export_dir.rglob("*"):
            relative = item.relative_to(export_dir)
            if item.is_symlink():
                raise ValueError(f"Export contains a symlink: {relative}")
            if any(part.startswith(".") for part in relative.parts) or item.suffix == ".gz" or relative == Path("index.wasm"):
                continue
            destination = staged / relative
            if item.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            elif item.is_file():
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, destination)
        (staged / "index.wasm.gz").write_bytes(compressed)
        (staged / "wasm-gzip.js").write_text(ADAPTER.replace("__DECODED_SIZE__", str(len(wasm))), encoding="utf-8")
        game_html = (staged / "index.html").read_text(encoding="utf-8")
        loader = '<script src="index.js"></script>'
        if "wasm-gzip.js" in game_html or game_html.count(loader) != 1:
            raise ValueError("Expected a fresh Godot HTML export with exactly one index.js loader")
        (staged / "index.html").write_text(game_html.replace(loader, '<script src="wasm-gzip.js"></script>\n\t' + loader), encoding="utf-8")
        for item in [*staged.rglob("*"), *dist.rglob("*")]:
            if game == item or game in item.parents:
                continue
            if item.is_file() and item.stat().st_size >= MAX_ASSET_BYTES:
                raise ValueError(f"Published asset exceeds the 25 MiB limit: {item.name}")
        backup = temporary / "previous-game"
        had_game = game.exists()
        if had_game:
            game.rename(backup)
        try:
            staged.rename(game)
            atomic_write(index_path, index.encode("utf-8"))
            atomic_write(source_path, (json.dumps(metadata, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        except BaseException:
            if game.exists():
                shutil.rmtree(game)
            if had_game:
                backup.rename(game)
            atomic_write(index_path, index_before)
            if source_before is None:
                source_path.unlink(missing_ok=True)
            else:
                atomic_write(source_path, source_before)
            raise
    if manifest_path.read_bytes() != manifest_bytes:
        raise RuntimeError("Unexpected hosting identity change")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export-dir", type=Path, required=True)
    parser.add_argument("--site-dir", type=Path, required=True)
    parser.add_argument("--version", help="Visible version label; defaults to project.godot config/name")
    args = parser.parse_args()
    try:
        result = prepare(args.export_dir, args.site_dir, args.version or source_version())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Web Site preparation stopped: {error}") from error
    print(f"Prepared {result['version']} from {result['source_commit']} in {args.site_dir.resolve()}")
    print(f"Engine {result['wasm_uncompressed_bytes']} bytes; original and gzip SHA256 verified.")
    print("Site identity preserved. Commit/push the Site checkout and publish using the existing Sites project.")


if __name__ == "__main__":
    main()
