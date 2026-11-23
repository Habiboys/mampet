import hashlib
import json
import os
import zipfile
from PIL import Image

ZIP_PATH = r"c:\Project\mampet\monster_collection_60_complete_flutter.zip"


def audit_source_zip():
    hashes = {}
    results = []
    with zipfile.ZipFile(ZIP_PATH) as zf:
        names = sorted([n for n in zf.namelist() if n.endswith(".png")])
        for n in names:
            data = zf.read(n)
            md5 = hashlib.md5(data).hexdigest()
            im = Image.open(zf.open(n)).convert("RGBA")
            w, h = im.size
            bbox = im.getbbox()
            alpha_bytes = im.getchannel("A").tobytes()
            opaque = sum(1 for a in alpha_bytes if a > 20)
            dup_of = hashes.get(md5)
            if not dup_of:
                hashes[md5] = n

            # Detect near-white/gray opaque checkerboard remnants inside alpha
            # (pure/near gray high-luminance pixels inside character interior)
            rgb = im.convert("RGB")
            px = im.load()
            checker_suspects = 0
            if bbox:
                x0, y0, x1, y1 = bbox
                for y in range(y0, y1, 4):
                    for x in range(x0, x1, 4):
                        r, g, b, a = px[x, y]
                        if a > 240 and abs(r - g) <= 2 and abs(g - b) <= 2 and 215 <= r <= 252:
                            checker_suspects += 1

            flags = []
            if opaque < 30000:
                flags.append(f"BLANK_OR_TINY({opaque}px)")
            if dup_of:
                flags.append(f"DUPLICATE_OF({dup_of})")
            if checker_suspects > 180:
                flags.append(f"CHECKER_OR_WHITE_INTERIOR({checker_suspects})")

            results.append({
                "path": n,
                "size": [w, h],
                "bbox": list(bbox) if bbox else None,
                "opaque_pixels": opaque,
                "fill_ratio": round(opaque / (w * h), 4),
                "duplicate_of": dup_of,
                "flags": flags,
            })

    print(f"Audited {len(results)} source PNGs from ZIP:")
    for r in results:
        if r["flags"]:
            print(f"  [!] {r['path']}: {', '.join(r['flags'])} | bbox={r['bbox']}")
    return results


if __name__ == "__main__":
    audit_source_zip()
