import json
import math
import os
import zipfile
from collections import deque
from PIL import Image, ImageDraw, ImageFilter

ZIP_PATH = r"c:\Project\mampet\monster_collection_60_complete_flutter.zip"
ASSETS_ROOT = r"c:\Project\mampet\assets\monsters"
QA_DIR = r"C:\Users\HP\.gemini\antigravity\brain\d7992aea-d791-48c5-9dd4-f867c7e6c352\scratch\qa"
CANVAS = 1024

ALL_SLUGS = [
    ("01", "fire_dragon", "winged_dragon"),
    ("02", "leaf_gorilla", "biped_gorilla"),
    ("03", "sky_bird", "winged_bird"),
    ("04", "fox", "tailed_fox"),
    ("05", "water_slime", "elastic_slime"),
    ("06", "leaf_spirit", "plant_sprout"),
    ("07", "pink_axolotl", "aquatic_axolotl"),
    ("08", "dessert_panda", "biped_bear"),
    ("09", "lamb", "quadruped_lamb"),
    ("10", "bread_turtle", "shelled_turtle"),
    ("11", "sea_dragon", "aquatic_dragon"),
    ("12", "moss_golem", "stone_golem"),
    ("13", "dessert_ghost", "floating_ghost"),
    ("14", "bee_moth", "winged_insect"),
    ("15", "ice_fox", "tailed_fox"),
    ("16", "forest_deer", "quadruped_deer"),
    ("17", "chef_penguin", "biped_penguin"),
    ("18", "mage_cat", "tailed_cat"),
    ("19", "mushroom", "capped_mushroom"),
    ("20", "bamboo_panda", "biped_panda"),
]
STAGES = ("baby", "young", "adult")


# ==============================================================================
# IMAGE & GEOMETRY UTILITIES
# ==============================================================================

def make_poly_mask(points, feather=0.9):
    m = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    if feather > 0:
        m = m.filter(ImageFilter.GaussianBlur(feather))
    return m


def apply_mask(img, mask):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def subtract_mask(img, cut_mask):
    r, g, b, a = img.split()
    a_bytes = bytearray(a.tobytes())
    c_bytes = cut_mask.tobytes()
    for i in range(len(a_bytes)):
        if c_bytes[i] > 0:
            a_bytes[i] = (a_bytes[i] * (255 - c_bytes[i])) // 255
    return Image.merge("RGBA", (r, g, b, Image.frombytes("L", img.size, bytes(a_bytes))))


def keep_largest_component(img, alpha_thresh=16, keep_top_k=1, min_ratio=0.04):
    """Keeps the largest 4-connected opaque region(s), stripping disconnected slivers."""
    w, h = img.size
    sw, sh = w // 2, h // 2
    a_small = img.getchannel("A").resize((sw, sh), Image.Resampling.BILINEAR)
    apx = a_small.load()
    visited = bytearray(sw * sh)
    comps = []
    for y in range(sh):
        row_off = y * sw
        for x in range(sw):
            idx = row_off + x
            if not visited[idx] and apx[x, y] >= alpha_thresh:
                comp = []
                q = deque([(x, y)])
                visited[idx] = 1
                while q:
                    cx, cy = q.popleft()
                    comp.append((cx, cy))
                    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < sw and 0 <= ny < sh:
                            nidx = ny * sw + nx
                            if not visited[nidx] and apx[nx, ny] >= alpha_thresh:
                                visited[nidx] = 1
                                q.append((nx, ny))
                comps.append(comp)
    if not comps:
        return img
    comps.sort(key=len, reverse=True)
    largest = len(comps[0])
    chosen = [comps[0]]
    for c in comps[1:keep_top_k]:
        if len(c) >= max(20, int(largest * min_ratio)):
            chosen.append(c)

    keep_small = Image.new("L", (sw, sh), 0)
    kpx = keep_small.load()
    for comp in chosen:
        for cx, cy in comp:
            kpx[cx, cy] = 255
    keep_small = keep_small.filter(ImageFilter.MaxFilter(3))
    keep_mask = keep_small.resize((w, h), Image.Resampling.BILINEAR)
    r, g, b, a = img.split()
    a_bytes = bytearray(a.tobytes())
    m_bytes = keep_mask.tobytes()
    for i in range(len(a_bytes)):
        if m_bytes[i] < 128:
            a_bytes[i] = 0
    return Image.merge("RGBA", (r, g, b, Image.frombytes("L", (w, h), bytes(a_bytes))))


def clean_checkerboard_box(img, box):
    """Removes trapped PNG gray/white checkerboard artifact squares inside a closed region."""
    out = img.copy()
    px = out.load()
    x0, y0, x1, y1 = box
    for y in range(max(0, y0), min(CANVAS, y1)):
        for x in range(max(0, x0), min(CANVAS, x1)):
            r, g, b, a = px[x, y]
            if a > 0:
                mx = max(r, g, b)
                mn = min(r, g, b)
                if (mx - mn) < 22 and mn > 175:
                    px[x, y] = (0, 0, 0, 0)
    return out


def erase_box(img, box):
    out = img.copy()
    px = out.load()
    x0, y0, x1, y1 = box
    for y in range(max(0, y0), min(CANVAS, y1)):
        for x in range(max(0, x0), min(CANVAS, x1)):
            px[x, y] = (0, 0, 0, 0)
    return out


def sample_ink_color(img):
    """Samples the authentic dark cartoon outline color of the character."""
    px = img.load()
    rs = gs = bs = cnt = 0
    for y in range(140, 900, 6):
        for x in range(140, 900, 6):
            r, g, b, a = px[x, y]
            lum = (r + g + b) / 3.0
            if a > 235 and 18 < lum < 85:
                rs += r
                gs += g
                bs += b
                cnt += 1
    if cnt == 0:
        return (62, 34, 24, 255)
    return (rs // cnt, gs // cnt, bs // cnt, 255)


def sample_local_fill(img, cx, cy, radius=24, prefer_bright=True):
    """Samples median bright interior color around (cx, cy) for seamless joint roots."""
    px = img.load()
    samples = []
    for y in range(max(0, cy - radius), min(CANVAS, cy + radius), 2):
        for x in range(max(0, cx - radius), min(CANVAS, cx + radius), 2):
            r, g, b, a = px[x, y]
            lum = (r + g + b) / 3.0
            if a > 220 and (not prefer_bright or lum > 85):
                samples.append((lum, r, g, b))
    if not samples:
        for y in range(max(0, cy - radius * 2), min(CANVAS, cy + radius * 2), 3):
            for x in range(max(0, cx - radius * 2), min(CANVAS, cx + radius * 2), 3):
                r, g, b, a = px[x, y]
                if a > 200:
                    samples.append(((r + g + b) / 3.0, r, g, b))
    if not samples:
        return (230, 180, 140, 255)
    samples.sort()
    _, r, g, b = samples[len(samples) // 2]
    return (r, g, b, 255)


def inpaint_region_harmonic(img, region_mask, smooth_iters=70, downweight_dark=True):
    """Smoothly reconstructs occluded cel-shaded skin pixels at 256x256 via harmonic
    Laplace smoothing, excluding dark cartoon outline pixels from boundary seeds so
    zero gray smudges ever bleed into reconstructed eye/mouth sockets."""
    sw = 256
    small_img = img.resize((sw, sw), Image.Resampling.LANCZOS)
    small_mask = region_mask.resize((sw, sw), Image.Resampling.BILINEAR)
    px = small_img.load()
    mpx = small_mask.load()
    bbox = small_mask.getbbox()
    if not bbox:
        return img.copy()

    x0 = max(1, bbox[0] - 4)
    y0 = max(1, bbox[1] - 4)
    x1 = min(sw - 2, bbox[2] + 4)
    y1 = min(sw - 2, bbox[3] + 4)

    hole = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if mpx[x, y] > 64:
                hole.add((x, y))

    # Also expand hole by 1px into any adjacent dark outline rim when downweight_dark is enabled
    if downweight_dark:
        extra_dark = set()
        for (x, y) in list(hole):
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 1 <= nx < sw - 1 and 1 <= ny < sw - 1 and (nx, ny) not in hole:
                    r, g, b, a = px[nx, ny]
                    if a > 180 and (r + g + b) / 3.0 < 120:
                        extra_dark.add((nx, ny))
        hole |= extra_dark

    vals = {}
    fallback_vals = {}
    for y in range(max(0, y0 - 4), min(sw, y1 + 4)):
        for x in range(max(0, x0 - 4), min(sw, x1 + 4)):
            if (x, y) not in hole:
                r, g, b, a = px[x, y]
                if a > 190:
                    lum = (r + g + b) / 3.0
                    if (not downweight_dark) or lum >= 115:
                        vals[(x, y)] = (float(r), float(g), float(b))
                    else:
                        fallback_vals[(x, y)] = (float(r), float(g), float(b))

    if not vals:
        vals.update(fallback_vals)

    remaining = set(hole)
    stall = 0
    while remaining and stall < 4:
        newly = {}
        for (x, y) in remaining:
            rs = gs = bs = ws = 0.0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)):
                nb = vals.get((x + dx, y + dy))
                if nb is not None:
                    rs += nb[0]
                    gs += nb[1]
                    bs += nb[2]
                    ws += 1.0
            if ws > 0:
                newly[(x, y)] = (rs / ws, gs / ws, bs / ws)
        if not newly:
            vals.update(fallback_vals)
            stall += 1
            continue
        vals.update(newly)
        for k in newly:
            remaining.discard(k)

    hole_list = list(hole)
    for _ in range(smooth_iters):
        next_vals = {}
        for (x, y) in hole_list:
            rs = gs = bs = cnt = 0.0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nb = vals.get((x + dx, y + dy))
                if nb is not None:
                    rs += nb[0]
                    gs += nb[1]
                    bs += nb[2]
                    cnt += 1.0
            if cnt > 0:
                next_vals[(x, y)] = (rs / cnt, gs / cnt, bs / cnt)
        vals.update(next_vals)

    for (x, y), (r, g, b) in vals.items():
        if (x, y) in hole:
            px[x, y] = (int(r), int(g), int(b), 255)

    # Expand paste mask slightly to cover extra_dark cleaned rim
    paste_small = Image.new("L", (sw, sw), 0)
    pmpx = paste_small.load()
    for (x, y) in hole:
        pmpx[x, y] = 255
    paste_mask = paste_small.resize(img.size, Image.Resampling.BILINEAR).filter(ImageFilter.GaussianBlur(1.8))

    inpainted_full = small_img.resize(img.size, Image.Resampling.BICUBIC)
    out = img.copy()
    out.paste(inpainted_full, (0, 0), paste_mask)
    return out


def save_quantized_png(img, path):
    q = img.quantize(
        colors=256,
        method=Image.Quantize.FASTOCTREE,
        dither=Image.Dither.FLOYDSTEINBERG,
    )
    q.save(path, "PNG", optimize=True)


def draw_cartoon_open_eyes(canvas_size, left_box, right_box, ink):
    """Draws MamPet-style cute dark oval eyes with crisp white highlights."""
    im = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for (x0, y0, x1, y1) in (left_box, right_box):
        cx = (x0 + x1) // 2
        cy = (y0 + y1) // 2
        rx = max(16, int((x1 - x0) * 0.36))
        ry = max(20, int(rx * 1.18))
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=ink)
        # Main top-left specular catchlight
        hr = max(6, int(rx * 0.34))
        d.ellipse(
            (cx - int(rx * 0.45) - hr, cy - int(ry * 0.38) - hr,
             cx - int(rx * 0.45) + hr, cy - int(ry * 0.38) + hr),
            fill=(255, 255, 255, 255),
        )
        # Subtle lower-right secondary sparkle
        sr = max(3, int(rx * 0.16))
        d.ellipse(
            (cx + int(rx * 0.32) - sr, cy + int(ry * 0.32) - sr,
             cx + int(rx * 0.32) + sr, cy + int(ry * 0.32) + sr),
            fill=(255, 255, 255, 210),
        )
    return im


def draw_cartoon_closed_eyes(canvas_size, left_box, right_box, ink, blush_col=(244, 128, 118, 115)):
    """Draws MamPet-style happy closed arcs (^ ^) + soft rosy blush."""
    im = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for idx, (x0, y0, x1, y1) in enumerate((left_box, right_box)):
        w = x1 - x0
        h = y1 - y0
        cy = (y0 + y1) // 2
        pad_x = max(4, int(w * 0.08))
        arc_h = max(28, int(h * 0.56))
        stroke = max(9, min(14, int(w * 0.13)))
        d.arc(
            (x0 + pad_x, cy - arc_h // 2 + 4, x1 - pad_x, cy + arc_h // 2 + 12),
            start=196,
            end=344,
            fill=ink,
            width=stroke,
        )
        # Soft blush oval slightly outward & below
        bw = max(24, int(w * 0.45))
        bh = max(14, int(h * 0.24))
        bx = x0 - bw // 4 if idx == 0 else x1 - int(bw * 0.75)
        by = cy + int(h * 0.24)
        d.ellipse((bx, by, bx + bw, by + bh), fill=blush_col)
    return im


def draw_cartoon_sleep_eyes(canvas_size, left_box, right_box, ink):
    """Draws peaceful downward sleeping arcs (u u)."""
    im = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for (x0, y0, x1, y1) in (left_box, right_box):
        w = x1 - x0
        h = y1 - y0
        cy = (y0 + y1) // 2
        pad_x = max(4, int(w * 0.08))
        arc_h = max(26, int(h * 0.52))
        stroke = max(9, min(13, int(w * 0.12)))
        d.arc(
            (x0 + pad_x, cy - arc_h // 2 - 4, x1 - pad_x, cy + arc_h // 2 + 2),
            start=18,
            end=162,
            fill=ink,
            width=stroke,
        )
    return im


def draw_cartoon_mouths(canvas_size, mouth_box, ink, style="mammal"):
    """Draws cute neutral smile, open happy mouth, and eating 'o' mouth."""
    x0, y0, x1, y1 = mouth_box
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    w = max(44, x1 - x0)
    h = max(36, y1 - y0)
    stroke = max(8, min(11, int(w * 0.11)))

    # Neutral mouth
    m_neutral = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    dn = ImageDraw.Draw(m_neutral)
    if style == "beak":
        # Cute closed golden beak
        bw = int(w * 0.44)
        bh = int(h * 0.34)
        dn.polygon(
            [(cx - bw, cy - 4), (cx, cy - bh), (cx + bw, cy - 4), (cx, cy + int(bh * 0.7))],
            fill=(246, 186, 62, 255),
            outline=ink,
        )
        dn.line([(cx - bw, cy - 4), (cx, cy - bh), (cx + bw, cy - 4), (cx, cy + int(bh * 0.7)), (cx - bw, cy - 4)], fill=ink, width=stroke - 1)
    else:
        # Cozy ':3' gentle smile
        rw = max(18, int(w * 0.28))
        rh = max(14, int(h * 0.28))
        dn.arc((cx - rw * 2 + 4, cy - rh, cx + 4, cy + rh), start=15, end=165, fill=ink, width=stroke)
        dn.arc((cx - 4, cy - rh, cx + rw * 2 - 4, cy + rh), start=15, end=165, fill=ink, width=stroke)

    # Happy open mouth (used when original was neutral :3)
    m_happy = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    dh = ImageDraw.Draw(m_happy)
    hw = max(24, int(w * 0.42))
    hh = max(20, int(h * 0.46))
    dh.chord((cx - hw, cy - hh // 2, cx + hw, cy + hh + hh // 2), start=0, end=180, fill=(176, 68, 74, 255), outline=ink, width=stroke)
    dh.ellipse((cx - int(hw * 0.58), cy + int(hh * 0.38), cx + int(hw * 0.58), cy + int(hh * 0.92)), fill=(242, 134, 132, 255))

    # Eating 'o' mouth
    m_eat = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    de = ImageDraw.Draw(m_eat)
    if style == "beak":
        bw = int(w * 0.42)
        bh = int(h * 0.38)
        de.polygon([(cx - bw, cy - 4), (cx, cy - bh), (cx + bw, cy - 4)], fill=(246, 186, 62, 255), outline=ink)
        de.ellipse((cx - int(bw * 0.72), cy - 4, cx + int(bw * 0.72), cy + int(bh * 1.15)), fill=(178, 66, 70, 255), outline=ink, width=stroke - 1)
        de.polygon([(cx - bw, cy - 4), (cx, cy - bh), (cx + bw, cy - 4)], fill=(246, 186, 62, 255))
        de.line([(cx - bw, cy - 4), (cx, cy - bh), (cx + bw, cy - 4), (cx - bw, cy - 4)], fill=ink, width=stroke - 1)
    else:
        erx = max(18, int(w * 0.30))
        ery = max(18, int(h * 0.34))
        de.ellipse((cx - erx, cy - ery + 4, cx + erx, cy + ery + 4), fill=(170, 62, 68, 255), outline=ink, width=stroke)
        de.ellipse((cx - int(erx * 0.55), cy + 2, cx + int(erx * 0.55), cy + int(ery * 0.78) + 4), fill=(240, 132, 128, 255))

    return m_neutral, m_happy, m_eat


# ==============================================================================
# ANIMATION PRESET BUILDER (SPECIES-APPROPRIATE MOTION!)
# ==============================================================================

def build_animations_for_rig(slug, stage, archetype, layer_ids, default_eyes="eyes_open", default_mouth="mouth_happy"):
    has = set(layer_ids)

    def make_tracks(mode):
        tracks = {}
        is_float = archetype in ("floating_ghost", "winged_insect")
        is_slime = archetype == "elastic_slime"
        is_heavy = archetype in ("stone_golem", "shelled_turtle", "biped_gorilla")

        # Body tracks
        if mode == "idle":
            if is_float:
                tracks["body"] = {"dy": [0.0, -18.0, 0.0, 10.0, 0.0], "rot_deg": [-2.2, 2.2, -2.2]}
            elif is_slime:
                tracks["body"] = {"scale_y": [1.0, 1.055, 0.965, 1.0], "scale_x": [1.0, 0.955, 1.04, 1.0], "dy": [0.0, -6.0, 2.0, 0.0]}
            elif is_heavy:
                tracks["body"] = {"scale_y": [1.0, 1.022, 1.0], "scale_x": [1.0, 0.99, 1.0], "dy": [0.0, -3.0, 0.0]}
            else:
                tracks["body"] = {"scale_y": [1.0, 1.028, 1.0], "scale_x": [1.0, 0.986, 1.0], "dy": [0.0, -5.0, 0.0]}
        elif mode == "happy":
            hop = -44.0 if is_float else (-26.0 if is_heavy else -36.0)
            tracks["body"] = {
                "dy": [0.0, hop, 0.0, hop * 0.62, 0.0],
                "scale_y": [1.0, 1.08, 0.93, 1.05, 1.0],
                "scale_x": [1.0, 0.94, 1.07, 0.97, 1.0],
            }
        elif mode == "pet":
            tracks["body"] = {
                "scale_y": [1.0, 0.94, 1.03, 0.97, 1.0],
                "scale_x": [1.0, 1.05, 0.98, 1.02, 1.0],
            }
        elif mode == "eat":
            tracks["body"] = {
                "scale_y": [1.0, 1.04, 0.97, 1.04, 0.98, 1.0],
                "dy": [0.0, -8.0, 2.0, -8.0, 0.0],
            }
        elif mode == "sleep":
            tracks["body"] = {
                "scale_y": [0.97, 1.015, 0.97],
                "scale_x": [1.025, 0.99, 1.025],
                "dy": [10.0, 6.0, 10.0],
            }
        elif mode == "play":
            hop = -54.0 if not is_heavy else -34.0
            tracks["body"] = {
                "dy": [0.0, hop * 0.85, hop, hop * 0.55, 0.0],
                "rot_deg": [0.0, -5.0, 5.0, -3.0, 0.0],
                "scale_y": [1.0, 1.07, 0.95, 1.05, 1.0],
            }
        elif mode == "evolve":
            tracks["body"] = {
                "scale_x": [1.0, 1.12, 0.94, 1.15, 1.0],
                "scale_y": [1.0, 1.12, 0.94, 1.15, 1.0],
                "dy": [0.0, -24.0, -12.0, -34.0, 0.0],
            }

        # Head tracks
        if "head" in has:
            if mode == "idle":
                tracks["head"] = {"rot_deg": [-2.0, 2.4, -2.0], "dy": [0.0, -4.0, 0.0]}
            elif mode == "happy":
                tracks["head"] = {"rot_deg": [0.0, -6.5, 6.5, -4.0, 0.0]}
            elif mode == "pet":
                tracks["head"] = {"rot_deg": [0.0, 8.5, -6.5, 5.0, 0.0], "dy": [0.0, 6.0, -4.0, 0.0]}
            elif mode == "eat":
                tracks["head"] = {"rot_deg": [0.0, -5.0, 4.0, -5.0, 3.0, 0.0], "dy": [0.0, 5.0, -4.0, 5.0, 0.0]}
            elif mode == "sleep":
                tracks["head"] = {"rot_deg": [5.5, 8.5, 5.5], "dy": [10.0, 14.0, 10.0]}
            elif mode == "play":
                tracks["head"] = {"rot_deg": [0.0, -9.0, 7.0, -5.0, 0.0]}
            elif mode == "evolve":
                tracks["head"] = {"rot_deg": [0.0, -6.0, 6.0, -4.0, 0.0]}

        # Wings / flippers / gills / fins / ears
        for left_id, right_id, amp in (
            ("wing_left", "wing_right", 24.0 if archetype == "winged_insect" else 18.0),
            ("flipper_left", "flipper_right", 16.0),
            ("gills_left", "gills_right", 10.0),
            ("fin_left", "fin_right", 12.0),
            ("ear_left", "ear_right", 10.0),
            ("leaf_left", "leaf_right", 11.0),
        ):
            if left_id in has:
                if mode == "idle":
                    a = amp * 0.42
                    tracks[left_id] = {"rot_deg": [-a * 0.5, a, -a * 0.5]}
                elif mode == "happy":
                    tracks[left_id] = {"rot_deg": [0.0, amp, -amp * 0.65, amp * 0.85, 0.0]}
                elif mode == "pet":
                    tracks[left_id] = {"rot_deg": [0.0, amp * 0.55, -amp * 0.25, amp * 0.45, 0.0]}
                elif mode == "eat":
                    tracks[left_id] = {"rot_deg": [0.0, amp * 0.55, 0.0, amp * 0.55, 0.0]}
                elif mode == "sleep":
                    tracks[left_id] = {"rot_deg": [-amp * 0.55, -amp * 0.4, -amp * 0.55]}
                elif mode == "play":
                    tracks[left_id] = {"rot_deg": [-amp * 0.5, amp * 1.25, -amp * 0.8, amp * 1.25, -amp * 0.65, amp, 0.0]}
                elif mode == "evolve":
                    tracks[left_id] = {"rot_deg": [0.0, amp * 1.1, -amp * 0.5, amp * 1.25, 0.0]}
            if right_id in has:
                if mode == "idle":
                    a = amp * 0.42
                    tracks[right_id] = {"rot_deg": [a * 0.5, -a, a * 0.5]}
                elif mode == "happy":
                    tracks[right_id] = {"rot_deg": [0.0, -amp, amp * 0.65, -amp * 0.85, 0.0]}
                elif mode == "pet":
                    tracks[right_id] = {"rot_deg": [0.0, -amp * 0.55, amp * 0.25, -amp * 0.45, 0.0]}
                elif mode == "eat":
                    tracks[right_id] = {"rot_deg": [0.0, -amp * 0.55, 0.0, -amp * 0.55, 0.0]}
                elif mode == "sleep":
                    tracks[right_id] = {"rot_deg": [amp * 0.55, amp * 0.4, amp * 0.55]}
                elif mode == "play":
                    tracks[right_id] = {"rot_deg": [amp * 0.5, -amp * 1.25, amp * 0.8, -amp * 1.25, amp * 0.65, -amp, 0.0]}
                elif mode == "evolve":
                    tracks[right_id] = {"rot_deg": [0.0, -amp * 1.1, amp * 0.5, -amp * 1.25, 0.0]}

        # Tail
        if "tail" in has:
            if mode == "idle":
                tracks["tail"] = {"rot_deg": [-6.5, 6.5, -6.5]}
            elif mode == "happy":
                tracks["tail"] = {"rot_deg": [-14.0, 14.0, -14.0, 12.0, 0.0]}
            elif mode == "pet":
                tracks["tail"] = {"rot_deg": [0.0, 15.0, -12.0, 12.0, 0.0]}
            elif mode == "eat":
                tracks["tail"] = {"rot_deg": [-10.0, 10.0, -10.0, 10.0, 0.0]}
            elif mode == "sleep":
                tracks["tail"] = {"rot_deg": [-4.0, -1.0, -4.0]}
            elif mode == "play":
                tracks["tail"] = {"rot_deg": [-16.0, 16.0, -16.0, 16.0, 0.0]}
            elif mode == "evolve":
                tracks["tail"] = {"rot_deg": [-12.0, 14.0, -12.0, 14.0, 0.0]}

        # Caps / hats / cherries / sprouts / crests / antennae / shell / bamboo_arm / droplets
        for top_id in ("cap", "chef_hat", "crown", "cherry", "sprout", "leaf", "crest", "antennae", "bamboo_arm"):
            if top_id in has:
                if mode == "idle":
                    tracks[top_id] = {"rot_deg": [-3.0, 3.5, -3.0], "dy": [0.0, -5.0, 0.0]}
                elif mode == "happy":
                    tracks[top_id] = {"rot_deg": [0.0, -10.0, 10.0, -6.0, 0.0], "dy": [0.0, -14.0, 2.0, -8.0, 0.0]}
                elif mode == "pet":
                    tracks[top_id] = {"rot_deg": [0.0, 9.0, -7.0, 5.0, 0.0], "dy": [0.0, 4.0, -4.0, 0.0]}
                elif mode == "eat":
                    tracks[top_id] = {"rot_deg": [0.0, -6.0, 6.0, -6.0, 0.0]}
                elif mode == "sleep":
                    tracks[top_id] = {"rot_deg": [3.0, 5.5, 3.0], "dy": [4.0, 7.0, 4.0]}
                elif mode == "play":
                    tracks[top_id] = {"rot_deg": [0.0, -14.0, 14.0, -10.0, 0.0], "dy": [0.0, -18.0, 0.0, -12.0, 0.0]}
                elif mode == "evolve":
                    tracks[top_id] = {"rot_deg": [-8.0, 8.0, -8.0, 8.0, 0.0], "dy": [0.0, -16.0, 0.0]}

        if "shell" in has:
            if mode == "idle":
                tracks["shell"] = {"dy": [0.0, -4.0, 0.0], "rot_deg": [-1.2, 1.2, -1.2]}
            elif mode in ("happy", "play"):
                tracks["shell"] = {"dy": [0.0, -12.0, 0.0, -8.0, 0.0], "rot_deg": [0.0, -4.0, 4.0, 0.0]}
            elif mode == "pet":
                tracks["shell"] = {"scale_y": [1.0, 0.96, 1.03, 1.0]}
            elif mode == "sleep":
                tracks["shell"] = {"dy": [6.0, 9.0, 6.0]}

        if "droplets" in has:
            if mode == "idle":
                tracks["droplets"] = {"dy": [4.0, -18.0, 4.0], "rot_deg": [-5.0, 5.0, -5.0]}
            elif mode in ("happy", "play"):
                tracks["droplets"] = {"dy": [0.0, -34.0, -12.0, -28.0, 0.0], "scale_x": [1.0, 1.12, 0.95, 1.1, 1.0], "scale_y": [1.0, 1.12, 0.95, 1.1, 1.0]}
            elif mode == "sleep":
                tracks["droplets"] = {"dy": [12.0, 4.0, 12.0], "opacity": [0.7, 0.9, 0.7]}

        return tracks

    idle_dur = 2200 if archetype == "winged_insect" else (2400 if archetype == "elastic_slime" else 2600)
    return {
        "monster_id": slug,
        "stage": stage,
        "blink_interval_ms": [2600, 4600],
        "blink_duration_ms": 140,
        "states": {
            "idle": {
                "loop": True,
                "duration_ms": idle_dur,
                "eyes": default_eyes,
                "mouth": default_mouth,
                "tracks": make_tracks("idle"),
            },
            "happy": {
                "loop": False,
                "duration_ms": 1200,
                "eyes": "eyes_closed",
                "mouth": "mouth_happy",
                "tracks": make_tracks("happy"),
            },
            "pet": {
                "loop": False,
                "duration_ms": 1400,
                "eyes": "eyes_closed",
                "mouth": "mouth_happy",
                "tracks": make_tracks("pet"),
            },
            "eat": {
                "loop": False,
                "duration_ms": 1500,
                "eyes": "eyes_open",
                "mouth": "mouth_eating",
                "mouth_alternate": "mouth_neutral",
                "tracks": make_tracks("eat"),
            },
            "sleep": {
                "loop": True,
                "duration_ms": 3800,
                "eyes": "eyes_sleep",
                "mouth": "mouth_neutral",
                "tracks": make_tracks("sleep"),
            },
            "play": {
                "loop": False,
                "duration_ms": 1550,
                "eyes": "eyes_open",
                "mouth": "mouth_happy",
                "tracks": make_tracks("play"),
            },
            "evolve": {
                "loop": False,
                "duration_ms": 1800,
                "eyes": "eyes_closed",
                "mouth": "mouth_happy",
                "tracks": make_tracks("evolve"),
            },
        },
    }


# ==============================================================================
# 25 CALIBRATED FULL LAYERED HERO RIG SPECIFICATIONS
# (+ fire_dragon/baby which is already perfected by rig_fire_dragon_baby.py = 26 TOTAL!)
# Every polygon, eye/mouth rect, root overlap, and pivot measured directly from
# our 1024x1024 coordinate grids!
# ==============================================================================

FULL_RIG_SPECS = {
    ("fire_dragon", "young"): {
        "archetype": "winged_dragon",
        "clean_checker": [(474, 508, 582, 602)],
        "body_pivot": (585, 895),
        "head": {
            "poly": [(305, 60), (905, 60), (905, 495), (845, 535), (775, 558), (695, 562), (610, 552), (535, 535), (465, 502), (370, 440), (305, 340)],
            "pivot": (625, 525),
            "neck_fill": [(545, 575), (552, 500), (692, 500), (705, 575)],
            "neck_sample": (640, 610),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (415, 795),
             "poly": [(95, 565), (335, 585), (400, 725), (405, 875), (95, 885)],
             "root": [(365, 730), (475, 745), (475, 855), (365, 850)], "sample": (360, 795), "reaction": "happy"},
            {"id": "wing_left", "z": 2, "parent": "body", "pivot": (470, 565),
             "poly": [(95, 330), (435, 365), (488, 525), (485, 610), (415, 665), (95, 625)],
             "root": [(430, 520), (545, 530), (545, 615), (430, 615)], "sample": (420, 560), "reaction": "play"},
            {"id": "wing_right", "z": 2, "parent": "body", "pivot": (745, 585),
             "poly": [(742, 530), (865, 495), (915, 550), (915, 735), (775, 735), (748, 645)],
             "root": [(690, 540), (775, 535), (775, 635), (690, 630)], "sample": (795, 590), "reaction": "play"},
        ],
        "face_parent": "head",
        "eyes": ((606, 336, 706, 448), (798, 340, 868, 438)),
        "mouth": (702, 408, 830, 526),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("fire_dragon", "adult"): {
        "archetype": "winged_dragon",
        "body_pivot": (580, 885),
        "head": {
            "poly": [(340, 65), (845, 65), (845, 390), (790, 428), (725, 442), (655, 434), (585, 412), (485, 375), (350, 260)],
            "pivot": (645, 405),
            "neck_fill": [(545, 505), (555, 365), (735, 365), (745, 505)],
            "neck_sample": (645, 495),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (385, 745),
             "poly": [(75, 455), (325, 485), (368, 675), (370, 895), (75, 910)],
             "root": [(330, 680), (465, 700), (465, 815), (330, 805)], "sample": (335, 750), "reaction": "happy"},
            {"id": "wing_left", "z": 2, "parent": "body", "pivot": (495, 455),
             "poly": [(60, 225), (460, 240), (508, 425), (498, 515), (365, 565), (60, 485)],
             "root": [(445, 400), (595, 420), (595, 520), (445, 510)], "sample": (455, 430), "reaction": "play"},
            {"id": "wing_right", "z": 2, "parent": "body", "pivot": (745, 485),
             "poly": [(740, 405), (840, 375), (945, 440), (945, 705), (775, 690), (745, 560)],
             "root": [(675, 435), (775, 425), (775, 540), (675, 535)], "sample": (810, 500), "reaction": "play"},
        ],
        "face_parent": "head",
        "eyes": ((610, 245, 706, 315), (735, 220, 800, 285)),
        "mouth": (685, 286, 795, 412),
        "orig_eyes": "closed",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("fox", "baby"): {
        "archetype": "tailed_fox",
        "body_pivot": (580, 865),
        "head": {
            "poly": [(195, 110), (880, 110), (880, 565), (815, 622), (720, 665), (595, 678), (470, 670), (360, 635), (275, 575), (200, 470)],
            "pivot": (565, 645),
            "neck_fill": [(455, 710), (465, 600), (695, 600), (710, 710)],
            "neck_sample": (580, 725),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (420, 775),
             "poly": [(135, 485), (335, 525), (415, 665), (432, 765), (425, 880), (135, 895)],
             "root": [(385, 695), (495, 715), (495, 845), (385, 840)], "sample": (345, 785), "reaction": "happy"},
        ],
        "face_parent": "head",
        "eyes": ((448, 476, 588, 554), (690, 430, 788, 504)),
        "mouth": (608, 488, 722, 560),
        "orig_eyes": "closed",
        "orig_mouth": "neutral",
        "mouth_style": "mammal",
    },
    ("fox", "young"): {
        "archetype": "tailed_fox",
        "erase_boxes": [(118, 505, 162, 598)],
        "clean_checker": [(456, 615, 524, 708)],
        "body_pivot": (615, 915),
        "head": {
            "poly": [(240, 55), (900, 55), (900, 515), (845, 565), (755, 608), (645, 620), (520, 608), (425, 568), (345, 495), (245, 365)],
            "pivot": (615, 585),
            "neck_fill": [(495, 660), (510, 545), (745, 545), (765, 660)],
            "neck_sample": (645, 675),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (450, 780),
             "poly": [(115, 460), (355, 485), (455, 635), (460, 760), (410, 910), (115, 920)],
             "root": [(405, 705), (525, 725), (525, 865), (405, 855)], "sample": (375, 790), "reaction": "happy"},
        ],
        "face_parent": "head",
        "eyes": ((526, 404, 662, 480), (746, 372, 838, 444)),
        "mouth": (668, 418, 784, 494),
        "orig_eyes": "closed",
        "orig_mouth": "neutral",
        "mouth_style": "mammal",
    },
    ("leaf_spirit", "baby"): {
        "archetype": "plant_sprout",
        "body_pivot": (540, 845),
        "head": None,
        "parts": [
            {"id": "leaf_left", "z": 7, "parent": "body", "pivot": (528, 305),
             "poly": [(145, 115), (525, 115), (545, 315), (390, 365), (155, 315)],
             "root": None, "sample": (440, 255), "reaction": "pet"},
            {"id": "leaf_right", "z": 7, "parent": "body", "pivot": (560, 310),
             "poly": [(525, 115), (845, 115), (845, 335), (675, 350), (540, 315)],
             "root": None, "sample": (645, 240), "reaction": "pet"},
        ],
        "body_top_fill": [(430, 365), (465, 295), (635, 295), (665, 365)],
        "body_top_sample": (535, 365),
        "face_parent": "body",
        "eyes": ((480, 480, 590, 614), (726, 460, 810, 578)),
        "mouth": (608, 534, 736, 654),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("pink_axolotl", "baby"): {
        "archetype": "aquatic_axolotl",
        "body_pivot": (525, 795),
        "head": {
            "poly": [(335, 240), (805, 240), (815, 535), (755, 608), (645, 636), (510, 636), (400, 615), (335, 550)],
            "pivot": (555, 605),
            "neck_fill": [(415, 665), (430, 565), (675, 565), (685, 665)],
            "neck_sample": (535, 690),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (368, 705),
             "poly": [(135, 605), (355, 610), (366, 710), (355, 815), (135, 825)],
             "root": [(325, 660), (440, 670), (440, 760), (325, 755)], "sample": (290, 710), "reaction": "happy"},
            {"id": "gills_left", "z": 6, "parent": "head", "pivot": (358, 425),
             "poly": [(115, 165), (358, 165), (366, 320), (344, 460), (358, 615), (115, 625)],
             "root": [(325, 345), (455, 360), (445, 515), (325, 500)], "sample": (295, 425), "reaction": "play"},
            {"id": "gills_right", "z": 6, "parent": "head", "pivot": (748, 405),
             "poly": [(738, 175), (905, 175), (905, 605), (756, 600), (776, 460), (738, 330)],
             "root": [(665, 340), (780, 355), (780, 505), (665, 490)], "sample": (800, 410), "reaction": "play"},
        ],
        "face_parent": "head",
        "eyes": ((402, 372, 506, 490), (670, 368, 752, 474)),
        "mouth": (538, 440, 664, 548),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("pink_axolotl", "young"): {
        "archetype": "aquatic_axolotl",
        "body_pivot": (575, 885),
        "head": {
            "poly": [(415, 200), (855, 200), (860, 475), (805, 548), (695, 578), (555, 578), (445, 548), (405, 455)],
            "pivot": (610, 545),
            "neck_fill": [(480, 620), (495, 510), (735, 510), (745, 620)],
            "neck_sample": (605, 650),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (385, 750),
             "poly": [(65, 580), (345, 585), (388, 725), (372, 890), (65, 895)],
             "root": [(340, 700), (460, 715), (460, 825), (340, 820)], "sample": (285, 755), "reaction": "happy"},
            {"id": "gills_left", "z": 6, "parent": "head", "pivot": (415, 385),
             "poly": [(125, 100), (420, 100), (440, 275), (408, 425), (418, 595), (125, 605)],
             "root": [(385, 305), (520, 320), (510, 475), (385, 465)], "sample": (335, 390), "reaction": "play"},
            {"id": "gills_right", "z": 6, "parent": "head", "pivot": (785, 365),
             "poly": [(755, 115), (945, 115), (945, 560), (800, 545), (822, 415), (765, 270)],
             "root": [(705, 295), (825, 310), (825, 460), (705, 450)], "sample": (840, 375), "reaction": "play"},
        ],
        "face_parent": "head",
        "eyes": ((508, 320, 618, 442), (742, 316, 818, 424)),
        "mouth": (634, 380, 758, 502),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("water_slime", "baby"): {
        "archetype": "elastic_slime",
        "body_pivot": (505, 850),
        "head": None,
        "parts": [
            {"id": "droplets", "z": 7, "parent": "body", "pivot": (820, 335),
             "poly": [(745, 200), (920, 200), (920, 455), (745, 455)],
             "root": None, "sample": (830, 340), "keep_k": 2, "reaction": "play"},
        ],
        "face_parent": "body",
        "eyes": ((274, 486, 370, 614), (510, 498, 620, 628)),
        "mouth": (354, 572, 500, 704),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("water_slime", "young"): {
        "archetype": "elastic_slime",
        "body_pivot": (500, 900),
        "head": None,
        "parts": [
            {"id": "droplets", "z": 7, "parent": "body", "pivot": (550, 240),
             "poly": [(265, 155), (410, 155), (410, 305), (265, 305)],
             "extra_poly": [(785, 190), (915, 190), (915, 325), (785, 325)],
             "root": None, "sample": (340, 225), "keep_k": 2, "reaction": "play"},
        ],
        "face_parent": "body",
        "eyes": ((260, 496, 350, 620), (490, 508, 610, 642)),
        "mouth": (332, 578, 486, 708),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("mushroom", "baby"): {
        "archetype": "capped_mushroom",
        "body_pivot": (525, 840),
        "head": None,
        "parts": [
            {"id": "cap", "z": 10, "parent": "body", "pivot": (545, 440),
             "poly": [(110, 125), (915, 125), (915, 585), (765, 595), (735, 500), (645, 445), (535, 435), (435, 455), (345, 535), (305, 640), (110, 635)],
             "root": None, "sample": (525, 290), "reaction": "pet"},
        ],
        "body_top_fill": [(375, 520), (415, 415), (695, 415), (735, 520)],
        "body_top_sample": (565, 520),
        "face_parent": "body",
        "eyes": ((426, 534, 520, 644), (628, 516, 710, 622)),
        "mouth": (536, 564, 636, 666),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("mushroom", "young"): {
        "archetype": "capped_mushroom",
        "body_pivot": (525, 910),
        "head": None,
        "parts": [
            {"id": "cap", "z": 10, "parent": "body", "pivot": (530, 420),
             "poly": [(95, 55), (925, 55), (925, 545), (765, 560), (745, 465), (645, 415), (520, 415), (410, 455), (335, 535), (285, 630), (95, 625)],
             "root": None, "sample": (510, 260), "reaction": "pet"},
        ],
        "body_top_fill": [(375, 505), (415, 395), (710, 395), (745, 505)],
        "body_top_sample": (565, 495),
        "face_parent": "body",
        "eyes": ((438, 498, 540, 622), (632, 482, 722, 604)),
        "mouth": (558, 540, 654, 642),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("sky_bird", "baby"): {
        "archetype": "winged_bird",
        "body_pivot": (535, 860),
        "head": None,
        "parts": [
            {"id": "wing_left", "z": 7, "parent": "body", "pivot": (410, 585),
             "poly": [(145, 370), (355, 425), (425, 545), (425, 660), (335, 725), (145, 695)],
             "root": None, "sample": (305, 580), "reaction": "play"},
            {"id": "wing_right", "z": 2, "parent": "body", "pivot": (700, 600),
             "poly": [(705, 490), (880, 490), (880, 725), (705, 725), (688, 620)],
             "root": [(655, 540), (740, 540), (740, 650), (655, 645)], "sample": (765, 600), "reaction": "play"},
            {"id": "crest", "z": 7, "parent": "body", "pivot": (525, 315),
             "poly": [(315, 115), (710, 115), (710, 310), (595, 345), (455, 330), (320, 295)],
             "root": None, "sample": (510, 225), "reaction": "pet"},
        ],
        "body_top_fill": [(385, 365), (430, 280), (655, 280), (685, 365)],
        "body_top_sample": (535, 355),
        "body_patch_fills": [
            ([(315, 515), (445, 515), (445, 695), (325, 685)], (485, 620)),
        ],
        "face_parent": "body",
        "eyes": ((452, 384, 562, 506), (666, 372, 756, 484)),
        "mouth": (574, 418, 698, 560),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "beak",
    },
    ("bee_moth", "baby"): {
        "archetype": "winged_insect",
        "body_pivot": (520, 745),
        "head": None,
        "parts": [
            {"id": "wing_left", "z": 2, "parent": "body", "pivot": (345, 475),
             "poly": [(110, 245), (345, 295), (348, 470), (305, 685), (110, 705)],
             "root": [(315, 405), (465, 425), (455, 565), (305, 550)], "sample": (255, 465), "reaction": "play"},
            {"id": "wing_right", "z": 2, "parent": "body", "pivot": (745, 510),
             "poly": [(735, 315), (905, 315), (905, 765), (735, 765), (755, 540)],
             "root": [(655, 440), (785, 440), (785, 580), (655, 575)], "sample": (805, 490), "reaction": "play"},
            {"id": "antennae", "z": 2, "parent": "body", "pivot": (585, 365),
             "poly": [(385, 145), (815, 145), (815, 335), (655, 365), (505, 360), (385, 315)],
             "root": [(535, 325), (635, 325), (625, 415), (545, 415)], "sample": (585, 300), "keep_k": 2, "reaction": "pet"},
        ],
        "face_parent": "body",
        "eyes": ((480, 428, 580, 550), (680, 406, 766, 522)),
        "mouth": (598, 484, 698, 584),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("dessert_ghost", "baby"): {
        "archetype": "floating_ghost",
        "body_pivot": (520, 620),
        "head": None,
        "parts": [
            {"id": "crown", "z": 10, "parent": "body", "pivot": (605, 345),
             "poly": [(420, 110), (805, 110), (805, 340), (715, 370), (565, 370), (435, 345)],
             "root": None, "sample": (615, 240), "reaction": "pet"},
        ],
        "body_top_fill": [(435, 395), (480, 300), (735, 300), (765, 395)],
        "body_top_sample": (520, 395),
        "face_parent": "body",
        "eyes": ((362, 460, 452, 566), (570, 492, 664, 604)),
        "mouth": (442, 542, 550, 642),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("chef_penguin", "baby"): {
        "archetype": "biped_penguin",
        "body_pivot": (515, 860),
        "head": None,
        "parts": [
            {"id": "chef_hat", "z": 9, "parent": "body", "pivot": (505, 335),
             "poly": [(290, 110), (710, 110), (710, 325), (625, 350), (375, 355), (295, 325)],
             "root": None, "sample": (495, 260), "reaction": "pet"},
            {"id": "flipper_left", "z": 7, "parent": "body", "pivot": (365, 610),
             "poly": [(190, 540), (355, 565), (395, 655), (365, 735), (200, 735)],
             "root": None, "sample": (290, 635), "reaction": "play"},
            {"id": "flipper_right", "z": 2, "parent": "body", "pivot": (695, 625),
             "poly": [(695, 565), (830, 565), (830, 750), (695, 750)],
             "root": [(650, 590), (735, 590), (735, 695), (650, 690)], "sample": (745, 645), "reaction": "play"},
        ],
        "body_top_fill": [(355, 395), (395, 315), (620, 315), (655, 395)],
        "body_top_sample": (500, 375),
        "body_patch_fills": [
            ([(310, 565), (415, 565), (415, 725), (315, 725)], (455, 655)),
        ],
        "face_parent": "body",
        "eyes": ((418, 418, 508, 530), (642, 398, 716, 502)),
        "mouth": (532, 438, 648, 582),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "beak",
    },
    ("bread_turtle", "baby"): {
        "archetype": "shelled_turtle",
        "body_pivot": (540, 795),
        "head": {
            "poly": [(125, 375), (465, 375), (520, 495), (510, 655), (415, 715), (215, 705), (125, 620)],
            "pivot": (465, 575),
            "neck_fill": [(405, 645), (425, 515), (565, 515), (565, 675)],
            "neck_sample": (490, 675),
        },
        "parts": [
            {"id": "shell", "z": 6, "parent": "body", "pivot": (585, 560),
             "poly": [(235, 190), (915, 190), (915, 645), (825, 695), (685, 705), (520, 655), (495, 505), (440, 405), (255, 395)],
             "root": None, "sample": (610, 420), "reaction": "happy"},
        ],
        "face_parent": "head",
        "eyes": ((180, 458, 248, 550), (354, 496, 440, 600)),
        "mouth": (230, 530, 334, 632),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("ice_fox", "baby"): {
        "archetype": "tailed_fox",
        "body_pivot": (600, 850),
        "head": {
            "poly": [(215, 110), (885, 110), (885, 560), (815, 620), (710, 665), (585, 675), (465, 665), (365, 625), (275, 555), (215, 455)],
            "pivot": (575, 640),
            "neck_fill": [(465, 710), (475, 595), (705, 595), (715, 710)],
            "neck_sample": (590, 720),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (420, 765),
             "poly": [(125, 485), (335, 515), (420, 655), (438, 760), (428, 875), (125, 880)],
             "root": [(385, 695), (495, 710), (495, 840), (385, 835)], "sample": (345, 780), "reaction": "happy"},
        ],
        "face_parent": "head",
        "eyes": ((464, 474, 612, 548), (700, 428, 800, 502)),
        "mouth": (624, 484, 732, 554),
        "orig_eyes": "closed",
        "orig_mouth": "neutral",
        "mouth_style": "mammal",
    },
    ("mage_cat", "baby"): {
        "archetype": "tailed_cat",
        "body_pivot": (585, 855),
        "head": {
            "poly": [(150, 115), (880, 115), (880, 540), (805, 595), (705, 625), (585, 635), (455, 625), (345, 595), (225, 545), (150, 445)],
            "pivot": (570, 600),
            "neck_fill": [(445, 670), (455, 565), (715, 565), (725, 670)],
            "neck_sample": (585, 685),
        },
        "parts": [
            {"id": "tail", "z": 1, "parent": "body", "pivot": (385, 780),
             "poly": [(155, 575), (360, 600), (390, 725), (390, 845), (155, 855)],
             "root": [(355, 740), (465, 750), (465, 835), (355, 830)], "sample": (355, 790), "reaction": "play"},
        ],
        "face_parent": "head",
        "eyes": ((404, 380, 530, 510), (672, 364, 760, 482)),
        "mouth": (560, 450, 676, 560),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("dessert_panda", "baby"): {
        "archetype": "biped_bear",
        "body_pivot": (505, 850),
        "head": {
            "poly": [(205, 255), (835, 255), (835, 595), (755, 655), (635, 682), (495, 686), (365, 665), (265, 615), (205, 535)],
            "pivot": (505, 650),
            "neck_fill": [(375, 720), (385, 610), (635, 610), (645, 720)],
            "neck_sample": (505, 725),
        },
        "head_patch_fills": [
            ([(435, 305), (615, 305), (615, 375), (435, 375)], (480, 380)),
        ],
        "parts": [
            {"id": "cherry", "z": 10, "parent": "head", "pivot": (535, 320),
             "poly": [(420, 115), (725, 115), (725, 330), (605, 350), (450, 345)],
             "root": None, "sample": (525, 255), "reaction": "pet"},
        ],
        "face_parent": "head",
        "eyes": ((286, 438, 382, 558), (568, 458, 664, 580)),
        "mouth": (410, 516, 520, 618),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("bamboo_panda", "baby"): {
        "archetype": "biped_panda",
        "body_pivot": (515, 855),
        "head": None,
        "parts": [
            {"id": "sprout", "z": 10, "parent": "body", "pivot": (510, 295),
             "poly": [(365, 115), (595, 115), (595, 315), (465, 325), (365, 295)],
             "root": None, "sample": (465, 220), "reaction": "pet"},
        ],
        "body_top_fill": [(435, 340), (465, 270), (575, 270), (595, 340)],
        "body_top_sample": (535, 345),
        "face_parent": "body",
        "eyes": ((414, 384, 514, 458), (638, 364, 728, 438)),
        "mouth": (540, 434, 642, 534),
        "orig_eyes": "closed",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
        "downweight_dark_inpaint": False,
    },
    ("leaf_gorilla", "baby"): {
        "archetype": "biped_gorilla",
        "body_pivot": (485, 850),
        "head": {
            "poly": [(165, 135), (865, 135), (865, 565), (765, 635), (625, 660), (475, 650), (345, 610), (225, 555), (165, 445)],
            "pivot": (535, 615),
            "neck_fill": [(375, 690), (385, 580), (665, 580), (675, 690)],
            "neck_sample": (510, 710),
        },
        "head_patch_fills": [
            ([(465, 200), (655, 200), (655, 315), (465, 315)], (445, 305)),
        ],
        "parts": [
            {"id": "leaf", "z": 10, "parent": "head", "pivot": (535, 255),
             "poly": [(485, 115), (725, 115), (725, 275), (565, 280), (485, 255)],
             "root": None, "sample": (595, 210), "reaction": "pet"},
        ],
        "face_parent": "head",
        "eyes": ((414, 390, 546, 478), (650, 390, 752, 474)),
        "mouth": (514, 470, 676, 618),
        "orig_eyes": "closed",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("lamb", "baby"): {
        "archetype": "quadruped_lamb",
        "body_pivot": (525, 860),
        "head": {
            "poly": [(200, 120), (765, 120), (765, 455), (685, 555), (565, 595), (425, 600), (295, 565), (215, 485)],
            "pivot": (460, 565),
            "neck_fill": [(365, 635), (375, 525), (595, 525), (605, 635)],
            "neck_sample": (480, 665),
        },
        "head_patch_fills": [
            ([(255, 260), (335, 260), (335, 385), (255, 385)], (355, 320)),
            ([(575, 275), (655, 275), (655, 405), (575, 405)], (555, 335)),
        ],
        "parts": [
            {"id": "tail", "z": 2, "parent": "body", "pivot": (695, 645),
             "poly": [(680, 515), (855, 515), (855, 745), (685, 745)],
             "root": [(615, 590), (720, 590), (720, 695), (615, 690)], "sample": (745, 635), "reaction": "happy"},
            {"id": "ear_left", "z": 6, "parent": "head", "pivot": (300, 305),
             "poly": [(125, 215), (310, 235), (300, 365), (235, 425), (125, 375)],
             "root": [(280, 270), (380, 285), (370, 365), (275, 355)], "sample": (245, 315), "reaction": "pet"},
            {"id": "ear_right", "z": 6, "parent": "head", "pivot": (635, 325),
             "poly": [(625, 250), (880, 265), (880, 455), (685, 455), (615, 385)],
             "root": [(555, 285), (660, 295), (650, 375), (550, 365)], "sample": (715, 345), "reaction": "pet"},
        ],
        "face_parent": "head",
        "eyes": ((264, 338, 350, 462), (470, 352, 582, 482)),
        "mouth": (340, 438, 448, 550),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("forest_deer", "baby"): {
        "archetype": "quadruped_deer",
        "body_pivot": (535, 860),
        "head": {
            "poly": [(195, 115), (880, 115), (880, 545), (815, 605), (705, 632), (565, 628), (445, 605), (325, 535), (205, 415)],
            "pivot": (555, 595),
            "neck_fill": [(435, 665), (445, 560), (675, 560), (685, 665)],
            "neck_sample": (555, 685),
        },
        "parts": [
            {"id": "tail", "z": 2, "parent": "body", "pivot": (315, 655),
             "poly": [(145, 485), (328, 520), (338, 665), (310, 755), (145, 755)],
             "root": [(285, 610), (390, 625), (385, 715), (285, 705)], "sample": (255, 630), "reaction": "happy"},
        ],
        "face_parent": "head",
        "eyes": ((498, 406, 618, 540), (740, 380, 810, 498)),
        "mouth": (648, 450, 762, 580),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("moss_golem", "baby"): {
        "archetype": "stone_golem",
        "body_pivot": (520, 850),
        "head": None,
        "parts": [
            {"id": "sprout", "z": 10, "parent": "body", "pivot": (595, 330),
             "poly": [(430, 140), (750, 140), (750, 355), (635, 375), (545, 365), (430, 325)],
             "root": None, "sample": (595, 255), "reaction": "pet"},
        ],
        "body_top_fill": [(525, 385), (545, 315), (645, 315), (665, 385)],
        "body_top_sample": (595, 395),
        "face_parent": "body",
        "eyes": ((480, 508, 614, 588), (686, 482, 798, 558)),
        "mouth": (588, 534, 726, 670),
        "orig_eyes": "closed",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
    ("sea_dragon", "baby"): {
        "archetype": "aquatic_dragon",
        "body_pivot": (565, 870),
        "head": {
            "poly": [(335, 115), (855, 115), (855, 565), (775, 632), (665, 665), (535, 665), (415, 635), (345, 555)],
            "pivot": (565, 625),
            "neck_fill": [(435, 700), (445, 590), (695, 590), (705, 700)],
            "neck_sample": (585, 725),
        },
        "parts": [
            {"id": "tail", "z": 2, "parent": "body", "pivot": (455, 765),
             "poly": [(125, 615), (418, 660), (472, 760), (445, 895), (125, 905)],
             "root": [(415, 720), (550, 735), (550, 840), (415, 835)], "sample": (385, 795), "reaction": "play"},
            {"id": "fin_left", "z": 6, "parent": "head", "pivot": (368, 465),
             "poly": [(155, 305), (355, 335), (382, 465), (362, 600), (155, 595)],
             "root": [(335, 410), (475, 425), (465, 535), (330, 525)], "sample": (310, 455), "reaction": "play"},
            {"id": "fin_right", "z": 6, "parent": "head", "pivot": (790, 475),
             "poly": [(786, 405), (890, 405), (890, 575), (786, 575)],
             "root": [(700, 435), (815, 435), (815, 530), (700, 525)], "sample": (815, 475), "reaction": "play"},
        ],
        "face_parent": "head",
        "eyes": ((452, 418, 566, 544), (692, 392, 774, 506)),
        "mouth": (582, 470, 710, 584),
        "orig_eyes": "open",
        "orig_mouth": "happy",
        "mouth_style": "mammal",
    },
}


# ==============================================================================
# RIG BUILDERS
# ==============================================================================

def bbox_norm(img, fallback=(0.2, 0.2, 0.6, 0.6)):
    bb = img.getbbox()
    if not bb:
        return list(fallback)
    return [
        round(bb[0] / CANVAS, 3),
        round(bb[1] / CANVAS, 3),
        round((bb[2] - bb[0]) / CANVAS, 3),
        round((bb[3] - bb[1]) / CANVAS, 3),
    ]


def build_full_layered_rig(slug, stage, orig, out_base):
    spec = FULL_RIG_SPECS[(slug, stage)]
    layers_dir = os.path.join(out_base, "layers")
    os.makedirs(layers_dir, exist_ok=True)

    # Apply any surgical source defect cleanups
    clean_orig = orig.copy()
    for b in spec.get("clean_checker", ()):
        clean_orig = clean_checkerboard_box(clean_orig, b)
    for b in spec.get("erase_boxes", ()):
        clean_orig = erase_box(clean_orig, b)

    ink = sample_ink_color(clean_orig)
    body_working = clean_orig.copy()
    layer_images = {}
    layer_meta = []
    hitboxes = []

    # 1. Extract all appendages / accessories cleanly
    #    - Behind-parent parts (z < parent_z) get seamless root extension behind parent AND
    #      parent stays completely solid behind them (minimal subtraction, zero carved bites!).
    #    - In-front parts (z > parent_z) NEVER draw boxy root stubs on top; instead we
    #      reconstruct the occluded parent surface behind them so zero white gaps show!
    parent_z_map = {"body": 5, "head": 8}

    for part in spec.get("parts", ()):
        pid = part["id"]
        pz = part["z"]
        par_z = parent_z_map.get(part["parent"], 5)
        is_behind = pz < par_z

        pmask = make_poly_mask(part["poly"], feather=0.9)
        if part.get("extra_poly"):
            m2 = make_poly_mask(part["extra_poly"], feather=0.9)
            pmask = Image.composite(Image.new("L", (CANVAS, CANVAS), 255), pmask, m2)

        vis = apply_mask(clean_orig, pmask)
        vis = keep_largest_component(vis, keep_top_k=part.get("keep_k", 1))

        # Subtract cleanly from working body/head canvas
        body_working = subtract_mask(body_working, pmask)

        # ONLY extend root stub on parts that sit BEHIND their parent (z < parent_z)!
        layer_im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        if is_behind and part.get("root"):
            fill_col = sample_local_fill(clean_orig, part["sample"][0], part["sample"][1])
            dr = ImageDraw.Draw(layer_im)
            dr.polygon(part["root"], fill=fill_col)
            rpts = part["root"]
            dr.line([rpts[0], rpts[1]], fill=ink, width=9)
            dr.line([rpts[3], rpts[2]], fill=ink, width=9)
        layer_im = Image.alpha_composite(layer_im, vis)
        layer_images[pid] = layer_im
        layer_meta.append({
            "id": pid,
            "asset": f"layers/{pid}.png",
            "z_index": pz,
            "pivot": [round(part["pivot"][0] / CANVAS, 3), round(part["pivot"][1] / CANVAS, 3)],
            "parent": part["parent"],
        })
        hitboxes.append({
            "part": pid,
            "rect": bbox_norm(vis),
            "reaction": part.get("reaction", "play"),
        })

    # 2. Extract Head (if distinct articulated head) + reconstruct wide hidden neck collar!
    head_spec = spec.get("head")
    if head_spec is not None:
        hmask = make_poly_mask(head_spec["poly"], feather=0.9)
        head_vis = keep_largest_component(apply_mask(body_working, hmask))
        body_vis = keep_largest_component(subtract_mask(body_working, hmask))

        # Reconstruct generous hidden neck behind chin on body layer so head tilt NEVER gaps!
        body_im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        if head_spec.get("neck_fill"):
            nf = head_spec["neck_fill"]
            sx, sy = head_spec["neck_sample"]
            ncol = sample_local_fill(clean_orig, sx, sy)
            # Widen neck collar slightly (+/- 28px horizontally, -22px upward) safely behind head!
            exp_nf = [
                (nf[0][0] - 22, nf[0][1] + 24),
                (nf[1][0] - 20, nf[1][1] - 22),
                (nf[2][0] + 20, nf[2][1] - 22),
                (nf[3][0] + 22, nf[3][1] + 24),
            ]
            bd = ImageDraw.Draw(body_im)
            bd.polygon(exp_nf, fill=ncol)
            bd.line([exp_nf[0], exp_nf[1]], fill=ink, width=10)
            bd.line([exp_nf[3], exp_nf[2]], fill=ink, width=10)
        body_im = Image.alpha_composite(body_im, body_vis)

        # Also patch any small side-notch on head where gills/ears/fins were trimmed cleanly
        if spec.get("head_patch_fills"):
            head_bg = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
            hd = ImageDraw.Draw(head_bg)
            for pf_poly, pf_sample in spec["head_patch_fills"]:
                pcol = sample_local_fill(clean_orig, pf_sample[0], pf_sample[1])
                hd.polygon(pf_poly, fill=pcol)
            head_vis = Image.alpha_composite(head_bg, head_vis)

        layer_images["body"] = body_im
        layer_images["head"] = head_vis
        layer_meta.append({
            "id": "body",
            "asset": "layers/body.png",
            "z_index": 5,
            "pivot": [round(spec["body_pivot"][0] / CANVAS, 3), round(spec["body_pivot"][1] / CANVAS, 3)],
            "parent": None,
        })
        layer_meta.append({
            "id": "head",
            "asset": "layers/head.png",
            "z_index": 8,
            "pivot": [round(head_spec["pivot"][0] / CANVAS, 3), round(head_spec["pivot"][1] / CANVAS, 3)],
            "parent": "body",
        })
        hitboxes.append({"part": "head", "rect": bbox_norm(head_vis), "reaction": "pet"})
        hitboxes.append({"part": "body", "rect": bbox_norm(body_vis), "reaction": "happy"})
    else:
        # Single-torso creatures (slime, mushroom, ghost, bee, bird, penguin, leaf_spirit, golem, panda)
        body_vis = keep_largest_component(body_working)
        body_im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        if spec.get("body_top_fill"):
            tf = spec["body_top_fill"]
            sx, sy = spec["body_top_sample"]
            tcol = sample_local_fill(clean_orig, sx, sy)
            bd = ImageDraw.Draw(body_im)
            bd.polygon(tf, fill=tcol)
        if spec.get("body_patch_fills"):
            bd = ImageDraw.Draw(body_im)
            for pf_poly, pf_sample in spec["body_patch_fills"]:
                pcol = sample_local_fill(clean_orig, pf_sample[0], pf_sample[1])
                bd.polygon(pf_poly, fill=pcol)
        body_im = Image.alpha_composite(body_im, body_vis)
        layer_images["body"] = body_im
        layer_meta.append({
            "id": "body",
            "asset": "layers/body.png",
            "z_index": 5,
            "pivot": [round(spec["body_pivot"][0] / CANVAS, 3), round(spec["body_pivot"][1] / CANVAS, 3)],
            "parent": None,
        })
        bb = bbox_norm(body_vis)
        hitboxes.append({"part": "body", "rect": bb, "reaction": "happy"})

    # 3. Facial Expression Separation on face_parent (head or body)!
    face_parent = spec["face_parent"]
    face_src = layer_images[face_parent]
    face_pivot = next(m["pivot"] for m in layer_meta if m["id"] == face_parent)
    left_eye, right_eye = spec["eyes"]
    mouth_box = spec["mouth"]

    eye_mask = Image.new("L", (CANVAS, CANVAS), 0)
    ed = ImageDraw.Draw(eye_mask)
    ed.ellipse(left_eye, fill=255)
    ed.ellipse(right_eye, fill=255)

    mouth_mask = Image.new("L", (CANVAS, CANVAS), 0)
    md = ImageDraw.Draw(mouth_mask)
    md.ellipse(mouth_box, fill=255)

    orig_eyes_cut = apply_mask(face_src, eye_mask.filter(ImageFilter.GaussianBlur(1.2)))
    orig_mouth_cut = apply_mask(face_src, mouth_mask.filter(ImageFilter.GaussianBlur(1.2)))

    # Smooth harmonic inpaint of eye & mouth sockets on face_parent
    face_hole = Image.new("L", (CANVAS, CANVAS), 0)
    face_hole.paste(eye_mask, (0, 0), eye_mask)
    face_hole.paste(mouth_mask, (0, 0), mouth_mask)
    face_hole = face_hole.filter(ImageFilter.MaxFilter(11))

    face_base = inpaint_region_harmonic(
        face_src,
        face_hole,
        downweight_dark=spec.get("downweight_dark_inpaint", True),
    )
    face_base.putalpha(face_src.getchannel("A"))
    layer_images[face_parent] = face_base

    # Build all 3 eye layers + 3 mouth layers preserving 100% original artwork for native states!
    if spec["orig_eyes"] == "open":
        eyes_open = orig_eyes_cut
        eyes_closed = draw_cartoon_closed_eyes(CANVAS, left_eye, right_eye, ink)
    else:
        eyes_closed = orig_eyes_cut
        eyes_open = draw_cartoon_open_eyes(CANVAS, left_eye, right_eye, ink)
    eyes_sleep = draw_cartoon_sleep_eyes(CANVAS, left_eye, right_eye, ink)

    gen_neutral, gen_happy, gen_eating = draw_cartoon_mouths(
        CANVAS, mouth_box, ink, style=spec.get("mouth_style", "mammal")
    )
    if spec["orig_mouth"] == "happy":
        mouth_happy = orig_mouth_cut
        mouth_neutral = gen_neutral
    else:
        mouth_neutral = orig_mouth_cut
        mouth_happy = gen_happy
    mouth_eating = gen_eating

    # Choose default idle expression so Neutral Composite matches original artwork 100%!
    default_eyes = "eyes_open" if spec["orig_eyes"] == "open" else "eyes_closed"
    default_mouth = "mouth_happy" if spec["orig_mouth"] == "happy" else "mouth_neutral"

    expr_layers = [
        ("eyes_open", eyes_open, "eyes", default_eyes == "eyes_open"),
        ("eyes_closed", eyes_closed, "eyes", default_eyes == "eyes_closed"),
        ("eyes_sleep", eyes_sleep, "eyes", False),
        ("mouth_happy", mouth_happy, "mouth", default_mouth == "mouth_happy"),
        ("mouth_neutral", mouth_neutral, "mouth", default_mouth == "mouth_neutral"),
        ("mouth_eating", mouth_eating, "mouth", False),
    ]
    for eid, eim, slot, def_vis in expr_layers:
        layer_images[eid] = eim
        layer_meta.append({
            "id": eid,
            "asset": f"layers/{eid}.png",
            "z_index": 9,
            "pivot": face_pivot,
            "parent": face_parent,
            "slot": slot,
            "default_visible": def_vis,
        })

    # Save all quantized 1024x1024 transparent PNGs
    for lid, lim in layer_images.items():
        save_quantized_png(lim, os.path.join(layers_dir, f"{lid}.png"))

    layer_meta.sort(key=lambda m: m["z_index"])

    rig = {
        "monster_id": slug,
        "stage": stage,
        "rig_tier": "full_layered",
        "archetype": spec["archetype"],
        "canvas_size": [CANVAS, CANVAS],
        "layers": layer_meta,
        "hitboxes": hitboxes,
        "animations": ["idle", "happy", "pet", "eat", "sleep", "play", "evolve"],
    }
    anims = build_animations_for_rig(
        slug, stage, spec["archetype"], [m["id"] for m in layer_meta],
        default_eyes=default_eyes, default_mouth=default_mouth,
    )

    with open(os.path.join(out_base, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, indent=2)
    with open(os.path.join(out_base, "animations.json"), "w", encoding="utf-8") as f:
        json.dump(anims, f, indent=2)

    # Render neutral composite + happy/sleep QA preview tiles
    neutral_comp = composite_rig_pose(layer_meta, layer_images, {}, default_eyes, default_mouth)
    happy_comp = composite_rig_pose(
        layer_meta, layer_images,
        {"head": (0, -6, 7), "wing_left": (0, 0, 20), "wing_right": (0, 0, -20),
         "tail": (0, 0, 14), "cap": (0, -10, -8), "leaf_left": (0, 0, 12), "leaf_right": (0, 0, -12),
         "gills_left": (0, 0, 10), "gills_right": (0, 0, -10), "flipper_left": (0, 0, 16), "flipper_right": (0, 0, -16)},
        "eyes_closed", "mouth_happy",
    )
    sleep_comp = composite_rig_pose(
        layer_meta, layer_images,
        {"head": (0, 10, 7), "wing_left": (0, 0, -10), "wing_right": (0, 0, 10)},
        "eyes_sleep", "mouth_neutral",
    )
    eat_comp = composite_rig_pose(
        layer_meta, layer_images,
        {"head": (0, -4, -5), "tail": (0, 0, -10)},
        "eyes_open", "mouth_eating",
    )

    # Save per-character comparison.png (4-panel strip)
    cell = 280
    comp = Image.new("RGBA", (cell * 4, cell), (252, 248, 242, 255))
    cd = ImageDraw.Draw(comp)
    for idx, (label, pim) in enumerate([
        ("1. Original", clean_orig),
        ("2. Neutral Rig", neutral_comp),
        ("3. Happy / Action", happy_comp),
        ("4. Eat / Sleep", sleep_comp if spec["orig_eyes"] == "open" else eat_comp),
    ]):
        x0 = idx * cell
        cd.rectangle((x0 + 4, 4, x0 + cell - 4, cell - 4), outline=(220, 205, 190, 255), width=2)
        comp.alpha_composite(pim.resize((cell - 22, cell - 34), Image.Resampling.LANCZOS), (x0 + 11, 6))
        cd.text((x0 + 12, cell - 22), label, fill=(45, 32, 27, 255))
    comp.save(os.path.join(out_base, "comparison.png"))

    # Generate lightweight 20-frame preview.gif for key hero rigs
    gif_frames = []
    for i in range(20):
        ph = (i / 20.0) * 2 * math.pi
        if i < 10:
            ey = "eyes_closed" if i in (5, 6) else default_eyes
            mo = default_mouth
            tr = {
                "body": (0, math.sin(ph) * -6, 0),
                "head": (0, math.sin(ph) * -3, math.sin(ph) * 3.0),
                "wing_left": (0, 0, math.sin(ph) * 14),
                "wing_right": (0, 0, -math.sin(ph) * 14),
                "tail": (0, 0, math.sin(ph * 2) * 10),
                "cap": (0, math.sin(ph) * -5, math.sin(ph) * 4),
                "leaf_left": (0, 0, math.sin(ph) * 9),
                "leaf_right": (0, 0, -math.sin(ph) * 9),
                "gills_left": (0, 0, math.sin(ph) * 8),
                "gills_right": (0, 0, -math.sin(ph) * 8),
                "flipper_left": (0, 0, math.sin(ph) * 12),
                "flipper_right": (0, 0, -math.sin(ph) * 12),
                "droplets": (0, math.sin(ph) * -14, math.sin(ph) * 5),
                "crown": (0, math.sin(ph) * -5, math.sin(ph) * 4),
                "cherry": (0, math.sin(ph) * -5, math.sin(ph) * 6),
                "chef_hat": (0, math.sin(ph) * -6, math.sin(ph) * 4),
                "sprout": (0, math.sin(ph) * -4, math.sin(ph) * 6),
                "leaf": (0, math.sin(ph) * -4, math.sin(ph) * 7),
                "crest": (0, math.sin(ph) * -4, math.sin(ph) * 5),
                "antennae": (0, math.sin(ph) * -4, math.sin(ph) * 6),
                "ear_left": (0, 0, math.sin(ph) * 8),
                "ear_right": (0, 0, -math.sin(ph) * 8),
                "fin_left": (0, 0, math.sin(ph) * 9),
                "fin_right": (0, 0, -math.sin(ph) * 9),
            }
        else:
            p = (i - 10) / 10.0
            ph2 = p * 2 * math.pi
            ey = "eyes_closed" if i < 16 else "eyes_open"
            mo = "mouth_happy" if i < 16 else "mouth_eating"
            tr = {
                "body": (0, -abs(math.sin(ph2)) * 28, 0),
                "head": (0, 0, math.sin(ph2) * 7),
                "wing_left": (0, 0, math.sin(ph2 * 2) * 22),
                "wing_right": (0, 0, -math.sin(ph2 * 2) * 22),
                "tail": (0, 0, math.sin(ph2 * 2) * 15),
                "cap": (0, -abs(math.sin(ph2)) * 12, math.sin(ph2) * 8),
                "leaf_left": (0, 0, math.sin(ph2 * 2) * 13),
                "leaf_right": (0, 0, -math.sin(ph2 * 2) * 13),
                "gills_left": (0, 0, math.sin(ph2 * 2) * 11),
                "gills_right": (0, 0, -math.sin(ph2 * 2) * 11),
                "flipper_left": (0, 0, math.sin(ph2 * 2) * 16),
                "flipper_right": (0, 0, -math.sin(ph2 * 2) * 16),
                "droplets": (0, -abs(math.sin(ph2)) * 24, math.sin(ph2) * 8),
            }
        fr = composite_rig_pose(layer_meta, layer_images, tr, ey, mo)
        bg = Image.new("RGBA", (240, 240), (255, 251, 243, 255))
        bg.alpha_composite(fr.resize((240, 240), Image.Resampling.LANCZOS))
        gif_frames.append(bg.convert("P", palette=Image.Palette.ADAPTIVE))

    gif_frames[0].save(
        os.path.join(out_base, "preview.gif"),
        save_all=True,
        append_images=gif_frames[1:],
        duration=85,
        loop=0,
        optimize=True,
    )

    return rig, (clean_orig, neutral_comp, happy_comp, eat_comp, sleep_comp)


def composite_rig_pose(layer_meta, layer_images, transforms, eyes_id, mouth_id):
    """Composites rig layers with simple parent-child transform support for QA previews."""
    frame = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    by_id = {m["id"]: m for m in layer_meta}

    def get_total_tr(lid):
        m = by_id[lid]
        dx, dy, rot = transforms.get(lid, (0.0, 0.0, 0.0))
        if m.get("parent") and m["parent"] in by_id:
            pdx, pdy, prot = get_total_tr(m["parent"])
            return (dx + pdx, dy + pdy, rot + prot)
        return (dx, dy, rot)

    for m in sorted(layer_meta, key=lambda x: x["z_index"]):
        lid = m["id"]
        slot = m.get("slot")
        if slot == "eyes" and lid != eyes_id:
            continue
        if slot == "mouth" and lid != mouth_id:
            continue
        im = layer_images[lid]
        dx, dy, rot = get_total_tr(lid)
        if abs(dx) > 0.01 or abs(dy) > 0.01 or abs(rot) > 0.01:
            px_c = m["pivot"][0] * CANVAS
            py_c = m["pivot"][1] * CANVAS
            rad = math.radians(-rot)
            ca, sa = math.cos(rad), math.sin(rad)
            c = px_c - ca * (px_c + dx) + sa * (py_c + dy)
            f_v = py_c - sa * (px_c + dx) - ca * (py_c + dy)
            im = im.transform(
                (CANVAS, CANVAS),
                Image.Transform.AFFINE,
                (ca, -sa, c, sa, ca, f_v),
                resample=Image.Resampling.BICUBIC,
            )
        frame.alpha_composite(im)
    return frame


def build_whole_body_rig(slug, stage, archetype, orig, out_base):
    """Creates an honest, clean whole-body elastic animated rig for dense Young/Adult
    evolutions where overlapping flames/foliage/armor need manual artist inpainting
    before limb separation."""
    layers_dir = os.path.join(out_base, "layers")
    os.makedirs(layers_dir, exist_ok=True)
    save_quantized_png(orig, os.path.join(layers_dir, "body.png"))

    bb = orig.getbbox() or (160, 140, 860, 880)
    cx = (bb[0] + bb[2]) / 2.0 / CANVAS
    foot_y = min(0.92, (bb[3] - 12) / CANVAS)
    top_y = bb[1] / CANVAS
    h_norm = (bb[3] - bb[1]) / CANVAS
    w_norm = (bb[2] - bb[0]) / CANVAS

    rig = {
        "monster_id": slug,
        "stage": stage,
        "rig_tier": "whole_body",
        "archetype": archetype,
        "canvas_size": [CANVAS, CANVAS],
        "notes": (
            f"Honest whole-body elastic rig: {slug}/{stage} has overlapping dense "
            f"{stage} details (foliage/flames/accessories/limbs) that require manual "
            "artist separation & background inpainting before upgrading to full_layered."
        ),
        "layers": [
            {
                "id": "body",
                "asset": "layers/body.png",
                "z_index": 5,
                "pivot": [round(cx, 3), round(foot_y, 3)],
                "parent": None,
            }
        ],
        "hitboxes": [
            {
                "part": "head",
                "rect": [round(bb[0] / CANVAS + w_norm * 0.12, 3), round(top_y, 3), round(w_norm * 0.76, 3), round(h_norm * 0.44, 3)],
                "reaction": "pet",
            },
            {
                "part": "body",
                "rect": [round(bb[0] / CANVAS, 3), round(top_y + h_norm * 0.36, 3), round(w_norm, 3), round(h_norm * 0.64, 3)],
                "reaction": "happy",
            },
        ],
        "animations": ["idle", "happy", "pet", "eat", "sleep", "play", "evolve"],
    }
    anims = build_animations_for_rig(slug, stage, archetype, ["body"])

    with open(os.path.join(out_base, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, indent=2)
    with open(os.path.join(out_base, "animations.json"), "w", encoding="utf-8") as f:
        json.dump(anims, f, indent=2)
    return rig


def build_missing_source_stub(slug, stage, archetype, reason, out_base):
    os.makedirs(out_base, exist_ok=True)
    rig = {
        "monster_id": slug,
        "stage": stage,
        "rig_tier": "needs_manual_art",
        "archetype": archetype,
        "canvas_size": [CANVAS, CANVAS],
        "notes": reason,
        "layers": [],
        "hitboxes": [
            {"part": "body", "rect": [0.18, 0.18, 0.64, 0.64], "reaction": "happy"}
        ],
        "animations": ["idle", "happy", "pet", "eat", "sleep", "play", "evolve"],
    }
    anims = build_animations_for_rig(slug, stage, archetype, ["body"])
    with open(os.path.join(out_base, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, indent=2)
    with open(os.path.join(out_base, "animations.json"), "w", encoding="utf-8") as f:
        json.dump(anims, f, indent=2)
    return rig


# ==============================================================================
# MAIN PIPELINE RUNNER
# ==============================================================================

def main():
    os.makedirs(QA_DIR, exist_ok=True)
    manifest_entries = []
    qa_rows = []

    with zipfile.ZipFile(ZIP_PATH) as zf:
        for sid, slug, archetype in ALL_SLUGS:
            for stage in STAGES:
                out_base = os.path.join(ASSETS_ROOT, slug, stage)
                os.makedirs(out_base, exist_ok=True)

                # Skip regenerating fire_dragon/baby since it is already 10/10 verified,
                # just register it in the manifest!
                if (slug, stage) == ("fire_dragon", "baby"):
                    with open(os.path.join(out_base, "rig.json"), "r", encoding="utf-8") as f:
                        rig = json.load(f)
                    manifest_entries.append({
                        "species_id": sid,
                        "monster_id": slug,
                        "stage": stage,
                        "rig_tier": rig["rig_tier"],
                        "archetype": rig["archetype"],
                        "layer_count": len(rig["layers"]),
                        "layers": [l["id"] for l in rig["layers"]],
                        "rig_path": f"assets/monsters/{slug}/{stage}/rig.json",
                        "animations_path": f"assets/monsters/{slug}/{stage}/animations.json",
                        "notes": "Reference benchmark full layered rig (11 layers, visually QA-verified).",
                    })
                    print(f"[KEEP] {slug}/{stage} -> full_layered (11 layers)")
                    continue

                # Handle known corrupted / duplicated source masters honestly!
                if (slug, stage) == ("leaf_spirit", "young"):
                    rig = build_missing_source_stub(
                        slug, stage, archetype,
                        "SOURCE DEFECT: assets/monsters/leaf_spirit/young.png in master ZIP is blank (only 0.8% faint pixels). Requires original Leaf Spirit Young illustration by 2D artist.",
                        out_base,
                    )
                    manifest_entries.append({
                        "species_id": sid, "monster_id": slug, "stage": stage,
                        "rig_tier": "needs_manual_art", "archetype": archetype,
                        "layer_count": 0, "layers": [],
                        "rig_path": f"assets/monsters/{slug}/{stage}/rig.json",
                        "animations_path": f"assets/monsters/{slug}/{stage}/animations.json",
                        "notes": rig["notes"],
                    })
                    print(f"[MANUAL] {slug}/{stage} -> needs_manual_art (blank source)")
                    continue

                if (slug, stage) == ("leaf_spirit", "adult"):
                    rig = build_missing_source_stub(
                        slug, stage, archetype,
                        "SOURCE DEFECT: assets/monsters/leaf_spirit/adult.png in master ZIP is a visual duplicate of forest_deer/adult.png. Requires original Leaf Spirit Adult illustration by 2D artist.",
                        out_base,
                    )
                    manifest_entries.append({
                        "species_id": sid, "monster_id": slug, "stage": stage,
                        "rig_tier": "needs_manual_art", "archetype": archetype,
                        "layer_count": 0, "layers": [],
                        "rig_path": f"assets/monsters/{slug}/{stage}/rig.json",
                        "animations_path": f"assets/monsters/{slug}/{stage}/animations.json",
                        "notes": rig["notes"],
                    })
                    print(f"[MANUAL] {slug}/{stage} -> needs_manual_art (duplicate forest_deer)")
                    continue

                # Read untouched 1024x1024 master from ZIP & preserve original.png
                raw = zf.read(f"assets/monsters/{slug}/{stage}.png")
                orig_path = os.path.join(out_base, "original.png")
                with open(orig_path, "wb") as f:
                    f.write(raw)
                orig = Image.open(orig_path).convert("RGBA")

                if (slug, stage) in FULL_RIG_SPECS:
                    rig, qa_tuple = build_full_layered_rig(slug, stage, orig, out_base)
                    qa_rows.append((f"{slug}/{stage}", qa_tuple))
                    note = "Calibrated multi-part layered rig with root extensions & 6 facial expression layers."
                    if (slug, stage) == ("fire_dragon", "young"):
                        note += " Cleaned trapped PNG checkerboard inside wing-neck loop."
                    if (slug, stage) == ("fox", "young"):
                        note += " Cleaned stray left-edge artifact & trapped checkerboard inside tail-neck loop."
                    print(f"[FULL] {slug}/{stage} -> full_layered ({len(rig['layers'])} layers)")
                else:
                    rig = build_whole_body_rig(slug, stage, archetype, orig, out_base)
                    note = rig["notes"]
                    print(f"[BODY] {slug}/{stage} -> whole_body (1 layer)")

                manifest_entries.append({
                    "species_id": sid,
                    "monster_id": slug,
                    "stage": stage,
                    "rig_tier": rig["rig_tier"],
                    "archetype": rig["archetype"],
                    "layer_count": len(rig["layers"]),
                    "layers": [l["id"] for l in rig["layers"]],
                    "rig_path": f"assets/monsters/{slug}/{stage}/rig.json",
                    "animations_path": f"assets/monsters/{slug}/{stage}/animations.json",
                    "notes": note,
                })

    # Write authoritative rig_manifest.json
    counts = {}
    for e in manifest_entries:
        counts[e["rig_tier"]] = counts.get(e["rig_tier"], 0) + 1
    manifest = {
        "version": "1.0.0",
        "total_characters": len(manifest_entries),
        "summary": counts,
        "characters": manifest_entries,
    }
    manifest_path = os.path.join(ASSETS_ROOT, "rig_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    # Render batch visual QA sheets (5 characters per sheet x 5 panels each) so we inspect EVERY full rig!
    cell = 200
    for b_idx in range(0, len(qa_rows), 5):
        batch = qa_rows[b_idx : b_idx + 5]
        sheet = Image.new("RGBA", (cell * 5, cell * len(batch)), (252, 248, 242, 255))
        sd = ImageDraw.Draw(sheet)
        for r_idx, (title, (im_orig, im_neut, im_hap, im_eat, im_slp)) in enumerate(batch):
            y0 = r_idx * cell
            for c_idx, (sub, pim) in enumerate([
                (f"{title} ORIG", im_orig),
                ("NEUTRAL", im_neut),
                ("HAPPY", im_hap),
                ("EAT", im_eat),
                ("SLEEP", im_slp),
            ]):
                x0 = c_idx * cell
                sd.rectangle((x0 + 2, y0 + 2, x0 + cell - 2, y0 + cell - 2), outline=(220, 205, 190, 255), width=1)
                sheet.alpha_composite(pim.resize((cell - 12, cell - 24), Image.Resampling.LANCZOS), (x0 + 6, y0 + 4))
                sd.text((x0 + 6, y0 + cell - 16), sub, fill=(45, 32, 27, 255))
        qa_p = os.path.join(QA_DIR, f"qa_full_rigs_{(b_idx // 5) + 1}.png")
        sheet.save(qa_p)
        print("Wrote QA sheet:", qa_p)

    print("\n=== REFACTOR COMPLETE ===")
    print("Tier summary:", counts)
    print("Manifest:", manifest_path)


if __name__ == "__main__":
    main()
