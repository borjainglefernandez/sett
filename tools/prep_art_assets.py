#!/usr/bin/env python3
"""Package generated exercise art into the Xcode asset catalog.
Pads each 1024 image ~10% (so a circular crop keeps hair/feet), resizes to 512,
and writes ExArt_<key>.imageset with a single-scale universal Contents.json."""
import json, os, sys
from PIL import Image

ART = os.environ.get("ART_SRC") or sys.exit("set ART_SRC to the generated-art directory")
CATALOG = os.environ.get("ART_CATALOG", "/Users/borja/Projects/sett-v2/Sett/Assets.xcassets")
BG = (10, 13, 18)   # #0A0D12 — the app's screen color

count = 0
for fname in sorted(os.listdir(ART)):
    if not fname.endswith(".png"):
        continue
    key = fname[:-4]
    img = Image.open(os.path.join(ART, fname)).convert("RGB")
    side = min(img.size)
    img = img.crop(((img.width - side) // 2, (img.height - side) // 2,
                    (img.width + side) // 2, (img.height + side) // 2))
    # pad 10% so a circle crop in-app doesn't clip the aura/hair
    pad = int(side * 0.10)
    canvas = Image.new("RGB", (side + 2 * pad, side + 2 * pad), BG)
    canvas.paste(img, (pad, pad))
    canvas = canvas.resize((512, 512), Image.LANCZOS)

    setdir = os.path.join(CATALOG, f"ExArt_{key}.imageset")
    os.makedirs(setdir, exist_ok=True)
    canvas.save(os.path.join(setdir, "art.png"), optimize=True)
    json.dump({"images": [{"filename": "art.png", "idiom": "universal"}],
               "info": {"author": "xcode", "version": 1}},
              open(os.path.join(setdir, "Contents.json"), "w"), indent=2)
    count += 1
print(f"packaged {count} imagesets into {CATALOG}")
