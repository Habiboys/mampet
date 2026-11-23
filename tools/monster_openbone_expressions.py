"""Draw independent eyelid, iris, and mouth poses in each MamPet face's native palette."""

import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from embergon_art import curve, heal, mask_layer
from monster_openbone_art import MASTER_SIZE, SURFACE, compress_feature, detect_face, face_strokes, manual_feature


PALETTES = {
    'fire_dragon': (112, 55, 32), 'fox': (99, 55, 38),
    'ice_fox': (58, 91, 128), 'sky_bird': (61, 100, 145),
    'sea_dragon': (53, 101, 146), 'water_slime': (58, 112, 159),
    'pink_axolotl': (118, 67, 83), 'mage_cat': (101, 70, 144),
    'dessert_ghost': (111, 59, 85), 'chef_penguin': (72, 82, 118),
    'forest_deer': (109, 78, 55), 'moss_golem': (100, 102, 57),
}
SLIM_EYES = {'fox', 'ice_fox', 'mage_cat', 'sky_bird', 'sea_dragon', 'forest_deer', 'fire_dragon'}
BEAKS = {'sky_bird', 'chef_penguin'}
IMAGEGEN_GUIDES = json.loads(Path(__file__).with_name('monster_openbone_imagegen_guides.json').read_text(encoding='utf-8'))
EXPRESSION_REVISION = 2
PROFILE_REVISIONS = {key:3 for key in (('sky_bird','young'),('water_slime','baby'),('water_slime','young'),
                                      ('dessert_panda','baby'),('dessert_panda','adult'),('sea_dragon','young'),
                                      ('lamb','baby'),('mushroom','adult'),('mage_cat','baby'),('mage_cat','young'))}
PROFILE_REVISIONS['dessert_panda','young'] = 4


def expression_version(identity, redrawn=False):
    if redrawn:
        return 8
    return PROFILE_REVISIONS.get(identity,EXPRESSION_REVISION)


def rgba(rgb):
    return tuple(int(min(255, max(0, v))) for v in rgb) + (255,)


def blend(a, b, amount):
    return tuple(x + (y-x)*amount for x, y in zip(a, b))


def painted_detail(cx, cy, radius, paint):
    """Supersample one expression detail, leaving the surrounding texture untouched."""
    x0 = max(0, math.floor(cx-radius))
    y0 = max(0, math.floor(cy-radius))
    x1 = min(1024, math.ceil(cx+radius))
    y1 = min(1024, math.ceil(cy+radius))
    dimensions = (x1-x0, y1-y0)
    canvas = Image.new('RGBA', tuple(d*3 for d in dimensions))
    local = ((cx-x0)*3, (cy-y0)*3)
    paint(canvas, *local)
    detail = Image.new('RGBA', MASTER_SIZE)
    detail.alpha_composite(canvas.resize(dimensions, Image.Resampling.LANCZOS), (x0, y0))
    return detail


def eye_shape(cx, cy, width, height, phase, tilt):
    rx = width/2
    ry = height/2
    aperture = (1, .59, .24)[phase]
    top = (1-aperture)*.44*ry-aperture*ry
    bottom = (1-aperture)*.25*ry+aperture*ry*.87
    left = (cx-rx, cy+tilt)
    right = (cx+rx, cy-tilt)
    return curve(left, [((cx-rx*.82,cy+top*1.4), (cx+rx*.76,cy+top*1.48), right),
                        ((cx+rx*.77,cy+bottom*1.44), (cx-rx*.80,cy+bottom*1.48), left)])


def draw_eye(feature, slug, stage, geometry, phase, glance=0):
    cx, cy, width, height, tilt = geometry
    source_ink = feature['ink'][:3]
    iris_tone = PALETTES.get(slug, (109, 76, 52))
    ink = rgba(blend(source_ink, iris_tone, .13))

    def paint(canvas, x, y):
        w, h = width*3, height*3
        points = eye_shape(x, y, w, h, phase, tilt*3)
        mask = Image.new('L', canvas.size)
        ImageDraw.Draw(mask).polygon(points, fill=255)
        detail = Image.new('RGBA', canvas.size)
        draw = ImageDraw.Draw(detail)
        for row in range(detail.height):
            value = max(0., min(1., (row-y+.42*h)/(.92*h)))
            base = blend(source_ink, iris_tone, .12 + .36*value)
            draw.line((0,row,detail.width,row), fill=rgba(base))
        iris_x, iris_y = x+w*(.075+glance*.14),y-h*.03
        ax, ay = w*.405,h*.49
        draw.ellipse((iris_x-ax,iris_y-ay,iris_x+ax,iris_y+ay), fill=rgba(blend(source_ink,iris_tone,.24)))
        draw.ellipse((iris_x-w*.26,iris_y-h*.40,iris_x+w*.26,iris_y+h*.35), fill=rgba(blend(source_ink,(18,17,22),.39)))
        hx, hy = iris_x-.145*w, iris_y-.214*h
        light = min(w,h)*(.115 if stage=='adult' else .132)
        draw.ellipse((hx-light,hy-light,hx+light,hy+light),fill=(255,247,232,255))
        if w>90:
            hx, hy = iris_x+.18*w,iris_y+.20*h
            light *= .32
            draw.ellipse((hx-light,hy-light,hx+light,hy+light),fill=rgba(blend(iris_tone,(249,215,190),.64)))
        canvas.alpha_composite(mask_layer(detail,mask))
        rim = ImageDraw.Draw(canvas)
        rim.line(points,fill=ink,width=max(5,round(w*.063)),joint='curve')
        rim.line(points[:33],fill=ink,width=max(6,round(w*.082)),joint='curve')
    return painted_detail(cx, cy, max(width,height)*.84+4, paint)


def opaque_support(art, pixels, protected):
    mask = np.asarray(art.getchannel('A')) > 24
    return bool(mask.any() and np.min(pixels[...,3][mask]) >= 239 and not (mask & protected).any())


def eye_variants(eyes, pixels, slug, stage, closed, mouth):
    result = {name:Image.new('RGBA',MASTER_SIZE) for name in ('eyes_open','eyes_lid_mid','eyes_lid_low','eyes_glance')}
    geometry = []
    if not closed:
        return result, geometry
    protected = cv2.dilate(mouth['mask'],np.ones((9,9),np.uint8)) != 0
    for eye in eyes:
        x0,y0,x1,y1 = eye['box']
        width = max(15,min(88,(x1-x0)*(.72 if slug in SLIM_EYES else .78)))
        height = width*(.88 if slug in SLIM_EYES else 1.04)*(1.04 if stage=='baby' else 1.)
        center = ((x0+x1)/2,(y0+y1)/2+max(2,width*.06))
        tilt = width*.033
        mx = (mouth['box'][0]+mouth['box'][2])/2
        away = 1 if center[0]>mx else -1
        # Far eyes on a turned muzzle have less space below the source lid.
        candidates = [(1,0,0),(.9,0,0),(.89,0,-.12),(.82,away*.07,-.16),(.74,0,-.18),
                      (.68,away*.13,-.18),(.58,0,-.21),(.53,away*.15,-.24)]
        for scale,offset_x,offset_y in candidates:
            shape = (center[0]+width*offset_x,center[1]+width*offset_y,
                     width*scale,height*scale,tilt*scale)
            opened = draw_eye(eye,slug,stage,shape,0)
            if opaque_support(opened,pixels,protected):
                break
        else:
            raise ValueError(f'Eyelid has insufficient face space around {eye["box"]}')
        result['eyes_open'].alpha_composite(opened)
        result['eyes_lid_mid'].alpha_composite(draw_eye(eye,slug,stage,shape,1))
        result['eyes_lid_low'].alpha_composite(draw_eye(eye,slug,stage,shape,2))
        result['eyes_glance'].alpha_composite(draw_eye(eye,slug,stage,shape,0,glance=1))
        geometry.append(shape)
    return result, geometry


def source_eyelid(image, feature, fraction):
    """Compress the original iris while retaining its original colors and highlight."""
    return compress_feature(image,feature,fraction,1.)


def drawn_mouth(feature, aperture, slug):
    x0,y0,x1,y1 = feature['box']
    width = min(124, (x1-x0)*.91)
    cx, cy = (x0+x1)/2, y0+(y1-y0)*.43
    height = width*aperture
    source_ink = feature['ink'][:3]
    ink = rgba(blend(source_ink,(78,36,37),.36))
    cavity = rgba(blend(source_ink,(134,48,55),.69))
    tongue = rgba(blend((229,126,117),(210,92,113),.55 if slug=='ice_fox' else .22))

    def paint(canvas,x,y):
        w,h = width*3,height*3
        le,ri = (x-w*.5,y-1.5), (x+w*.5,y-4)
        outline = curve(le,[((x-w*.22,y+h*.25),(x+w*.18,y+h*.21),ri),
                            ((x+w*.38,y+h*.98),(x+w*.16,y+h*1.21),(x-w*.04,y+h*.95)),
                            ((x-w*.27,y+h*.88),(x-w*.40,y+h*.42),le)])
        mask = Image.new('L',canvas.size)
        ImageDraw.Draw(mask).polygon(outline,fill=255)
        interior = Image.new('RGBA',canvas.size,cavity)
        d = ImageDraw.Draw(interior)
        d.ellipse((x-w*.30,y+h*.48,x+w*.20,y+h*1.12),fill=tongue)
        canvas.alpha_composite(mask_layer(interior,mask))
        ImageDraw.Draw(canvas).line(outline,fill=ink,width=max(6,round(w*.067)),joint='curve')
    return painted_detail(cx,cy,max(width,height)*.84+8,paint)


def combine_inks(pieces):
    combined = Image.new('RGBA', MASTER_SIZE)
    for piece in pieces:
        combined.alpha_composite(piece)
    return combined


def tapered_crease(canvas, points, width, color):
    draw = ImageDraw.Draw(canvas)
    for index, (x,y) in enumerate(points):
        radius = width*.5*(.35+.65*math.sin(math.pi*index/(len(points)-1))**.57)
        draw.ellipse((x-radius,y-radius,x+radius,y+radius),fill=color)


def adult_lids(eyes, geometry, sleeping):
    pieces = []
    for eye,(cx,cy,width,height,tilt) in zip(eyes,geometry,strict=True):
        def paint(canvas,x,y):
            w = width*3
            tilt_ = tilt*3
            sag = height*(.23 if sleeping else .15)*3
            start,end = (x-w*.43,y+tilt_), (x+w*.44,y-tilt_)
            points = curve(start,[((x-w*.16,y+sag+tilt_), (x+w*.19,y+sag-tilt_), end)])
            tapered_crease(canvas,points,max(6.5,w*.083),eye['ink'])
        pieces.append(painted_detail(cx,cy,width*.62+4,paint))
    return combine_inks(pieces)


def beak_pose(cleaned, pixels, mouth, coverage, closure):
    """Keep the upper bill in register and articulate only the lower jaw."""
    x0,y0,x1,y1 = mouth['box']
    section = pixels[y0:y1,x0:x1,:3]
    hsv = cv2.cvtColor(section,cv2.COLOR_RGB2HSV)
    amber = (hsv[...,0] >= 12) & (hsv[...,0] <= 40) & (hsv[...,1] > 107) & (hsv[...,2] > 132)
    amber &= coverage[y0:y1,x0:x1]
    amber[int(.58*(y1-y0)):] = False
    rows = np.nonzero(amber)[0]
    pivot = y0 + (round(np.percentile(rows, 94)) + 2 if len(rows)>35 else max(1,round((y1-y0)*.10)))
    mask = Image.fromarray(coverage.astype(np.uint8)*255).filter(ImageFilter.GaussianBlur(.85))
    ink = mask_layer(cleaned,mask)
    bx0,by0,bx1,by1 = mask.getbbox()
    upper = ink.crop((bx0,by0,bx1,pivot))
    lower = ink.crop((bx0,pivot,bx1,by1))
    lowered = lower.resize((lower.width,max(1,round(lower.height*closure))),Image.Resampling.LANCZOS)
    layer = Image.new('RGBA',MASTER_SIZE)
    layer.alpha_composite(upper,(bx0,by0))
    layer.alpha_composite(lowered,(bx0,pivot))
    return layer


def open_redrawn_bill(cleaned, mouth, seam, clearance):
    (lx,ly),(rx,ry) = seam
    x0,y0,x1,y1 = mouth['box']
    bounds = (x0-2,y0-2,x1+2,y1+clearance+3)
    xx,yy = np.meshgrid(np.arange(bounds[0],bounds[2]),np.arange(bounds[1],bounds[3]))
    phase = np.clip((xx-lx)/(rx-lx),0,1)
    split = ly+(ry-ly)*phase+2.2*np.sin(np.pi*phase)
    travel = clearance * np.sin(np.pi*phase)**.65
    cover = np.asarray(Image.fromarray(mouth['mask']*255).filter(ImageFilter.GaussianBlur(.72)))[yy,xx]
    part = cleaned.crop(bounds)
    upper = mask_layer(part,Image.fromarray((cover*(yy<split)).astype(np.uint8)))
    lower = mask_layer(part,Image.fromarray((cover*(yy>=split)).astype(np.uint8)))
    opened = cv2.remap(np.asarray(lower), (xx-bounds[0]).astype(np.float32),
                       (yy-bounds[1]-travel).astype(np.float32), cv2.INTER_LINEAR)
    cavity = np.zeros_like(opened)
    gap = (yy >= split-1) & (yy <= split+travel+1) & (xx >= lx) & (xx <= rx)
    cavity[gap] = (132,43,44,255)
    result = Image.new('RGBA',MASTER_SIZE)
    result.alpha_composite(Image.fromarray(cavity),bounds[:2])
    result.alpha_composite(Image.fromarray(opened),bounds[:2])
    result.alpha_composite(upper,bounds[:2])
    return result


def lift_repair_shadow(surface, pixels, support, face_mask, amount):
    ring = (cv2.dilate(support.astype(np.uint8),np.ones((17,17),np.uint8)) != 0) & ~face_mask
    ring &= pixels[...,3] > 246
    swatches = pixels[ring,:3]
    if len(swatches) < 30:
        return
    light = np.mean(swatches,axis=1)
    color = np.median(swatches[light>=np.percentile(light,58)],axis=0)
    distance = cv2.distanceTransform(support.astype(np.uint8),cv2.DIST_L2,3)[support]
    rgb = surface[support,:3].astype(float)
    shadow = np.clip((color.mean()-rgb.mean(axis=1)-28)/52,0.,1.)
    strength = np.clip((distance-2)/10,0.,1.) * shadow * amount
    surface[support,:3] = np.clip(rgb + (color-rgb)*strength[:,None],0,255).astype(np.uint8)


def match_skin(surface,pixels,support,samples):
    if not samples or not support.any():
        return
    yy,xx = np.nonzero(support)
    colors,weights = [],[]
    for x,y in samples:
        swatch = pixels[y-2:y+3,x-2:x+3]
        valid = swatch[...,3]>=246
        if valid.any():
            colors.append(np.median(swatch[valid,:3],axis=0))
            weights.append(1/(34+(xx-x)**2+(yy-y)**2))
    if not colors:
        return
    weights = np.asarray(weights)
    field = weights.T @ np.asarray(colors) / weights.sum(axis=0)[:,None]
    inner = cv2.distanceTransform(support.astype(np.uint8),cv2.DIST_L2,3)[support]
    strength = np.clip(inner/5.,0.,1.)[:,None]
    existing = surface[yy,xx,:3].astype(float)
    surface[yy,xx,:3] = np.clip(existing + (field-existing)*strength,0,255).astype(np.uint8)


def heal_surface(pixels, eye_support, mouth_support, identity, eyes, profile):
    face_mask = eye_support | mouth_support
    surface = heal(pixels,face_mask)
    # A neighboring contour can seed a dark shadow into an otherwise pale repair patch.
    lift_repair_shadow(surface,pixels,mouth_support,face_mask,.91)
    if identity==('sky_bird','young'):
        right = eye_support & (np.arange(1024)[None,:] > 670)
        lift_repair_shadow(surface,pixels,right,face_mask,1.)
    samples = profile.get('skin',{})
    match_skin(surface,pixels,mouth_support,samples.get('mouth'))
    for eye,swatches in zip(eyes,samples.get('eyes',[])):
        area = cv2.dilate(eye['mask'],np.ones((15,15),np.uint8)) != 0
        match_skin(surface,pixels,eye_support & area,swatches)
    return Image.fromarray(surface)


def isolate_iris(cleaned, surface, eye):
    left,top,right,bottom = eye['box']
    box = (left-3,top-3,right+3,bottom+3)
    source = cleaned.crop(box)
    rgb = np.asarray(source,dtype=np.int16)[...,:3]
    skin = np.asarray(surface.crop(box),dtype=np.int16)[...,:3]
    diff = np.max(np.abs(rgb-skin),axis=2)
    allowed = eye['mask'][box[1]:box[3],box[0]:box[2]] != 0
    ink = (allowed & (diff >= 21)).astype(np.uint8)
    contours,_ = cv2.findContours(ink,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        raise ValueError(f'No ImageGen iris inside {eye["box"]}')
    matte = np.zeros_like(ink)
    cv2.drawContours(matte,[max(contours,key=cv2.contourArea)],0,255,cv2.FILLED)
    matte = Image.fromarray(matte).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(.65))
    sprite = mask_layer(source,matte)
    x0,y0,x1,y1 = matte.getbbox()
    center = (box[0]+(x0+x1)/2,box[1]+(y0+y1)/2)
    return sprite.crop((x0,y0,x1,y1)),center


def balance_axis(first, second, minimum_ratio):
    smaller,larger = sorted((first,second))
    if smaller/larger >= minimum_ratio:
        return first,second
    smaller = round((first+second)*minimum_ratio/(1+minimum_ratio))
    larger = first+second-smaller
    return (smaller,larger) if first<second else (larger,smaller)


def balanced_iris_poses(cleaned, surface, eyes, pixels, mouth_core, slug):
    parts,centers = zip(*(isolate_iris(cleaned,surface,eye) for eye in eyes))
    widths = balance_axis(*(p.width for p in parts),.86 if slug=='bamboo_panda' else .90)
    heights = balance_axis(*(p.height for p in parts),.91)
    frames = {name:Image.new('RGBA',MASTER_SIZE) for name in ('eyes_open','eyes_lid_mid','eyes_lid_low')}
    geometry = []
    face_center = sum(c[0] for c in centers)/2
    for part,(cx,cy),width,height in zip(parts,centers,widths,heights,strict=True):
        inward = max(0,width-part.width)*.23
        cx += inward if cx<face_center else -inward
        geometry.append((cx,cy,width,height,0.))
        for (name,frame),ratio in zip(frames.items(),(1.,.55,.26),strict=True):
            aperture = max(1,round(height*ratio))
            crop = part.resize((width,aperture),Image.Resampling.LANCZOS)
            pose = Image.new('RGBA',MASTER_SIZE)
            pose.alpha_composite(crop,(round(cx-width/2),round(cy-aperture/2)))
            if name=='eyes_open' and not opaque_support(pose,pixels,mouth_core):
                raise ValueError(f'Balanced eye exceeds the painted face around {(cx,cy)}')
            frame.alpha_composite(pose)
    frames['eyes_glance'] = frames['eyes_open']
    return frames,geometry


def prepare_expression_layers(cleaned, face, target, identity, redrawn=False):
    slug, stage = identity
    profile = IMAGEGEN_GUIDES[slug] if redrawn else {}
    pixels = np.asarray(cleaned)
    if redrawn:
        eyes = [manual_feature(pixels,box,'eye') for box in profile['eyes']]
        mouth = manual_feature(pixels,profile['mouth'],'mouth')
    else:
        eyes, mouth = detect_face(pixels,face,identity)
    if not eyes or not all(eyes) or mouth is None:
        raise ValueError('The source ink masks could not be recovered')
    mouth_core = mouth['mask'] != 0
    eye_core = np.maximum.reduce([eye['mask'] for eye in eyes]) != 0
    opaque_skin = pixels[...,3] >= 241
    eye_size = 9 if redrawn else 15
    eye_support = (cv2.dilate(eye_core.astype(np.uint8),np.ones((eye_size,eye_size),np.uint8)) != 0) & opaque_skin & ~mouth_core
    inside = cv2.distanceTransform(opaque_skin.astype(np.uint8),cv2.DIST_L2,3) >= 4
    fringe = (cv2.dilate(mouth_core.astype(np.uint8),np.ones((13,13),np.uint8)) != 0) & inside
    mouth_support = (mouth_core | fringe) & opaque_skin & ~eye_support
    surface = heal_surface(pixels,eye_support,mouth_support,identity,eyes,profile)
    source_closed = face['closed'] and not redrawn
    drawn_eyes, geometry = eye_variants(eyes,pixels,slug,stage,source_closed,mouth)
    if redrawn and len(eyes)==2:
        drawn_eyes,geometry = balanced_iris_poses(cleaned,surface,eyes,pixels,mouth_core,slug)
        open_art = drawn_eyes['eyes_open']
        happy_eye = adult_lids(eyes,geometry,False)
    elif source_closed:
        open_art = drawn_eyes['eyes_open']
        happy_eye = None
    else:
        open_art = None
        drawn_eyes['eyes_lid_mid'] = combine_inks(source_eyelid(cleaned,e,.54) for e in eyes)
        drawn_eyes['eyes_lid_low'] = combine_inks(source_eyelid(cleaned,e,.25) for e in eyes)
        drawn_eyes['eyes_glance'] = drawn_eyes['eyes_lid_mid']
        happy_eye = face_strokes(eyes)
    if redrawn and not geometry:
        for eye in eyes:
            left,top,right,bottom = eye['box']
            geometry.append(((left+right)/2,(top+bottom)/2,(right-left)*.75,(bottom-top)*.83,0.))
    eye_closed = adult_lids(eyes,geometry,False) if redrawn else face_strokes(eyes,sleep=True)
    eye_sleep = adult_lids(eyes,geometry,True) if redrawn else eye_closed
    eye_designs = {'eyes_open':open_art,'eyes_original':None,'eyes_lid_mid':drawn_eyes['eyes_lid_mid'],
                   'eyes_lid_low':drawn_eyes['eyes_lid_low'],'eyes_joy':happy_eye,
                   'eyes_closed':eye_closed,'eyes_sleep':eye_sleep,
                   'eyes_glance':drawn_eyes['eyes_glance']}

    # A painted beak keeps the original bill and varies jaw clearance rather than inheriting mammal lips.
    x0,y0,x1,y1 = mouth['box']
    thin_source = (y1-y0)/(x1-x0) < .50 and slug not in BEAKS
    mouth_drawn = False
    if redrawn and 'bill_seam' in profile:
        opened,parted,chew = (open_redrawn_bill(cleaned,mouth,profile['bill_seam'],gap) for gap in (18,11,6))
        relaxed = None
        mouth_drawn = True
    elif slug in BEAKS:
        parted = beak_pose(cleaned,pixels,mouth,mouth_support,.74)
        chew = beak_pose(cleaned,pixels,mouth,mouth_support,.46)
        relaxed = beak_pose(cleaned,pixels,mouth,mouth_support,.23)
        opened = None
    elif thin_source or redrawn:
        protected = eye_core if redrawn else cv2.dilate(eye_support.astype(np.uint8),np.ones((7,7),np.uint8)) != 0
        for amount in (.64,.53,.42,.33):
            opened = drawn_mouth(mouth,amount,slug)
            if opaque_support(opened,pixels,protected):
                break
        else:
            raise ValueError(f'Mouth opening exceeds the muzzle around {mouth["box"]}')
        mouth_drawn = True
        parted = drawn_mouth(mouth,amount*.70,slug)
        chew = drawn_mouth(mouth,amount*.42,slug)
        relaxed = None
    else:
        opened = None
        parted = compress_feature(cleaned,mouth,.73,.98)
        chew = compress_feature(cleaned,mouth,.42,.95)
        relaxed = face_strokes([],mouth=mouth)
    mouth_designs = {'mouth_original':None,'mouth_relaxed':relaxed,'mouth_open':opened,
                     'mouth_parted':parted,'mouth_chew':chew}
    face_coverage = {'eyes':eye_support.copy(),'mouth':mouth_support.copy()}
    for slot,designs in (('eyes',eye_designs),('mouth',mouth_designs)):
        for art in designs.values():
            if art is not None:
                face_coverage[slot] |= np.asarray(art.getchannel('A')) > 3

    bounds = {}

    def save(name, image, box):
        bounds[name] = box
        image.crop(box).save(target / 'layers' / f'{name}.png', compress_level=5)

    save(SURFACE,surface,cleaned.getbbox())

    def save_variants(slot, designs, mask, other):
        coverage = Image.fromarray(face_coverage[slot].astype(np.uint8)*255)
        coverage = coverage.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(1.2))
        matte = np.asarray(coverage).copy()
        matte[other] = 0
        matte[mask] = 255
        matte = Image.fromarray(matte)
        box = matte.getbbox()
        for name,ink in designs.items():
            art = cleaned if ink is None else Image.alpha_composite(surface,ink)
            save(name,mask_layer(art,matte),box)

    save_variants('eyes',eye_designs,eye_support,mouth_support)
    protected_eye = eye_support
    if redrawn:
        opened_pixels = np.asarray(drawn_eyes['eyes_open'].getchannel('A'))>0
        protected_eye = eye_support | opened_pixels
    save_variants('mouth',mouth_designs,mouth_support & ~protected_eye,protected_eye)
    fit_mask = (face_coverage['eyes'] | face_coverage['mouth']).astype(np.uint8)
    return bounds, fit_mask, {'version':expression_version(identity,redrawn),'eyes_redrawn_open':bool(geometry) or redrawn,'visible_eyes':len(eyes),
                              'mouth_cavity_redrawn':mouth_drawn,'beak_preserved':slug in BEAKS,
                              'sprite_eye_anchors_px':[[round(a,2) for a in shape] for shape in geometry]}


def expression_keys(clip, wake_duration, redesigned):
    """Facial beats are local to existing clips and never change external trigger names."""
    eyes = {
        'idle':[(.40,'lid_mid'),(.42,'lid_low'),(.44,'closed'),(.463,'lid_low'),(.483,'lid_mid'),(.505,'open')],
        'happy':[(.16,'lid_mid'),(.25,'joy'),(.64,'lid_mid'),(.70,'open')],
        'pet':[(.11,'lid_mid'),(.18,'lid_low'),(.25,'joy'),(.69,'lid_low'),(.76,'lid_mid'),(.83,'open')],
        'eat':[(.17,'lid_mid'),(.23,'open'),(.66,'lid_mid'),(.73,'joy'),(.86,'lid_mid'),(.93,'open')],
        'sleep':[],
        'play':[(.14,'glance' if redesigned else 'open'),(.32,'lid_mid'),(.39,'open'),(.51,'lid_low'),(.60,'open')],
        'special':[(.14,'lid_mid'),(.24,'open'),(.48,'joy'),(.62,'lid_mid'),(.68,'open')],
    }
    mouth = {
        'idle':[], 'happy':[(.15,'parted'),(.27,'open'),(.68,'parted'),(.82,'relaxed')],
        'pet':[(.33,'parted'),(.50,'relaxed')],
        'eat':[(.10,'parted'),(.17,'open'),(.25,'chew'),(.33,'relaxed'),(.40,'chew'),(.48,'parted'),
               (.56,'chew'),(.64,'relaxed'),(.73,'parted'),(.79,'open'),(.89,'parted'),(.96,'relaxed')],
        'sleep':[], 'play':[(.17,'parted'),(.23,'open'),(.39,'relaxed'),(.56,'parted'),(.67,'open'),(.86,'relaxed')],
        'special':[(.14,'parted'),(.28,'open'),(.47,'chew'),(.61,'open'),(.81,'relaxed')],
    }
    eye_rest = 'sleep' if clip=='sleep' else 'open'
    return {slot:[(round(t*wake_duration,5),f'{slot}_{pose}') for t,pose in ((0,rest),*frames,(1,rest))]
            for slot,rest,frames in (('eyes',eye_rest,eyes[clip]),('mouth','relaxed',mouth[clip]))}
