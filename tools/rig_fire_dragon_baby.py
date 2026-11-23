import json
import math
import os
import zipfile
from collections import deque
from PIL import Image, ImageDraw, ImageFilter

ZIP_PATH = r"c:\Project\mampet\monster_collection_60_complete_flutter.zip"
OUT_BASE = r"c:\Project\mampet\assets\monsters\fire_dragon\baby"
LAYERS_DIR = os.path.join(OUT_BASE, "layers")
CANVAS = 1024


def make_poly_mask(points, feather=0.0):
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
    inv = cut_mask.point(lambda v: 255 - v)
    new_a = Image.composite(a, Image.new("L", img.size, 0), inv)
    # Soft multiply for clean anti-aliased edge
    a_bytes = bytearray(a.tobytes())
    c_bytes = cut_mask.tobytes()
    for i in range(len(a_bytes)):
        if c_bytes[i] > 0:
            a_bytes[i] = (a_bytes[i] * (255 - c_bytes[i])) // 255
    return Image.merge("RGBA", (r, g, b, Image.frombytes("L", img.size, bytes(a_bytes))))


def keep_largest_component(img, alpha_thresh=16):
    """Keeps only the largest 4-connected opaque region, eliminating any stray
    disconnected outline slivers or neighboring-part fragments cleanly."""
    # Downsample to 512x512 for ultra-fast connected component labeling, then mask 1024x1024
    w, h = img.size
    sw, sh = w // 2, h // 2
    a_small = img.getchannel("A").resize((sw, sh), Image.Resampling.BILINEAR)
    apx = a_small.load()
    visited = bytearray(sw * sh)
    best_comp = []
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
                if len(comp) > len(best_comp):
                    best_comp = comp
    keep_small = Image.new("L", (sw, sh), 0)
    kpx = keep_small.load()
    for cx, cy in best_comp:
        kpx[cx, cy] = 255
    # Dilate by 1px on 512x512 so anti-aliased fringes of main component stay 100% intact
    keep_small = keep_small.filter(ImageFilter.MaxFilter(3))
    keep_mask = keep_small.resize((w, h), Image.Resampling.BILINEAR)
    r, g, b, a = img.split()
    a_bytes = bytearray(a.tobytes())
    m_bytes = keep_mask.tobytes()
    for i in range(len(a_bytes)):
        if m_bytes[i] < 128:
            a_bytes[i] = 0
    return Image.merge("RGBA", (r, g, b, Image.frombytes("L", (w, h), bytes(a_bytes))))


def inpaint_region_harmonic(img, region_mask, smooth_iters=60):
    """Smoothly reconstructs occluded cel-shaded skin pixels using fast 256x256
    boundary-inward initialization followed by harmonic Laplace smoothing,
    compositing ONLY the inpainted interior back onto the crisp 1024x1024 image."""
    sw = 256
    small_img = img.resize((sw, sw), Image.Resampling.LANCZOS)
    small_mask = region_mask.resize((sw, sw), Image.Resampling.BILINEAR)
    px = small_img.load()
    mpx = small_mask.load()
    bbox = small_mask.getbbox()
    if not bbox:
        return img.copy()

    x0 = max(1, bbox[0] - 3)
    y0 = max(1, bbox[1] - 3)
    x1 = min(sw - 2, bbox[2] + 3)
    y1 = min(sw - 2, bbox[3] + 3)

    hole = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if mpx[x, y] > 96:
                hole.add((x, y))

    # 1. Seed boundary ring with bright skin pixels (skipping dark outline fringes)
    vals = {}
    for y in range(y0 - 2, y1 + 2):
        for x in range(x0 - 2, x1 + 2):
            if (x, y) not in hole:
                r, g, b, a = px[x, y]
                if a > 200:
                    vals[(x, y)] = (float(r), float(g), float(b))

    remaining = set(hole)
    while remaining:
        newly = {}
        for (x, y) in remaining:
            rs = gs = bs = ws = 0.0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nb = vals.get((x + dx, y + dy))
                if nb is not None:
                    lum = (nb[0] + nb[1] + nb[2]) / 3.0
                    w = 0.05 if lum < 95 else 1.0
                    rs += nb[0] * w
                    gs += nb[1] * w
                    bs += nb[2] * w
                    ws += w
            if ws > 0:
                newly[(x, y)] = (rs / ws, gs / ws, bs / ws)
        if not newly:
            break
        vals.update(newly)
        for k in newly:
            remaining.discard(k)

    # 2. Harmonic Laplace relaxation inside the hole -> velvety crease-free skin!
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

    inpainted_full = small_img.resize(img.size, Image.Resampling.BICUBIC)
    out = img.copy()
    soft_mask = region_mask.filter(ImageFilter.GaussianBlur(2.0))
    out.paste(inpainted_full, (0, 0), soft_mask)
    return out


def sample_ink_color(img):
    """Samples the authentic dark brown-maroon outline color of the character."""
    px = img.load()
    r_s = g_s = b_s = cnt = 0
    for y in range(150, 880, 4):
        for x in range(150, 880, 4):
            r, g, b, a = px[x, y]
            if a > 235 and 25 < r < 110 and g < 75 and b < 65:
                r_s += r
                g_s += g
                b_s += b
                cnt += 1
    if cnt == 0:
        return (68, 32, 20, 255)
    return (r_s // cnt, g_s // cnt, b_s // cnt, 255)


def build_fire_dragon_baby():
    os.makedirs(LAYERS_DIR, exist_ok=True)

    with zipfile.ZipFile(ZIP_PATH) as zf:
        raw_bytes = zf.read("assets/monsters/fire_dragon/baby.png")

    orig_path = os.path.join(OUT_BASE, "original.png")
    with open(orig_path, "wb") as f:
        f.write(raw_bytes)

    orig = Image.open(orig_path).convert("RGBA")
    assert orig.size == (CANVAS, CANVAS)
    ink = sample_ink_color(orig)
    print(f"Sampled Fire Dragon Baby ink color: {ink}")

    # ==========================================================
    # 1. HEAD MASK — follows exact chin/jaw dark outline cleanly
    # ==========================================================
    head_poly = [
        (190, 120), (880, 120), (880, 520),
        (830, 540), (775, 578), (725, 598), (665, 610),
        (595, 614), (528, 606), (468, 592), (412, 572),
        (388, 534), (362, 496), (210, 455),
    ]
    head_mask = make_poly_mask(head_poly, feather=1.0)
    head_raw = keep_largest_component(apply_mask(orig, head_mask))

    # ==========================================================
    # 2. WING LEFT MASK — behind torso, pivot at (435, 650)
    # ==========================================================
    wing_left_poly = [
        (110, 500), (350, 495), (382, 525), (418, 578), (446, 616), (452, 650),
        (422, 682), (382, 718), (240, 710), (110, 685),
    ]
    wing_left_mask = make_poly_mask(wing_left_poly, feather=1.0)
    wing_left_vis = keep_largest_component(apply_mask(orig, wing_left_mask))
    wing_left = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Extend wing_left root smoothly +38px inward behind torso so flapping NEVER gaps!
    wl_draw = ImageDraw.Draw(wing_left)
    wl_draw.polygon(
        [(405, 612), (485, 618), (485, 682), (392, 692)],
        fill=(220, 94, 52, 255),
    )
    wl_draw.line([(405, 612), (485, 618)], fill=ink, width=10)
    wl_draw.line([(392, 692), (485, 682)], fill=ink, width=10)
    # Re-composite clean original visible wing pixels on top so visible region is 100% original!
    wing_left = Image.alpha_composite(wing_left, wing_left_vis)

    # ==========================================================
    # 3. WING RIGHT MASK — behind torso, pivot at (692, 628)
    # ==========================================================
    wing_right_poly = [
        (685, 596), (780, 560), (895, 570), (895, 735),
        (745, 735), (695, 695), (684, 655),
    ]
    wing_right_mask = make_poly_mask(wing_right_poly, feather=1.0)
    wing_right_vis = keep_largest_component(apply_mask(orig, wing_right_mask))
    wing_right = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Extend wing_right root smoothly -38px behind torso
    wr_draw = ImageDraw.Draw(wing_right)
    wr_draw.polygon(
        [(645, 600), (710, 596), (710, 668), (645, 666)],
        fill=(216, 90, 48, 255),
    )
    wr_draw.line([(645, 600), (710, 596)], fill=ink, width=10)
    wr_draw.line([(645, 666), (710, 668)], fill=ink, width=10)
    wing_right = Image.alpha_composite(wing_right, wing_right_vis)

    # ==========================================================
    # 4. TAIL MASK — behind hip, pivot at (387, 804)
    # ==========================================================
    tail_poly = [
        (210, 700), (355, 705), (382, 745), (370, 795),
        (372, 845), (392, 875), (220, 875),
    ]
    tail_mask = make_poly_mask(tail_poly, feather=1.0)
    tail_vis = keep_largest_component(apply_mask(orig, tail_mask))
    tail = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Extend tail root +45px into hip behind body
    t_draw = ImageDraw.Draw(tail)
    t_draw.polygon(
        [(355, 742), (432, 756), (432, 848), (355, 844)],
        fill=(228, 98, 54, 255),
    )
    t_draw.polygon(
        [(355, 810), (432, 816), (432, 848), (355, 844)],
        fill=(242, 198, 134, 255),
    )
    t_draw.line([(355, 742), (432, 756)], fill=ink, width=11)
    t_draw.line([(355, 844), (432, 848)], fill=ink, width=11)
    tail = Image.alpha_composite(tail, tail_vis)

    # ==========================================================
    # 5. BODY — subtract head, wings, tail, then keep main torso
    #    component cleanly & reconstruct hidden neck collar!
    # ==========================================================
    body_cut_head = make_poly_mask([
        (190, 120), (880, 120), (880, 555),
        (810, 588), (740, 610), (665, 616),
        (595, 616), (528, 610), (455, 594),
        (392, 574), (345, 520), (210, 460),
    ], feather=0.8)
    body_cut_wl = make_poly_mask([
        (110, 500), (350, 495), (382, 525), (430, 608), (432, 650),
        (408, 680), (376, 712), (240, 710), (110, 685),
    ], feather=0.8)
    body_cut_wr = make_poly_mask([
        (696, 598), (780, 560), (895, 570), (895, 735),
        (745, 735), (706, 690), (696, 652),
    ], feather=0.8)
    body_cut_tail = make_poly_mask([
        (210, 700), (350, 705), (374, 748), (364, 795),
        (366, 845), (382, 875), (220, 875),
    ], feather=0.8)

    body_visible = orig.copy()
    for m in (body_cut_head, body_cut_wl, body_cut_wr, body_cut_tail):
        body_visible = subtract_mask(body_visible, m)
    body_visible = keep_largest_component(body_visible)

    # Reconstruct hidden neck/chest extension behind chin (y: 558..624)
    body = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.polygon(
        [(496, 624), (502, 562), (664, 562), (678, 624)],
        fill=(228, 98, 54, 255),
    )
    bd.polygon(
        [(568, 626), (566, 564), (642, 564), (654, 626)],
        fill=(248, 214, 152, 255),
    )
    bd.line([(496, 624), (502, 562)], fill=ink, width=11)
    bd.line([(678, 624), (664, 562)], fill=ink, width=11)
    body = Image.alpha_composite(body, body_visible)

    # ==========================================================
    # 6. FACIAL EXPRESSION SEPARATION (parented to HEAD!)
    #    - eyes_open.png: exact original eyes
    #    - head.png: clean skin-inpainted face base
    #    - eyes_closed.png: adorable happy closed arcs (^ ^)
    #    - eyes_sleep.png: peaceful sleeping closed arcs (u u)
    #    - mouth_happy.png: exact original happy mouth
    #    - mouth_neutral.png: cute closed gentle smile
    #    - mouth_eating.png: cute chewing 'o' mouth
    # ==========================================================
    eye_mask = Image.new("L", (CANVAS, CANVAS), 0)
    ed = ImageDraw.Draw(eye_mask)
    # Left eye exact ellipse (x: 513..617, y: 372..490)
    ed.ellipse((513, 372, 617, 490), fill=255)
    # Right eye exact ellipse (x: 752..814, y: 371..472)
    ed.ellipse((752, 371, 814, 472), fill=255)

    mouth_mask = Image.new("L", (CANVAS, CANVAS), 0)
    md = ImageDraw.Draw(mouth_mask)
    # Open happy mouth exact bounds (x: 622..766, y: 468..579)
    md.polygon([
        (620, 476), (652, 466), (710, 470), (766, 468),
        (764, 520), (740, 566), (696, 582), (650, 574), (624, 535),
    ], fill=255)

    eyes_open = apply_mask(head_raw, eye_mask.filter(ImageFilter.GaussianBlur(1.2)))
    mouth_happy = apply_mask(head_raw, mouth_mask.filter(ImageFilter.GaussianBlur(1.2)))

    # Inpaint eye & mouth sockets on head_base so alternative expressions have ZERO ghosting
    combined_face_hole = Image.new("L", (CANVAS, CANVAS), 0)
    combined_face_hole.paste(eye_mask, (0, 0), eye_mask)
    combined_face_hole.paste(mouth_mask, (0, 0), mouth_mask)
    # Dilate slightly so outline fringe around eye/mouth also vanishes cleanly
    combined_face_hole = combined_face_hole.filter(ImageFilter.MaxFilter(7))
    head_base = inpaint_region_harmonic(head_raw, combined_face_hole)

    # Preserve original head alpha silhouette cleanly
    head_base.putalpha(head_raw.getchannel("A"))

    # Draw crisp MamPet-style closed happy eyes (^ ^) for Blink / Pet / Happy
    eyes_closed = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ec = ImageDraw.Draw(eyes_closed)
    # Left happy arc (thick smooth cartoon stroke)
    ec.arc((524, 412, 608, 476), start=195, end=345, fill=ink, width=13)
    # Soft rosy cheek blush beneath happy closed eyes!
    ec.ellipse((500, 462, 548, 492), fill=(244, 118, 92, 130))
    # Right happy arc
    ec.arc((756, 408, 810, 464), start=195, end=345, fill=ink, width=12)
    ec.ellipse((782, 456, 822, 482), fill=(244, 118, 92, 130))

    # Draw peaceful sleeping eyes (u u) for Sleep state
    eyes_sleep = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    es = ImageDraw.Draw(eyes_sleep)
    es.arc((524, 402, 608, 464), start=18, end=162, fill=ink, width=12)
    es.arc((756, 398, 810, 452), start=18, end=162, fill=ink, width=11)

    # Draw cute neutral gentle smile (:3 style matching chibi dragon muzzle)
    mouth_neutral = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    mn = ImageDraw.Draw(mouth_neutral)
    mn.arc((646, 478, 704, 514), start=15, end=165, fill=ink, width=10)
    mn.arc((698, 478, 750, 512), start=15, end=165, fill=ink, width=10)

    # Draw adorable chewing/eating 'o' mouth for EAT state
    mouth_eating = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    me = ImageDraw.Draw(mouth_eating)
    me.ellipse((662, 486, 730, 548), fill=(168, 62, 68, 255), outline=ink, width=10)
    me.ellipse((678, 512, 718, 540), fill=(238, 128, 124, 255))

    # Save all separated transparent 1024x1024 layers
    layer_files = {
        "tail.png": tail,
        "wing_left.png": wing_left,
        "wing_right.png": wing_right,
        "body.png": body,
        "head.png": head_base,
        "eyes_open.png": eyes_open,
        "eyes_closed.png": eyes_closed,
        "eyes_sleep.png": eyes_sleep,
        "mouth_happy.png": mouth_happy,
        "mouth_neutral.png": mouth_neutral,
        "mouth_eating.png": mouth_eating,
    }
    for fname, im in layer_files.items():
        # Save as crisp optimized RGBA PNG (quantized 256-color keeps file ~15-35KB at full 1024x1024!)
        q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
        q.save(os.path.join(LAYERS_DIR, fname), "PNG", optimize=True)

    # ==========================================================
    # 7. WRITE rig.json & animations.json
    # ==========================================================
    rig = {
        "monster_id": "fire_dragon",
        "stage": "baby",
        "rig_tier": "full_layered",
        "archetype": "winged_dragon",
        "canvas_size": [CANVAS, CANVAS],
        "layers": [
            {"id": "tail", "asset": "layers/tail.png", "z_index": 1, "pivot": [0.378, 0.785], "parent": "body"},
            {"id": "wing_left", "asset": "layers/wing_left.png", "z_index": 2, "pivot": [0.425, 0.635], "parent": "body"},
            {"id": "wing_right", "asset": "layers/wing_right.png", "z_index": 2, "pivot": [0.676, 0.613], "parent": "body"},
            {"id": "body", "asset": "layers/body.png", "z_index": 5, "pivot": [0.555, 0.845], "parent": None},
            {"id": "head", "asset": "layers/head.png", "z_index": 8, "pivot": [0.571, 0.566], "parent": "body"},
            {"id": "eyes_open", "asset": "layers/eyes_open.png", "z_index": 9, "pivot": [0.571, 0.566], "parent": "head", "slot": "eyes", "default_visible": True},
            {"id": "eyes_closed", "asset": "layers/eyes_closed.png", "z_index": 9, "pivot": [0.571, 0.566], "parent": "head", "slot": "eyes", "default_visible": False},
            {"id": "eyes_sleep", "asset": "layers/eyes_sleep.png", "z_index": 9, "pivot": [0.571, 0.566], "parent": "head", "slot": "eyes", "default_visible": False},
            {"id": "mouth_happy", "asset": "layers/mouth_happy.png", "z_index": 9, "pivot": [0.571, 0.566], "parent": "head", "slot": "mouth", "default_visible": True},
            {"id": "mouth_neutral", "asset": "layers/mouth_neutral.png", "z_index": 9, "pivot": [0.571, 0.566], "parent": "head", "slot": "mouth", "default_visible": False},
            {"id": "mouth_eating", "asset": "layers/mouth_eating.png", "z_index": 9, "pivot": [0.571, 0.566], "parent": "head", "slot": "mouth", "default_visible": False},
        ],
        "hitboxes": [
            {"part": "head", "rect": [0.24, 0.14, 0.60, 0.45], "reaction": "pet"},
            {"part": "wing_left", "rect": [0.13, 0.49, 0.30, 0.22], "reaction": "play"},
            {"part": "wing_right", "rect": [0.68, 0.56, 0.20, 0.16], "reaction": "play"},
            {"part": "tail", "rect": [0.22, 0.69, 0.16, 0.17], "reaction": "happy"},
            {"part": "body", "rect": [0.36, 0.58, 0.36, 0.29], "reaction": "happy"},
        ],
        "animations": ["idle", "happy", "pet", "eat", "sleep", "play", "evolve"],
    }

    animations = {
        "monster_id": "fire_dragon",
        "stage": "baby",
        "blink_interval_ms": [2800, 4800],
        "blink_duration_ms": 140,
        "states": {
            "idle": {
                "loop": True,
                "duration_ms": 2600,
                "eyes": "eyes_open",
                "mouth": "mouth_happy",
                "tracks": {
                    "body": {"scale_y": [1.0, 1.028, 1.0], "scale_x": [1.0, 0.988, 1.0], "dy": [0.0, -5.0, 0.0]},
                    "head": {"rot_deg": [-1.8, 2.2, -1.8], "dy": [0.0, -4.0, 0.0]},
                    "wing_left": {"rot_deg": [-4.0, 8.0, -4.0]},
                    "wing_right": {"rot_deg": [4.0, -8.0, 4.0]},
                    "tail": {"rot_deg": [-7.0, 7.0, -7.0]},
                },
            },
            "happy": {
                "loop": False,
                "duration_ms": 1200,
                "eyes": "eyes_closed",
                "mouth": "mouth_happy",
                "tracks": {
                    "body": {"dy": [0.0, -34.0, 0.0, -22.0, 0.0], "scale_y": [1.0, 1.07, 0.94, 1.05, 1.0], "scale_x": [1.0, 0.95, 1.06, 0.97, 1.0]},
                    "head": {"rot_deg": [0.0, -6.0, 6.0, -4.0, 0.0]},
                    "wing_left": {"rot_deg": [0.0, 22.0, -14.0, 20.0, 0.0]},
                    "wing_right": {"rot_deg": [0.0, -22.0, 14.0, -20.0, 0.0]},
                    "tail": {"rot_deg": [-14.0, 14.0, -14.0, 12.0, 0.0]},
                },
            },
            "pet": {
                "loop": False,
                "duration_ms": 1400,
                "eyes": "eyes_closed",
                "mouth": "mouth_happy",
                "tracks": {
                    "body": {"scale_y": [1.0, 0.95, 1.03, 1.0], "scale_x": [1.0, 1.04, 0.98, 1.0]},
                    "head": {"rot_deg": [0.0, 8.5, -6.5, 5.0, 0.0], "dy": [0.0, 6.0, -4.0, 0.0]},
                    "wing_left": {"rot_deg": [0.0, 10.0, -4.0, 8.0, 0.0]},
                    "wing_right": {"rot_deg": [0.0, -10.0, 4.0, -8.0, 0.0]},
                    "tail": {"rot_deg": [0.0, 15.0, -12.0, 12.0, 0.0]},
                },
            },
            "eat": {
                "loop": False,
                "duration_ms": 1500,
                "eyes": "eyes_open",
                "mouth": "mouth_eating",
                "mouth_alternate": "mouth_neutral",
                "tracks": {
                    "body": {"scale_y": [1.0, 1.04, 0.97, 1.04, 0.98, 1.0], "dy": [0.0, -8.0, 2.0, -8.0, 0.0]},
                    "head": {"rot_deg": [0.0, -5.0, 4.0, -5.0, 3.0, 0.0], "dy": [0.0, 5.0, -4.0, 5.0, 0.0]},
                    "wing_left": {"rot_deg": [0.0, 12.0, 0.0, 12.0, 0.0]},
                    "wing_right": {"rot_deg": [0.0, -12.0, 0.0, -12.0, 0.0]},
                    "tail": {"rot_deg": [-10.0, 10.0, -10.0, 10.0, 0.0]},
                },
            },
            "sleep": {
                "loop": True,
                "duration_ms": 3800,
                "eyes": "eyes_sleep",
                "mouth": "mouth_neutral",
                "tracks": {
                    "body": {"scale_y": [0.98, 1.02, 0.98], "scale_x": [1.02, 0.99, 1.02], "dy": [10.0, 6.0, 10.0]},
                    "head": {"rot_deg": [5.5, 8.5, 5.5], "dy": [12.0, 16.0, 12.0]},
                    "wing_left": {"rot_deg": [-12.0, -9.0, -12.0]},
                    "wing_right": {"rot_deg": [12.0, 9.0, 12.0]},
                    "tail": {"rot_deg": [-4.0, -1.0, -4.0]},
                },
            },
            "play": {
                "loop": False,
                "duration_ms": 1600,
                "eyes": "eyes_open",
                "mouth": "mouth_happy",
                "tracks": {
                    "body": {"dy": [0.0, -46.0, -54.0, -32.0, 0.0], "rot_deg": [0.0, -4.0, 4.0, -2.0, 0.0]},
                    "head": {"rot_deg": [0.0, -8.0, 6.0, -4.0, 0.0]},
                    "wing_left": {"rot_deg": [-10.0, 26.0, -18.0, 26.0, -16.0, 22.0, 0.0]},
                    "wing_right": {"rot_deg": [10.0, -26.0, 18.0, -26.0, 16.0, -22.0, 0.0]},
                    "tail": {"rot_deg": [-16.0, 16.0, -16.0, 16.0, 0.0]},
                },
            },
            "evolve": {
                "loop": False,
                "duration_ms": 1800,
                "eyes": "eyes_closed",
                "mouth": "mouth_happy",
                "tracks": {
                    "body": {"scale_x": [1.0, 1.12, 0.94, 1.15, 1.0], "scale_y": [1.0, 1.12, 0.94, 1.15, 1.0], "dy": [0.0, -24.0, -12.0, -32.0, 0.0]},
                    "wing_left": {"rot_deg": [0.0, 24.0, -10.0, 28.0, 0.0]},
                    "wing_right": {"rot_deg": [0.0, -24.0, 10.0, -28.0, 0.0]},
                },
            },
        },
    }

    with open(os.path.join(OUT_BASE, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, indent=2)
    with open(os.path.join(OUT_BASE, "animations.json"), "w", encoding="utf-8") as f:
        json.dump(animations, f, indent=2)

    # ==========================================================
    # 8. COMPOSITE HELPER -> RENDER COMPARISON SHEET & PREVIEW GIF
    # ==========================================================
    def transform_layer(layer_im, pivot_norm, rot_deg=0.0, dx=0.0, dy=0.0, sx=1.0, sy=1.0):
        px_c = pivot_norm[0] * CANVAS
        py_c = pivot_norm[1] * CANVAS
        rad = math.radians(-rot_deg)
        cos_a = math.cos(rad)
        sin_a = math.sin(rad)
        # Inverse affine matrix mapping destination (x, y) -> source (u, v)
        a = cos_a / sx
        b = -sin_a / sx
        c = px_c - a * (px_c + dx) - b * (py_c + dy)
        d = sin_a / sy
        e = cos_a / sy
        f_val = py_c - d * (px_c + dx) - e * (py_c + dy)
        return layer_im.transform(
            (CANVAS, CANVAS),
            Image.Transform.AFFINE,
            (a, b, c, d, e, f_val),
            resample=Image.Resampling.BICUBIC,
        )

    def render_pose(
        body_dy=0.0, body_sx=1.0, body_sy=1.0,
        head_rot=0.0, head_dy=0.0,
        wl_rot=0.0, wr_rot=0.0, tail_rot=0.0,
        eyes_key="eyes_open.png", mouth_key="mouth_happy.png",
    ):
        frame = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        # Tail
        t_im = transform_layer(tail, (0.378, 0.785), rot_deg=tail_rot, dy=body_dy)
        frame.alpha_composite(t_im)
        # Wings
        wl_im = transform_layer(wing_left, (0.425, 0.635), rot_deg=wl_rot, dy=body_dy)
        wr_im = transform_layer(wing_right, (0.676, 0.613), rot_deg=wr_rot, dy=body_dy)
        frame.alpha_composite(wl_im)
        frame.alpha_composite(wr_im)
        # Body
        b_im = transform_layer(body, (0.555, 0.845), dy=body_dy, sx=body_sx, sy=body_sy)
        frame.alpha_composite(b_im)
        # Head + expressions composed together in head space first!
        head_comp = head_base.copy()
        head_comp.alpha_composite(layer_files[eyes_key])
        head_comp.alpha_composite(layer_files[mouth_key])
        h_im = transform_layer(head_comp, (0.571, 0.566), rot_deg=head_rot, dy=body_dy + head_dy)
        frame.alpha_composite(h_im)
        return frame

    # Render 6-panel Comparison Sheet (3 cols x 2 rows)
    panels = [
        ("1. Original PNG", orig),
        ("2. Neutral Rig Composite", render_pose()),
        ("3. Wing Flap + Tail Wag", render_pose(body_dy=-22, head_rot=-5, wl_rot=22, wr_rot=-22, tail_rot=15)),
        ("4. Pet / Happy (^ ^)", render_pose(body_sy=0.96, body_sx=1.04, head_rot=8, wl_rot=10, wr_rot=-10, tail_rot=-14, eyes_key="eyes_closed.png")),
        ("5. Eat Reaction ('o')", render_pose(body_dy=-6, head_rot=-4, wl_rot=10, wr_rot=-10, eyes_key="eyes_open.png", mouth_key="mouth_eating.png")),
        ("6. Sleep State (u u)", render_pose(body_dy=10, body_sy=0.97, head_rot=7, head_dy=12, wl_rot=-12, wr_rot=12, eyes_key="eyes_sleep.png", mouth_key="mouth_neutral.png")),
    ]
    cell = 340
    comp = Image.new("RGBA", (cell * 3, cell * 2), (252, 248, 242, 255))
    cd = ImageDraw.Draw(comp)
    for idx, (title, pim) in enumerate(panels):
        r, c = divmod(idx, 3)
        x0, y0 = c * cell, r * cell
        cd.rectangle((x0 + 6, y0 + 6, x0 + cell - 6, y0 + cell - 6), outline=(220, 205, 190, 255), width=2)
        small = pim.resize((cell - 28, cell - 46), Image.Resampling.LANCZOS)
        comp.alpha_composite(small, (x0 + 14, y0 + 10))
        cd.text((x0 + 16, y0 + cell - 28), title, fill=(45, 32, 27, 255))
    comp_path = os.path.join(OUT_BASE, "comparison.png")
    comp.save(comp_path)

    # Render smooth preview.gif (36 frames @ 60ms = ~2.2s showcase loop)
    gif_frames = []
    for i in range(36):
        t = i / 36.0
        if i < 16:
            # Idle breathe + blink at frames 8-9 + subtle wing/tail sway
            ph = (i / 16.0) * 2 * math.pi
            eyes = "eyes_closed.png" if i in (8, 9) else "eyes_open.png"
            fr = render_pose(
                body_dy=math.sin(ph) * -5,
                body_sy=1.0 + math.sin(ph) * 0.025,
                head_rot=math.sin(ph) * 2.5,
                wl_rot=math.sin(ph) * 9,
                wr_rot=-math.sin(ph) * 9,
                tail_rot=math.sin(ph * 2) * 8,
                eyes_key=eyes,
            )
        elif i < 28:
            # Playful flap + hop!
            p = (i - 16) / 12.0
            ph = p * 2 * math.pi
            fr = render_pose(
                body_dy=-abs(math.sin(ph)) * 36,
                head_rot=math.sin(ph) * 6,
                wl_rot=math.sin(ph * 2) * 24,
                wr_rot=-math.sin(ph * 2) * 24,
                tail_rot=math.sin(ph * 2) * 15,
                eyes_key="eyes_closed.png" if 0.25 < p < 0.75 else "eyes_open.png",
            )
        else:
            # Eat nom-nom!
            p = (i - 28) / 8.0
            ph = p * 2 * math.pi
            mouth = "mouth_eating.png" if i % 2 == 0 else "mouth_neutral.png"
            fr = render_pose(
                body_dy=-abs(math.sin(ph)) * 8,
                head_rot=math.sin(ph) * 5,
                wl_rot=math.sin(ph) * 10,
                wr_rot=-math.sin(ph) * 10,
                tail_rot=math.sin(ph) * 12,
                eyes_key="eyes_open.png",
                mouth_key=mouth,
            )
        bg = Image.new("RGBA", (320, 320), (255, 251, 243, 255))
        bg.alpha_composite(fr.resize((320, 320), Image.Resampling.LANCZOS))
        gif_frames.append(bg.convert("P", palette=Image.Palette.ADAPTIVE))

    gif_path = os.path.join(OUT_BASE, "preview.gif")
    gif_frames[0].save(
        gif_path,
        save_all=True,
        append_images=gif_frames[1:],
        duration=75,
        loop=0,
        optimize=True,
    )

    total_layer_kb = sum(
        os.path.getsize(os.path.join(LAYERS_DIR, fn)) for fn in layer_files
    ) / 1024
    print(f"Fire Dragon Baby benchmark COMPLETE! 11 layers total: {total_layer_kb:.1f} KB")
    print(f"Comparison sheet: {comp_path}")
    print(f"Animated GIF: {gif_path}")


if __name__ == "__main__":
    build_fire_dragon_baby()
