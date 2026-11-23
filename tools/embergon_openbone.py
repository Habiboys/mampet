"""Author and export Embergon Baby through the OpenBone MCP stdio protocol."""

import argparse
import json
import math
import os
import subprocess
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from embergon_art import ASSET, prepare_art


ARTBOARD_ORIGIN = (512, 870)
MACHINE = 'EmbergonBaby'
BODY = 'character_surface'
# Positions are artboard pixels. Orientations are world degrees counter-clockwise.
BONES = {
    'torso': ('root', 553, 729, 0, 115),
    'head': ('torso', 580, 574, 0, 145),
    'wing_left': ('torso', 431, 632, 161, 106),
    'wing_left_tip': ('wing_left', 330, 597, 174, 120),
    'wing_right': ('torso', 714, 636, 14, 63),
    'wing_right_tip': ('wing_right', 774, 620, -22, 90),
    'tail': ('torso', 399, 773, 191, 77),
    'tail_tip': ('tail', 316, 792, 169, 78),
    'arm_left': ('torso', 536, 668, -74, 120),
    'arm_right': ('torso', 679, 663, -77, 120),
    'foot_left': ('root', 481, 819, -16, 63),
    'foot_right': ('root', 717, 811, 20, 52),
}


class OpenBone:
    def __init__(self, command):
        self.command = command

    def __enter__(self):
        self.process = subprocess.Popen(self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        encoding='utf-8', text=True)
        self.serial = 0
        self.tool_names = set()
        hello = self.request('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                            'clientInfo': {'name': 'mampet-asset-pipeline', 'version': '1.0'}})
        self.version = hello['serverInfo']['version']
        self.send({'method': 'notifications/initialized'})
        cursor = None
        while True:
            page = self.request('tools/list', {'cursor': cursor} if cursor else {})
            self.tool_names.update(tool['name'] for tool in page['tools'])
            cursor = page.get('nextCursor')
            if not cursor:
                break
        return self

    def __exit__(self, *exc):
        self.process.stdin.close()
        self.process.wait(timeout=30)
        self.process.stdout.close()

    def send(self, message):
        self.process.stdin.write(json.dumps({'jsonrpc': '2.0', **message}) + '\n')
        self.process.stdin.flush()

    def request(self, method, params):
        self.serial += 1
        self.send({'id': self.serial, 'method': method, 'params': params})
        for line in self.process.stdout:
            message = json.loads(line)
            if message.get('id') != self.serial:
                continue
            if 'error' in message:
                raise RuntimeError(f'{method}: {message["error"]}')
            return message['result']
        raise RuntimeError(f'{method}: OpenBone process ended without returning a result')

    def call(self, tool, **arguments):
        if tool not in self.tool_names:
            raise ValueError(f'OpenBone MCP tool unavailable: {tool}')
        result = self.request('tools/call', {'name': tool, 'arguments': arguments})
        output = [part['text'] for part in result['content'] if part['type'] == 'text']
        if result.get('isError'):
            raise RuntimeError(f'{tool}: {output}')
        if len(output) != 1:
            return output
        try:
            return json.loads(output[0])
        except ValueError:
            return output[0]


def smooth(start, end, value):
    t = clamp((value - start) / (end - start))
    return t * t * (3 - 2 * t)


def clamp(value):
    return max(0., min(1., value))


def weights_at(x, y, band):
    chin = np.interp(x, [128, 300, 370, 410, 450, 490, 557, 630, 695, 760, 805, 895],
                     [454, 485, 502, 529, 556, 575, 592, 599, 594, 581, 556, 505])
    head = 1 - smooth(chin + 1, chin + 66, y)
    left_limit = np.interp(y, [515, 563, 615, 655, 695, 719], [370, 402, 466, 440, 412, 397])
    left = (1 - smooth(left_limit - 58, left_limit + 12, x))
    left *= smooth(492, 553, y) * (1 - smooth(697, 740, y))
    right_limit = np.interp(y, [565, 610, 647, 684, 719], [755, 729, 692, 713, 786])
    right = smooth(right_limit - 9, right_limit + 75, x)
    right *= smooth(550, 605, y) * (1 - smooth(706, 750, y))
    tail_limit = np.interp(y, [715, 764, 822, 890], [380, 381, 364, 391])
    tail = (1 - smooth(tail_limit - 44, tail_limit + 18, x)) * smooth(706, 750, y)

    if band is not None:
        outer_left = 1 - smooth(348, 417, x)
        outer_right = smooth(795, 844, x)
        outer_tail = 1 - smooth(342, 383, x)
        if band == 0:
            head = max(head, smooth(770, 819, x))
        else:
            head *= 1 - max(outer_left, outer_right)
        left = left * (1 - outer_left) + outer_left * (band == 1)
        right = right * (1 - outer_right) + outer_right * (band == 1)
        tail = tail * (1 - outer_tail) + outer_tail * (band == 2)
    left_tip, right_tip, tail_tip = (1 - smooth(197, 385, x), smooth(744, 879, x), 1 - smooth(246, 356, x))

    def limb(cx, cy, rx, ry, amount):
        d = math.hypot((x - cx) / rx, (y - cy) / ry)
        return amount * (1 - smooth(.3, 1., d))

    body = 1 - head
    groups = {
        'head': head,
        'wing_left': body * left * (1 - left_tip),
        'wing_left_tip': body * left * left_tip,
        'wing_right': body * right * (1 - right_tip),
        'wing_right_tip': body * right * right_tip,
        'tail': body * tail * (1 - tail_tip),
        'tail_tip': body * tail * tail_tip,
        'arm_left': body * limb(553, 767, 69, 105, .90),
        'arm_right': body * limb(683, 767, 43, 96, .83),
        'foot_left': body * limb(478, 850, 96, 72, .95),
        'foot_right': body * limb(732, 838, 72, 64, .94),
    }
    groups['torso'] = max(0., 1 - sum(groups.values()))
    strongest = sorted(groups.items(), key=lambda group: -group[1])[:4]
    total = sum(weight for _, weight in strongest if weight >= .003)
    return [{'bone': bone, 'weight': round(weight / total, 6)} for bone, weight in strongest if weight >= .003]


def surface_mesh(box):
    x0, y0, x1, y1 = box
    alpha = np.asarray(Image.open(ASSET / 'layers' / f'{BODY}.png').getchannel('A'))
    coverage = cv2.dilate(alpha, np.ones((3, 3), dtype=np.uint8))
    nx = 30
    bands = (17, 8, 7)
    grid = {}
    vertices, uv, triangles, influences = [], [], [], []

    def location(i, band, j):
        x = x0 + i / nx * (x1-x0)
        a = np.interp(x, [128, 250, 290, 320, 345, 373, 384, 396, 411, 436, 465, 495, 700, 758, 794, 805, 819, 845, 896],
                      [490, 493, 501, 502, 505, 518, 538, 548, 592, 605, 616, 599, 603, 590, 578, 575, 576, 567, 565])
        b = np.interp(x, [128, 204, 230, 250, 276, 294, 317, 344, 367, 382, 440, 762, 896],
                      [696, 691, 690, 699, 718, 712, 716, 710, 722, 725, 730, 746, 750])
        edges = (y0, a, b, y1)
        y = edges[band] + j / bands[band] * (edges[band+1] - edges[band])
        return x, y

    def vertex(i, band, j):
        x, y = location(i, band, j)
        boundary = band if j == 0 and band > 0 else band + 1 if j == bands[band] and band < 2 else None
        # Split the boundary vertices only in transparent gaps between branches.
        split = (boundary == 1 and (x < 413 or x > 803)) or (boundary == 2 and x < 375)
        key = (i, band, j) if boundary is None or split else (i, 'edge', boundary)
        if key not in grid:
            index = len(vertices) // 2
            grid[key] = index
            vertices.extend([x - ARTBOARD_ORIGIN[0], ARTBOARD_ORIGIN[1] - y])
            uv.extend([(x-x0)/(x1-x0), (y-y0)/(y1-y0)])
            influences.append({'vertex': index, 'influences': weights_at(x, y, band if boundary is None or split else None)})
        return grid[key]

    def keep_triangle(points):
        xy = np.asarray([(round(x-x0), round(y-y0)) for x, y in points], dtype=np.int32)
        low, high = xy.min(axis=0), xy.max(axis=0)
        mask = np.zeros((high[1]-low[1]+1, high[0]-low[0]+1), dtype=np.uint8)
        cv2.fillConvexPoly(mask, xy-low, 1)
        limit_x, limit_y = min(high[0]+1, alpha.shape[1]), min(high[1]+1, alpha.shape[0])
        sample = coverage[low[1]:limit_y, low[0]:limit_x]
        return np.any(mask[:sample.shape[0], :sample.shape[1]] * sample)

    for band, rows in enumerate(bands):
        for j in range(rows):
            for i in range(nx):
                a, b, c, d = ((i, band, j), (i+1, band, j), (i, band, j+1), (i+1, band, j+1))
                for tri in ((a, c, b), (b, c, d)):
                    if keep_triangle([location(*point) for point in tri]):
                        triangles.extend(vertex(*point) for point in tri)
    return vertices, uv, triangles, influences


def setup(mcp, bounds):
    for name, (parent, x, y, angle, length) in BONES.items():
        _, x0, y0, parent_angle, _ = BONES.get(parent, (None, *ARTBOARD_ORIGIN, 0, 0))
        theta = math.radians(parent_angle)
        dx, dy = x - x0, y0 - y
        mcp.call('add_bone', name=name, id=name, parent=parent, length=length, rotation=angle-parent_angle,
                 x=dx * math.cos(theta) + dy * math.sin(theta), y=-dx * math.sin(theta) + dy * math.cos(theta))
    for name, bone in [('surface', 'root'), ('eyes', 'head'), ('mouth', 'head'), ('touch', 'head')]:
        mcp.call('add_slot', name=name, id=name, bone=bone)
    for name in bounds:
        mcp.call('import_image', name=name, path=str(ASSET / 'layers' / f'{name}.png'))
    vertices, uv, triangles, weights = surface_mesh(bounds[BODY])
    mcp.call('add_mesh', slot='surface', image=BODY, name=BODY, activate=True, vertices=vertices,
             uvs=uv, triangles=triangles, hull=0)
    mcp.call('set_mesh_weights', slot='surface', attachment=BODY, vertices=weights)
    for name, (x0, y0, x1, y1) in bounds.items():
        if name == BODY:
            continue
        slot = name.split('_')[0]
        mcp.call('add_region', slot=slot, image=name, name=name,
                 x=(x0+x1)/2-BONES['head'][1], y=BONES['head'][2]-(y0+y1)/2,
                 activate=name in ('eyes_open', 'mouth_happy'))
    pixels = [(452,355),(511,300),(672,297),(764,354),(818,432),(805,508),(738,560),
              (617,581),(489,550),(418,492),(426,406)]
    hit = [coordinate for x, y in pixels for coordinate in (x-580, 574-y)]
    mcp.call('add_bounding_box', slot='touch', name='face_touch', vertices=hit, activate=True)
    return len(vertices) // 2, len(triangles) // 3


def track(mcp, animation, target, name, property_, points, baseline=0.):
    keys = []
    for time, value, *curve in points:
        if target == 'slot':
            keys.append({'time': time, 'value': value, 'curve': 'stepped'})
        else:
            keys.append({'time': time, 'value': round(baseline + value, 6),
                         'curve': curve[0] if curve else 'easeInOut'})
    mcp.call('set_keys', animation=animation, target=target, id=name, property=property_, keys=keys, replace=True)


def animate(mcp, clip):
    name = clip['name']
    mcp.call('create_animation', name=name, id=name, duration=clip['duration'])
    for bone, channels in clip['bones'].items():
        parent, _, _, angle, _ = BONES.get(bone, (None, 0, 0, 0, 0))
        parent_angle = BONES[parent][3] if parent in BONES else 0
        for property_, points in channels.items():
            if property_ == 'rotation':
                baseline = angle - parent_angle
            elif property_ in ('scaleX', 'scaleY'):
                baseline = 1
            elif property_ in ('x', 'y') and bone in BONES:
                _, x, y, _, _ = BONES[bone]
                _, p_x, p_y, _, _ = BONES.get(parent, (None, *ARTBOARD_ORIGIN, 0, 0))
                angle_r = math.radians(parent_angle)
                dx, dy = x-p_x, p_y-y
                baseline = (dx*math.cos(angle_r) + dy*math.sin(angle_r) if property_ == 'x'
                            else -dx*math.sin(angle_r) + dy*math.cos(angle_r))
            else:
                baseline = 0
            track(mcp, name, 'bone', bone, property_, points, baseline)
    for slot, points in clip['face'].items():
        track(mcp, name, 'slot', slot, 'attachment', points)


def state_machine(mcp, clips):
    mcp.call('create_state_machine', name=MACHINE, id=MACHINE, layerName='Motion')
    for clip in clips:
        name = clip['name']
        mcp.call('add_state', stateMachine=MACHINE, name=name, id=f'state_{name}', animation=name,
                 loop=clip['loop'], x=clip['graph'][0], y=clip['graph'][1])
    for clip in clips[1:]:
        name = clip['name']
        trigger = clip['trigger']
        mcp.call('add_input', stateMachine=MACHINE, type='trigger', name=trigger)
        mcp.call('add_transition', stateMachine=MACHINE, to=name, duration=.11 if name == 'sleep' else .08,
                 conditions=[{'input': trigger}], **{'from': '@any'})
        if not clip['loop']:
            mcp.call('add_transition', stateMachine=MACHINE, to='idle', duration=.12, exitTime=1, **{'from': name})
    mcp.call('add_input', stateMachine=MACHINE, type='trigger', name='wake')
    mcp.call('add_transition', stateMachine=MACHINE, to='idle', duration=.13,
             conditions=[{'input': 'wake'}], **{'from': '@any'})
    mcp.call('add_listener', stateMachine=MACHINE, name='Pet on face click', slot='touch', event='click',
             actions=[{'type': 'fireTrigger', 'input': 'pet'}])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, help='Path to the installed @openbone/mcp dist/bin.js')
    parser.add_argument('--resume', action='store_true', help='Open existing rig and repeat verification and export')
    parser.add_argument('--rebuild', action='store_true', help='Regenerate the OpenBone rig from the authoring sources')
    parser.add_argument('--rig-only', action='store_true', help='Stop after saving the editable rig')
    args = parser.parse_args()
    npx = 'npx.cmd' if os.name == 'nt' else 'npx'
    command = ['node', str(args.server), '--no-bridge'] if args.server else [npx, '-y', '@openbone/mcp@0.4.8', '--no-bridge']
    clips = json.loads((Path(__file__).with_name('embergon_clips.json')).read_text(encoding='utf-8'))
    project = ASSET / 'rig/embergon_baby.obone'
    with OpenBone(command) as mcp:
        mcp.call('get_guide')
        print(f'OpenBone MCP {mcp.version} | {len(mcp.tool_names)} tools', flush=True)
        if args.resume:
            mcp.call('open_project', path=str(project))
        else:
            if project.exists() and not args.rebuild:
                parser.error('An editable rig already exists. Use --resume for exports or --rebuild to regenerate it.')
            bounds = prepare_art()
            mcp.call('new_project', name='MamPet · Embergon Baby', path=str(project), width=1024, height=1024,
                     originX=ARTBOARD_ORIGIN[0], originY=ARTBOARD_ORIGIN[1], background='#00000000', overwrite=args.rebuild)
            mcp.call('set_document', fps=30)
            print('Surface:', setup(mcp, bounds), flush=True)
            for clip in clips:
                animate(mcp, clip)
                print(f'Keyframed {clip["name"]}', flush=True)
            state_machine(mcp, clips)
            print(mcp.call('save_project'), flush=True)
        validation = mcp.call('validate')
        print('Validation:', validation, flush=True)
        if validation != 'No issues found.':
            raise RuntimeError(validation)
        if not args.rig_only:
            from embergon_preview import deliver
            deliver(mcp, clips, args.server)


if __name__ == '__main__':
    main()
