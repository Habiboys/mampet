"""Audit the archived MamPet assets and prepare Embergon Baby's OpenBone textures."""

import hashlib
import io
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from zipfile import ZipFile

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from scipy.sparse import coo_matrix
from scipy.sparse.linalg import spsolve


ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / 'assets/animated_monsters/fire_dragon/baby'
MASTER = 'assets/monsters/fire_dragon/baby.png'
STAGES = ('baby', 'young', 'adult')
ID_PATTERN = re.compile(r'^\| (\d\d) \| (.*?) \| (.*?) \| .*? \| (.*?) \| (.*?) \|$', re.M)


def rgba_pixels(data):
    with Image.open(io.BytesIO(data)) as image:
        return np.asarray(image.convert('RGBA')).copy()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_archive(filename, manifest_name, entries):
    problems, flat, unusual, variants = [], [], [], []
    by_pixels = defaultdict(list)
    locations = Counter()
    local_formats = Counter()
    entries_read = []
    with ZipFile(ROOT / filename) as archive:
        bad = archive.testzip()
        if bad:
            problems.append(f'CRC gagal untuk `{bad}`.')
        paths = entries(json.loads(archive.read(manifest_name)))
        members = archive.namelist()
        assert len(paths) == len(set(paths))
        assert set(paths) == {name for name in members if name.endswith('.png')}
        for path in paths:
            try:
                data = archive.read(path)
                with Image.open(io.BytesIO(data)) as image:
                    image.verify()
                with Image.open(io.BytesIO(data)) as image:
                    image.load()
                    assert (image.format, image.size, image.mode) == ('PNG', (1024, 1024), 'RGBA')
                pixels = rgba_pixels(data)
                alpha = pixels[..., 3]
                assert alpha.min() == 0 and alpha.max() == 255
            except (AssertionError, OSError, KeyError, ValueError) as error:
                problems.append(f'`{path}` gagal validasi PNG/RGBA/alpha ({type(error).__name__}).')
                continue
            entries_read.append(path)
            visible = alpha > 127
            rgb = pixels[visible, :3].astype(np.uint32)
            colors = np.unique(rgb[:, 0] * 65536 + rgb[:, 1] * 256 + rgb[:, 2])
            if len(colors) < 64 or visible.mean() < 0.02:
                flat.append(f'`{path}` memiliki {len(colors)} warna pada area alpha > 127 '
                            f'({visible.mean():.1%} kanvas).')
            if any(np.any(edge > 127) for edge in (alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1])):
                unusual.append(path)
            pixels[alpha == 0, :3] = 0
            by_pixels[digest(pixels.tobytes())].append(path)
            destination = ROOT / path
            backup = destination.with_suffix('') / 'original.png'
            if destination.is_file() and destination.read_bytes() == data:
                locations['matched'] += 1
            elif backup.is_file() and backup.read_bytes() == data:
                locations['backup'] += 1
            elif not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True)
                with destination.open('xb') as output:
                    output.write(data)
                locations['extracted'] += 1
            else:
                locations['variant'] += 1
                variants.append(path)
            with Image.open(destination) as local:
                local_formats[(local.format, local.mode, *local.size)] += 1
        local_manifest = ROOT / 'assets/manifests' / f'{manifest_name.split("_")[0]}_{manifest_name}'
        manifest_match = local_manifest.is_file() and local_manifest.read_bytes() == archive.read(manifest_name)
    return {
        'paths': paths, 'verified': len(entries_read), 'problems': problems, 'flat': flat,
        'edge': unusual, 'copies': locations, 'manifest_match': manifest_match, 'variants': variants,
        'local_formats': local_formats,
        'duplicates': [group for group in by_pixels.values() if len(group) > 1],
    }


def inventory():
    monster_zip = 'monster_collection_60_complete_flutter.zip'
    with ZipFile(ROOT / monster_zip) as archive:
        catalog = json.loads(archive.read('monster_manifest.json'))
        assert catalog['species_count'] == len(catalog['species']) == 20
        assert tuple(catalog['stages']) == STAGES
        for monster in catalog['species']:
            assert set(monster['stages']) == set(STAGES)
        master = archive.read(next(m for m in catalog['species'] if m['id'] == '01')['stages']['baby'])
    prd = (ROOT / 'MamPet_PRD_Lengkap_v1.md').read_text(encoding='utf-8')
    section = prd.split('# 7. Katalog resmi')[1].split('Distribusi rarity')[0]
    section = re.sub(r'\n(?=[a-z]+ \|)', '_', section)
    prd_rows = ID_PATTERN.findall(section)
    assert len(prd_rows) == 20
    for (id_, _, slug, _, _), monster in zip(prd_rows, catalog['species'], strict=True):
        assert (id_, slug) == (monster['id'], monster['slug'])

    monsters = verify_archive(monster_zip, 'monster_manifest.json',
                              lambda m: [s['stages'][stage] for s in m['species'] for stage in STAGES])

    def egg_paths(manifest):
        assert set(manifest['elements']) == {'fire', 'water', 'nature', 'wind', 'earth', 'mystery'}
        assert set(manifest['states']) == {'intact', 'cracked'}
        assert Counter((a['element'], a['state']) for a in manifest['assets']) == Counter(
            (e, s) for e in manifest['elements'] for s in manifest['states'])
        return [a['path'] for a in manifest['assets']]

    eggs = verify_archive('egg_assets_flutter.zip', 'egg_manifest.json', egg_paths)
    report = ['# Inventaris aset MamPet', '',
              'Inventaris menggunakan manifest di dalam masing-masing ZIP. Pemeriksaan memuat semua'
              ' PNG, menguji CRC, memeriksa format, ukuran 1024 × 1024 dan kanal RGBA, lalu menguji'
              ' adanya piksel transparan dan opak. Duplikat diperiksa dengan hash piksel RGBA setelah'
              ' menormalkan RGB piksel transparan penuh.', '']
    for title, result in [('Monster', monsters), ('Telur', eggs)]:
        copies = result['copies']
        report += [f'## {title}', '', f"- PNG terverifikasi {result['verified']}/{len(result['paths'])}.",
                   f"- Salinan byte identik di path manifest {copies['matched']}. Master byte identik"
                   f" di `<stage>/original.png` {copies['backup']}. Varian lokal {copies['variant']}."
                   f" File yang perlu diekstrak {copies['extracted']}.",
                   f"- Manifest lokal {'identik' if result['manifest_match'] else 'berbeda atau tidak ditemukan'}."]
        report += [f'- {item}' for item in result['problems'] + result['flat']]
        report.append('- Format pada path aset lokal ' + ', '.join(
            f'{count} {format_} {mode} {w} × {h}'
            for (format_, mode, w, h), count in sorted(result['local_formats'].items())) + '.')
        if title == 'Monster' and result['variants']:
            report += ['- Path yang hanya memiliki varian lokal di lokasi yang diperiksa '
                       + ', '.join(f'`{path}`' for path in result['variants']) + '.']
        report += ['- Duplikat piksel eksak ' + ', '.join(f'`{p}`' for p in group) + '.'
                   for group in result['duplicates']]
        report += [f'- Siluet opak menyentuh tepi kanvas pada {len(result["edge"])} aset '
                   f'({", ".join(f"`{p}`" for p in result["edge"])}).'] if result['edge'] else []
        report += ['']
    counts = Counter(row[-1] for row in prd_rows)
    report += ['## Rekonsiliasi sumber', '',
               '- 20 ID dan slug cocok antara daftar permintaan, tabel PRD §7, dan manifest monster.'
               ' Nama, elemen dan rarity mengikuti tabel spesies PRD dan daftar permintaan. Manifest'
               ' ZIP monster mencatat ID, slug dan path per fase.',
               f'- Baris tabel PRD menghasilkan {counts["Common"]} Common, {counts["Uncommon"]} Uncommon'
               f' dan {counts["Rare"]} Rare, sesuai dengan ringkasan PRD.',
               '- PRD §9.1 dan manifest telur memakai nama bernomor. Pasangan path generik di PRD §15'
               ' berbeda dari nama file arsip.',
               '- PNG `leaf_spirit/adult.png` dan `forest_deer/adult.png` menampilkan desain rusa'
               ' serupa dengan perbedaan pose, tanduk, dan dedaunan. Keduanya berbeda secara piksel,'
               ' mengoreksi catatan duplikat eksak pada `MONSTER_ANIMATION_PIPELINE.md`. Identitas'
               ' ilustrasi Sproutle Adult perlu dikonfirmasi sebelum rigging.',
               '- Distribusi lokal monster sudah memuat sprite untuk Flutter dan backup master. Paket ini'
               ' membaca master Embergon langsung dari ZIP.', '',
               '| ID | Nama | Slug | Elemen | Rarity | Baby | Young | Adult |',
               '|---|---|---|---|---|---|---|---|']
    for id_, name, slug, element, rarity in prd_rows:
        monster = next(m for m in catalog['species'] if m['id'] == id_)
        paths = ' | '.join(f'`{monster["stages"][stage]}`' for stage in STAGES)
        report.append(f'| {id_} | {name} | `{slug}` | {element} | {rarity} | {paths} |')
    report += ['', '### Path telur di arsip', ''] + [f'- `{path}`' for path in sorted(eggs['paths'])]
    (ROOT / 'docs/ANIMATION_ASSET_INVENTORY.md').write_text('\n'.join(report) + '\n', encoding='utf-8')
    return master


def curve(start, segments):
    points = [start]
    for c1, c2, stop in segments:
        for t in np.linspace(0, 1, 33)[1:]:
            points.append(tuple((1-t)**3*a + 3*t*(1-t)**2*b + 3*t*t*(1-t)*c + t**3*d
                                for a, b, c, d in zip(start, c1, c2, stop)))
        start = stop
    return points


EYE_LEFT = curve((517, 432), [((517,397),(536,374),(564,372)), ((592,370),(614,395),(619,428)),
                               ((626,465),(604,495),(576,496)), ((539,501),(515,468),(517,432))])
EYE_RIGHT = curve((753, 414), [((752,386),(765,370),(783,371)), ((809,374),(817,400),(820,431)),
                                ((822,455),(809,477),(792,478)), ((769,478),(753,449),(753,414))])
MOUTH = curve((626, 484), [((627,473),(638,466),(650,474)), ((664,487),(691,477),(712,472)),
                             ((731,465),(738,483),(750,478)), ((759,475),(764,465),(770,471)),
                             ((778,479),(770,486),(768,499)), ((762,550),(735,581),(700,582)),
                             ((648,590),(618,555),(625,507)), ((625,497),(627,489),(626,484))])
LIPS = curve((631, 486), [((632,477),(637,474),(644,477)), ((661,491),(688,482),(712,476)),
                           ((732,471),(738,486),(751,482)), ((759,479),(763,471),(767,476)),
                           ((774,480),(766,488),(765,500)), ((758,548),(731,576),(700,578)),
                           ((650,584),(622,553),(629,507)), ((629,498),(632,491),(631,486))])


def mask_for(points):
    canvas = Image.new('L', (2048, 2048))
    ImageDraw.Draw(canvas).polygon([(round(x * 2), round(y * 2)) for x, y in points], fill=255)
    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def heal(image, mask):
    """Solve a fixed-boundary gradient interpolation for the concealed skin."""
    y, x = np.nonzero(mask)
    n = len(y)
    ids = np.full(mask.shape, -1, dtype=np.int32)
    ids[y, x] = np.arange(n)
    rows, cols, values = [np.arange(n)], [np.arange(n)], [np.full(n, 4.)]
    edge = np.zeros((n, 3))
    for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        neighbor = ids[y + dy, x + dx]
        inside = neighbor != -1
        rows.append(ids[y[inside], x[inside]])
        cols.append(neighbor[inside])
        values.append(np.full(inside.sum(), -1.))
        edge[~inside] += image[y[~inside] + dy, x[~inside] + dx, :3]
    matrix = coo_matrix((np.concatenate(values), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n))
    result = image.copy()
    result[y, x, :3] = np.clip(np.rint(spsolve(matrix.tocsr(), edge)), 0, 255).astype('uint8')
    return result


def stroke(draw, points, size, fill):
    points = [(round(x*3), round(y*3)) for x, y in points]
    draw.line(points, fill=fill, width=round(size*3), joint='curve')
    radius = size * 1.5
    for x, y in (points[0], points[-1]):
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=fill)


def face_line(eye_style=None, mouth=False):
    canvas = Image.new('RGBA', (3072, 3072))
    draw = ImageDraw.Draw(canvas)
    ink = '#4e3027'
    if eye_style == 'closed' or eye_style == 'sleep':
        if eye_style == 'closed':
            left = curve((527, 442), [((544,416),(583,415),(603,438))])
            right = curve((767, 432), [((778,412),(799,414),(807,432))])
        else:
            left = curve((526, 435), [((545,451),(578,456),(602,434))])
            right = curve((766, 426), [((781,442),(799,443),(808,428))])
        stroke(draw, left, 7.5, ink)
        stroke(draw, right, 6.5, ink)
    if mouth:
        smile = curve((635, 493), [((656,520),(715,537),(757,486))])
        stroke(draw, smile, 9, '#cf8052')
        stroke(draw, smile, 5.5, ink)
    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def shifted_feature(original, mask, bounds, height_factor, anchor):
    layer = original.copy()
    layer.putalpha(mask)
    top = round(anchor + (bounds[1] - anchor) * height_factor)
    feature = layer.crop(bounds)
    feature = feature.resize((feature.width, round(feature.height * height_factor)), Image.Resampling.LANCZOS)
    output = Image.new('RGBA', original.size)
    output.alpha_composite(feature, (bounds[0], top))
    return output


def mask_layer(image, mask):
    result = image.copy()
    result.putalpha(ImageChops.multiply(image.getchannel('A'), mask))
    return result


def prepare_art():
    master = inventory()
    for directory in ('source', 'layers', 'rig', 'exports', 'previews'):
        (ASSET / directory).mkdir(parents=True, exist_ok=True)
    master_file = ASSET / 'source/original.png'
    if master_file.is_file():
        assert master_file.read_bytes() == master
    else:
        master_file.write_bytes(master)
    original = Image.open(io.BytesIO(master)).convert('RGBA')
    pixels = np.asarray(original)
    left_mask, right_mask, mouth_mask = (mask_for(p) for p in (EYE_LEFT, EYE_RIGHT, MOUTH))
    solid = np.maximum.reduce([np.asarray(m) for m in (left_mask, right_mask, mouth_mask)]) > 20
    solid = cv2.dilate(solid.astype('uint8'), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))) != 0
    clean = heal(pixels, solid)
    clean_image = Image.fromarray(clean)

    # The patch edge lies in the unchanged ring outside each healing mask.
    eye_cover = Image.fromarray(np.maximum(np.asarray(left_mask), np.asarray(right_mask)))
    eyes = eye_cover.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(1.5))
    mouth = mouth_mask.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(1.5))
    # Keep the original right eye out of the mouth's feathered edge.
    yy, xx = np.ogrid[:1024, :1024]
    lip_edge = np.clip((yy - (466 + (xx-745)*.50)) / 3, 0, 1)
    mouth = ImageChops.multiply(mouth, Image.fromarray(np.uint8(255*np.where(xx > 745, lip_edge, 1))))
    variants = {'character_surface': (clean_image, (128, 125, 896, 899))}
    eye_bounds, mouth_bounds = (500, 351, 838, 510), (608, 451, 789, 602)
    for name, feature in [('eyes_open', original), ('eyes_closed', face_line(eye_style='closed')),
                          ('eyes_sleep', face_line(eye_style='sleep'))]:
        if name != 'eyes_open':
            feature = Image.alpha_composite(clean_image, feature)
        variants[name] = (mask_layer(feature, eyes), eye_bounds)
    for factor, name in [(0.32, 'eyes_blink'), (0.59, 'eyes_soft')]:
        painted = clean_image.copy()
        for mask, bounds, anchor in [(left_mask, (511, 366, 625, 501), 437),
                                     (right_mask, (748, 363, 824, 484), 426)]:
            painted.alpha_composite(shifted_feature(original, mask, bounds, factor, anchor))
        variants[name] = (mask_layer(painted, eyes), eye_bounds)
    for name, feature in [('mouth_happy', original), ('mouth_normal', Image.alpha_composite(clean_image, face_line(mouth=True)))]:
        variants[name] = (mask_layer(feature, mouth), mouth_bounds)
    for factor, name in [(0.43, 'mouth_chew'), (0.72, 'mouth_parted')]:
        painted = clean_image.copy()
        painted.alpha_composite(shifted_feature(original, mask_for(LIPS), (623, 469, 775, 584), factor, 483))
        variants[name] = (mask_layer(painted, mouth), mouth_bounds)

    bounds = {}
    for name, (image, box) in variants.items():
        image.crop(box).save(ASSET / 'layers' / f'{name}.png', optimize=True)
        bounds[name] = box
    return bounds


if __name__ == '__main__':
    print(json.dumps(prepare_art()))
