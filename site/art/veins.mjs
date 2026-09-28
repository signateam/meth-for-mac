// Generates the bloodshot vein SVG for the "Meth" headline and writes it into index.html.
// Usage: node site/art/veins.mjs site/index.html 23
// Box: the span's content box at font-size 100px (220 x 118). Cap line y=26.5, baseline y=97.
import fs from 'node:fs';
const [,, target, seedArg = '7', outSvg] = process.argv;
let seed = Number(seedArg);
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const R = (a, b) => a + (b - a) * rnd();
const W = 220, H = 118, CAP = 26.5, BASE = 97, XH = 44, GLYPH = BASE - CAP;
const DEPTH = GLYPH * 0.5;

// Where each letter's top edge sits (M and the h stem reach cap height; e, t, h shoulder are lower).
const topAt = (x) => (x < 80 ? CAP : x < 134 ? XH : x < 142 ? 34 : x < 166 ? XH : x < 184 ? CAP : XH);

const polys = [];
let MINW = 0.55; // thinnest a vein tapers to; capillaries go finer
function vein(x, y, ang, len, w0, depth, group) {
  const pts = [];
  let a = ang, s = 0, px = x, py = y;
  const phase = R(0, 6.28), freq = R(0.3, 0.6), amp = R(0.06, 0.12);
  const branches = [];
  const nb = depth === 0 ? 2 + Math.floor(R(0, 3)) : depth === 1 ? (rnd() < 0.7 ? 1 : 0) : 0;
  for (let i = 0; i < nb; i++) branches.push(R(0.25, 0.7) * len);
  branches.sort((p, q) => p - q);
  const step = 1.4;
  while (s <= len) {
    const w = MINW + (w0 - MINW) * Math.pow(1 - s / len, 0.9);
    pts.push([px, py, a, w]);
    if (branches.length && s >= branches[0]) {
      branches.shift();
      const side = rnd() < 0.5 ? -1 : 1;
      vein(px, py, a + side * R(0.35, 0.75), (len - s) * R(0.5, 0.85) + 2, Math.max(0.5, w * 0.78), depth + 1, group);
    }
    a += Math.sin(s * freq + phase) * amp + R(-0.035, 0.035);
    a = ang + Math.max(-0.7, Math.min(0.7, a - ang));
    px += Math.cos(a) * step; py += Math.sin(a) * step; s += step;
  }
  const L = [], Rr = [];
  for (const [x1, y1, a1, w] of pts) {
    const nx = -Math.sin(a1) * w / 2, ny = Math.cos(a1) * w / 2;
    L.push([x1 + nx, y1 + ny]); Rr.push([x1 - nx, y1 - ny]);
  }
  const f = (n) => Math.round(n * 10);
  const all = L.concat(Rr.reverse()).map(([a1, b1]) => [f(a1), f(b1)]);
  const num = (n) => (n < 0 ? '-' : ' ') + (Math.abs(n) / 10).toString().replace(/^0\./, '.');
  let d = `M${all[0][0] / 10} ${all[0][1] / 10}l`;
  for (let i = 1; i < all.length; i++) d += num(all[i][0] - all[i - 1][0]) + num(all[i][1] - all[i - 1][1]);
  polys.push({ group, d: d.replace('l ', 'l') + 'z' });
}

// Top edge: roots just above each letter's top, heading down.
for (let x = 3; x < W - 1; x += R(8, 12)) {
  const top = topAt(x), deep = top === CAP ? 1 : 0.7;
  vein(x, top - 3, Math.PI / 2 + R(-0.5, 0.5), (DEPTH * R(0.6, 1.05) + 3) * deep, R(2.3, 3.1), 0, 't');
}
// Bottom edge: roots just below the baseline, heading up.
for (let x = 5; x < W - 1; x += R(9, 13)) {
  vein(x, BASE + 3, -Math.PI / 2 + R(-0.5, 0.5), DEPTH * R(0.55, 1.0) + 3, R(2.3, 3.1), 0, 'b');
}
// A few from the outer sides of M and h.
for (const y of [CAP + GLYPH * 0.28, CAP + GLYPH * 0.66]) vein(-1, y + R(-4, 4), (y < 60 ? 0.75 : -0.75) + R(-0.12, 0.12), 9, 1.2, 1, 'l');
for (const y of [CAP + GLYPH * 0.42, CAP + GLYPH * 0.78]) vein(W + 1, y + R(-4, 4), Math.PI + (y < 60 ? -0.75 : 0.75) + R(-0.12, 0.12), 9, 1.2, 1, 'r');

// Capillaries: a dense web of short, hair-thin, faint pink vessels under the main veins.
// At reading size they blur into a pink tinge along the edges; up close they read as fine veins.
MINW = 0.18;
for (let x = 1; x < W; x += R(2.2, 4)) vein(x, topAt(x) - 2, Math.PI / 2 + R(-0.9, 0.9), R(4, 12), R(0.45, 0.75), 1, 'c');
for (let x = 1; x < W; x += R(2.2, 4)) vein(x, BASE + 2, -Math.PI / 2 + R(-0.9, 0.9), R(4, 12), R(0.45, 0.75), 1, 'c');
for (let i = 0; i < 45; i++) {
  const x = R(0, W), top = rnd() < 0.5;
  vein(x, top ? topAt(x) + R(4, 14) : BASE - R(4, 14), R(0, 6.28), R(3, 7), R(0.3, 0.5), 2, 'c');
}

const grad = (id, x1, y1, x2, y2) => `<linearGradient id='${id}' gradientUnits='userSpaceOnUse' x1='${x1}' y1='${y1}' x2='${x2}' y2='${y2}'><stop offset='0' stop-color='%23ff3b30'/><stop offset='.55' stop-color='%23f0342c' stop-opacity='.95'/><stop offset='1' stop-color='%23e5322d' stop-opacity='0'/></linearGradient>`;
const cap = `<linearGradient id='c' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='0' y2='${H}'><stop offset='${(CAP - 3) / H}' stop-color='%23ff6b6b' stop-opacity='.55'/><stop offset='${(CAP + DEPTH * 0.85) / H}' stop-color='%23ff6b6b' stop-opacity='0'/><stop offset='${(BASE - DEPTH * 0.85) / H}' stop-color='%23ff6b6b' stop-opacity='0'/><stop offset='${(BASE + 3) / H}' stop-color='%23ff6b6b' stop-opacity='.55'/></linearGradient>`;
const defs = cap + grad('t', 0, CAP - 3, 0, CAP + DEPTH + 4) + grad('b', 0, BASE + 3, 0, BASE - DEPTH - 3) + grad('l', 0, 0, 20, 0) + grad('r', W, 0, W - 18, 0);
const flush = `<linearGradient id='f' x1='0' y1='0' x2='0' y2='1'><stop offset='${(CAP - 2) / H}' stop-color='%23e5322d' stop-opacity='.3'/><stop offset='${(CAP + 9) / H}' stop-color='%23e5322d' stop-opacity='0'/><stop offset='${(BASE - 9) / H}' stop-color='%23e5322d' stop-opacity='0'/><stop offset='${(BASE + 2) / H}' stop-color='%23e5322d' stop-opacity='.3'/></linearGradient>`;
const body = ['c', 't', 'b', 'l', 'r'].map((g) => `<path fill='url(%23${g})' d='${polys.filter((p) => p.group === g).map((p) => p.d).join('')}'/>`).join('');
const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${W} ${H}' preserveAspectRatio='none'><defs>${defs}</defs>${body}</svg>`;
const uri = `url("data:image/svg+xml,${svg.replace(/</g, '%3C').replace(/>/g, '%3E')}")`;
if (outSvg) fs.writeFileSync(outSvg, svg.replace(/%23/g, '#'));
const html = fs.readFileSync(target, 'utf8');
const next = html.replace(/--veins: (none|url\("[^"]*"\));/, `--veins: ${uri};`);
if (next === html && !html.includes(uri)) throw new Error('marker not found');
fs.writeFileSync(target, next);
console.log('flush stops %', [(CAP - 2) / H, (CAP + 9) / H, (BASE - 9) / H, (BASE + 2) / H].map((n) => (n * 100).toFixed(1)).join(' '), 'polys', polys.length, 'bytes', uri.length);
