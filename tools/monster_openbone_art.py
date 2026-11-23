"""Prepare a continuous MamPet sprite surface and locally repainted face slots."""

import io
import json
import os
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import binary_fill_holes

from embergon_art import ROOT, curve, heal, mask_layer, stroke
from refactor_all_monsters import FULL_RIG_SPECS


MASTER_SIZE = (1024, 1024)
GRID = 102.4
SURFACE = 'character_surface'
FACE_GUIDES = json.loads(Path(__file__).with_name('monster_openbone_face_guides.json').read_text(encoding='utf-8'))


def load_art(master, relpath, target):
    original = Image.open(io.BytesIO(master)).convert('RGBA')
    backup = (ROOT / relpath).with_suffix('') / 'original.png'
    result = target / 'source/original.png'
    if backup.exists() and backup.read_bytes() == master:
        try:
            os.link(backup, result)
        except OSError:
            result.write_bytes(master)
    else:
        result.write_bytes(master)

    # Defects already documented by the legacy asset team. Keep their source masters intact.
    cleaned = original.copy()
    slug, stage = Path(relpath).parent.name, Path(relpath).stem
    repairs = []
    checkers = {('fire_dragon', 'young'): (474, 508, 582, 602), ('fox', 'young'): (456, 615, 524, 708)}
    box = checkers.get((slug, stage))
    if box:
        patch = np.asarray(cleaned.crop(box)).copy()
        rgb = patch[..., :3]
        patch[(np.ptp(rgb, axis=2) < 22) & (rgb.min(axis=2) > 175)] = 0
        cleaned.paste(Image.fromarray(patch), box)
        repairs.append('Trapped checkerboard inside the illustrated silhouette removed locally.')
    isolated_strips = {('fox', 'young'): (118, 505, 162, 598), ('sky_bird', 'young'): (876, 535, 1024, 812)}
    if box := isolated_strips.get((slug, stage)):
        cleaned.paste((0, 0, 0, 0), box)
        repairs.append('Isolated crop artefact removed locally.')
    return original, cleaned, repairs


def load_redrawn_art(path):
    with Image.open(path) as generated:
        pixels = np.asarray(generated.convert('RGBA').resize(MASTER_SIZE,Image.Resampling.LANCZOS)).copy()
    opaque = (pixels[...,3] >= 128).astype(np.uint8)
    count,labels,stats,_ = cv2.connectedComponentsWithStats(opaque)
    if count < 2:
        raise ValueError('ImageGen sprite has no opaque subject')
    # Retain disconnected design elements such as Frostelle's ice crystals.
    kept = stats[:,cv2.CC_STAT_AREA] >= 36
    kept[0] = False
    fringe = cv2.dilate(kept[labels].astype(np.uint8),np.ones((5,5),np.uint8))
    pixels[fringe == 0] = 0
    return Image.fromarray(pixels)


def ellipse_restrict(x, y, cx, cy, rx, ry, limit):
    return ((x-cx)/rx)**2 + ((y-cy)/ry)**2 < limit


def find_feature(pixels, point, radii, kind):
    """Select a compact source-ink component close to an artist-marked feature."""
    cx, cy = map(lambda v: round(v * GRID), point)
    rx, ry = map(round, radii)
    x0, y0, x1, y1 = cx-rx, cy-ry, cx+rx+1, cy+ry+1
    roi = pixels[y0:y1, x0:x1]
    lum = cv2.cvtColor(roi[..., :3], cv2.COLOR_RGB2GRAY)
    xx, yy = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
    ellipse = ellipse_restrict(xx, yy, cx, cy, rx, ry, 1.05)
    range_ = lum[ellipse & (roi[..., 3] > 235)]
    if len(range_) < 20:
        return None
    dark, skin = np.percentile(range_, [8, 78])
    if skin-dark < 33:
        return None
    threshold = min(149, dark + .53*(skin-dark))
    signal = (lum < threshold) & ellipse & (roi[..., 3] > 204)
    signal = cv2.morphologyEx(signal.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, ids, stats, centers = cv2.connectedComponentsWithStats(signal)
    nearby = []
    for index in range(1, n):
        left, top, w, h, area = stats[index]
        qx, qy = centers[index]
        norm = ((qx-rx)/rx)**2 + ((qy-ry)/ry)**2
        if area >= 20 and w >= 9 and h >= 5 and norm < .46:
            nearby.append((area / (1 + 8*norm), index))
    if not nearby:
        return None
    _, best = max(nearby)
    ink = ids == best
    if ((ink & ~ellipse_restrict(xx, yy, cx, cy, rx, ry, .91)).sum() / ink.sum()) > .12:
        return None
    points = cv2.findNonZero(ink.astype(np.uint8))
    hull = np.zeros_like(signal)
    if kind == 'mouth':
        cv2.fillConvexPoly(hull, cv2.convexHull(points), 1)
    else:
        hull = binary_fill_holes(ink).astype(np.uint8)
    left, top, w, h = cv2.boundingRect(cv2.findNonZero(hull))
    if w >= rx*1.91 or h >= ry*1.95:
        return None
    # The hard mask is the inpaint domain, with a larger compositing ring on unchanged pixels.
    hard = np.zeros((1024, 1024), dtype=np.uint8)
    hard[y0:y1, x0:x1] = hull
    margins = 9 if kind == 'eye' else 11
    hard = cv2.dilate(hard, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (margins, margins)))
    if (pixels[..., 3][hard != 0] < 240).mean() > .009:
        return None
    color = np.median(roi[..., :3][ink & (lum <= np.percentile(lum[ink], 50))], axis=0).astype(int)
    return {'mask': hard, 'ink': (*color.tolist(), 255), 'box': (x0+left, y0+top, x0+left+w, y0+top+h)}


def fit_feature(pixels, point, radii, kind):
    for sx,sy in ((1,1),(.82,.87),(.95,1.17),(1.10,.70),(.67,.74),(1.13,1.19)):
        feature = find_feature(pixels, point, (radii[0]*sx,radii[1]*sy), kind)
        if feature is not None:
            return feature
    return None


def calibrated_feature(pixels, box, kind):
    x0,y0,x1,y1 = box
    point = ((x0+x1)/2/GRID,(y0+y1)/2/GRID)
    if feature := fit_feature(pixels,point,((x1-x0)/2+9,(y1-y0)/2+9),kind):
        return feature
    mask = np.zeros((1024,1024),dtype=np.uint8)
    cv2.ellipse(mask, (round((x0+x1)/2),round((y0+y1)/2)),
                (round((x1-x0)/2)+1,round((y1-y0)/2)+1),0,0,360,1,-1)
    return guide_feature(pixels,mask,box)


def guide_feature(pixels, mask, box, min_contrast=33):
    sample = pixels[mask!=0]
    if not len(sample) or (sample[:,3]<243).mean() > .032:
        return None
    luma = cv2.cvtColor(sample[None,:,:3],cv2.COLOR_RGB2GRAY)[0]
    dark = np.percentile(luma,15)
    if np.percentile(luma,77)-dark < min_contrast:
        return None
    ink = np.median(sample[luma<dark+6,:3],axis=0).astype(int)
    return {'mask':mask,'ink':(*ink.tolist(),255),'box':box}


def manual_feature(pixels, guide, kind):
    if isinstance(guide[0],int):
        return calibrated_feature(pixels,guide,kind)
    mask = np.zeros((1024,1024),dtype=np.uint8)
    xy = np.asarray(guide,dtype=np.int32)
    cv2.fillPoly(mask,[xy],1)
    x0,y0,w,h = cv2.boundingRect(xy)
    # Artist-traced polygons enclose the feature itself, often excluding the
    # surrounding skin that supplies the contrast in the automatic detector.
    return guide_feature(pixels,mask,(x0,y0,x0+w,y0+h),min_contrast=12)


def upper_lid(box, sleep=False):
    x0,y0,x1,y1 = box
    w, h = x1-x0, y1-y0
    cx, cy = (x0+x1)/2, y0 + h*.57
    depth = min(w*.24, max(4., h*.25)) * (1 if sleep else -1)
    return curve((cx-w*.41,cy), [((cx-w*.20,cy+depth),(cx+w*.21,cy+depth),(cx+w*.41,cy-1.5))])


def face_strokes(features, mouth=None, sleep=False):
    canvas = Image.new('RGBA', (3072,3072))
    draw = ImageDraw.Draw(canvas)
    for feature in features:
        x0, _, x1, _ = feature['box']
        stroke(draw, upper_lid(feature['box'],sleep), max(4, min(8,(x1-x0)*.105)), feature['ink'])
    if mouth:
        x0,y0,x1,y1 = mouth['box']
        w,h = x1-x0,y1-y0
        a,b,c = x0+.12*w, y0+.39*h, x1-.10*w
        smile = curve((a,b), [((a+.24*w,b+.36*h),(c-.20*w,b+.36*h),(c,b-2.7))])
        stroke(draw, smile, min(7,max(4,w*.075)), mouth['ink'])
    return canvas.resize(MASTER_SIZE, Image.Resampling.LANCZOS)


def compress_feature(original, feature, vertical, weight=1.0):
    cut = Image.fromarray(feature['mask'] * 255).filter(ImageFilter.GaussianBlur(1.3))
    box = cut.getbbox()
    x0,y0,x1,y1 = box
    crop = mask_layer(original, cut).crop(box)
    width = round(crop.width*weight)
    crop = crop.resize((width, max(1,round(crop.height*vertical))),Image.Resampling.LANCZOS)
    feature_box = feature['box']
    center = feature_box[1]+(feature_box[3]-feature_box[1])*.40
    offset = round(center + (y0-center)*vertical)
    out = Image.new('RGBA',MASTER_SIZE)
    out.alpha_composite(crop, (round((x0+x1-width)/2),offset))
    return out


def detect_face(pixels, face, identity):
    spacing = GRID*np.linalg.norm(np.subtract(*face['eyes']))
    radius = min(67,max(26,spacing*.265))
    eyes = [fit_feature(pixels,point,(radius * end, (radius*.93 if face['closed'] else radius*1.26)*end),'eye')
            for point,end in zip(face['eyes'],(1,.85))]
    legacy = FULL_RIG_SPECS.get(identity,{})
    for index,box in enumerate(legacy.get('eyes',())):
        if eyes[index] is None:
            eyes[index] = calibrated_feature(pixels,box,'eye')
    guide = FACE_GUIDES.get('/'.join(identity),{})
    if 'eyes' in guide:
        chosen = [manual_feature(pixels,area,'eye') for area in guide['eyes']]
        if all(chosen):
            eyes = chosen
    expected_eyes = len(guide.get('eyes',face['eyes']))
    eyes = [eye for eye in eyes if eye is not None]
    if len(eyes) != expected_eyes:
        eyes = []
    mouth = fit_feature(pixels,face['mouth'],(min(72,spacing*.38+14),min(66,spacing*.34+17)),'mouth')
    if mouth is None and 'mouth' in legacy:
        mouth = calibrated_feature(pixels,legacy['mouth'],'mouth')
    if 'mouth' in guide:
        mouth = manual_feature(pixels,guide['mouth'],'mouth') or mouth
    if eyes and mouth:
        for eye in eyes:
            overlap = mouth['mask'] & eye['mask']
            tolerance = .16 if 'mouth' in guide else .075
            if overlap.sum() > tolerance*min(mouth['mask'].sum(),eye['mask'].sum()):
                mouth = None
                break
            if overlap.any():
                # The intersection is the padding around adjacent features. Assign it to
                # the nearest ink center, so the two original-art patches never fight.
                yy,xx = np.nonzero(overlap)
                mx,my = np.mean(np.asarray(mouth['box']).reshape(2,2),axis=0)
                ex,ey = np.mean(np.asarray(eye['box']).reshape(2,2),axis=0)
                closer = (xx-mx)**2 + (yy-my)**2 < (xx-ex)**2 + (yy-ey)**2
                eye['mask'][yy[closer],xx[closer]] = 0
                mouth['mask'][yy[~closer],xx[~closer]] = 0
    return eyes,mouth


def prepare_layers(cleaned, face, target, identity):
    pixels = np.asarray(cleaned)
    eyes,mouth = detect_face(pixels,face,identity)

    bounds = {}
    def save(name, image, box):
        bounds[name] = tuple(box)
        image.crop(box).save(target / 'layers' / f'{name}.png', compress_level=5)

    mask = np.zeros((1024,1024),dtype=np.uint8)
    for feature in eyes + ([mouth] if mouth else []):
        mask |= feature['mask']
    surface = Image.fromarray(heal(pixels, mask != 0)) if mask.any() else cleaned
    # At rest the base art's exact visible surface is reassembled from its original pixels.
    save(SURFACE, surface, cleaned.getbbox())

    def variants(selected, designs):
        cover = np.maximum.reduce([f['mask'] for f in selected]) * 255
        matte = Image.fromarray(cover).filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(1.35))
        other = (mask != 0) & (cover == 0)
        if other.any():
            ownership = np.asarray(matte).copy()
            ownership[other] = 0
            matte = Image.fromarray(ownership)
        box = matte.getbbox()
        save(designs[0][0], mask_layer(cleaned, matte), box)
        for name, art in designs[1:]:
            save(name, mask_layer(Image.alpha_composite(surface, art), matte), box)

    if eyes:
        soft = Image.new('RGBA',MASTER_SIZE)
        for eye in eyes:
            soft.alpha_composite(compress_feature(cleaned,eye,.64,.96))
        variants(eyes,[('eyes_original',None),('eyes_soft',soft),
                       ('eyes_closed',face_strokes(eyes)),('eyes_sleep',face_strokes(eyes,sleep=True))])
    if mouth:
        x0,y0,x1,y1 = mouth['box']
        if identity[0]=='sky_bird':
            medium = compress_feature(cleaned,mouth,.73,.97)
            settled = compress_feature(cleaned,mouth,.55,.96)
            variants([mouth],[('mouth_original',None),('mouth_chew',medium),('mouth_smile',settled)])
        elif (y1-y0)/(x1-x0) >= .33:
            medium = compress_feature(cleaned,mouth,.62)
            variants([mouth],[('mouth_original',None),('mouth_chew',medium),('mouth_smile',face_strokes([],mouth=mouth))])
        else:
            # A closed smile is already the authored rest pose. Stretch the real lip line
            # for chewing without inventing detached teeth or a new character expression.
            medium = compress_feature(cleaned,mouth,1.32,.90)
            variants([mouth],[('mouth_original',None),('mouth_chew',medium),('mouth_smile',face_strokes([],mouth=mouth))])
    return bounds, bool(eyes), bool(mouth), mask
