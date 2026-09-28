// Generates bloodshot veins for the active "With Meth" toggle pill and writes them into index.html.
// Usage: node site/art/pill-veins.mjs site/index.html 5
import fs from 'node:fs';
const [,, target, seedArg = '5'] = process.argv;
let seed = Number(seedArg);
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const R = (a, b) => a + (b - a) * rnd();
const W = 130, H = 40, r = H / 2;

const paths = [], caps = [];
let MINW = 0.35, into = paths; // capillaries go finer and into their own layer
function vein(x, y, ang, len, w0, depth) {
  const pts = [];
  let a = ang, s = 0, px = x, py = y;
  const phase = R(0, 6.28), freq = R(0.4, 0.8), amp = R(0.08, 0.14);
  const forks = depth === 0 ? [R(0.25, 0.45) * len, R(0.55, 0.8) * len] : depth === 1 && rnd() < 0.5 ? [R(0.4, 0.7) * len] : [];
  while (s <= len) {
    pts.push([px, py, a, MINW + (w0 - MINW) * Math.pow(1 - s / len, 0.9)]);
    if (forks.length && s >= forks[0]) {
      forks.shift();
      vein(px, py, a + (rnd() < 0.5 ? -1 : 1) * R(0.4, 0.8), (len - s) * R(0.5, 0.8) + 1.5, pts.at(-1)[3] * 0.8, depth + 1);
    }
    a += Math.sin(s * freq + phase) * amp + R(-0.05, 0.05);
    a = ang + Math.max(-0.6, Math.min(0.6, a - ang));
    px += Math.cos(a) * 0.8; py += Math.sin(a) * 0.8; s += 0.8;
  }
  const L = [], Rr = [];
  for (const [x1, y1, a1, w] of pts) {
    const nx = -Math.sin(a1) * w / 2, ny = Math.cos(a1) * w / 2;
    L.push(`${(x1 + nx).toFixed(1)} ${(y1 + ny).toFixed(1)}`); Rr.push(`${(x1 - nx).toFixed(1)} ${(y1 - ny).toFixed(1)}`);
  }
  into.push(`M${L.concat(Rr.reverse()).join('L')}z`);
}

// Roots around the stadium outline, each pointing at the pill's centre line.
for (let x = r - 4; x < W - r + 4; x += R(11, 20)) {
  vein(x, -0.5, Math.PI / 2 + R(-0.55, 0.55), R(8, 15), R(1.4, 1.9), 0);
}
for (let x = r + R(0, 8); x < W - r + 4; x += R(12, 21)) {
  vein(x, H + 0.5, -Math.PI / 2 + R(-0.55, 0.55), R(8, 15), R(1.4, 1.9), 0);
}
for (const [cx, dir] of [[r, 1], [W - r, -1]]) {
  for (const t of [-1.0, -0.2, 0.55]) {
    const ang = Math.PI * (dir > 0 ? 1 : 0) + t;
    const x = cx + Math.cos(ang) * (r + 0.5), y = r + Math.sin(ang) * (r + 0.5);
    vein(x, y, ang + Math.PI + R(-0.3, 0.3), R(9, 16), R(1.4, 1.9), 0);
  }
}

// Capillaries: dense, hair-thin, faint pink vessels all around the rim, under the main veins.
MINW = 0.15; into = caps;
const rim = (t) => {
  // A point on the stadium outline and the inward direction, for t in [0, 1).
  const straight = W - H, perim = 2 * straight + Math.PI * H, d = t * perim;
  if (d < straight) return [r + d, -0.3, Math.PI / 2];
  if (d < straight + Math.PI * r) { const a = -Math.PI / 2 + (d - straight) / r; return [W - r + Math.cos(a) * (r + 0.3), r + Math.sin(a) * (r + 0.3), a + Math.PI]; }
  if (d < 2 * straight + Math.PI * r) return [W - r - (d - straight - Math.PI * r), H + 0.3, -Math.PI / 2];
  const a = Math.PI / 2 + (d - 2 * straight - Math.PI * r) / r; return [r + Math.cos(a) * (r + 0.3), r + Math.sin(a) * (r + 0.3), a + Math.PI];
};
for (let t = 0; t < 1; t += R(0.006, 0.012)) { const [x, y, a] = rim(t); vein(x, y, a + R(-0.9, 0.9), R(3, 8), R(0.35, 0.6), 1); }

const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${W} ${H}' preserveAspectRatio='none'><defs><radialGradient id='g' cx='.5' cy='.5' r='.62' gradientTransform='translate(.5 .5) scale(.32 1) translate(-.5 -.5)'><stop offset='.35' stop-color='%23d0211c' stop-opacity='0'/><stop offset='.75' stop-color='%23d0211c' stop-opacity='.75'/><stop offset='1' stop-color='%23ff3b30'/></radialGradient><radialGradient id='c' cx='.5' cy='.5' r='.62' gradientTransform='translate(.5 .5) scale(.32 1) translate(-.5 -.5)'><stop offset='.5' stop-color='%23ff6b6b' stop-opacity='0'/><stop offset='1' stop-color='%23ff6b6b' stop-opacity='.55'/></radialGradient></defs><path fill='url(%23c)' d='${caps.join('')}'/><path fill='url(%23g)' d='${paths.join('')}'/></svg>`;
const uri = `url("data:image/svg+xml,${svg.replace(/</g, '%3C').replace(/>/g, '%3E')}")`;
const html = fs.readFileSync(target, 'utf8');
const next = html.replace(/--pill-veins: (none|url\("[^"]*"\));/, `--pill-veins: ${uri};`);
if (next === html) throw new Error('--pill-veins marker not found');
fs.writeFileSync(target, next);
console.log('veins', paths.length, 'bytes', uri.length);
