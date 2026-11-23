import os
import zipfile
from PIL import Image, ImageDraw

ZIP_PATH = r"c:\Project\mampet\monster_collection_60_complete_flutter.zip"
OUT_DIR = r"C:\Users\HP\.gemini\antigravity\brain\d7992aea-d791-48c5-9dd4-f867c7e6c352\scratch\grids"

TARGETS = [
    ("leaf_gorilla", "baby"),
    ("lamb", "baby"),
    ("forest_deer", "baby"),
    ("moss_golem", "baby"),
    ("sea_dragon", "baby"),
]

os.makedirs(OUT_DIR, exist_ok=True)


def draw_gridded_tile(im, label, tile_size=512):
    bg = Image.new("RGBA", (tile_size, tile_size), (248, 244, 238, 255))
    bg.alpha_composite(im.resize((tile_size, tile_size), Image.Resampling.LANCZOS))
    d = ImageDraw.Draw(bg)
    for orig_v in range(64, 1024, 64):
        p = orig_v // 2
        is_major = (orig_v % 128 == 0)
        col = (60, 120, 220, 150) if is_major else (160, 185, 225, 95)
        d.line([(p, 0), (p, tile_size)], fill=col, width=1)
        d.line([(0, p), (tile_size, p)], fill=col, width=1)
        if is_major:
            d.text((p + 2, 2), str(orig_v), fill=(30, 70, 160, 230))
            d.text((2, p + 2), str(orig_v), fill=(30, 70, 160, 230))
    d.rectangle((0, 0, tile_size - 1, tile_size - 1), outline=(140, 120, 100, 255), width=2)
    d.rectangle((4, tile_size - 22, 230, tile_size - 4), fill=(40, 28, 22, 210))
    d.text((10, tile_size - 19), label, fill=(255, 255, 255, 255))
    return bg


with zipfile.ZipFile(ZIP_PATH) as zf:
    sheet = Image.new("RGBA", (1536, 1024), (255, 255, 255, 255))
    for i, (slug, stage) in enumerate(TARGETS):
        with zf.open(f"assets/monsters/{slug}/{stage}.png") as f:
            im = Image.open(f).convert("RGBA")
        tile = draw_gridded_tile(im, f"{slug}/{stage}")
        r, c = divmod(i, 3)
        sheet.paste(tile, (c * 512, r * 512))
    out_p = os.path.join(OUT_DIR, "hero_grid_6.png")
    sheet.save(out_p)
    print("Wrote", out_p)
