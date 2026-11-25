#!/usr/bin/env python3
"""Self-contained Petdex manager for the Omarchy Hermes Pets plugin.

Zero external CLI dependencies (no `hermes`, no `curl`, no `timeout` required):
uses only the Python standard library.

Commands:
  petdex.py scan <pets-dir>
  petdex.py catalog <pets-dir> [--refresh]
  petdex.py install <pets-dir> <slug>
  petdex.py remove <pets-dir> <slug>
"""
from __future__ import annotations

import errno
import itertools
import json
import os
import re
import shutil
import stat
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

MANIFEST_URL = "https://petdex.dev/api/manifest"
ALLOWED_HOSTS = {"petdex.dev", "assets.petdex.dev"}
USER_AGENT = "hermes-pets-omarchy/0.2"

CATALOG_CACHE_FILE = ".catalog-cache.json"
CATALOG_CACHE_TTL_S = 900  # 15 minutes
HTTP_TIMEOUT_S = 25

MAX_ENTRIES = 500
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
MAX_JSON_BYTES = 64 * 1024
MAX_SHEET_BYTES = 32 * 1024 * 1024
HEADER_BYTES = 30
SHEET_WIDTH = 192 * 8
CELL_HEIGHT = 208
MIN_ROWS = 9
MAX_ROWS = 32
MAX_TEXT = 80
MAX_KIND = 32
MAX_PATH = 255
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
OPEN_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOCTTY


class Skip(Exception):
    """Not a usable pet; the message says why."""


def read_regular(path: str, limit: int, want: int) -> bytes:
    """Descriptor-bound read: no symlink, regular file, bounded size."""
    name = os.path.basename(path)
    try:
        fd = os.open(path, OPEN_FLAGS)
    except FileNotFoundError:
        raise
    except OSError as error:
        if error.errno == errno.ELOOP:
            raise Skip(f"{name} is a symlink") from None
        raise Skip(f"{name}: {error.strerror}") from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise Skip(f"{name} is not a regular file")
        if info.st_size > limit:
            raise Skip(f"{name} is {info.st_size} bytes, limit {limit}")
        chunks = []
        remaining = min(want, info.st_size)
        while remaining > 0:
            chunk = os.read(fd, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)
    finally:
        os.close(fd)


def sheet_size(header: bytes) -> tuple[int, int] | None:
    """(width, height) from a PNG or WebP header, else None."""
    if header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR" and len(header) >= 25:
        return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")
    if header[:4] != b"RIFF" or header[8:12] != b"WEBP" or len(header) < 30:
        return None
    chunk = header[12:16]
    if chunk == b"VP8X":
        return int.from_bytes(header[24:27], "little") + 1, int.from_bytes(header[27:30], "little") + 1
    if chunk == b"VP8L" and header[20:21] == b"\x2f":
        bits = int.from_bytes(header[21:25], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if chunk == b"VP8 " and header[23:26] == b"\x9d\x01\x2a":
        return int.from_bytes(header[26:28], "little") & 0x3FFF, int.from_bytes(header[28:30], "little") & 0x3FFF
    return None


def validate_sheet_header(header: bytes, label: str = "spritesheet") -> str:
    """Validate atlas header and return extension ('.png' or '.webp'), or raise Skip."""
    size = sheet_size(header)
    if size is None:
        raise Skip(f"{label} is not a WebP or PNG file")
    is_png = header[:4] == b"\x89PNG"
    if is_png and len(header) > 24 and header[24] > 8:
        raise Skip(f"PNG bit depth {header[24]} is not supported")
    width, height = size
    if width != SHEET_WIDTH:
        raise Skip(f"atlas width {width} is not {SHEET_WIDTH}")
    if height % CELL_HEIGHT:
        raise Skip(f"atlas height {height} is not a multiple of {CELL_HEIGHT}")
    rows = height // CELL_HEIGHT
    if not MIN_ROWS <= rows <= MAX_ROWS:
        raise Skip(f"atlas has {rows} rows, expected {MIN_ROWS}-{MAX_ROWS}")
    return ".png" if is_png else ".webp"


def text_problem(text: str) -> str | None:
    """Why text cannot be emitted, or None."""
    try:
        text.encode("utf-8")
    except UnicodeEncodeError:
        return "is not valid UTF-8"
    if any(unicodedata.category(c) in ("Cc", "Zl", "Zp") for c in text):
        return "has control characters"
    return None


def sanitize_text(value: object, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    cleaned = "".join(c for c in value if unicodedata.category(c) not in ("Cc", "Zl", "Zp"))
    return cleaned.strip()[:limit]


def plain_relative(path: object) -> bool:
    return (
        isinstance(path, str)
        and 0 < len(path) <= MAX_PATH
        and not path.startswith("/")
        and ".." not in path.split("/")
        and text_problem(path) is None
    )


def validate_slug(slug: str) -> str:
    if not isinstance(slug, str) or not SLUG_RE.match(slug):
        raise ValueError(f"invalid pet slug: {slug!r}")
    return slug


def validate_url(url: object) -> str:
    if not isinstance(url, str) or not url:
        raise ValueError("empty URL")
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        raise ValueError(f"disallowed URL: {url}")
    return url


def fetch_bytes(url: str, max_bytes: int) -> bytes:
    validate_url(url)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            if resp.status != 200:
                raise RuntimeError(f"HTTP {resp.status} for {url}")
            chunks = []
            total = 0
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise RuntimeError(f"response exceeds {max_bytes} bytes")
                chunks.append(chunk)
            return b"".join(chunks)
    except urllib.error.URLError as exc:
        raise RuntimeError(f"network error: {exc.reason}") from None


# --- scan --------------------------------------------------------------------

def metadata(directory: str) -> tuple[dict, str]:
    data = read_regular(os.path.join(directory, "pet.json"), MAX_JSON_BYTES, MAX_JSON_BYTES)
    try:
        meta = json.loads(data)
    except (ValueError, RecursionError):
        raise Skip("pet.json is not valid JSON") from None
    if not isinstance(meta, dict):
        raise Skip("pet.json is not a JSON object")
    pet_id = meta.get("id")
    if not isinstance(pet_id, str) or not pet_id:
        raise Skip("pet.json has no id")
    sheet = meta.get("spritesheetPath")
    if not plain_relative(sheet):
        raise Skip("spritesheetPath is not a plain relative path")
    out = {}
    for key, limit in (("id", MAX_TEXT), ("displayName", MAX_TEXT), ("kind", MAX_KIND)):
        if key in meta:
            if not isinstance(meta[key], str):
                raise Skip(f"{key} is not a string")
            problem = text_problem(meta[key])
            if problem:
                raise Skip(f"{key} {problem}")
            out[key] = meta[key][:limit]
    out["spritesheetPath"] = sheet
    return out, sheet


def describe(entry: os.DirEntry) -> tuple[str, str] | None:
    if entry.name.startswith("."):
        return None
    try:
        if not entry.is_dir(follow_symlinks=False):
            return None
    except OSError as error:
        return "skip", f"cannot stat: {error.strerror}"
    try:
        meta, sheet = metadata(entry.path)
    except FileNotFoundError:
        return None
    except Skip as skip:
        return "skip", str(skip)
    try:
        header = read_regular(os.path.join(entry.path, sheet), MAX_SHEET_BYTES, HEADER_BYTES)
    except FileNotFoundError:
        return "skip", f"spritesheet missing: {sheet}"
    except Skip as skip:
        return "skip", str(skip)
    try:
        validate_sheet_header(header, os.path.basename(sheet))
    except Skip as skip:
        return "skip", str(skip)
    return "pet", json.dumps(meta, ensure_ascii=False, separators=(",", ":"))


def cmd_scan(root: str) -> None:
    problem = text_problem(root)
    if problem:
        sys.exit(f"pets directory path {problem}: {root!r}")
    try:
        os.stat(root)
    except FileNotFoundError:
        return
    with os.scandir(root) as entries:
        listed = list(itertools.islice(entries, MAX_ENTRIES + 1))
    if len(listed) > MAX_ENTRIES:
        print(f"more than {MAX_ENTRIES} entries in {root}, ignoring the rest", file=sys.stderr)
        del listed[MAX_ENTRIES:]
    for entry in sorted(listed, key=lambda e: e.name):
        problem = text_problem(entry.name)
        if problem:
            print(f"skip\t{entry.path!r}\tdirectory name {problem}")
            continue
        described = describe(entry)
        if described:
            print(f"{described[0]}\t{entry.path}\t{described[1]}")


# --- catalog -----------------------------------------------------------------

def load_manifest(pets_dir: str, refresh: bool = False) -> list[dict]:
    cache_path = os.path.join(pets_dir, CATALOG_CACHE_FILE)
    if not refresh and os.path.isfile(cache_path):
        try:
            age = time.time() - os.path.getmtime(cache_path)
            if 0 <= age <= CATALOG_CACHE_TTL_S:
                raw = read_regular(cache_path, MAX_MANIFEST_BYTES, MAX_MANIFEST_BYTES)
                cached = json.loads(raw)
                if isinstance(cached, list) and cached:
                    return cached
        except (OSError, ValueError, Skip):
            pass

    raw = fetch_bytes(MANIFEST_URL, MAX_MANIFEST_BYTES)
    data = json.loads(raw)
    arr = data.get("pets") if isinstance(data, dict) else None
    if not isinstance(arr, list):
        raise RuntimeError("invalid manifest format")

    pets = []
    for entry in arr:
        if not isinstance(entry, dict):
            continue
        slug = entry.get("slug")
        if not isinstance(slug, str) or not SLUG_RE.match(slug):
            continue
        sheet_url = entry.get("spritesheetUrl")
        try:
            validate_url(sheet_url)
        except ValueError:
            continue
        pet_json_url = ""
        if entry.get("petJsonUrl"):
            try:
                pet_json_url = validate_url(entry["petJsonUrl"])
            except ValueError:
                pet_json_url = ""
        pets.append({
            "slug": slug,
            "displayName": sanitize_text(entry.get("displayName"), MAX_TEXT) or slug,
            "kind": sanitize_text(entry.get("kind"), MAX_KIND),
            "sheetUrl": sheet_url,
            "petJsonUrl": pet_json_url,
        })

    try:
        os.makedirs(pets_dir, exist_ok=True)
        tmp = f"{cache_path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(pets, fh, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, cache_path)
    except OSError:
        pass

    return pets


def cmd_catalog(pets_dir: str, refresh: bool = False) -> None:
    pets = load_manifest(pets_dir, refresh=refresh)
    compact = [
        {
            "slug": p["slug"],
            "displayName": p["displayName"],
            "kind": p["kind"],
            "sheetUrl": p["sheetUrl"],
        }
        for p in pets
    ]
    print(json.dumps({"total": len(compact), "pets": compact}, ensure_ascii=False, separators=(",", ":")))


# --- install -----------------------------------------------------------------

def cmd_install(pets_dir: str, slug: str) -> None:
    validate_slug(slug)
    pets = load_manifest(pets_dir, refresh=False)
    entry = next((p for p in pets if p["slug"] == slug), None)
    if entry is None:
        pets = load_manifest(pets_dir, refresh=True)
        entry = next((p for p in pets if p["slug"] == slug), None)
    if entry is None:
        sys.exit(f"pet not found in catalog: {slug}")

    sheet_bytes = fetch_bytes(entry["sheetUrl"], MAX_SHEET_BYTES)
    try:
        ext = validate_sheet_header(sheet_bytes[:HEADER_BYTES], slug)
    except Skip as skip:
        sys.exit(f"invalid spritesheet for {slug}: {skip}")

    sheet_filename = f"spritesheet{ext}"
    pet_meta: dict = {
        "id": slug,
        "displayName": entry["displayName"] or slug,
        "kind": entry["kind"],
        "spritesheetPath": sheet_filename,
    }

    if entry.get("petJsonUrl"):
        try:
            raw_meta = fetch_bytes(entry["petJsonUrl"], MAX_JSON_BYTES)
            parsed = json.loads(raw_meta)
            if isinstance(parsed, dict):
                if isinstance(parsed.get("displayName"), str):
                    name = sanitize_text(parsed["displayName"], MAX_TEXT)
                    if name:
                        pet_meta["displayName"] = name
                if isinstance(parsed.get("kind"), str):
                    pet_meta["kind"] = sanitize_text(parsed["kind"], MAX_KIND)
                if isinstance(parsed.get("description"), str):
                    pet_meta["description"] = sanitize_text(parsed["description"], 240)
                if isinstance(parsed.get("spriteVersionNumber"), int):
                    pet_meta["spriteVersionNumber"] = parsed["spriteVersionNumber"]
        except (RuntimeError, ValueError):
            pass

    os.makedirs(pets_dir, exist_ok=True)
    staging = os.path.join(pets_dir, f".tmp-{slug}-{os.getpid()}")
    target = os.path.join(pets_dir, slug)
    if os.path.islink(target):
        sys.exit(f"refusing to overwrite symlink: {target}")

    try:
        os.makedirs(staging, exist_ok=False)
        with open(os.path.join(staging, sheet_filename), "wb") as fh:
            fh.write(sheet_bytes)
        with open(os.path.join(staging, "pet.json"), "w", encoding="utf-8") as fh:
            json.dump(pet_meta, fh, ensure_ascii=False, indent=2)
            fh.write("\n")

        if os.path.exists(target):
            shutil.rmtree(target)
        os.replace(staging, target)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    print(json.dumps({"ok": True, "slug": slug, "displayName": pet_meta["displayName"]}, ensure_ascii=False))


# --- remove ------------------------------------------------------------------

def cmd_remove(pets_dir: str, slug: str) -> None:
    validate_slug(slug)
    real_root = os.path.realpath(pets_dir)
    target = os.path.join(pets_dir, slug)
    if os.path.islink(target):
        sys.exit(f"refusing to delete symlink: {target}")
    if not os.path.isdir(target):
        sys.exit(f"pet not installed: {slug}")
    if os.path.dirname(os.path.realpath(target)) != real_root:
        sys.exit(f"refusing to delete outside pets directory: {slug}")

    shutil.rmtree(target)

    thumb = os.path.join(pets_dir, ".thumbs", f"{slug}.png")
    if os.path.isfile(thumb) and not os.path.islink(thumb):
        try:
            os.remove(thumb)
        except OSError:
            pass

    print(json.dumps({"ok": True, "slug": slug}, ensure_ascii=False))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit("usage: petdex.py <scan|catalog|install|remove> <pets-dir> [args...]")

    cmd = args[0]
    pets_dir = args[1]
    try:
        if cmd == "scan" and len(args) == 2:
            cmd_scan(pets_dir)
        elif cmd == "catalog" and len(args) in (2, 3):
            refresh = len(args) == 3 and args[2] == "--refresh"
            cmd_catalog(pets_dir, refresh=refresh)
        elif cmd == "install" and len(args) == 3:
            cmd_install(pets_dir, args[2])
        elif cmd == "remove" and len(args) == 3:
            cmd_remove(pets_dir, args[2])
        else:
            sys.exit("usage: petdex.py <scan|catalog|install|remove> <pets-dir> [args...]")
    except (ValueError, RuntimeError, OSError) as exc:
        sys.exit(str(exc))


if __name__ == "__main__":
    main()
