// Render GIF previews from OpenBone's posed mesh and attachment draw list.
// The batch rig uses only normal-blended texture slots. MCP separately renders the QA stills.
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [server, rig, output, fpsArg = '20'] = process.argv.slice(2);
if (!server || !rig || !output) throw new Error('Usage: monster_openbone_render OPENBONE_BIN RIG PREVIEWS [FPS|stills]');
const npmRequire = createRequire(resolve(server));
const { createCanvas, loadImage } = npmRequire('@napi-rs/canvas');
const { GIFEncoder, quantize } = npmRequire('gifenc');
const packages = resolve(dirname(server), '../..');
const moduleURL = (name) => pathToFileURL(join(packages, name, 'dist/index.js'));
const { deserialize } = await import(moduleURL('core'));
const { OpenBoneInstance } = await import(moduleURL('runtime'));

const document = deserialize(await readFile(rig, 'utf8'));
const stills = fpsArg === 'stills';
const pixelSize = stills ? 512 : 144;
const images = new Map();
const zoom = pixelSize / document.width;
const fps = Number(fpsArg);

for (const asset of document.images) {
  if (typeof asset.src !== 'string' || asset.src.startsWith('data:')) {
    throw new Error('Batch preview requires an unpacked, local editor rig');
  }
  const texture = await loadImage(await readFile(resolve(dirname(rig), asset.src)));
  const width = Math.max(2, Math.ceil(asset.width * zoom * 2));
  const height = Math.max(2, Math.ceil(asset.height * zoom * 2));
  const reduced = createCanvas(width, height);
  reduced.getContext('2d').drawImage(texture, 0, 0, width, height);
  const pixels = reduced.getContext('2d').getImageData(0, 0, width, height).data;
  for (let i = 0; i < pixels.length; i += 4) {
    const alpha = pixels[i + 3] / 255;
    pixels[i] *= alpha;
    pixels[i + 1] *= alpha;
    pixels[i + 2] *= alpha;
  }
  images.set(asset.id, { pixels, width, height });
}

function rasterLayer(item, target, covered) {
  const image = images.get(item.image?.id);
  if (!image || item.blend !== 'normal' || item.clip || item.textureRect) {
    throw new Error('Preview layer exceeds the batch texture renderer’s supported inputs');
  }
  const { pixels, width, height } = image;
  const { vertices, uvs, indices, color } = item;
  covered.fill(0);
  const screen = new Float32Array(vertices.length);
  for (let i = 0; i < screen.length; i += 2) {
    screen[i] = (vertices[i] + document.originX) * zoom;
    screen[i + 1] = (document.originY - vertices[i + 1]) * zoom;
  }

  for (let i = 0; i < indices.length; i += 3) {
    const ai = indices[i] * 2;
    const bi = indices[i + 1] * 2;
    const ci = indices[i + 2] * 2;
    const ax = screen[ai], ay = screen[ai + 1];
    const bx = screen[bi], by = screen[bi + 1];
    const cx = screen[ci], cy = screen[ci + 1];
    const determinant = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax);
    if (Math.abs(determinant) < 1e-5) continue;
    const left = Math.max(0, Math.floor(Math.min(ax, bx, cx)));
    const right = Math.min(pixelSize-1, Math.ceil(Math.max(ax, bx, cx)));
    const top = Math.max(0, Math.floor(Math.min(ay, by, cy)));
    const bottom = Math.min(pixelSize-1, Math.ceil(Math.max(ay, by, cy)));
    const dux = (cy-ay)/determinant, duy = (ax-cx)/determinant;
    const dvx = (ay-by)/determinant, dvy = (bx-ax)/determinant;
    for (let y = top; y <= bottom; y++) {
      const dy = y + .5 - ay;
      for (let x = left; x <= right; x++) {
        const at = y * pixelSize + x;
        if (covered[at]) continue;
        const dx = x + .5 - ax;
        const ub = dux * dx + duy * dy;
        const uc = dvx * dx + dvy * dy;
        const ua = 1 - ub - uc;
        if (Math.min(ua, ub, uc) < -1e-6) continue;
        covered[at] = 1;
        const u = ua*uvs[ai] + ub*uvs[bi] + uc*uvs[ci];
        const v = ua*uvs[ai+1] + ub*uvs[bi+1] + uc*uvs[ci+1];
        const sx = Math.max(0, Math.min(width-1.001, u*width-.5));
        const sy = Math.max(0, Math.min(height-1.001, v*height-.5));
        const x0 = Math.floor(sx), y0 = Math.floor(sy);
        const tx = sx-x0, ty = sy-y0;
        const tl = (y0*width+x0)*4, bl = tl+width*4;
        const wtl = (1-tx)*(1-ty), wtr = tx*(1-ty), wbl = (1-tx)*ty, wbr = tx*ty;
        const opacity = color[3]*(pixels[tl+3]*wtl + pixels[tl+7]*wtr + pixels[bl+3]*wbl + pixels[bl+7]*wbr)/255;
        const targetIndex = at*4;
        for (let channel = 0; channel < 3; channel++) {
          const component = pixels[tl+channel]*wtl + pixels[tl+4+channel]*wtr +
            pixels[bl+channel]*wbl + pixels[bl+4+channel]*wbr;
          target[targetIndex+channel] = component*color[channel]*color[3] + target[targetIndex+channel]*(1-opacity);
        }
        target[targetIndex+3] = 255*opacity + target[targetIndex+3]*(1-opacity);
      }
    }
  }
}

const background = new Uint8ClampedArray(pixelSize*pixelSize*4);
if (!stills) {
  for (let i = 0; i < background.length; i += 4) background.set([27,41,64,255],i);
}
const covered = new Uint8Array(pixelSize*pixelSize);

function renderPose(instance) {
  const data = background.slice();
  for (const layer of instance.skeleton.drawList()) rasterLayer(layer,data,covered);
  return data;
}

if (stills) {
  const canvas = createCanvas(pixelSize,pixelSize);
  const context = canvas.getContext('2d');
  const samples = [['neutral',null,0],['mid','idle',.41],['closed','idle',.45],['joy','happy',.39],
    ['eat','eat',.242],['chew','eat',.27],['sleep','sleep',.31]];
  for (const [label,animation,position] of samples) {
    const instance = new OpenBoneInstance(document);
    if (animation) {
      const clip = document.animations.find((item) => item.name === animation);
      instance.animationState.setAnimation(0,animation,false,0);
      instance.advance(clip.duration*position);
    }
    const rgba = renderPose(instance);
    for (let i = 0; i < rgba.length; i += 4) {
      const a = rgba[i+3]/255;
      if (a>0 && a<1) for (let j=0; j<3; j++) rgba[i+j] /= a;
    }
    const image = context.createImageData(pixelSize,pixelSize);
    image.data.set(rgba);
    context.putImageData(image,0,0);
    await writeFile(join(output,`${label}.png`),canvas.toBuffer('image/png'));
  }
  process.exit(0);
}

const library = new Map();
for (const clip of document.animations) {
  const instance = new OpenBoneInstance(document);
  const loop = clip.name === 'idle' || clip.name === 'sleep';
  instance.animationState.setAnimation(0, clip.name, loop, 0);
  const frames = [];
  for (let index = 0; index < Math.round(clip.duration * fps); index++) {
    instance.advance(index ? 1 / fps : 0);
    frames.push(renderPose(instance));
  }
  library.set(clip.name, frames);
}

const samples = [...library.values()].flatMap((frames) => [0, .38, .67].map((at) => frames[Math.round(at*(frames.length-1))]));
const swatches = new Uint8Array(samples.length*background.length);
samples.forEach((rgba, i) => swatches.set(rgba, i*background.length));
const palette = quantize(swatches,256);
const cache = new Int16Array(65536).fill(-1);

function indexedFrame(rgba) {
  const result = new Uint8Array(pixelSize*pixelSize);
  for (let i = 0; i < result.length; i++) {
    const r = (rgba[i*4] >> 3) << 3;
    const g = (rgba[i*4+1] >> 2) << 2;
    const b = (rgba[i*4+2] >> 3) << 3;
    const key = (r<<8) | (g<<3) | (b>>3);
    let index = cache[key];
    if (index < 0) {
      let best = Infinity;
      for (let j = 0; j < palette.length; j++) {
        const [pr,pg,pb] = palette[j];
        const distance = (r+4-pr)**2 + (g+2-pg)**2 + (b+4-pb)**2;
        if (distance < best) { best = distance; index = j; }
      }
      cache[key] = index;
    }
    result[i] = index;
  }
  return result;
}

for (const [name, frames] of library) {
  const gif = GIFEncoder();
  frames.forEach((data, n) => gif.writeFrame(indexedFrame(data),pixelSize,pixelSize,
    n ? { delay:1000/fps } : { palette,repeat:0,delay:1000/fps }));
  gif.finish();
  await writeFile(join(output,`${name}.gif`),gif.bytes());
}
