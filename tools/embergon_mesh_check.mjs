// Validate the packed runtime data and measure the Embergon mesh at 60 Hz.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, extname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [server, asset] = process.argv.slice(2);
assert(server && asset, 'Usage: node embergon_mesh_check.mjs OPENBONE_MCP_BIN RIG_OR_EXPORT');
const packages = resolve(dirname(server), '../..');
const { deserialize, deserializeBinary, validate } = await import(
  pathToFileURL(resolve(packages, 'core/dist/index.js'))
);
const { OpenBoneInstance } = await import(pathToFileURL(resolve(packages, 'runtime/dist/index.js')));
const binary = extname(asset) === '.obonb';
const bytes = await readFile(asset);
const document = binary ? deserializeBinary(bytes) : deserialize(bytes.toString('utf8'));
assert.deepEqual(validate(document), []);
assert.equal(document.animations.length, 7);
assert.equal(document.stateMachines.length, 1);
if (binary) {
  assert(document.atlas.pages.length > 0);
  assert(document.atlas.pages.every((page) => page.src.startsWith('data:image/png;base64,')));
}

const hasExpressionRevision = document.images.some((image) => image.name === 'eyes_lid_low');
if (hasExpressionRevision) {
  const appearances = [
    ['idle', 0, 'eyes', 'eyes_open'],
    ['idle', .41, 'eyes', 'eyes_lid_mid'],
    ['idle', .45, 'eyes', 'eyes_closed'],
    ['sleep', .31, 'eyes', 'eyes_sleep'],
    ['happy', .50, 'eyes', 'eyes_joy'],
    ['idle', 0, 'mouth', 'mouth_relaxed'],
    ['eat', .205, 'mouth', 'mouth_open'],
    ['eat', .27, 'mouth', 'mouth_chew'],
  ];
  for (const [name, time, slotName, expected] of appearances) {
    const scene = new OpenBoneInstance(document);
    const clip = document.animations.find((animation) => animation.name === name);
    scene.animationState.setAnimation(0, name, false, 0);
    scene.advance(clip.duration * time);
    const slot = scene.skeleton.slots.find((slot) => slot.data.name === slotName);
    assert.equal(slot.attachmentName, expected, `${name}/${slotName} at ${time}`);
  }
}

function area(vertices, a, b, c) {
  return (vertices[b] - vertices[a]) * (vertices[c + 1] - vertices[a + 1]) -
    (vertices[b + 1] - vertices[a + 1]) * (vertices[c] - vertices[a]);
}

function surface(instance) {
  return instance.drawList().find(({ slot }) => slot.data.name === 'surface');
}

const setup = surface(new OpenBoneInstance(document));
const { indices } = setup;
const metrics = {};
for (const clip of document.animations) {
  const instance = new OpenBoneInstance(document);
  instance.animationState.setAnimation(0, clip.name, false, 0);
  let inversions = 0;
  let minRatio = Infinity;
  let maxRatio = 0;
  let worstTriangle = null;
  const bounds = [Infinity, Infinity, -Infinity, -Infinity];
  const frames = Math.ceil(clip.duration * 60);
  for (let frame = 0; frame <= frames; frame++) {
    instance.advance(frame ? 1 / 60 : 0);
    const { vertices } = surface(instance);
    for (let i = 0; i < vertices.length; i += 2) {
      const x = document.originX + vertices[i];
      const y = document.originY - vertices[i + 1];
      bounds[0] = Math.min(bounds[0], x);
      bounds[1] = Math.min(bounds[1], y);
      bounds[2] = Math.max(bounds[2], x);
      bounds[3] = Math.max(bounds[3], y);
    }
    for (let i = 0; i < indices.length; i += 3) {
      const a = 2 * indices[i];
      const b = 2 * indices[i + 1];
      const c = 2 * indices[i + 2];
      const ratio = area(vertices, a, b, c) / area(setup.vertices, a, b, c);
      if (ratio <= 0) inversions++;
      if (ratio < minRatio) {
        minRatio = ratio;
        worstTriangle = [a, b, c].map((v) => [
          Math.round(document.originX + setup.vertices[v]), Math.round(document.originY - setup.vertices[v + 1]),
        ]);
      }
      maxRatio = Math.max(maxRatio, ratio);
    }
  }
  const cropped = bounds[0] < 0 || bounds[1] < 0 || bounds[2] > document.width || bounds[3] > document.height;
  metrics[clip.name] = {
    poses: frames + 1,
    inversions,
    cropped,
    bounds: bounds.map(Math.round),
    minAreaRatio: Number(minRatio.toFixed(4)),
    maxAreaRatio: Number(maxRatio.toFixed(4)),
    worstTriangle,
  };
  if (inversions || cropped) process.exitCode = 1;
}
console.log(JSON.stringify({ meshVertices: setup.vertices.length / 2, meshTriangles: indices.length / 3, clips: metrics }));
