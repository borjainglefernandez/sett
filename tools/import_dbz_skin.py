#!/usr/bin/env python3
"""Personal-build skin importer: pulls Dragon Ball character art from the free
community API (dragonball-api.com) into the swappable asset-pack format.

The output directory (Skins/DBZ/) is GITIGNORED on purpose: this art is
Toei/Shueisha IP served by an unofficial fan API. It may live on your personal
dev build only — never commit it, never ship it in the TestFlight build
(which uses the original Ashfall Clan art).

Usage: python3 tools/import_dbz_skin.py
Output: Skins/DBZ/<characterKey>/tier<N>.webp + Skins/DBZ/manifest.json
"""

import json
import pathlib
import sys
import urllib.parse
import urllib.request

API = "https://dragonball-api.com/api"
OUT = pathlib.Path(__file__).resolve().parent.parent / "Skins" / "DBZ"

# Our roster -> the real one. Tier ladder (base, kindled, ascendant, radiant, zenith)
# fills from base image + up to 4 transformations in API order.
ROSTER = {
    "vego": "Vegeta",
    "gosi": "Goku",
    "barok": "Broly",
    "nyra": "Android 18",
    "torren": "Piccolo",
    "zia": "Bulma",
    "zyn": "Gohan",
    "vexeth": "Freezer",  # API uses the Japanese/Spanish romanization
}
TIER_COUNT = 5


def get(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "sett-skin-importer"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def download(url: str, dest: pathlib.Path):
    # API image URLs contain literal spaces — encode the path segment only.
    parts = urllib.parse.urlsplit(url)
    safe = urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, urllib.parse.quote(parts.path), parts.query, "")
    )
    req = urllib.request.Request(safe, headers={"User-Agent": "sett-skin-importer"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        dest.write_bytes(resp.read())


def main() -> int:
    print(f"Fetching character index from {API} ...")
    items = []
    page = 1
    while True:
        data = get(f"{API}/characters?page={page}&limit=50")
        items.extend(data["items"])
        if not data["links"].get("next"):
            break
        page += 1
    by_name = {c["name"].lower(): c for c in items}
    print(f"  {len(items)} characters available")

    manifest = {}
    missing = []
    for key, wanted in ROSTER.items():
        entry = by_name.get(wanted.lower())
        if entry is None:
            # loose match (e.g. "Frieza" vs "Freezer")
            entry = next((c for c in items if wanted.lower()[:4] in c["name"].lower()), None)
        if entry is None:
            missing.append(wanted)
            continue

        detail = get(f"{API}/characters/{entry['id']}")
        char_dir = OUT / key
        char_dir.mkdir(parents=True, exist_ok=True)

        images = [detail["image"]] + [t["image"] for t in detail.get("transformations", [])]
        images = images[:TIER_COUNT]
        # Pad short ladders by repeating the highest form.
        while len(images) < TIER_COUNT:
            images.append(images[-1])

        tiers = {}
        for tier, url in enumerate(images):
            dest = char_dir / f"tier{tier}.webp"
            download(url, dest)
            tiers[str(tier)] = str(dest.relative_to(OUT))
        manifest[key] = {
            "sourceName": detail["name"],
            "maxKi": detail.get("maxKi"),
            "tiers": tiers,
        }
        print(f"  {key:8s} <- {detail['name']:12s} ({len(detail.get('transformations', []))} forms)")

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nWrote {OUT / 'manifest.json'}")
    if missing:
        print(f"NOT FOUND in API (placeholder art stays): {', '.join(missing)}")
    print("Reminder: Skins/ is gitignored — personal build only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
