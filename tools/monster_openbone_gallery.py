"""Validate collection deliverables and assemble the four collection preview sheets."""

import hashlib
import json
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/animated_monsters'
CLIPS = ('idle','happy','pet','eat','sleep','play','special')
STAGES = ('baby','young','adult')


def font(size, title=False):
    file = 'Fredoka-Bold.ttf' if title else 'Nunito-Variable.ttf'
    return ImageFont.truetype(ROOT/'assets/fonts'/file,size)


def gif_metadata(path):
    data = path.read_bytes()
    assert data.startswith((b'GIF87a',b'GIF89a')),path
    flags = data[10]
    offset = 13 + (3 * 2**((flags&7)+1) if flags&128 else 0)
    frames,loop = 0,False
    while offset < len(data):
        tag = data[offset]
        if tag==0x3b:
            return frames,loop
        if tag==0x21:
            loop |= data[offset+2:offset+18]==b'\x0bNETSCAPE2.0\x03\x01\x00\x00'
            offset += 2
        elif tag==0x2c:
            frames += 1
            flags = data[offset+9]
            offset += 11 + (3 * 2**((flags&7)+1) if flags&128 else 0)
        else:
            raise ValueError(f'Unexpected GIF block {tag} in {path}')
        while data[offset]:
            offset += data[offset]+1
        offset += 1
    raise ValueError(f'GIF has no trailer: {path}')


def verify_form(root, record):
    manifest_path = root / record['manifest']
    folder = manifest_path.parent
    data = json.loads(manifest_path.read_text(encoding='utf-8'))
    assert data['stage']==record['stage'] and data['monster_slug']==record['monster_slug']
    assert list(data['clips'])==list(CLIPS)
    assert (folder/data['editable_rig']).is_file()
    assert hashlib.sha256((folder/data['source_master']).read_bytes()).hexdigest()==data['source_sha256']
    if drawing:=data.get('drawing_source'):
        path = folder/drawing['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==drawing['sha256']
        with Image.open(path) as png:
            assert png.format=='PNG' and png.mode=='RGBA'
            png.verify()
    for export in data['exports']:
        path = folder/export['path']
        assert path.stat().st_size==export['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==export['sha256']
    for name,metadata in data['clips'].items():
        assert (folder/metadata['file']).is_file()
        frames,loop = gif_metadata(folder/metadata['preview'])
        assert frames == round(metadata['duration_seconds']*metadata['preview_fps']),name
        assert loop==metadata['loop'],name
    for preview in ('contact_sheet','comparison','neutral_preview'):
        with Image.open(folder/data['quality'][preview]) as picture:
            picture.verify()
    if revision:=data.get('expression_revision'):
        with Image.open(folder/revision['preview']) as face_sheet:
            face_sheet.verify()
        assert revision['default_eyes']=='eyes_open' and revision['default_mouth']=='mouth_relaxed'
        assert (folder/'layers/eyes_open.png').is_file() and (folder/'layers/mouth_open.png').is_file()
    return manifest_path, data


def thumb(record,kind):
    manifest, data = record['manifest_data']
    folder = manifest.parent
    with Image.open(folder/data['quality']['contact_sheet']) as rendered:
        row = list(CLIPS).index(kind)
        if rendered.format=='JPEG':
            x,y,size=220,row*107+5,103
        else:
            x,y,size=160+194,row*220+92,184
        return rendered.crop((x,y,x+size,y+size)).convert('RGBA')


def sheet(records, number, output):
    cell_x,cell_y = 344,188
    sheet = Image.new('RGB',(1064,96+5*cell_y),'#111a2b')
    d = ImageDraw.Draw(sheet)
    d.text((20,11),'Koleksi animasi MamPet',font=font(29,title=True),fill='#ffcf89')
    for i,stage in enumerate(STAGES):
        d.text((22+i*cell_x,58),stage.title(),font=font(19,title=True),fill='#e4edf9')
    for index,row in enumerate(records):
        x = 18+(index%3)*cell_x
        y = 92+(index//3)*cell_y
        record = row
        if index%3==0:
            d.text((x,y),f'{record["monster_id"]}  {record["monster_name"]}',font=font(17,title=True),fill='#ffdca6')
        d.rounded_rectangle((x,y+27,x+329,y+175),10,fill='#1b2940')
        if 'manifest_data' not in record:
            d.text((x+12,y+75),'Master perlu koreksi',font=font(16),fill='#ffd0af')
            continue
        if record['status']=='review_only':
            d.text((x+92,y),'Tinjauan sumber',font=font(14),fill='#ffc285')
        for column,clip in enumerate(('sleep','special')):
            pose = thumb(record,clip)
            left = x+11+column*160
            sheet.paste(pose.resize((120,120),Image.Resampling.LANCZOS),(left,y+30))
            d.text((left+5,y+151),clip,font=font(13),fill='#c1d1e7')
    sheet.save(output/f'collection_{number:02}.jpg',quality=87,optimize=True)


def expressions_sheet(records, number, output):
    stride_x, stride_y, tile = 335, 133, 96
    sheet = Image.new('RGB',(1024,83+5*stride_y),'#111a2b')
    draw = ImageDraw.Draw(sheet)
    draw.text((13,8),'Ekspresi MamPet',font=font(25,title=True),fill='#ffcf89')
    for stage, name in enumerate(STAGES):
        x = 12+stage*stride_x
        draw.text((x,45),name.title(),font=font(16,title=True),fill='#edf3fb')
        for col, name in enumerate(('Master','Mata terbuka','Makan')):
            draw.text((x+col*105,65),name,font=font(13),fill='#91abc8')
    for i,record in enumerate(records):
        x,y = 12+(i%3)*stride_x,86+(i//3)*stride_y
        if i%3==0:
            draw.text((x,y),record['monster_name'],font=font(16,title=True),fill='#ffcf89')
        value = record.get('manifest_data')
        if value and (revision:=value[1].get('expression_revision')):
            with Image.open(value[0].parent/revision['preview']) as render:
                for col,(sx,sy) in enumerate(((8,8),(157,8),(157,172))):
                    head = render.crop((sx,sy,sx+136,sy+136)).resize((tile,tile),Image.Resampling.LANCZOS)
                    sheet.paste(head,(x+col*105,y+24))
        else:
            label = 'Tinjauan sumber' if record['status']=='review_only' else 'Master perlu koreksi'
            if value and record['status']=='exported':
                label = 'Rig pilot' if record['monster_slug']=='fire_dragon' and record['stage']=='baby' else 'Ekspresi versi awal'
            draw.text((x,y+35),label,font=font(14),fill='#b6c7dc')
    sheet.save(output/f'expressions_{number:02}.jpg',quality=89,optimize=True)


def main():
    data = json.loads((OUT/'collection_manifest.json').read_text(encoding='utf-8'))
    output = OUT/'previews'
    output.mkdir(exist_ok=True)
    counters = Counter()
    for record in data['forms']:
        counters[record['status']] += 1
        if 'manifest' in record:
            record['manifest_data']=verify_form(OUT,record)
            counters['expressions_both'] += bool(record['eyes_attachment'] and record['mouth_attachment'])
            counters['eyes'] += bool(record['eyes_attachment'])
            counters['mouth'] += bool(record['mouth_attachment'])
            if revision:=record['manifest_data'][1].get('expression_revision'):
                counters['expression_revision'] += 1
                counters['eyes_redrawn_open'] += bool(revision['eyes_redrawn_open'])
                counters['mouth_cavity_redrawn'] += bool(revision['mouth_cavity_redrawn'])
    for i in range(4):
        records = data['forms'][i*15:(i+1)*15]
        sheet(records,i+1,output)
        if counters['expression_revision']:
            expressions_sheet(records,i+1,output)
    print(json.dumps(counters,ensure_ascii=False))


if __name__=='__main__':
    main()
