"""Synchronizes pubspec.yaml flutter/assets with MamPet's OpenBone monster packages.

Bundles ONLY lean production runtime assets in the Flutter APK:
  - assets/branding/
  - assets/data/
  - assets/eggs/
  - assets/monsters/<slug>/ (400x400 static preview PNGs for MonsterDex, Home Widget, and fallback)
  - assets/animated_monsters/collection_manifest.json
  - For every form in collection_manifest.json with status == "exported":
      - assets/animated_monsters/<slug>/<stage>/animation_manifest.json
      - assets/animated_monsters/<slug>/<stage>/<exports[0].path> (.obonb binary + embedded atlas)

Deliberately EXCLUDES from the APK bundle:
  - Forms marked `review_only` or `source_blocked` (excluded from production runtime per guide)
  - Heavy QA/editor assets: `previews/*.gif`, `previews/*.png`, `interactive.html`, `rig/*.obone`,
    `layers/*.png`, and `source/original.png`
  - Legacy superseded `assets/monsters/<slug>/<stage>/layers/` rigs
"""

import json
import os
import pathlib

ROOT = pathlib.Path(r"c:\Project\mampet")
PUBSPEC = ROOT / "pubspec.yaml"
ANIM_ROOT = ROOT / "assets" / "animated_monsters"
COLLECTION_MANIFEST = ANIM_ROOT / "collection_manifest.json"

collection = json.loads(COLLECTION_MANIFEST.read_text(encoding="utf-8"))

lines = [
    "  assets:",
    "    - assets/branding/",
    "    - assets/data/",
    "    - assets/eggs/",
    "    - assets/animated_monsters/collection_manifest.json",
]

seen_slugs = set()
for form in collection["forms"]:
    slug = form["monster_slug"]
    if slug not in seen_slugs:
        seen_slugs.add(slug)
        lines.append(f"    - assets/monsters/{slug}/")

exported_count = 0
excluded_forms = []
total_obonb_bytes = 0

for form in collection["forms"]:
    slug = form["monster_slug"]
    stage = form["stage"]
    status = form.get("status", "source_blocked")
    if status != "exported" or not form.get("manifest"):
        excluded_forms.append(f"{slug}/{stage} ({status})")
        continue

    manifest_rel = form["manifest"].replace("\\", "/")
    manifest_abs = ANIM_ROOT / manifest_rel
    if not manifest_abs.is_file():
        excluded_forms.append(f"{slug}/{stage} (missing manifest)")
        continue

    pkg = json.loads(manifest_abs.read_text(encoding="utf-8"))
    exports = pkg.get("exports") or []
    obonb_rel = None
    for exp in exports:
        path_val = exp.get("path")
        if isinstance(path_val, str) and (
            exp.get("format") == "obonb" or path_val.endswith(".obonb")
        ):
            obonb_rel = path_val.replace("\\", "/")
            break

    if not obonb_rel:
        excluded_forms.append(f"{slug}/{stage} (missing obonb entry)")
        continue

    obonb_abs = manifest_abs.parent / obonb_rel
    if not obonb_abs.is_file():
        excluded_forms.append(f"{slug}/{stage} (missing obonb file)")
        continue

    base_rel = f"assets/animated_monsters/{manifest_rel.rsplit('/', 1)[0]}"
    lines.append(f"    - {base_rel}/animation_manifest.json")
    lines.append(f"    - {base_rel}/{obonb_rel}")
    exported_count += 1
    total_obonb_bytes += obonb_abs.stat().st_size

src = PUBSPEC.read_text(encoding="utf-8")
start_marker = "  assets:\n"
end_marker = "\n  fonts:\n"
s_idx = src.index(start_marker)
e_idx = src.index(end_marker)

updated = src[:s_idx] + "\n".join(lines) + "\n" + src[e_idx:]
PUBSPEC.write_text(updated, encoding="utf-8", newline="\n")

print(
    f"Synced pubspec.yaml: {exported_count}/60 exported OpenBone packages "
    f"({total_obonb_bytes / (1024 * 1024):.2f} MB total .obonb), "
    f"excluded: {excluded_forms}"
)
