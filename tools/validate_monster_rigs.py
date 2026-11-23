"""Automated MamPet Monster Rig & Asset Validation Script (Section 14).

Checks:
1. Authoritative rig_manifest.json exists and indexes all 60 characters (20 species x 3 stages).
2. Every character has valid rig.json & animations.json matching the required schema.
3. Every declared layer asset exists, is non-empty, has RGBA transparency (alpha channel),
   has transparent corners (no baked opaque box), and matches the declared 1024x1024 canvas.
4. Every pivot coordinate lies within [0.0 .. 1.0] and every parent reference resolves cleanly.
5. Every animations.json defines all 7 required states (idle, happy, pet, eat, sleep, play, evolve).
6. Reports accurate counts by rig_tier and total bundled layer size in MB.
"""

import json
import os
import sys
from PIL import Image

ASSETS_ROOT = r"c:\Project\mampet\assets\monsters"
MANIFEST_PATH = os.path.join(ASSETS_ROOT, "rig_manifest.json")
REQUIRED_STATES = {"idle", "happy", "pet", "eat", "sleep", "play", "evolve"}
VALID_TIERS = {"full_layered", "partial_rig", "whole_body", "needs_manual_art"}


def validate():
    errors = []
    warnings = []
    tier_counts = {}
    total_layer_bytes = 0
    total_layers = 0

    if not os.path.isfile(MANIFEST_PATH):
        print(f"FATAL: Missing {MANIFEST_PATH}")
        return 1

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    chars = manifest.get("characters", [])
    if len(chars) != 60:
        errors.append(f"Expected 60 characters in rig_manifest.json, found {len(chars)}")

    for entry in chars:
        slug = entry["monster_id"]
        stage = entry["stage"]
        base_dir = os.path.join(ASSETS_ROOT, slug, stage)
        rig_path = os.path.join(base_dir, "rig.json")
        anim_path = os.path.join(base_dir, "animations.json")

        if not os.path.isfile(rig_path):
            errors.append(f"{slug}/{stage}: missing rig.json")
            continue
        if not os.path.isfile(anim_path):
            errors.append(f"{slug}/{stage}: missing animations.json")
            continue

        with open(rig_path, "r", encoding="utf-8") as f:
            rig = json.load(f)
        with open(anim_path, "r", encoding="utf-8") as f:
            anims = json.load(f)

        tier = rig.get("rig_tier")
        if tier not in VALID_TIERS:
            errors.append(f"{slug}/{stage}: invalid rig_tier '{tier}'")
        tier_counts[tier] = tier_counts.get(tier, 0) + 1

        cw, ch = rig.get("canvas_size", [0, 0])
        if (cw, ch) != (1024, 1024):
            errors.append(f"{slug}/{stage}: unexpected canvas_size {[cw, ch]}")

        layers = rig.get("layers", [])
        layer_ids = {l["id"] for l in layers}

        if tier == "full_layered" and len(layers) < 5:
            errors.append(f"{slug}/{stage}: marked full_layered but only has {len(layers)} layers")
        if tier == "needs_manual_art":
            warnings.append(f"{slug}/{stage}: {rig.get('notes', 'requires manual art')}")

        for layer in layers:
            lid = layer["id"]
            rel = layer["asset"]
            parent = layer.get("parent")
            if parent is not None and parent not in layer_ids:
                errors.append(f"{slug}/{stage}: layer '{lid}' references unknown parent '{parent}'")

            pivot = layer.get("pivot", [])
            if len(pivot) != 2 or not (0.0 <= pivot[0] <= 1.0 and 0.0 <= pivot[1] <= 1.0):
                errors.append(f"{slug}/{stage}: layer '{lid}' has invalid pivot {pivot}")

            full_img_path = os.path.join(base_dir, rel.replace("/", os.sep))
            if not os.path.isfile(full_img_path):
                errors.append(f"{slug}/{stage}: missing layer asset '{rel}'")
                continue

            total_layers += 1
            total_layer_bytes += os.path.getsize(full_img_path)

            with Image.open(full_img_path) as im:
                if im.size != (cw, ch):
                    errors.append(f"{slug}/{stage}/{rel}: size {im.size} != {(cw, ch)}")
                rgba = im.convert("RGBA")
                alpha = rgba.getchannel("A")
                extrema = alpha.getextrema()
                if extrema[1] == 0:
                    errors.append(f"{slug}/{stage}/{rel}: completely empty transparent layer!")
                # Verify transparent corners (no baked white/opaque background)
                corners = [alpha.getpixel((0, 0)), alpha.getpixel((cw - 1, 0)),
                           alpha.getpixel((0, ch - 1)), alpha.getpixel((cw - 1, ch - 1))]
                if any(c > 16 for c in corners):
                    errors.append(f"{slug}/{stage}/{rel}: opaque corner detected {corners}!")

        # Validate hitboxes
        for hb in rig.get("hitboxes", []):
            r = hb.get("rect", [])
            if len(r) != 4 or r[2] <= 0 or r[3] <= 0:
                errors.append(f"{slug}/{stage}: invalid hitbox {hb}")

        # Validate animations.json states
        states = set(anims.get("states", {}).keys())
        missing_states = REQUIRED_STATES - states
        if missing_states:
            errors.append(f"{slug}/{stage}: animations.json missing states {missing_states}")

        # Verify original backup exists for valid characters
        if tier != "needs_manual_art":
            orig_p = os.path.join(base_dir, "original.png")
            if not os.path.isfile(orig_p):
                errors.append(f"{slug}/{stage}: missing preserved original.png backup")

    print("=== MamPet Monster Rig Validation Report ===")
    print(f"Characters indexed : {len(chars)} / 60")
    print(f"Rig Tier Breakdown : {tier_counts}")
    print(f"Total Layer PNGs   : {total_layers} ({total_layer_bytes / (1024 * 1024):.2f} MB)")
    print(f"Manual Art Warnings: {len(warnings)}")
    for w in warnings:
        print(f"  [WARN] {w}")
    print(f"Validation Errors  : {len(errors)}")
    for e in errors[:30]:
        print(f"  [ERR]  {e}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(validate())
