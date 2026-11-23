"""Render OpenBone QA images and write the Embergon Baby handoff manifest."""

import base64
import io
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from embergon_art import ASSET, MASTER, ROOT, digest


MACHINE = 'EmbergonBaby'
PREVIEWS = ASSET / 'previews'
EXPORTS = ASSET / 'exports'
FPS = 25
CHOSEN_TIMES = {
    'idle': [0, .84, 1.64, 2.52, 3.4],
    'happy': [0, .18, .47, .78, 1.4],
    'pet': [0, .16, .43, .74, 1],
    'eat': [0, .25, .55, 1.29, 1.8],
    'sleep': [0, .9, 1.8, 2.7, 3.6],
    'play': [0, .46, .74, 1.19, 2],
    'special': [0, .47, .72, 1.02, 1.8],
}


def frame(mcp, scale=1, **pose):
    result = mcp.request('tools/call', {'name': 'render_frame', 'arguments': {
        **pose, 'showBones': False, 'showBoundingBoxes': False, 'scale': scale}})
    for part in result['content']:
        if part['type'] == 'image' and part['mimeType'] == 'image/png':
            return Image.open(io.BytesIO(base64.b64decode(part['data']))).convert('RGBA')
    raise RuntimeError(result)


def font(size, title=False):
    name = 'Fredoka-Bold.ttf' if title else 'Nunito-Variable.ttf'
    return ImageFont.truetype(ROOT / 'assets/fonts' / name, size)


def backdrop(size, checker=True):
    image = Image.new('RGB', size, '#172239')
    if checker:
        draw = ImageDraw.Draw(image)
        for y in range(0, size[1], 22):
            for x in range(0, size[0], 22):
                if (x//22 + y//22) % 2:
                    draw.rectangle((x, y, x+21, y+21), fill='#202d44')
    return image


def put_pose(sheet, pose, x, y, size):
    tile = backdrop((size, size))
    pose = pose.resize(tile.size, Image.Resampling.LANCZOS)
    tile.paste(pose, (0, 0), pose)
    sheet.paste(tile, (x, y))


def compare(original, rebuilt):
    sheet = Image.new('RGB', (1084, 630), '#111a2b')
    draw = ImageDraw.Draw(sheet)
    draw.text((30, 22), 'Embergon Baby', font=font(42, title=True), fill='#ffcf89')
    draw.text((32, 74), 'POSE NETRAL  /  MASTER ASLI DAN RENDER OPENBONE', font=font(19), fill='#b6c7dc')
    for i, (label, pose) in enumerate([('Original dari ZIP', original), ('Rekonstruksi OpenBone', rebuilt)]):
        x = 30 + i*528
        put_pose(sheet, pose, x, 116, 496)
        draw.rounded_rectangle((x+16, 132, x+250, 168), 10, fill='#111a2b')
        draw.text((x+28, 139), label, font=font(18), fill='#f3f5fa')
    sheet.save(PREVIEWS / 'original_vs_reconstruction.png', optimize=True)


def contact_sheet(frames, clips):
    cell = 184
    gutter = 10
    side = 160
    header = 92
    row = 220
    sheet = Image.new('RGB', (side+(cell+gutter)*5+12, header+row*len(clips)+10), '#111a2b')
    draw = ImageDraw.Draw(sheet)
    draw.text((28, 17), 'Embergon Baby', font=font(42, title=True), fill='#ffcf89')
    draw.text((32, 67), 'OPENBONE  /  POSE KUNCI  /  01 · FIRE DRAGON', font=font(17), fill='#b6c7dc')
    for r, clip in enumerate(clips):
        y = header+r*row
        name = clip['name']
        draw.text((28, y+19), name, font=font(27, title=True), fill='#ffdcaa')
        draw.text((30, y+55), f'{clip["duration"]:.2f} s', font=font(18), fill='#edf3fc')
        draw.text((30, y+83), 'Loop' if clip['loop'] else 'Satu kali', font=font(16), fill='#95a8c3')
        for column, (time, pose) in enumerate(frames[name]):
            x = side + (cell+gutter)*column
            put_pose(sheet, pose, x, y, cell)
            draw.text((x+8, y+cell+5), f'{time:.2f} s', font=font(15), fill='#b6c7dc')
    sheet.save(PREVIEWS / 'contact_sheet.png', optimize=True)


def check_alignment(original, neutral):
    a, b = (np.asarray(image).astype(np.int16) for image in (original, neutral))
    intersection = (a[..., 3] > 127) & (b[..., 3] > 127)
    union = (a[..., 3] > 127) | (b[..., 3] > 127)
    opaque = (a[..., 3] > 245) & (b[..., 3] > 245)
    intersection_pct = 100 * intersection.sum() / union.sum()
    rgb_error = np.abs(a[opaque, :3] - b[opaque, :3]).mean()
    assert intersection_pct > 98 and rgb_error < 6, (intersection_pct, rgb_error)
    return round(float(intersection_pct), 3), round(float(rgb_error), 3)


def check_states(mcp, clips):
    traces = {}
    state_steps = {'tap_face': [{'advance': .1, 'pointer': {'x': 645, 'y': 389, 'type': 'down'}},
                                {'advance': .24, 'pointer': {'x': 645, 'y': 389, 'type': 'up'}},
                                {'advance': 1.2}],
                   'tap_outside': [{'advance': .1, 'pointer': {'x': 50, 'y': 50, 'type': 'down'}},
                                   {'advance': .24, 'pointer': {'x': 50, 'y': 50, 'type': 'up'}}]}
    for clip in clips[1:]:
        name = clip['name']
        steps = [{'advance': .2}, {'fire': [clip['trigger']], 'advance': clip['duration'] + .3}]
        if name == 'sleep':
            steps += [{'advance': .3}, {'fire': ['wake'], 'advance': .4}]
        state_steps[name] = steps
    for name, steps in state_steps.items():
        traces[name] = mcp.call('simulate_state_machine', stateMachine=MACHINE, steps=steps)
    return traces


def remove_gif_loop(path):
    """The MCP GIF encoder always adds a Netscape loop extension."""
    data = path.read_bytes()
    marker = b'\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00'
    if marker in data:
        path.write_bytes(data.replace(marker, b'', 1))


def manifest(mcp, clips, metrics, exported):
    source = ASSET / 'source/original.png'
    payload = {
        'schema_version': 1,
        'monster_id': '01', 'monster_slug': 'fire_dragon', 'monster_name': 'Embergon',
        'stage': 'baby', 'element': 'fire', 'rarity': 'rare',
        'source_asset': MASTER, 'source_master': 'source/original.png', 'source_sha256': digest(source.read_bytes()),
        'artboard_px': [1024, 1024], 'skeleton_origin_px': [512, 870],
        'tool': {'name': 'OpenBone MCP', 'package': '@openbone/mcp', 'version': mcp.version},
        'editable_rig': 'rig/embergon_baby.obone',
        'exports': exported, 'path_base': 'directory of animation_manifest.json',
        'state_machine': {'name': MACHINE, 'entry': 'idle', 'wake_trigger': 'wake',
                          'head_click_trigger': 'pet', 'return_state': 'idle', 'layer': 'Motion'},
        'animations': [clip['name'] for clip in clips],
        'clips': {clip['name']: {'file': 'exports/embergon_baby.obonb', 'format': 'obonb',
                                'animation': clip['name'], 'state': clip['name'], 'trigger': clip['trigger'],
                                'duration_seconds': clip['duration'], 'loop': clip['loop'],
                                'preview': f'previews/{clip["name"]}.gif', 'preview_fps': FPS}
                  for clip in clips},
        'quality': {'measurements': metrics, 'neutral_preview': 'previews/neutral.png',
                    'contact_sheet': 'previews/contact_sheet.png',
                    'comparison': 'previews/original_vs_reconstruction.png'},
        'runtime_compatibility': {
            'requires': 'Weighted meshes, attachment timelines and OpenBone state machines (0.4.8 export).',
            'flutter_existing_renderer': 'MamPet rig.json / animations.json loader uses a different format.',
            'android_device_verified': False,
            'local_playback': 'Packed OBONB has an embedded texture atlas. Web preview is self-contained.',
        },
    }
    (ASSET / 'animation_manifest.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')


def deliver(mcp, clips, server):
    traces = check_states(mcp, clips)
    print('State machine:', json.dumps(traces), flush=True)
    for triggered in ('happy', 'pet', 'eat', 'play', 'special', 'sleep'):
        assert f'idle → {triggered}' in traces[triggered] and f'{triggered} → idle' in traces[triggered], traces[triggered]
    assert 'idle → pet' in traces['tap_face'] and 'pet → idle' in traces['tap_face'], traces
    assert '→ pet' not in traces['tap_outside'], traces
    mcp.call('set_document', background='#00000000')
    neutral = frame(mcp)
    neutral.save(PREVIEWS / 'neutral.png', optimize=True)
    original = Image.open(ASSET / 'source/original.png').convert('RGBA')
    silhouette, error = check_alignment(original, neutral)
    compare(original, neutral)
    frames = {}
    loops = {}
    for clip in clips:
        name = clip['name']
        frames[name] = [(time, frame(mcp, animation=name, time=time, scale=.5)) for time in CHOSEN_TIMES[name]]
        if clip['loop']:
            a, b = frames[name][0][1], frames[name][-1][1]
            loops[name] = a.tobytes() == b.tobytes()
            assert loops[name], name
        gif = PREVIEWS / f'{name}.gif'
        mcp.call('set_document', background='#1b2940')
        try:
            mcp.call('render_gif', animation=name, duration=clip['duration'], fps=FPS, scale=.4375, out=str(gif))
        finally:
            mcp.call('set_document', background='#00000000')
        if not clip['loop']:
            remove_gif_loop(gif)
        with Image.open(gif) as preview:
            assert preview.n_frames == round(FPS * clip['duration']), (name, preview.n_frames)
            assert (preview.info.get('loop') == 0) == clip['loop'], name
        print(f'Previewed {name}', flush=True)
    contact_sheet(frames, clips)
    binary = EXPORTS / 'embergon_baby.obonb'
    mcp.call('export_file', format='obonb', embed=True, pack=True, transparent=True, out=str(binary),
             atlas={'rotate': False, 'padding': 4, 'duplicatePadding': True, 'bleed': True})
    mesh_report = None
    if server:
        command = ['node', str(Path(__file__).with_name('embergon_mesh_check.mjs')), str(server), str(binary)]
        mesh_test = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', check=False)
        if mesh_test.returncode:
            raise RuntimeError(mesh_test.stderr or mesh_test.stdout)
        mesh_report = json.loads(mesh_test.stdout)
    web = PREVIEWS / 'interactive.html'
    mcp.call('export_file', format='web', singleFile=True, embed=True, pack=True, transparent=True,
             stateMachine=MACHINE, out=str(web))
    exported = [{'path': 'exports/embergon_baby.obonb', 'format': 'obonb', 'embedded_atlas': True},
                {'path': 'previews/interactive.html', 'format': 'openbone-web', 'self_contained': True}]
    for item in exported:
        path = ASSET / item['path']
        item.update({'bytes': path.stat().st_size, 'sha256': digest(path.read_bytes())})
    metrics = {'silhouette_iou_percent': silhouette, 'opaque_rgb_mean_absolute_error_0_255': error,
               'matching_loop_endpoints': loops, 'mcp_validation': 'No issues found.',
               'mcp_simulation': {'entry_exit_and_wake': True, 'head_tap': True, 'outside_tap_ignored': True}}
    if mesh_report:
        metrics['mesh_playback_60_hz'] = mesh_report
    manifest(mcp, clips, metrics, exported)
    print('QA:', json.dumps(metrics), flush=True)
