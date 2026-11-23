import os
from collections import deque
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\HP\.gemini\antigravity\brain\d7992aea-d791-48c5-9dd4-f867c7e6c352\.user_uploaded\media_1795371541831_80d189b7.jpg"
ROOT = r"c:\Project\mampet"
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

im = Image.open(SRC).convert("RGBA")
w, h = im.size
# Center-crop to square if needed
side = min(w, h)
im = im.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))
im = im.resize((1024, 1024), Image.Resampling.LANCZOS)

# Sample warm cream background color inside the squircle (top-left cream area)
px = im.load()
cream_rgb = px[220, 120][:3]
cream_hex = "#{:02X}{:02X}{:02X}".format(*cream_rgb)
print(f"Sampled warm cream logo background: RGB={cream_rgb} ({cream_hex})")

# 1. Remove outer white corners via flood-fill from all 4 corners -> clean transparent squircle!
squircle = im.copy()
spx = squircle.load()
visited = bytearray(1024 * 1024)
q = deque([(0, 0), (1023, 0), (0, 1023), (1023, 1023)])
for x, y in list(q):
    visited[y * 1024 + x] = 1


def is_outer_white(r, g, b):
    # Pure/near-white outside the warm cream squircle (cream has noticeably lower B channel)
    return r > 242 and g > 242 and b > 240 and abs(r - b) < 12


while q:
    cx, cy = q.popleft()
    r, g, b, a = spx[cx, cy]
    if is_outer_white(r, g, b):
        spx[cx, cy] = (r, g, b, 0)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < 1024 and 0 <= ny < 1024:
                idx = ny * 1024 + nx
                if not visited[idx]:
                    visited[idx] = 1
                    q.append((nx, ny))

# Soften outer alpha fringe by 1px for crisp anti-aliased squircle edge
r_c, g_c, b_c, a_c = squircle.split()
a_soft = a_c.filter(ImageFilter.GaussianBlur(0.8))
squircle = Image.merge("RGBA", (r_c, g_c, b_c, a_soft))

# Save Flutter branding logo (512x512) & Android native splash logo (360x360)
brand_out = os.path.join(ROOT, "assets", "branding", "mampet_logo.png")
squircle.resize((512, 512), Image.Resampling.LANCZOS).save(brand_out, "PNG", optimize=True)

splash_out = os.path.join(RES, "drawable-xxhdpi", "splash_logo.png")
os.makedirs(os.path.dirname(splash_out), exist_ok=True)
squircle.resize((360, 360), Image.Resampling.LANCZOS).save(splash_out, "PNG", optimize=True)

# 2. Build full-bleed cream + centered character for Android Adaptive Icon Foreground (108dp safe zone)
# Erode outer squircle edge slightly before compositing over solid cream so zero white halo remains!
a_tight = a_c.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.GaussianBlur(1.5))
squircle_no_halo = Image.merge("RGBA", (r_c, g_c, b_c, a_tight))
full_bleed = Image.new("RGBA", (1024, 1024), (*cream_rgb, 255))
full_bleed.alpha_composite(squircle_no_halo)

fg_canvas = Image.new("RGBA", (1024, 1024), (*cream_rgb, 255))
# Scale artwork into 78% safe zone so dragon wings & sparkles stay well inside circular/squircle masks
inner_sz = int(1024 * 0.78)
inner = full_bleed.resize((inner_sz, inner_sz), Image.Resampling.LANCZOS)
off = (1024 - inner_sz) // 2
fg_canvas.paste(inner, (off, off))

# 3. Export all mipmap densities (legacy ic_launcher.png + adaptive ic_launcher_foreground.png)
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

for dens, (legacy_px, fg_px) in DENSITIES.items():
    mdir = os.path.join(RES, f"mipmap-{dens}")
    os.makedirs(mdir, exist_ok=True)
    squircle.resize((legacy_px, legacy_px), Image.Resampling.LANCZOS).save(
        os.path.join(mdir, "ic_launcher.png"), "PNG", optimize=True
    )
    fg_canvas.resize((fg_px, fg_px), Image.Resampling.LANCZOS).save(
        os.path.join(mdir, "ic_launcher_foreground.png"), "PNG", optimize=True
    )

# 4. Update Android colors.xml so adaptive background seamlessly matches sampled warm cream
colors_xml = os.path.join(RES, "values", "colors.xml")
with open(colors_xml, "w", encoding="utf-8", newline="\n") as f:
    f.write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="splash_bg">#FFFBF5</color>\n'
        f'    <color name="ic_launcher_background">{cream_hex}</color>\n'
        "</resources>\n"
    )

print("Updated mampet_logo.png, splash_logo.png, all 5 mipmap densities, and colors.xml!")
