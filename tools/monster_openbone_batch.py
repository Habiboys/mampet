"""Build anatomy-calibrated MamPet rigs, previews and runtime exports via OpenBone MCP."""

import argparse
import concurrent.futures
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
from collections import Counter
from pathlib import Path
from zipfile import ZipFile

import cv2
import numpy as np
from PIL import Image, ImageDraw

from embergon_art import ROOT, ID_PATTERN, STAGES, digest
from embergon_openbone import OpenBone, smooth, track
from embergon_preview import backdrop, frame, font, put_pose, remove_gif_loop
from monster_openbone_art import GRID, SURFACE, load_art, load_redrawn_art, prepare_layers
from monster_openbone_expressions import IMAGEGEN_GUIDES, expression_keys, expression_version, prepare_expression_layers
from monster_openbone_gallery import gif_metadata


OUT = ROOT / 'assets/animated_monsters'
ARCHIVE = ROOT / 'monster_collection_60_complete_flutter.zip'
ANATOMY = Path(__file__).with_name('monster_openbone_specs.json')
CHECK = Path(__file__).with_name('embergon_mesh_check.mjs')
PREVIEW_RENDERER = Path(__file__).with_name('monster_openbone_render.mjs')
FPS = 20
CLIPS = {'idle': (3.2, True), 'happy': (1.4, False), 'pet': (1, False), 'eat': (1.8, False),
         'sleep': (3.6, True), 'play': (2, False), 'special': (1.8, False)}
BLOCKERS = {
    ('leaf_spirit','young'): 'Master hampir kosong. Area alpha di atas 127 hanya 0,3% kanvas.',
}
REVIEW = {('leaf_spirit','adult'):
          'Master arsip memperlihatkan desain rusa serupa Floradeer. Paket hanya untuk tinjauan identitas ilustrasi.'}
ELEMENTS = {'Api':'fire','Air':'water','Alam':'nature','Angin':'wind','Bumi':'earth','Misteri':'mystery'}


def catalog():
    with ZipFile(ARCHIVE) as archive:
        manifest = json.loads(archive.read('monster_manifest.json'))
    doc = (ROOT / 'MamPet_PRD_Lengkap_v1.md').read_text(encoding='utf-8')
    section = doc.split('# 7. Katalog resmi')[1].split('Distribusi rarity')[0]
    rows = {id_: (name,slug,ELEMENTS[element],rarity.lower()) for id_,name,slug,element,rarity in
            ID_PATTERN.findall(re.sub(r'\n(?=[a-z]+ \|)', '_', section))}
    anatomy = json.loads(ANATOMY.read_text(encoding='utf-8'))
    assert len(rows) == len(manifest['species']) == len(anatomy) == 20
    for monster in manifest['species']:
        name, slug, element, rarity = rows[monster['id']]
        assert slug == monster['slug']
        for stage, spec in zip(STAGES, anatomy[slug], strict=True):
            yield {'monster_id':monster['id'], 'monster_slug':slug, 'monster_name':name, 'stage':stage,
                   'element':element, 'rarity':rarity, 'source_asset':monster['stages'][stage], 'spec':spec}


def anatomy(item, sprite_box):
    spec = item['spec']
    l,t,r,b = sprite_box
    x,y = (float(c)*GRID for c in spec['head'])
    fx = np.mean([e[0] for e in spec['face']['eyes']])*GRID
    body_x = round((x+(l+r)/2)*.5)
    origin = (round((l+r)*.5),b-2)
    soft_body = item['monster_slug'] in ('water_slime','dessert_ghost','mushroom') or (
        item['monster_slug']=='leaf_spirit' and item['stage']=='baby')
    parts = {}
    joints = {
        'root':(None,*origin,0.,0.),
        'torso':('root',body_x,round(y+.62*(b-y)),0.,max(48.,(b-y)*.55)),
        'head':('torso',x,y,0.,max(62.,(y-t)*.48)),
    }
    for name, raw in spec['parts'].items():
        px,py,tx,ty,width = (value*GRID for value in raw)
        angle = math.degrees(math.atan2(py-ty,tx-px))
        length = math.hypot(px-tx,py-ty)
        front = name.startswith(('antenna','gill','ear','cap')) or name in ('hat','cherry','plume','sprout','frosting')
        parent = 'head' if front or (name.startswith('leaf') and py < y*.76) else 'torso'
        joints[name] = (parent,px,py,angle,length)
        parts[name] = (px,py,tx,ty,width,parent)
    return origin,joints,parts,soft_body,fx


def weight_field(px,py, item, joints, parts, soft_body, face_x, face_distance):
    _, hx,hy,_,_ = joints['head']
    # The common surface keeps the neck and shoulder contours continuous under flexion.
    taper = .77 if soft_body else 1.
    head = taper*(1-smooth(hy-26,hy+101,py))*(1-smooth(148,302,abs(px-face_x)))
    if item['monster_slug'] == 'bread_turtle':
        head *= 1-smooth(hx-16,hx+68,px)
    if item['monster_slug'] == 'moss_golem':
        head *= (1-smooth(101,215,abs(px-face_x)))
    faces = 1-smooth(30,102,face_distance)
    head = max(head,faces)
    influences = {}
    for name,(x,y,end_x,end_y,width,parent) in parts.items():
        dx,dy = end_x-x,end_y-y
        length = math.hypot(dx,dy)
        u = ((px-x)*dx+(py-y)*dy)/(length**2)
        distance = abs((px-x)*dy-(py-y)*dx)/length
        fan = smooth(-.17,.83,u)*(1-smooth(.59*width,1.54*width,distance))
        fan *= 1-smooth(1.45,2.55,u)
        face_protection = (1-faces) if parent=='head' else 1-max(faces,.81*head)
        if name.startswith('cap'):
            face_protection = 1-max(faces, smooth(y-18,y+55,py))
        influences[name] = .94*fan*face_protection
    capacity = sum(influences.values())
    if capacity > .94:
        influences = {key:value*.94/capacity for key,value in influences.items()}
        capacity = .94
    influences['head'] = head*(1-capacity)
    planted = (1-head)*smooth(joints['torso'][2]+12,joints['root'][2]+2,py)*(.60 if soft_body else .93)
    influences['root'] = planted*(1-capacity)
    influences['torso'] = max(0.,1-sum(influences.values()))
    top = sorted(influences.items(),key=lambda p:-p[1])[:4]
    total = sum(weight for _,weight in top if weight > .004)
    return [{'bone': name, 'weight':round(weight/total,5)} for name,weight in top if weight > .004]


def mesh(item, image, texture_box, origin, joints, parts, soft_body, fx, face_mask):
    alpha = image.getchannel('A')
    alpha = np.asarray(alpha)
    coverage = cv2.dilate(alpha,np.ones((3,3), np.uint8))
    face_distance = cv2.distanceTransform(1-face_mask,cv2.DIST_L2,3) if face_mask.any() else None
    x0,y0,x1,y1 = texture_box
    nx = 20
    ny = 21
    vertices,uv,triangles,weights = [],[],[],[]
    index = {}

    def vertex(i,j,x,y):
        key = i,j
        if key not in index:
            index[key] = len(vertices)//2
            vertices.extend([round(x-origin[0],5),round(origin[1]-y,5)])
            uv.extend([i/nx,j/ny])
            distance = float(face_distance[round(y),round(x)]) if face_distance is not None else 200.
            weights.append({'vertex':index[key],'influences':weight_field(x,y,item,joints,parts,soft_body,fx,distance)})
        return index[key]

    for j in range(ny):
        ya,yb = y0+(y1-y0)*j/ny,y0+(y1-y0)*(j+1)/ny
        for i in range(nx):
            xa,xb = x0+(x1-x0)*i/nx,x0+(x1-x0)*(i+1)/nx
            if not np.any(coverage[int(ya):math.ceil(yb)+1,int(xa):math.ceil(xb)+1]):
                continue
            a,b,c,d = vertex(i,j,xa,ya),vertex(i+1,j,xb,ya),vertex(i,j+1,xa,yb),vertex(i+1,j+1,xb,yb)
            triangles.extend([a,c,b,b,c,d])
    return vertices,uv,triangles,weights


def setup_rig(mcp,item,source,bounds,joints,parts,soft_body,face_mask,origin,fx,revision=None):
    values={}
    for name,(parent,x,y,angle,length) in joints.items():
        if parent is None:
            values[name] = (0.,0.,0.)
            continue
        _,x0,y0,a0,_ = joints[parent]
        theta = math.radians(a0)
        dx,dy = x-x0,y0-y
        values[name] = (dx*math.cos(theta)+dy*math.sin(theta),-dx*math.sin(theta)+dy*math.cos(theta),angle-a0)
        vx,vy,vr = values[name]
        mcp.call('add_bone',name=name,id=name,parent=parent,x=vx,y=vy,rotation=vr,length=length)
    mcp.call('add_slot',name='surface',id='surface',bone='root')
    vertices,uv,triangles,weights = mesh(item,source,bounds[SURFACE],origin,joints,parts,soft_body,fx,face_mask)
    for name,(x0,y0,x1,y1) in bounds.items():
        mcp.call('add_image',name=name,id=name,src=f'../layers/{name}.png',width=x1-x0,height=y1-y0)
    mcp.call('add_mesh',slot='surface',name=SURFACE,image=SURFACE,vertices=vertices,uvs=uv,triangles=triangles,
             hull=0,activate=True)
    mcp.call('set_mesh_weights',slot='surface',attachment=SURFACE,vertices=weights)
    _, hx, hy, _, _ = joints['head']
    for slot in ('eyes','mouth'):
        if f'{slot}_original' not in bounds:
            continue
        mcp.call('add_slot',name=slot,id=slot,bone='head')
        setup = {'eyes':'eyes_open','mouth':'mouth_relaxed'}[slot] if revision else f'{slot}_original'
        for name,(x0,y0,x1,y1) in bounds.items():
            if name.startswith(slot):
                mcp.call('add_region',slot=slot,name=name,image=name,x=(x0+x1)/2-hx,y=hy-(y0+y1)/2,
                         activate=name==setup)
    mcp.call('add_slot',name='touch',id='touch',bone='head')
    y = np.mean([point[1] for point in item['spec']['face']['eyes']])*GRID
    wide = min(440., GRID*abs(item['spec']['face']['eyes'][1][0]-item['spec']['face']['eyes'][0][0])+145.)
    mcp.call('add_bounding_box',slot='touch',name='face_touch',x=fx-hx,y=hy-y,width=wide,height=165,activate=True)
    return values,(fx,y)


# Time is normalized per clip. Shape and timing survive each form's amplitude tuning.
ROOT_Y = {
    'idle':[(0,0),(.5,0),(1,0)],
    'happy':[(0,0),(.18,-.06),(.29,.50,'easeOut'),(.40,1,'easeIn'),(.54,.6),(.65,0),(.77,.07),(1,0)],
    'pet':[(0,0),(.28,-.06),(.65,.01),(1,0)],
    'eat':[(0,0),(.24,-.035),(.65,0),(1,0)],
    'sleep':[(0,0),(.50,0),(1,0)],
    'play':[(0,0),(.11,-.05),(.25,.82,'easeIn'),(.41,0),(.50,-.04),(.66,1,'easeIn'),(.82,0),(.90,.07),(1,0)],
    'special':[(0,0),(.14,-.06),(.29,.73,'easeIn'),(.45,.02),(.60,.64,'easeIn'),(.77,0),(.86,.05),(1,0)],
}
BODY_WAVE = {
    'idle':[(0,0),(.25,.65),(.74,-.36),(1,0)],
    'happy':[(0,0),(.18,-.82),(.36,.95),(.63,-.69),(.78,.18),(1,0)],
    'pet':[(0,0),(.21,.25),(.44,-.52),(.68,-.28),(1,0)],
    'eat':[(0,0),(.19,.37),(.29,-.45),(.41,.36),(.53,-.20),(.70,.58),(1,0)],
    'sleep':[(0,-.36),(.26,.06),(.76,-.59),(1,-.36)],
    'play':[(0,0),(.10,-.75),(.25,.95),(.41,-.81),(.64,.88),(.81,-.79),(.90,.18),(1,0)],
    'special':[(0,0),(.15,-.68),(.29,.66),(.44,-.47),(.61,.72),(.77,-.45),(1,0)],
}
HEAD = {
    'idle':[(0,0),(.27,-.50),(.72,.47),(1,0)],
    'happy':[(0,0),(.15,-.48),(.37,.85),(.58,-.42),(.74,.35),(1,0)],
    'pet':[(0,0),(.37,1),(.62,.74),(.83,.2),(1,0)],
    'eat':[(0,0),(.13,.6),(.25,-.67),(.36,.55),(.47,-.47),(.57,.2),(.70,.67),(.88,.10),(1,0)],
    'sleep':[(0,-.49),(.24,-.33),(.74,-.59),(1,-.49)],
    'play':[(0,0),(.19,-.6),(.34,.60),(.47,-.5),(.63,.75),(.79,-.52),(.90,.15),(1,0)],
    'special':[(0,0),(.17,-.51),(.30,.6),(.45,-.33),(.58,.81),(.78,-.26),(1,0)],
}
APPENDAGE = {
    'idle':[(0,0),(.30,.48),(.76,-.36),(1,0)],
    'happy':[(0,0),(.16,-.47),(.34,1),(.52,-.56),(.72,.31),(1,0)],
    'pet':[(0,0),(.22,.40),(.47,-.67),(.72,.42),(1,0)],
    'eat':[(0,0),(.28,.38),(.51,-.37),(.72,.55),(1,0)],
    'sleep':[(0,-.32),(.22,-.23),(.73,-.41),(1,-.32)],
    'play':[(0,0),(.12,-.50),(.24,.92),(.38,-.65),(.49,.42),(.64,-.88),(.76,.74),(.88,-.22),(1,0)],
    'special':[(0,0),(.13,-.51),(.27,1),(.43,-.84),(.57,.92),(.71,-.63),(.83,.25),(1,0)],
}
EYES = {'idle':[(.46,'soft'),(.48,'closed'),(.51,'soft'),(.535,'original')],
        'happy':[(.13,'soft'),(.20,'closed'),(.31,'original'),(.59,'soft'),(.68,'original')],
        'pet':[(.12,'soft'),(.19,'closed'),(.69,'soft'),(.79,'original')],
        'eat':[(.52,'soft'),(.61,'closed'),(.79,'soft'),(.87,'original')],
        'sleep':[], 'play':[(.32,'soft'),(.37,'closed'),(.43,'original'),(.81,'soft'),(.88,'original')],
        'special':[(.13,'soft'),(.21,'original'),(.47,'soft'),(.58,'original'),(.77,'closed'),(.86,'original')]}
MOUTH = {'idle':[], 'happy':[(.15,'smile'),(.28,'original'),(.68,'smile'),(.84,'original')],
         'pet':[(.20,'smile'),(.79,'original')],
         'eat':[(.13,'chew'),(.20,'original'),(.29,'smile'),(.36,'chew'),(.43,'original'),(.51,'smile'),
                (.57,'chew'),(.66,'original'),(.78,'smile'),(.94,'original')],
         'sleep':[], 'play':[(.16,'chew'),(.22,'original'),(.42,'chew'),(.55,'original'),(.86,'smile'),(.95,'original')],
         'special':[(.20,'chew'),(.30,'original'),(.48,'smile'),(.60,'original'),(.80,'chew'),(.94,'original')]}


def add_actions(mcp,item,values,parts,features,art_box,amplitude,create,revision=None):
    unit = item['stage']
    l,t,r,b = art_box
    hover = item['monster_slug'] in ('dessert_ghost','bee_moth')
    slime = item['monster_slug'] in ('water_slime','leaf_spirit')
    stretch = .086 if slime else .051 if unit=='baby' else .043
    active = .92 if unit=='adult' else 1.
    lift = min(73,max(0,(t-16)*.57))
    sway = min(40,max(0,min(l,1024-r)-25)*.61)
    rig_motion = active*amplitude

    for clip,(duration,_) in CLIPS.items():
        if create:
            mcp.call('create_animation',name=clip,id=clip,duration=duration)

        def bone(bone_name,key,points,size):
            x,y,angle=values[bone_name]
            baseline = {'x':x,'y':y,'rotation':angle,'scaleX':1,'scaleY':1}[key]
            times = [(round(t_*duration,5),value*size,*curve_) for t_,value,*curve_ in points]
            track(mcp,clip,'bone',bone_name,key,times,baseline)

        bone('root','y',ROOT_Y[clip],lift*rig_motion)
        bone('torso','scaleX',BODY_WAVE[clip],-.74*stretch*rig_motion)
        bone('torso','scaleY',BODY_WAVE[clip],stretch*rig_motion)
        bone('head','rotation',HEAD[clip],(7 if clip=='pet' else 5.6)*rig_motion)
        if clip in ('eat','sleep','pet'):
            movement = -11 if clip=='sleep' else 8.3 if clip=='eat' else 5.2
            wave = [(t_, -v if clip=='sleep' else v) for t_,v in HEAD[clip]]
            bone('head','y',wave,movement*rig_motion)
        if clip=='idle' and hover:
            bone('root','y',BODY_WAVE[clip],14.0*rig_motion)
        if clip=='play':
            bone('root','x',[(0,0),(.23,-.83),(.40,-1),(.53,-.41),(.68,1),(.82,.62),(1,0)],sway*rig_motion)
        if clip in ('play','special'):
            bone('root','rotation',HEAD[clip],2.8*rig_motion)

        for name,part in parts.items():
            x,_,tx,_,_,_ = part
            side = 1 if tx>=x else -1
            wave = APPENDAGE[clip]
            if name.startswith(('wing','fin','gill')):
                extent = 11 if clip in ('play','special','happy') else 5
            elif name.startswith(('tail','skirt','crest')):
                extent = 12 if clip in ('play','special') else 8
            elif name.startswith(('leg','foot','hoof','arm','flipper')):
                extent = 8.4 if clip in ('play','eat','special') else 4.8
            else:
                extent = 8.6 if clip in ('pet','special') else 5.8
            if name.endswith('right'):
                wave = [(min(1,t_+.045) if 0<t_<1 else t_,v) for t_,v in wave]
            bone(name,'rotation',wave,side*extent*rig_motion)

        if not create:
            continue
        if revision:
            for slot,points in expression_keys(clip,duration,revision['eyes_redrawn_open']).items():
                track(mcp,clip,'slot',slot,'attachment',points)
            continue
        for slot,enabled,expressions in (('eyes',features[0],EYES),('mouth',features[1],MOUTH)):
            if enabled:
                initial = ('sleep' if slot=='eyes' else 'smile') if clip=='sleep' else 'original'
                points = [(0,initial),*expressions[clip],(1,initial)]
                track(mcp,clip,'slot',slot,'attachment',[(round(t_*duration,5),f'{slot}_{state}') for t_,state in points])


def machine(mcp,item):
    name = f'{item["monster_name"]}{item["stage"].title()}'
    mcp.call('create_state_machine',name=name,id=name,layerName='Motion')
    for i,(clip,(_,loop)) in enumerate(CLIPS.items()):
        mcp.call('add_state',stateMachine=name,name=clip,id=f'state_{clip}',animation=clip,loop=loop,
                 x=(i//3)*240,y=(i%3)*112)
    for clip,(_,loop) in CLIPS.items():
        if clip=='idle':
            continue
        mcp.call('add_input',stateMachine=name,type='trigger',name=clip)
        mcp.call('add_transition',stateMachine=name,to=clip,conditions=[{'input':clip}],
                 duration=.11 if clip=='sleep' else .08,**{'from':'@any'})
        if not loop:
            mcp.call('add_transition',stateMachine=name,to='idle',exitTime=1,duration=.12,**{'from':clip})
    mcp.call('add_input',stateMachine=name,type='trigger',name='wake')
    mcp.call('add_transition',stateMachine=name,to='idle',duration=.13,conditions=[{'input':'wake'}],**{'from':'@any'})
    mcp.call('add_listener',stateMachine=name,name='Pet on face click',slot='touch',event='click',
             actions=[{'type':'fireTrigger','input':'pet'}])
    return name


def motion_check(server, path):
    result = subprocess.run(['node',str(CHECK),str(server),str(path)],capture_output=True,text=True,encoding='utf-8')
    if not result.stdout:
        raise RuntimeError(result.stderr)
    return result.returncode == 0,json.loads(result.stdout)


def state_check(mcp, machine_name, position):
    script = [{'pointer':{'type':'down','x':position[0],'y':position[1]},'advance':.03},
              {'pointer':{'type':'up','x':position[0],'y':position[1]},'advance':1.17}]
    for clip,(duration,_) in CLIPS.items():
        if clip!='idle':
            script.append({'fire':[clip],'advance':duration+.24})
    script.append({'fire':['sleep'],'advance':.33})
    script.append({'fire':['wake'],'advance':.27})
    log = mcp.call('simulate_state_machine',stateMachine=machine_name,steps=script)
    for clip,(_,loop) in CLIPS.items():
        if clip!='idle':
            assert f'→ {clip}' in log,log
        if not loop:
            assert f'{clip} → idle' in log,log
    assert 't=0.030 input pet = true' in log and 'sleep → idle' in log,log
    assert 'input wake = true\n' in log and '"Motion":"idle"' in log,log


def render_face_sheet(original, stills, sheet_path, face_mask):
    ys,xs = np.nonzero(face_mask)
    cx,cy = (xs.min()+xs.max())/2,(ys.min()+ys.max())/2
    radius = max(xs.max()-xs.min(),ys.max()-ys.min())*.60+19
    box = tuple(round(v*.5) for v in (cx-radius,cy-radius,cx+radius,cy+radius))
    samples = [('Master', original.resize((512,512),Image.Resampling.LANCZOS))]
    samples.extend((label,stills[key]) for label,key in [('Mata terbuka','neutral'),('Setengah kedip','mid'),
            ('Kelopak tertutup','closed'),('Senyum','joy'),('Mulut terbuka','eat'),('Kunyah','chew'),('Tidur','sleep')])
    sheet = Image.new('RGB',(4*149+12,334),'#111a2b')
    labels = ImageDraw.Draw(sheet)
    for i,(title,pose) in enumerate(samples):
        x,y = 8+(i%4)*149,8+(i//4)*164
        put_pose(sheet,pose.crop(box),x,y,136)
        labels.text((x+3,y+139),title,font=font(15),fill='#f0d6b0')
    sheet.save(sheet_path,quality=89,optimize=True)


def preview_process(server, rig, output, mode):
    result = subprocess.run(['node',str(PREVIEW_RENDERER),str(server),str(rig),str(output),str(mode)],
                            capture_output=True,text=True,encoding='utf-8')
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)


def render_stills(server, folder):
    stills = {}
    with tempfile.TemporaryDirectory(dir=folder) as location:
        preview_process(server,folder/'rig/character.obone',location,'stills')
        for path in Path(location).glob('*.png'):
            with Image.open(path) as posed:
                stills[path.stem] = posed.convert('RGBA')
    return stills


def render(mcp, folder, original, cleaned, server=None, face_mask=None):
    p = folder / 'previews'
    neutral = frame(mcp,scale=.5)
    a = np.asarray(cleaned.getchannel('A').resize(neutral.size,Image.Resampling.LANCZOS)) > 127
    b = np.asarray(neutral.getchannel('A')) > 127
    iou = (a&b).sum()/(a|b).sum()
    a_rgb = np.asarray(cleaned.resize(neutral.size,Image.Resampling.LANCZOS),dtype=np.int16)
    b_rgb = np.asarray(neutral,dtype=np.int16)
    solids = (a_rgb[...,3]>=246) & (b_rgb[...,3]>=246)
    if face_mask is not None:
        face_pixels = cv2.dilate(face_mask,np.ones((35,35),np.uint8))
        solids &= cv2.resize(face_pixels,neutral.size,interpolation=cv2.INTER_AREA) == 0
    rgb_mae = np.abs(a_rgb[solids,:3]-b_rgb[solids,:3]).mean()
    assert iou > .975 and rgb_mae < 4.5,(iou,rgb_mae)
    stills = render_stills(server,folder) if server else None
    if stills:
        neutral = stills['neutral']
        sampled = np.asarray(neutral.getchannel('A')) > 127
        assert (sampled & a).sum()/(sampled | a).sum() > .975
    neutral.save(p/'neutral.png',compress_level=7)

    comparison = Image.new('RGB',(488,268),'#111a2b')
    c = ImageDraw.Draw(comparison)
    c.text((12,8),'Master dari ZIP',font=font(16),fill='#ffdcaa')
    c.text((252,8),'Pose netral OpenBone',font=font(16),fill='#ffdcaa')
    put_pose(comparison,original,10,34,224)
    put_pose(comparison,neutral,249,34,224)
    comparison.save(p/'original_vs_reconstruction.jpg',quality=82,optimize=True)

    sample_times = {'idle':(.23,.49,.75),'happy':(.17,.41,.63),'pet':(.15,.40,.77),
                    'eat':(.24,.54,.71),'sleep':(.05,.27,.76),'play':(.24,.50,.66),'special':(.26,.44,.62)}
    sheet = Image.new('RGB',(476,752),'#111a2b')
    labels = ImageDraw.Draw(sheet)
    loop_matches = {}
    for i,(clip,(duration,loop)) in enumerate(CLIPS.items()):
        row = i*107+5
        labels.text((9,row+18),clip,font=font(18,title=True),fill='#ffdcaa')
        labels.text((9,row+45),f'{duration:g} s',font=font(14),fill='#cad6e8')
        for j,pose in enumerate(sample_times[clip]):
            picture = frame(mcp,scale=.18,animation=clip,time=duration*pose)
            put_pose(sheet,picture,96+j*124,row,103)
        if loop:
            a = frame(mcp,scale=.16,animation=clip,time=0)
            b = frame(mcp,scale=.16,animation=clip,time=duration)
            loop_matches[clip] = a.tobytes()==b.tobytes()
            assert loop_matches[clip],clip
    sheet.save(p/'contact_sheet.jpg',quality=85,optimize=True)
    if server:
        render_face_sheet(original,stills,p/'face_expressions.jpg',face_mask)
        preview_process(server,folder/'rig/character.obone',p,FPS)
    else:
        mcp.call('set_document',background='#1b2940')
    try:
        for clip,(duration,loop) in CLIPS.items():
            path = p / f'{clip}.gif'
            if not server:
                mcp.call('render_gif',animation=clip,fps=FPS,duration=duration,scale=.131,out=str(path))
            if not loop:
                remove_gif_loop(path)
            count,does_loop = gif_metadata(path)
            assert count==round(FPS*duration) and does_loop==loop,(clip,count,does_loop)
    finally:
        if not server:
            mcp.call('set_document',background='#00000000')
    rgb_key = 'outside_face_rgb_mean_absolute_error_0_255' if face_mask is not None else 'opaque_rgb_mean_absolute_error_0_255'
    return {'silhouette_iou_percent':round(iou*100,3),rgb_key:round(rgb_mae,3),'matching_loop_endpoints':loop_matches}


def manifest(item,folder,mcp,bounds,amp,features,report,measurements,repairs,machine_name,master,revision=None):
    base = {k:v for k,v in item.items() if k!='spec'}
    binary = folder / 'exports/character.obonb'
    mesh_results = report['clips']
    base.update({'schema_version':1,'artboard_px':[1024,1024],
                 'source_master':'source/original.png','source_sha256':digest(master),
                 'path_base':'directory of animation_manifest.json','tool':{'name':'OpenBone MCP','version':mcp.version},
                 'editable_rig':'rig/character.obone','exports':[{'path':'exports/character.obonb','format':'obonb',
                     'bytes':binary.stat().st_size,'sha256':digest(binary.read_bytes()),'embedded_atlas':True,
                     'atlas_resolution_scale':.5}],
                 'state_machine':{'name':machine_name,'entry':'idle','wake_trigger':'wake','head_click_trigger':'pet',
                                  'return_state':'idle','layer':'Motion'},
                 'animations':list(CLIPS),'clips':{name:{'file':'exports/character.obonb','format':'obonb','animation':name,
                     'state':name,'trigger':None if name=='idle' else name,'duration_seconds':duration,'loop':loop,
                     'preview':f'previews/{name}.gif','preview_fps':FPS} for name,(duration,loop) in CLIPS.items()},
                 'surface':{'attachment':SURFACE,'bones':list(item['spec']['parts']),
                            'layers':[f'layers/{name}.png' for name in bounds],'source_repairs':repairs,
                            'eyes_attachment':features[0],'mouth_attachment':features[1]},
                 'quality':{'metrics':measurements,'mcp_validation':'No issues found.','state_simulation':'passed',
                            'range_multiplier':amp,'samples_60_hz':sum(c['poses'] for c in mesh_results.values()),
                            'triangle_inversions_60_hz':sum(c['inversions'] for c in mesh_results.values()),
                            'mesh_triangles':report['meshTriangles'],'mesh_vertices':report['meshVertices'],
                            'clipped_pose':any(c['cropped'] for c in mesh_results.values()),
                            'neutral_preview':'previews/neutral.png','contact_sheet':'previews/contact_sheet.jpg',
                            'comparison':'previews/original_vs_reconstruction.jpg'},
                 'runtime_compatibility':{'android_device_verified':False,'local_playback':'self-contained OpenBone OBONB',
                                          'requires':'OpenBone weighted meshes, slots and state machines.'}})
    if reason:=REVIEW.get((item['monster_slug'],item['stage'])):
        base['release_status']='review_only'
        base['source_review_reason']=reason
    if revision:
        base['expression_revision'] = {**revision,'preview':'previews/face_expressions.jpg',
                                       'default_eyes':'eyes_open','default_mouth':'mouth_relaxed'}
    if (redrawn := folder/'source/redrawn.png').is_file():
        base['drawing_source'] = {'path':'source/redrawn.png','method':'ImageGen',
                                  'sha256':digest(redrawn.read_bytes())}
    (folder/'animation_manifest.json').write_text(json.dumps(base,indent=2)+'\n',encoding='utf-8')


def build_item(item, server, mcp, repair, expressions):
    key = (item['monster_slug'], item['stage'])
    final = OUT.joinpath(*key)
    imagegen = final/'source/redrawn.png'
    redrawn = expressions and key[1]=='adult' and key[0] in IMAGEGEN_GUIDES and imagegen.is_file()
    previous = None
    expression_revision = None
    if final.exists():
        if (final/'animation_manifest.json').exists():
            existing = json.loads((final/'animation_manifest.json').read_text(encoding='utf-8'))
            previous = existing.get('surface')
            if expressions and existing.get('expression_revision',{}).get('version') == expression_version(key,redrawn):
                return 'existing expression revision'
            if not expressions and (not repair or previous is None or (previous['eyes_attachment'] and previous['mouth_attachment'])):
                return 'existing'
        else:
            raise RuntimeError(f'Incomplete existing folder left intact: {final}')
    final.parent.mkdir(parents=True,exist_ok=True)
    with ZipFile(ARCHIVE) as archive:
        master = archive.read(item['source_asset'])
    with tempfile.TemporaryDirectory(prefix=f'.{key[1]}_',dir=final.parent) as temp:
        folder = Path(temp)/key[1]
        for sub in ('source','rig','layers','exports','previews'):
            (folder/sub).mkdir(parents=True)
        original,cleaned,repairs = load_art(master,item['source_asset'],folder)
        if redrawn:
            shutil.copyfile(imagegen,folder/'source/redrawn.png')
            cleaned = load_redrawn_art(imagegen)
            repairs.append('ImageGen sprite drawn with open eyes, normalized to the rig artboard.')
        if expressions:
            bounds,face_mask,expression_revision = prepare_expression_layers(cleaned,item['spec']['face'],folder,key,redrawn)
            eyes = mouth = True
        else:
            bounds,eyes,mouth,face_mask = prepare_layers(cleaned,item['spec']['face'],folder,key)
        features = eyes,mouth
        if previous and not expressions:
            before = previous['eyes_attachment'],previous['mouth_attachment']
            if before==features or any(old and not new for old,new in zip(before,features)):
                return f'existing eyes={before[0]} mouth={before[1]}'
        l,t,r,b = cleaned.getbbox()
        cropped = (max(l-2,1),max(t-2,1),min(r+2,1023),min(b+2,1023))
        # Include a transparent pixel ring around the textured mesh so atlasing cannot smear edge pixels.
        surface_file = folder/'layers'/f'{SURFACE}.png'
        with Image.open(surface_file) as part:
            padded = Image.new('RGBA',(cropped[2]-cropped[0],cropped[3]-cropped[1]))
            padded.paste(part,(l-cropped[0],t-cropped[1]))
        padded.save(surface_file,compress_level=5)
        bounds[SURFACE] = cropped
        origin,joints,parts,soft_body,fx = anatomy(item,cleaned.getbbox())
        mcp.call('new_project',name=f'{item["monster_name"]} {key[1].title()}',width=1024,height=1024,
                 originX=origin[0],originY=origin[1],background='#00000000')
        values,position = setup_rig(mcp,item,cleaned,bounds,joints,parts,soft_body,face_mask,origin,fx,expression_revision)
        rig = folder/'rig/character.obone'
        add_actions(mcp,item,values,parts,features,cropped,1.,True,expression_revision)
        name = machine(mcp,item)
        mcp.call('save_project',path=str(rig))
        for amp in (1.,.78,.57,.39,.24):
            if amp != 1.:
                add_actions(mcp,item,values,parts,features,cropped,amp,False)
            good,report = motion_check(server,rig)
            if good:
                break
        else:
            raise RuntimeError(f'Mesh quality failed: {report}')
        validation=mcp.call('validate')
        assert validation=='No issues found.',validation
        state_check(mcp,name,position)
        binary = folder/'exports/character.obonb'
        mcp.call('export_file',format='obonb',embed=True,pack=True,transparent=True,out=str(binary),
                 atlas={'scale':.5,'rotate':False,'padding':3,'duplicatePadding':True,'bleed':True})
        passed,report = motion_check(server,binary)
        assert passed,report
        measurements = render(mcp,folder,original,cleaned,server if expressions else None,face_mask if expressions else None)
        manifest(item,folder,mcp,bounds,amp,features,report,measurements,repairs,name,master,expression_revision)
        if previous:
            backup = Path(temp)/'previous_export'
            final.rename(backup)
            try:
                folder.rename(final)
            except OSError:
                backup.rename(final)
                raise
        else:
            folder.rename(final)
    return f'exported eyes={eyes} mouth={mouth} amplitude={amp:g}'


def run_group(items,server,repair,expressions):
    failures = []
    with OpenBone(['node',str(server),'--no-bridge']) as mcp:
        mcp.call('get_guide')
        for item in items:
            key = item['monster_slug'],item['stage']
            try:
                result=build_item(item,server,mcp,repair,expressions)
            except (AssertionError,OSError,ValueError,RuntimeError) as exc:
                print(f'{"/".join(key)} | FAILED {exc}',flush=True)
                failures.append((key,str(exc)))
            else:
                print(f'{"/".join(key)} | {result}',flush=True)
    return failures


def index_collection(items,failures):
    records = []
    failure_by_key = dict(failures)
    for item in items:
        key=item['monster_slug'],item['stage']
        row={k:v for k,v in item.items() if k!='spec'}
        manifest_path=OUT.joinpath(*key,'animation_manifest.json')
        if manifest_path.is_file():
            data=json.loads(manifest_path.read_text(encoding='utf-8'))
            art=data.get('surface',{'eyes_attachment':True,'mouth_attachment':True})
            row.update(status=data.get('release_status','exported'),manifest=manifest_path.relative_to(OUT).as_posix(),
                       eyes_attachment=art['eyes_attachment'],mouth_attachment=art['mouth_attachment'])
            if reason:=data.get('source_review_reason'):
                row['reason']=reason
            if revision:=data.get('expression_revision'):
                row['expression_revision']=revision['version']
                row['eyes_redrawn_open']=revision['eyes_redrawn_open']
        elif key in BLOCKERS:
            row.update(status='source_blocked',reason=BLOCKERS[key])
        elif key in failure_by_key:
            row.update(status='qa_blocked',reason=failure_by_key[key])
        else:
            row['status']='pending'
        records.append(row)
    groups = Counter(row['status'] for row in records)
    payload={'schema_version':1,'total_forms':len(items),'counts':dict(groups),'forms':records}
    (OUT/'collection_manifest.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Collection',dict(groups),'free bytes',shutil.disk_usage(OUT).free,flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server',type=Path,required=True,help='Installed @openbone/mcp/dist/bin.js')
    parser.add_argument('--workers',type=int,default=4)
    parser.add_argument('--slugs',nargs='+')
    parser.add_argument('--index-only',action='store_true')
    parser.add_argument('--repair-faces',action='store_true',help='Rebuild only if an existing face gains a verified attachment')
    parser.add_argument('--expressions',action='store_true',help='Redraw neutral and animated expressions from existing masters')
    parser.add_argument('--forms',nargs='+',help='Limit the batch to slug/stage pairs')
    parser.add_argument('--existing-only',action='store_true',help='Restrict the run to completed output folders')
    args=parser.parse_args()
    items=list(catalog())
    def needs_work(item):
        if item['spec'] is None or (args.slugs and item['monster_slug'] not in args.slugs):
            return False
        identity = item['monster_slug'],item['stage']
        if args.forms and '/'.join(identity) not in args.forms:
            return False
        if args.expressions and identity in REVIEW:
            return False
        path = OUT/item['monster_slug']/item['stage']/'animation_manifest.json'
        if not path.is_file():
            return not args.existing_only
        if args.expressions:
            current = json.loads(path.read_text(encoding='utf-8')).get('expression_revision',{})
            redrawn = (identity[1]=='adult' and identity[0] in IMAGEGEN_GUIDES and
                       (path.parent/'source/redrawn.png').is_file())
            return current.get('version') != expression_version(identity,redrawn)
        if not args.repair_faces:
            return False
        surface = json.loads(path.read_text(encoding='utf-8')).get('surface')
        return bool(surface and not (surface['eyes_attachment'] and surface['mouth_attachment']))

    targets=[] if args.index_only else [item for item in items if needs_work(item)]
    failures=[]
    if targets:
        n=min(max(args.workers,1),len(targets))
        with concurrent.futures.ThreadPoolExecutor(max_workers=n) as pool:
            futures=[pool.submit(run_group,targets[i::n],args.server,args.repair_faces,args.expressions) for i in range(n)]
            for future in concurrent.futures.as_completed(futures):
                failures.extend(future.result())
    index_collection(items,failures)
    return bool(failures)


if __name__=='__main__':
    raise SystemExit(main())
