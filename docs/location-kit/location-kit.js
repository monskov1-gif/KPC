import * as THREE from 'three';

/**
 * Location kit — whole locations: the room shell (walls with openings, floors, ceilings, sloped
 * roofs, stairs, mouldings), windows with painted views and light falling in, lamps and the
 * day / evening / night state system, furniture and props.
 * A standalone ES module (depends only on `three`, r150+), extracted from "Blood of the North".
 * Companions: window-light.js (exposure + lens flare when the player passes a bright window or
 * lamp), nature.js (outdoor: rocks, spruces, bare trees, relief ground, mist).
 *
 *   const kit = new LocationKit(scene, { low: false });    // root = any THREE.Object3D
 *   kit.setupLights();                                     // hemi + fill, driven by states
 *   kit.wall(-6, 6, 2.8, BACK, wallM, [{ x0, x1, y0, y1 }]);    // shell: walls with holes, floor…
 *   kit.sofa(-2, BACK, 0);                                 // builders: x, z, ry, options
 *   kit.withT(1, BACK, 0, () => { kit.rb(...); kit.mug(...); });  // free-form in a local frame
 *   kit.flushBatches();                                    // ALWAYS at the end of the build
 *   kit.setState('evening');                               // 'evening' | 'night' | 'day'
 *   // per frame: kit.update(dt); windowLight.update(dt, { world: kit, player, camera })
 *
 * Conventions: metres; y up; side-on "dollhouse" camera on +z, x along the location, back wall at
 * z = BACK, the near wall cut away. A piece's local frame has its back against z = 0 and its front
 * facing +z. Textures are small canvases with nearest filtering, 1 texel ≈ 1 cm — the pixel-art
 * register. Static geometry is batched per material (one draw call per material); anything that
 * changes (lamps, flames, doors that open) is a separate mesh.
 */

// ------------------------------------------------------------------ small utils

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
const cl = (v) => Math.max(0, Math.min(255, Math.round(v)));
export const rgb = (r, g, b, a = 1) => (a >= 1 ? `rgb(${cl(r)},${cl(g)},${cl(b)})` : `rgba(${cl(r)},${cl(g)},${cl(b)},${a})`);

/** Seeded PRNG (mulberry32) → () => 0…1. Everything procedural is seeded and deterministic. */
export function rng(seed = 1) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const texCache = new Map();
/** A cached canvas texture: draw(ctx, w, h) paints it once per key. */
export function canvasTexture(key, w, h, draw, { repeat = [1, 1], color = true, aniso = 4, nearest = false } = {}) {
  const ck = `${key}:${repeat}`;
  if (texCache.has(ck)) return texCache.get(ck);
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  if (color) t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(...repeat);
  t.anisotropy = aniso;
  if (nearest) { t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter; t.generateMipmaps = false; }
  texCache.set(ck, t);
  return t;
}
/** Pixel texture: nearest-filtered, no mipmaps. Size it so 1 texel ≈ 1 cm of the surface. */
export const TX = (key, w, h, draw, o = {}) => canvasTexture(`fk-${key}`, w, h, draw, { nearest: true, aniso: 1, ...o });

/**
 * Posterise a painted canvas into pixel art: downscale by k, stepped tones with a 2×2 ordered
 * dither, upscale with nearest. Smooth glows and fog become pixel bands (window views, backdrops).
 */
export function pixelate(ctx, w, h, k = 3) {
  const sw = Math.max(1, Math.round(w / k)), sh = Math.max(1, Math.round(h / k));
  const small = document.createElement('canvas'); small.width = sw; small.height = sh;
  const sc = small.getContext('2d');
  sc.imageSmoothingEnabled = true; sc.drawImage(ctx.canvas, 0, 0, sw, sh);
  const img = sc.getImageData(0, 0, sw, sh), d = img.data, step = 14, bayer = [-0.375, 0.125, 0.375, -0.125];
  for (let y = 0; y < sh; y++) for (let x = 0; x < sw; x++) {
    const i = (y * sw + x) * 4, o = bayer[(y & 1) * 2 + (x & 1)] * step;
    for (let c = 0; c < 3; c++) d[i + c] = Math.max(0, Math.min(255, Math.round((d[i + c] + o) / step) * step));
  }
  sc.putImageData(img, 0, 0);
  ctx.save(); ctx.imageSmoothingEnabled = false; ctx.clearRect(0, 0, w, h); ctx.drawImage(small, 0, 0, w, h); ctx.restore();
}

export function glowTexture() {
  return canvasTexture('fk-glow', 128, 128, (ctx, w, h) => {
    const g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    g.addColorStop(0, 'rgba(255,255,255,1)');
    g.addColorStop(0.25, 'rgba(255,255,255,0.45)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  }, { color: false });
}
const glowMats = new Map();
/** Additive soft sprite (lamp halo). */
export function glow(color, size, opacity = 0.6) {
  const k = `${color}-${opacity}`;
  if (!glowMats.has(k)) glowMats.set(k, new THREE.SpriteMaterial({ map: glowTexture(), color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false }));
  const s = new THREE.Sprite(glowMats.get(k));
  s.scale.set(size, size, 1);
  s.renderOrder = 5;
  return s;
}
/** Soft additive light pool (fake bounce light on a floor / wall). */
export function lightPool(color, w, h, opacity = 0.25) {
  const m = new THREE.MeshBasicMaterial({ map: glowTexture(), color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false });
  const p = new THREE.Mesh(new THREE.PlaneGeometry(w, h), m);
  p.renderOrder = 2;
  return p;
}

// ------------------------------------------------------------------ noise + geometry helpers

function hash3(x, y, z, s) {
  let h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(z | 0, 1274126177) ^ Math.imul(s | 0, 1103515245);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
/** Value noise 0…1. */
export function noise3(x, y, z, s = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const xf = x - xi, yf = y - yi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf), w = zf * zf * (3 - 2 * zf);
  const c = (a, b, d) => hash3(xi + a, yi + b, zi + d, s);
  const x00 = c(0, 0, 0) + (c(1, 0, 0) - c(0, 0, 0)) * u, x10 = c(0, 1, 0) + (c(1, 1, 0) - c(0, 1, 0)) * u;
  const x01 = c(0, 0, 1) + (c(1, 0, 1) - c(0, 0, 1)) * u, x11 = c(0, 1, 1) + (c(1, 1, 1) - c(0, 1, 1)) * u;
  const y0 = x00 + (x10 - x00) * v, y1 = x01 + (x11 - x01) * v;
  return y0 + (y1 - y0) * w;
}
/** Fractal noise, roughly 0…1. */
export function fbm3(x, y, z, s = 0, oct = 4) {
  let a = 0.5, f = 1, sum = 0, norm = 0;
  for (let i = 0; i < oct; i++) { sum += a * noise3(x * f, y * f, z * f, s + i * 17); norm += a; a *= 0.5; f *= 2.03; }
  return sum / norm;
}

/** Smooth normals for a non-indexed geometry: faces sharing a position share the normal. */
export function smoothNormals(geo) {
  geo.computeVertexNormals();
  const p = geo.attributes.position, n = geo.attributes.normal;
  const acc = new Map();
  const key = (i) => `${Math.round(p.getX(i) * 1e4)},${Math.round(p.getY(i) * 1e4)},${Math.round(p.getZ(i) * 1e4)}`;
  for (let i = 0; i < p.count; i++) {
    const k = key(i);
    const a = acc.get(k) || [0, 0, 0];
    a[0] += n.getX(i); a[1] += n.getY(i); a[2] += n.getZ(i);
    acc.set(k, a);
  }
  for (let i = 0; i < p.count; i++) {
    const a = acc.get(key(i));
    const l = Math.hypot(a[0], a[1], a[2]) || 1;
    n.setXYZ(i, a[0] / l, a[1] / l, a[2] / l);
  }
  n.needsUpdate = true;
  return geo;
}

/**
 * Zero / NaN normals render as NaN in the shader, and bloom smears them into black blocks half a
 * screen wide. Run this over the root after building (lathes with a point on the axis, collapsed
 * bevels and degenerate faces produce them).
 */
export function sanitizeNormals(root) {
  root.traverse((o) => {
    const n = o.geometry?.attributes?.normal;
    if (!n) return;
    let bad = false;
    for (let i = 0; i < n.count; i++) {
      const x = n.getX(i), y = n.getY(i), z = n.getZ(i), l = Math.hypot(x, y, z);
      if (!(l > 1e-6)) { n.setXYZ(i, 0, 1, 0); bad = true; } else if (Math.abs(l - 1) > 1e-3) { n.setXYZ(i, x / l, y / l, z / l); bad = true; }
    }
    if (bad) n.needsUpdate = true;
  });
}

/** A box with rounded edges: smooth-shaded, no hard primitive look. */
export function roundedBox(w, h, d, rad = 0.04, seg = 3) {
  const geo = new THREE.BoxGeometry(w, h, d, seg * 2, seg * 2, seg * 2).toNonIndexed();
  const p = geo.attributes.position;
  const hx = w / 2 - rad, hy = h / 2 - rad, hz = d / 2 - rad;
  const v = new THREE.Vector3(), c = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.set(p.getX(i), p.getY(i), p.getZ(i));
    c.set(Math.max(-hx, Math.min(hx, v.x)), Math.max(-hy, Math.min(hy, v.y)), Math.max(-hz, Math.min(hz, v.z)));
    v.sub(c);
    if (v.lengthSq() > 1e-10) v.setLength(rad);
    p.setXYZ(i, c.x + v.x, c.y + v.y, c.z + v.z);
  }
  return smoothNormals(geo);
}

const bevelCache = new Map();
/** Drop-in for `new THREE.BoxGeometry(w, h, d)`: same size, softly bevelled edges. Returns a clone. */
export function bevelBox(w, h, d) {
  const key = `${(+w).toFixed(3)}|${(+h).toFixed(3)}|${(+d).toFixed(3)}`;
  let geo = bevelCache.get(key);
  if (!geo) {
    const r = Math.min(0.02, 0.18 * Math.min(w, h, d));
    geo = r > 0.002 ? roundedBox(w, h, d, r, 1) : new THREE.BoxGeometry(w, h, d);
    bevelCache.set(key, geo);
  }
  return geo.clone();             // callers translate / merge it in place — never hand out the cached one
}

const geoCache = new Map();
/** Cache by key, ALWAYS return a clone (batching translates geometry in place). */
export const cached = (key, make) => { let g = geoCache.get(key); if (!g) { g = make(); geoCache.set(key, g); } return g.clone(); };

/** A soft cushion: a rounded box whose faces bulge out, with a little lumpy noise. */
export function cushionGeo(w, h, d, r, puff = 0.3, seed = 1, lump = 0.006) {
  return cached(`cush|${w}|${h}|${d}|${r}|${puff}|${seed}|${lump}`, () => {
    const g = roundedBox(w, h, d, Math.min(r, w / 2 - 0.002, h / 2 - 0.002, d / 2 - 0.002), 3);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      let x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const nx = Math.min(1, Math.abs(x) / (w / 2)), ny = Math.min(1, Math.abs(y) / (h / 2)), nz = Math.min(1, Math.abs(z) / (d / 2));
      y += Math.sign(y) * h * puff * 0.5 * (1 - nx * nx) * (1 - nz * nz) * ny;
      z += Math.sign(z) * d * puff * 0.2 * (1 - nx * nx) * (1 - ny * ny) * nz;
      x += Math.sign(x) * w * puff * 0.1 * (1 - ny * ny) * (1 - nz * nz) * nx;
      const n = (noise3(x * 11, y * 11, z * 11, seed) - 0.5) * lump * 2;
      p.setXYZ(i, x + Math.sign(x) * n * nx, y + Math.sign(y) * n * ny, z + Math.sign(z) * n * nz);
    }
    return smoothNormals(g);
  });
}

/**
 * Fabric over a box top (L along x, W along z, top at y = 0), hanging `drop` down the sides
 * flagged in `sides` [-x, +x, -z, +z]: rounded fold over the edge, wrinkles on top, vertical
 * folds and a slight flare where it hangs. Duvets, throws, tablecloths, a jacket on a chair.
 */
export function drapeGeo(L, W, drop, o = {}) {
  const { sides = [1, 1, 1, 1], r = 0.04, seed = 1, wrinkle = 0.01, seg = [40, 24], uv = [0.5, 0.5], flare = 0.025, folds = 0.012 } = o;
  const S0 = -L / 2 - sides[0] * drop, S1 = L / 2 + sides[1] * drop, T0 = -W / 2 - sides[2] * drop, T1 = W / 2 + sides[3] * drop;
  const [nx, nz] = seg;
  const fold = (s, half) => {
    const a = Math.abs(s), sg = Math.sign(s) || 1;
    if (a <= half) return [s, 0, 0];
    const e = a - half, arc = (r * Math.PI) / 2;
    if (e < arc) { const ang = e / r; return [sg * (half + r * Math.sin(ang)), -r * (1 - Math.cos(ang)), 0]; }
    return [sg * (half + r), -r - (e - arc), e - arc];
  };
  const pos = [], uvs = [], idx = [];
  for (let j = 0; j <= nz; j++) for (let i = 0; i <= nx; i++) {
    const s = S0 + ((S1 - S0) * i) / nx, t = T0 + ((T1 - T0) * j) / nz;
    const [x, hx, ex] = fold(s, L / 2), [z, hz, ez] = fold(t, W / 2);
    let X = x, Y = Math.max(hx + hz, -(drop + r + 0.04)), Z = z;
    const n = noise3(s * 5, t * 5, 0.5, seed) - 0.5;
    if (ex <= 0 && ez <= 0) Y += n * wrinkle * 2 + (noise3(s * 13, t * 13, 3.1, seed) - 0.5) * wrinkle;
    else {
      const hang = Math.max(ex, ez), k = Math.min(1, hang / 0.08);
      const f = Math.sin((ex > 0 ? t : s) * 24 + n * 5) * folds * k + flare * (hang / Math.max(drop, 0.01));
      if (ex > 0) X += Math.sign(x) * f;
      if (ez > 0) Z += Math.sign(z) * f;
    }
    pos.push(X, Y, Z);
    uvs.push(s / uv[0], t / uv[1]);
  }
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const a = j * (nx + 1) + i, b = a + 1, c = a + nx + 1, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/** Project UVs by the dominant normal axis: texture covers su × sv metres (rugs, tiled tops). */
export function worldUV(geo, su, sv) {
  const p = geo.attributes.position, n = geo.attributes.normal, uv = geo.attributes.uv;
  if (!uv || !n) return;
  for (let i = 0; i < p.count; i++) {
    const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    if (ay >= ax && ay >= az) uv.setXY(i, x / su, z / sv);
    else if (ax >= az) uv.setXY(i, z / su, y / sv);
    else uv.setXY(i, x / su, y / sv);
  }
}

/** Cylinder from point a to point b (radius r at a, r2 at b). */
export function rodGeo(a, b, r, seg = 12, r2 = r) {
  const A = V3(...a), B = V3(...b);
  const geo = new THREE.CylinderGeometry(r2, r, A.distanceTo(B), seg, 1);
  geo.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), B.clone().sub(A).normalize()));
  const m = A.add(B).multiplyScalar(0.5);
  geo.translate(m.x, m.y, m.z);
  return geo;
}

/** Merge indexed / non-indexed geometries (position + normal + uv) into one indexed geometry. */
export function mergeGeos(geos) {
  let nv = 0, ni = 0;
  for (const g of geos) { nv += g.attributes.position.count; ni += g.index ? g.index.count : g.attributes.position.count; }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), uv = new Float32Array(nv * 2);
  const idx = nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni);
  let vo = 0, io = 0;
  for (const g of geos) {
    const p = g.attributes.position;
    pos.set(p.array, vo * 3);
    nor.set(g.attributes.normal.array, vo * 3);
    if (g.attributes.uv) uv.set(g.attributes.uv.array, vo * 2);
    if (g.index) { const a = g.index.array; for (let i = 0; i < a.length; i++) idx[io + i] = a[i] + vo; io += a.length; }
    else { for (let i = 0; i < p.count; i++) idx[io + i] = vo + i; io += p.count; }
    vo += p.count;
    g.dispose();
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  out.computeBoundingSphere();
  return out;
}

// ------------------------------------------------------------------ textures (1 texel ≈ 1 cm)

/** Floor boards along x, staggered butt joints, grain (tone 0 honey, 1 darker, 2 pale). */
const planksTex = (tone = 0) => TX(`planks-${tone}`, 128, 128, (ctx, w, h) => {
  const r = rng(901 + tone);
  const base = [[170, 118, 72], [150, 102, 64], [178, 140, 98]][tone];
  const bh = 14;
  for (let y = 0; y < h; y += bh) {
    let x = -Math.floor(r() * 90);
    while (x < w) {
      const len = 50 + r() * 70, v = (r() - 0.5) * 30, warm = (r() - 0.5) * 10;
      for (const ox of [0, w]) {
        ctx.fillStyle = rgb(base[0] + v + warm, base[1] + v, base[2] + v - warm); ctx.fillRect(x - ox, y, len, bh);
        for (let k = 0; k < 6; k++) {
          ctx.fillStyle = rgb(base[0] + v - 28, base[1] + v - 24, base[2] + v - 20, 0.35);
          const gy = y + 1 + Math.floor(r() * (bh - 2));
          ctx.fillRect(x - ox + r() * 8, gy, len * (0.3 + r() * 0.7), 1);
        }
        if (r() < 0.25) { ctx.fillStyle = rgb(base[0] - 60, base[1] - 50, base[2] - 40, 0.6); ctx.fillRect(x - ox + len * r(), y + 4 + r() * 6, 3, 2); }
        ctx.fillStyle = rgb(base[0] - 80, base[1] - 66, base[2] - 50, 0.9); ctx.fillRect(x - ox, y, 1, bh);
      }
      x += len;
    }
    ctx.fillStyle = rgb(base[0] - 90, base[1] - 72, base[2] - 56, 0.85); ctx.fillRect(0, y + bh - 1, w, 1);
    ctx.fillStyle = rgb(base[0] + 30, base[1] + 26, base[2] + 20, 0.25); ctx.fillRect(0, y, w, 1);
  }
});
/** Plain painted plaster with a faint mottle; c = [r, g, b]. */
const paintTex = (key, c) => TX(`paint-${key}`, 64, 64, (ctx, w, h) => {
  const r = rng(key.length * 7 + 3);
  ctx.fillStyle = rgb(...c); ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 700; i++) { const v = (r() - 0.5) * 12; ctx.fillStyle = rgb(c[0] + v, c[1] + v, c[2] + v, 0.5); ctx.fillRect(r() * w, r() * h, 1 + r() * 2, 1); }
});
const terracottaTex = () => TX('terracotta', 64, 64, (ctx, w, h) => {
  const r = rng(77);
  for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) {
    const v = (r() - 0.5) * 24;
    ctx.fillStyle = rgb(150 + v, 86 + v * 0.7, 58 + v * 0.5); ctx.fillRect(i * 32, j * 32, 32, 32);
    for (let k = 0; k < 90; k++) { const q = (r() - 0.5) * 30; ctx.fillStyle = rgb(150 + v + q, 86 + v + q * 0.6, 58 + v + q * 0.4, 0.5); ctx.fillRect(i * 32 + r() * 32, j * 32 + r() * 32, 2, 2); }
  }
  ctx.fillStyle = '#6e5444'; for (let k = 0; k < 2; k++) { ctx.fillRect(k * 32, 0, 1, h); ctx.fillRect(0, k * 32, w, 1); }
});
/** Dark red glazed tiles, light grout, glaze highlights. */
const redTileTex = () => TX('redtile', 64, 64, (ctx, w, h) => {
  const r = rng(51);
  const s = 16;
  ctx.fillStyle = '#c8bcb0'; ctx.fillRect(0, 0, w, h);
  for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
    const v = (r() - 0.5) * 26, x = i * s + 1, y = j * s + 1;
    ctx.fillStyle = rgb(112 + v, 18 + v * 0.3, 28 + v * 0.3); ctx.fillRect(x, y, s - 1, s - 1);
    ctx.fillStyle = rgb(80 + v, 10, 20, 0.6); ctx.fillRect(x, y + s - 3, s - 1, 2);
    ctx.fillStyle = 'rgba(255,200,200,0.45)'; ctx.fillRect(x + 2 + r() * 3, y + 2, 4 + r() * 4, 1); ctx.fillRect(x + 2, y + 3, 2, 2);
    for (let k = 0; k < 6; k++) { ctx.fillStyle = rgb(150 + v, 40, 50, 0.4); ctx.fillRect(x + r() * s, y + r() * s, 2, 1); }
  }
});
/** Oak, k: 0 grey-brown, 1 mid honey, 2 dark. Grain runs along v. */
const oakTex = (k = 0) => TX(`oak-${k}`, 32, 128, (ctx, w, h) => {
  const r = rng(61 + k);
  const b = [[132, 100, 68], [168, 122, 74], [118, 82, 52]][k];
  ctx.fillStyle = rgb(...b); ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 40; i++) {
    const x = r() * w, v = (r() - 0.5) * 40;
    ctx.fillStyle = rgb(b[0] + v, b[1] + v * 0.8, b[2] + v * 0.6, 0.35);
    for (let y = 0; y < h; y += 2) ctx.fillRect(x + Math.sin(y * 0.05 + i) * 1.5, y, 1, 2);
  }
  for (let i = 0; i < 3; i++) { ctx.fillStyle = rgb(b[0] - 50, b[1] - 40, b[2] - 30, 0.5); ctx.fillRect(r() * w, r() * h, 2, 4); }
});
/** Espresso-stained wood. */
const darkWoodTex = () => TX('darkwood', 32, 64, (ctx, w, h) => {
  const r = rng(71);
  ctx.fillStyle = '#3a2219'; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 30; i++) { const x = r() * w; ctx.fillStyle = r() < 0.5 ? 'rgba(20,10,6,0.4)' : 'rgba(90,56,40,0.25)'; ctx.fillRect(x, 0, 1, h); }
});
/** Leaded stained glass: rippled panes, a wheat sheaf in gold and green (cabinet doors). */
const stainedTex = () => TX('stained', 48, 96, (ctx, w, h) => {
  const r = rng(81);
  ctx.fillStyle = '#7d8a88'; ctx.fillRect(0, 0, w, h);
  for (let y = 0; y < h; y += 2) { ctx.fillStyle = `rgba(${r() < 0.5 ? '210,220,214' : '60,70,70'},${0.15 + r() * 0.2})`; ctx.fillRect(0, y, w, 1); }
  const wheat = (cx, cy, s) => {
    ctx.fillStyle = '#4a7a3a'; ctx.fillRect(cx, cy, 1, s); ctx.fillRect(cx - 4, cy + 6, 1, s - 6); ctx.fillRect(cx + 4, cy + 6, 1, s - 6);
    for (const dx of [-4, 0, 4]) for (let k = 0; k < 5; k++) { ctx.fillStyle = k % 2 ? '#e0b040' : '#c88a20'; ctx.fillRect(cx + dx - 1, cy - 8 + k * 3 + Math.abs(dx) / 2, 3, 2); }
    ctx.fillStyle = '#78a848'; ctx.fillRect(cx - 3, cy + s - 8, 2, 4); ctx.fillRect(cx + 2, cy + s - 10, 2, 4);
  };
  wheat(24, 14, 22); wheat(24, 64, 22);
  ctx.fillStyle = '#2a2a24';
  ctx.fillRect(0, 0, w, 2); ctx.fillRect(0, h - 2, w, 2); ctx.fillRect(0, 0, 2, h); ctx.fillRect(w - 2, 0, 2, h);
  ctx.fillRect(0, 44, w, 2); ctx.fillRect(0, 50, w, 2); ctx.fillRect(w / 2 - 1, 44, 2, 8);
});
/** White slatted blinds: 2.5 cm slats with see-through gaps and two ladder cords (alpha). */
const blindsTex = () => TX('blinds', 32, 32, (ctx, w, h) => {
  for (let y = 0; y < h; y += 4) {
    ctx.fillStyle = '#efeee8'; ctx.fillRect(0, y, w, 2);
    ctx.fillStyle = '#c8c6be'; ctx.fillRect(0, y + 2, w, 1);
  }
  ctx.fillStyle = 'rgba(220,214,200,0.9)'; ctx.fillRect(7, 0, 1, h); ctx.fillRect(24, 0, 1, h);
});
/** Cream bedding with navy stripes. */
const stripeTex = () => TX('stripes', 64, 32, (ctx, w, h) => {
  const r = rng(91);
  ctx.fillStyle = '#e9e2d0'; ctx.fillRect(0, 0, w, h);
  for (let x = 4; x < w; x += 16) {
    ctx.fillStyle = '#3a3e52'; ctx.fillRect(x, 0, 2, h); ctx.fillRect(x + 4, 0, 1, h);
    for (let y = 0; y < h; y += 4) { ctx.fillStyle = '#2a2e40'; ctx.fillRect(x + 8, y, 1, 2); }
  }
  for (let i = 0; i < 120; i++) { ctx.fillStyle = 'rgba(120,110,90,0.12)'; ctx.fillRect(r() * w, r() * h, 2, 1); }
});
const tickingTex = () => TX('ticking', 32, 32, (ctx, w, h) => {
  ctx.fillStyle = '#9aa6b4'; ctx.fillRect(0, 0, w, h);
  for (let x = 0; x < w; x += 4) { ctx.fillStyle = '#7e8a9a'; ctx.fillRect(x, 0, 1, h); }
  for (let y = 0; y < h; y += 2) { ctx.fillStyle = 'rgba(255,255,255,0.05)'; ctx.fillRect(0, y, w, 1); }
});
const shagTex = () => TX('shag', 64, 64, (ctx, w, h) => {
  const r = rng(101);
  ctx.fillStyle = '#8c8578'; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 1600; i++) { const v = (r() - 0.5) * 50; ctx.fillStyle = rgb(140 + v, 133 + v, 120 + v, 0.7); ctx.fillRect(r() * w, r() * h, 1, 2 + r() * 2); }
});
const carpetTex = () => TX('carpet', 32, 32, (ctx, w, h) => {
  const r = rng(111);
  ctx.fillStyle = '#7e7c7a'; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 500; i++) { const v = (r() - 0.5) * 30; ctx.fillStyle = rgb(126 + v, 124 + v, 122 + v); ctx.fillRect(r() * w, r() * h, 1, 1); }
});
const juteTex = () => TX('jute', 32, 32, (ctx, w, h) => {
  const r = rng(121);
  for (let y = 0; y < h; y += 2) for (let x = 0; x < w; x += 2) {
    const v = (r() - 0.5) * 24 + (((x + y) / 2) % 2 ? 10 : -10);
    ctx.fillStyle = rgb(176 + v, 150 + v, 104 + v); ctx.fillRect(x, y, 2, 2);
  }
});
/** Wool tartan, k: 0 cream/red, 1 green. */
const plaidTex = (k = 0) => TX(`plaid-${k}`, 32, 32, (ctx, w, h) => {
  const base = k ? '#4a5a48' : '#c8b89a', band = k ? '#2a3428' : '#8a3a2a', thin = k ? '#c8b070' : '#3a2e28';
  ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
  ctx.globalAlpha = 0.7; ctx.fillStyle = band; ctx.fillRect(0, 10, w, 6); ctx.fillRect(10, 0, 6, h);
  ctx.globalAlpha = 0.8; ctx.fillStyle = thin; ctx.fillRect(0, 24, w, 1); ctx.fillRect(24, 0, 1, h);
  ctx.globalAlpha = 1;
});
const quiltTex = () => TX('quilt', 32, 32, (ctx, w, h) => {
  const r = rng(131);
  const cols = ['#b85a3a', '#e0c070', '#4a6a8a', '#7a9a5a', '#d8d0c0', '#8a3a4a', '#5a8a8a'];
  for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
    ctx.fillStyle = cols[Math.floor(r() * cols.length)]; ctx.fillRect(i * 8, j * 8, 8, 8);
    ctx.fillStyle = 'rgba(255,255,255,0.25)'; ctx.fillRect(i * 8 + 2, j * 8 + 2, 2, 2);
  }
  ctx.fillStyle = 'rgba(40,30,20,0.35)'; for (let k = 0; k < 4; k++) { ctx.fillRect(k * 8, 0, 1, h); ctx.fillRect(0, k * 8, w, 1); }
});
const coirTex = () => TX('coir', 32, 16, (ctx, w, h) => {
  const r = rng(141);
  for (let i = 0; i < 400; i++) { const v = (r() - 0.5) * 40; ctx.fillStyle = rgb(150 + v, 110 + v, 60 + v); ctx.fillRect(r() * w, r() * h, 1, 1); }
  ctx.fillStyle = '#3a2a1a'; ctx.fillRect(0, 0, w, 1); ctx.fillRect(0, h - 1, w, 1); ctx.fillRect(0, 0, 1, h); ctx.fillRect(w - 1, 0, 1, h);
});
/** A sheet of paper with typed lines (k 0 white, 1 with a red header, 2 yellowed). */
const paperTex = (k = 0) => TX(`paper-${k}`, 24, 32, (ctx, w, h) => {
  const r = rng(151 + k);
  ctx.fillStyle = k === 2 ? '#e8e0c8' : '#eeece6'; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(40,40,50,0.55)';
  for (let y = 4; y < h - 3; y += 2) ctx.fillRect(3, y, 6 + r() * 14, 1);
  if (k === 1) { ctx.fillStyle = '#8a2a2a'; ctx.fillRect(3, 2, 10, 1); }
});
/** Palm frond / pothos leaves with alpha. */
const leafTex = (kind) => TX(`leaf-${kind}`, 64, 96, (ctx, w, h) => {
  const r = rng(kind === 'palm' ? 221 : 231);
  if (kind === 'palm') {
    ctx.strokeStyle = '#3a5a2a'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(32, h); ctx.quadraticCurveTo(30, 40, 34, 2); ctx.stroke();
    for (let y = 8; y < h - 8; y += 3) {
      const t = y / h, len = 24 * Math.sin(Math.PI * Math.min(1, (1 - t) * 1.2)) + 4;
      for (const s of [-1, 1]) {
        ctx.strokeStyle = r() < 0.5 ? '#4a7a34' : '#5a8a3c'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(32 + (1 - t) * 2, y); ctx.lineTo(32 + s * len, y + 10 + len * 0.3); ctx.stroke();
      }
    }
  } else {
    for (let i = 0; i < 9; i++) {
      const x = 10 + r() * 44, y = 8 + i * 9 + r() * 4, s = 7 + r() * 4;
      ctx.fillStyle = r() < 0.5 ? '#4a8a3a' : '#6a9a3a';
      ctx.beginPath(); ctx.moveTo(x, y + s); ctx.bezierCurveTo(x - s, y + s * 0.3, x - s * 0.6, y - s * 0.6, x, y - s * 0.2); ctx.bezierCurveTo(x + s * 0.6, y - s * 0.6, x + s, y + s * 0.3, x, y + s); ctx.fill();
      ctx.fillStyle = 'rgba(230,230,150,0.4)'; ctx.fillRect(x - 1, y, 2, s * 0.6);
    }
    ctx.strokeStyle = '#3a5a2a'; ctx.beginPath(); ctx.moveTo(32, 0); ctx.bezierCurveTo(20, 30, 44, 60, 30, h); ctx.stroke();
  }
}, { nearest: false });
/** Mirror: a soft painted reflection of a warm room (no env map). */
const mirrorTex = () => TX('mirror', 32, 48, (ctx, w, h) => {
  const g = ctx.createLinearGradient(0, 0, w, h); g.addColorStop(0, '#6a6460'); g.addColorStop(0.5, '#4a4440'); g.addColorStop(1, '#2a2624');
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(255,220,170,0.25)'; ctx.fillRect(4, 8, 10, 16);
  ctx.fillStyle = 'rgba(255,255,255,0.18)'; for (let i = 0; i < 6; i++) ctx.fillRect(18 + i, 4 + i * 2, 2, 30);
}, { nearest: false });
/** Roman shade fabric: oatmeal linen weave with small sprigs in `color`. */
function romanTex(color) {
  const c = new THREE.Color(color);
  const tint = `rgb(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)})`;
  return canvasTexture(`fk-roman-${color}`, 128, 128, (ctx, w, h) => {
    const r = rng(733);
    ctx.fillStyle = '#e6dcc8'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 2) { ctx.fillStyle = `rgba(150,130,100,${0.06 + r() * 0.06})`; ctx.fillRect(0, y, w, 1); }
    for (let x = 0; x < w; x += 2) { ctx.fillStyle = `rgba(255,250,240,${0.04 + r() * 0.05})`; ctx.fillRect(x, 0, 1, h); }
    for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
      const x = i * 32 + (j % 2) * 16 + 8, y = j * 32 + 10;
      ctx.strokeStyle = tint; ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.moveTo(x, y + 12); ctx.quadraticCurveTo(x + 1, y + 5, x + 2, y); ctx.stroke();
      ctx.fillStyle = tint;
      for (const [dx, dy, a] of [[-3, 4, -0.6], [4, 6, 0.6], [-2, 9, -0.5], [3, 1, 0.5]]) { ctx.beginPath(); ctx.ellipse(x + dx, y + dy, 2.6, 1.2, a, 0, 7); ctx.fill(); }
    }
  }, { repeat: [2, 2] });
}
/** A placeholder picture for frames: a few pixel hills under a sky. Pass your own texture instead. */
const artTex = (k = 0) => TX(`art-${k}`, 48, 32, (ctx, w, h) => {
  const r = rng(301 + k);
  const sky = [[180, 170, 150], [120, 140, 160], [200, 160, 120]][k % 3];
  ctx.fillStyle = rgb(...sky); ctx.fillRect(0, 0, w, h);
  for (let l = 0; l < 3; l++) {
    ctx.fillStyle = rgb(sky[0] - 40 - l * 30, sky[1] - 30 - l * 28, sky[2] - 40 - l * 30);
    let y = h * (0.45 + l * 0.15);
    for (let x = 0; x < w; x++) { y += (r() - 0.5) * 2; ctx.fillRect(x, y, 1, h - y); }
  }
});

/** Soft vertical light shaft (a sunbeam through a window or between trees), additive alpha. */
export function shaftTexture() {
  return canvasTexture('fk-shaft', 64, 256, (ctx, w, h) => {
    const img = ctx.createImageData(w, h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const u = Math.abs(x / w - 0.5) * 2, v = y / h;
      const a = Math.pow(1 - u, 2.2) * Math.sin(Math.PI * Math.min(1, v * 1.15)) * (0.75 + 0.25 * noise3(x / 9, y / 40, 1, 4));
      const i = (y * w + x) * 4;
      img.data[i] = 255; img.data[i + 1] = 255; img.data[i + 2] = 255; img.data[i + 3] = Math.max(0, a) * 255;
    }
    ctx.putImageData(img, 0, 0);
  }, { color: false });
}

// ------------------------------------------------------------------ window views

/**
 * The view out of a window, painted per state ('day' | 'evening' | 'night') and pixelated:
 * a small northern town in November — grey hills with snow on the tops, a spruce belt, wood-sided
 * houses with lit windows, street lamps, a pickup. variant 'low' = across the street (ground
 * floor), 'high' = over the roofs (upper floor). Write your own view functions with the same
 * signature (time, variant) → texture and pass them to viewPlane / brightWindow.
 * Never brighter than #E4DCCC on screen: the view material is tinted per state.
 */
export function townView(time, variant = 'low') {
  return canvasTexture(`fk-view-${variant}-${time}`, 768, 512, (ctx, w, h) => {
    const r = rng(variant === 'high' ? 77 : 41);
    const day = time === 'day', eve = time === 'evening';
    const pick = (d, e, n) => (day ? d : eve ? e : n);
    const high = variant === 'high';
    const hz = h * (high ? 0.44 : 0.36);
    // sky
    const sk = ctx.createLinearGradient(0, 0, 0, hz + 40);
    if (day) { sk.addColorStop(0, '#7c8794'); sk.addColorStop(0.6, '#a6afb8'); sk.addColorStop(1, '#bcc3c8'); }
    else if (eve) { sk.addColorStop(0, '#0a1226'); sk.addColorStop(0.55, '#1c2b4c'); sk.addColorStop(1, '#3c4668'); }
    else { sk.addColorStop(0, '#02040a'); sk.addColorStop(0.6, '#070d1a'); sk.addColorStop(1, '#0e1628'); }
    ctx.fillStyle = sk; ctx.fillRect(0, 0, w, h);
    if (!day) for (let i = 0; i < (eve ? 12 : 40); i++) { ctx.fillStyle = `rgba(220,230,255,${0.3 + r() * 0.5})`; ctx.fillRect(r() * w, r() * hz * 0.6, 2, 2); }
    if (time === 'night') { const m = ctx.createRadialGradient(600, 70, 2, 600, 70, 60); m.addColorStop(0, 'rgba(230,236,255,0.9)'); m.addColorStop(0.2, 'rgba(160,180,220,0.3)'); m.addColorStop(1, 'rgba(60,80,120,0)'); ctx.fillStyle = m; ctx.fillRect(520, 0, 160, 150); ctx.fillStyle = '#e4e8f0'; ctx.beginPath(); ctx.arc(600, 70, 11, 0, 7); ctx.fill(); }
    if (eve) { const gl = ctx.createLinearGradient(0, hz - 40, 0, hz + 30); gl.addColorStop(0, 'rgba(140,110,120,0)'); gl.addColorStop(1, 'rgba(150,110,110,0.35)'); ctx.fillStyle = gl; ctx.fillRect(0, hz - 40, w, 70); }
    // hills: two ranges, snow on the higher tops only (November)
    for (let k = 0; k < 2; k++) {
      const ridge = [];
      for (let x = 0; x <= w; x += 4) ridge.push(hz - (k ? 50 : 110) + Math.sin(x * 0.006 + k * 2.1) * (k ? 22 : 46) + Math.sin(x * 0.019 + k) * 12 + Math.sin(x * 0.05) * 4);
      ctx.fillStyle = pick(['#8892a0', '#6c7682'][k], ['#1d2844', '#151e36'][k], ['#0b1220', '#080e1a'][k]);
      ctx.beginPath(); ctx.moveTo(0, h); ridge.forEach((y, i) => ctx.lineTo(i * 4, y)); ctx.lineTo(w, h); ctx.fill();
      if (k === 0) {
        const top = Math.min(...ridge);
        ctx.fillStyle = pick('#d4d9de', '#4a5878', '#24304a');
        ridge.forEach((y, i) => { const d = (top + 44 - y) * 0.7 + Math.sin(i * 1.7) * 6; if (d > 2) ctx.fillRect(i * 4, y, 4, d); });
      }
    }
    // spruce belt
    const spruce = (x, y, s, c) => {
      ctx.fillStyle = c; ctx.beginPath(); ctx.moveTo(x, y - s);
      for (let k = 1; k <= 6; k++) { const yy = y - s + (s * k) / 6, ww = s * (0.05 + 0.2 * k / 6); ctx.lineTo(x + ww, yy); ctx.lineTo(x + ww * 0.4, yy - s * 0.02); }
      for (let k = 6; k >= 1; k--) { const yy = y - s + (s * k) / 6, ww = s * (0.05 + 0.2 * k / 6); ctx.lineTo(x - ww * 0.4, yy - s * 0.02); ctx.lineTo(x - ww, yy); }
      ctx.fill();
    };
    const belt = hz + (high ? 20 : 10);
    ctx.fillStyle = pick('#4a5450', '#0e1420', '#05080e'); ctx.fillRect(0, belt - 8, w, h);
    for (let i = 0; i < 110; i++) spruce(r() * w, belt + r() * 10, 30 + r() * 30, pick(r() < 0.5 ? '#3a4640' : '#46524a', '#0a101a', '#04070c'));
    // houses across the street
    const groundY = high ? h * 0.78 : h * 0.72;
    ctx.fillStyle = pick('#6e6656', '#16181e', '#0a0c10'); ctx.fillRect(0, groundY - 40, w, h);
    const sidings = [[138, 74, 58], [90, 106, 120], [176, 150, 90], [95, 112, 90], [200, 192, 176], [120, 60, 50]];
    const k0 = pick(1, 0.28, 0.12);
    const lamps = [];
    let hx = -40 + r() * 30;
    while (hx < w) {
      const bw = 120 + r() * 70, wh = 70 + r() * 30, rh = 34 + r() * 20, y = groundY - 10 + r() * 8;
      const c = sidings[Math.floor(r() * sidings.length)];
      const tint = (v, i) => v * k0 + (day ? 0 : [10, 14, 28][i]);
      ctx.fillStyle = rgb(tint(c[0], 0), tint(c[1], 1), tint(c[2], 2)); ctx.fillRect(hx, y - wh, bw, wh);
      ctx.fillStyle = 'rgba(0,0,0,0.12)'; for (let yy = y - wh; yy < y; yy += 5) ctx.fillRect(hx, yy, bw, 1);
      ctx.fillStyle = pick('#3a3a40', '#0e1018', '#06080c');
      ctx.beginPath(); ctx.moveTo(hx - 8, y - wh); ctx.lineTo(hx + bw / 2, y - wh - rh); ctx.lineTo(hx + bw + 8, y - wh); ctx.fill();
      ctx.fillStyle = pick('rgba(226,230,234,0.75)', 'rgba(90,104,140,0.6)', 'rgba(50,62,90,0.6)');
      for (let k = 0; k < 14; k++) { const t = r(), side = r() < 0.5 ? -1 : 1; const px = hx + bw / 2 + side * t * (bw / 2 + 6), py = y - wh - rh * (1 - t); ctx.fillRect(px - 6, py, 10 + r() * 8, 3); }
      ctx.fillStyle = pick('#4a3a34', '#120e10', '#08080a'); ctx.fillRect(hx + bw * 0.7, y - wh - rh * 0.8, 10, rh * 0.6);
      for (let k = 0; k < 3; k++) {
        const wx = hx + 14 + k * (bw - 40) / 2, wy = y - wh + 18;
        const lit = eve ? r() < 0.75 : time === 'night' ? r() < 0.22 : false;
        ctx.fillStyle = pick('#e4e6e2', '#2a2e38', '#1a1c22'); ctx.fillRect(wx - 2, wy - 2, 24, 26);
        ctx.fillStyle = lit ? (r() < 0.7 ? '#ffc878' : '#ffe2a8') : pick('#4a5868', '#141a28', '#0c1018');
        ctx.fillRect(wx, wy, 20, 22);
        if (lit) { const gg = ctx.createRadialGradient(wx + 10, wy + 11, 2, wx + 10, wy + 11, 30); gg.addColorStop(0, 'rgba(255,190,110,0.35)'); gg.addColorStop(1, 'rgba(255,190,110,0)'); ctx.fillStyle = gg; ctx.fillRect(wx - 20, wy - 20, 60, 62); }
        ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(wx + 9, wy, 2, 22);
      }
      ctx.fillStyle = pick('#5a4030', '#120c0a', '#080606'); ctx.fillRect(hx + bw - 34, y - 46, 18, 46);
      lamps.push(hx + bw + 12);
      hx += bw + 30 + r() * 30;
    }
    // bare birches, the street, sidewalk, a pickup, lamp posts
    for (let i = 0; i < 6; i++) {
      const tx = r() * w, ty = groundY + 4, s = 90 + r() * 50;
      ctx.strokeStyle = pick('#c8c4bc', '#2a2c34', '#14161c'); ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(tx, ty - s); ctx.stroke();
      ctx.strokeStyle = pick('#5a4a40', '#181a20', '#0c0e12'); ctx.lineWidth = 1;
      for (let k = 0; k < 14; k++) { const by = ty - s * (0.4 + r() * 0.6), a = (r() - 0.5) * 1.6; ctx.beginPath(); ctx.moveTo(tx, by); ctx.lineTo(tx + Math.sin(a) * 30, by - Math.cos(a) * 26); ctx.stroke(); }
    }
    ctx.fillStyle = pick('#8a8a86', '#24262c', '#121418'); ctx.fillRect(0, groundY + 6, w, 8);
    ctx.fillStyle = pick('#4e5054', '#141820', '#0a0c10'); ctx.fillRect(0, groundY + 14, w, h);
    ctx.fillStyle = pick('rgba(220,224,228,0.6)', 'rgba(80,90,120,0.5)', 'rgba(50,60,80,0.5)'); for (let i = 0; i < 50; i++) ctx.fillRect(r() * w, groundY + 4 + r() * 6, 6 + r() * 14, 2);
    const px = 420, py = groundY + 40;
    ctx.fillStyle = pick('#6a2a22', '#1e1418', '#0e0a0c'); ctx.fillRect(px, py - 26, 130, 26); ctx.fillRect(px + 10, py - 46, 56, 22);
    ctx.fillStyle = pick('#8a9aa8', '#1a2230', '#0c1018'); ctx.fillRect(px + 16, py - 42, 44, 14);
    ctx.fillStyle = '#0a0a0c'; ctx.fillRect(px + 14, py - 6, 24, 14); ctx.fillRect(px + 94, py - 6, 24, 14);
    for (const lx of lamps.filter((_, i) => i % 2 === 0)) {
      ctx.fillStyle = pick('#3a3c40', '#0c0e12', '#06070a'); ctx.fillRect(lx, groundY - 120, 4, 134); ctx.fillRect(lx - 14, groundY - 120, 18, 4);
      if (!day) {
        const gg = ctx.createRadialGradient(lx - 10, groundY - 114, 1, lx - 10, groundY - 114, 60); gg.addColorStop(0, 'rgba(255,200,120,0.95)'); gg.addColorStop(0.15, 'rgba(255,160,80,0.4)'); gg.addColorStop(1, 'rgba(255,140,60,0)');
        ctx.fillStyle = gg; ctx.fillRect(lx - 80, groundY - 180, 140, 140);
        const pool = ctx.createRadialGradient(lx - 10, groundY + 30, 2, lx - 10, groundY + 30, 70); pool.addColorStop(0, 'rgba(255,170,90,0.35)'); pool.addColorStop(1, 'rgba(255,170,90,0)');
        ctx.fillStyle = pool; ctx.fillRect(lx - 90, groundY - 10, 160, 90);
      }
    }
    pixelate(ctx, w, h, 3);
  }, { nearest: true, aniso: 1 });
}


// ------------------------------------------------------------------ light profiles

/**
 * Lens-flare / exposure profiles for window-light.js. A "light zone" = profile + position + dir.
 *   Windows (brightWindow):  A warm old window · B cold modern · C through blinds (streaks) · D very strong
 *   Point sources (flareSource): LAMP warm lamp · PALE overcast window · MOON · MIST sun in fog ·
 *   LOWSUN low sun / headlights ('anamorphic')
 * shaft / patch = opacity of the light shaft and the floor patch that brightWindow builds.
 */
export const WINDOW_PROFILES = {
  A: { id: 'A', color: 0xffd8a0, triggerDistance: 3.4, fadeDistance: 2.2, intensity: 1.0, exposure: 0.13, bloom: 0.18, shaft: 0.18, patch: 0.28,
    flareSize: 1.0, starburstIntensity: 1.0, ghostIntensity: 0.8, ghostCount: 6, ghostSpacing: 0.42, ringIntensity: 0.5, colorTint: [1.0, 0.86, 0.6], ghostTints: [[0.5, 1.0, 0.6], [0.8, 1.0, 0.5], [1.0, 0.7, 0.3]], maxScreenOpacity: 0.85, old: true },
  B: { id: 'B', color: 0xdfe8ff, triggerDistance: 2.8, fadeDistance: 1.8, intensity: 0.7, exposure: 0.12, bloom: 0.2, shaft: 0.14, patch: 0.18,
    flareSize: 0.75, starburstIntensity: 0.45, ghostIntensity: 0.6, ghostCount: 5, ghostSpacing: 0.5, ringIntensity: 0.6, colorTint: [0.85, 0.92, 1.0], ghostTints: [[0.5, 0.6, 1.0], [0.8, 0.5, 1.0], [0.6, 0.9, 1.0]], maxScreenOpacity: 0.6 },
  C: { id: 'C', color: 0xe8ecf4, triggerDistance: 2.6, fadeDistance: 1.6, intensity: 0.55, exposure: 0.08, bloom: 0.25, shaft: 0.12, patch: 0.14,
    flareSize: 0.7, starburstIntensity: 0.3, ghostIntensity: 0.35, ghostCount: 3, ghostSpacing: 0.6, ringIntensity: 0.2, colorTint: [0.95, 0.97, 1.0], ghostTints: [[0.9, 0.95, 1.0]], streaks: true, maxScreenOpacity: 0.5, old: true },
  D: { id: 'D', color: 0xfff0d4, triggerDistance: 4.5, fadeDistance: 4.0, intensity: 1.2, exposure: 0.24, bloom: 0.4, shaft: 0.2, patch: 0.3,
    flareSize: 1.35, starburstIntensity: 1.4, ghostIntensity: 1.0, ghostCount: 8, ghostSpacing: 0.36, ringIntensity: 0.8, colorTint: [1.0, 0.94, 0.8], ghostTints: [[0.5, 1.0, 0.6], [0.4, 0.7, 1.0], [1.0, 0.4, 0.3], [1.0, 0.85, 0.4]], maxScreenOpacity: 0.95, old: true },
};
const fbase = { triggerDistance: 3.0, fadeDistance: 2.0, exposure: 0.08, bloom: 0.15, starburstIntensity: 0, ringIntensity: 0, ghostCount: 6, ghostSpacing: 0.4, ghostTints: [[1, 0.8, 0.5]] };
export const FLARE_PROFILES = {
  LAMP: { ...fbase, id: 'LAMP', style: 'star', intensity: 0.8, flareSize: 0.75, ghostIntensity: 0.7, colorTint: [1.0, 0.78, 0.5], maxScreenOpacity: 0.75 },
  PALE: { ...fbase, id: 'PALE', style: 'star', intensity: 0.6, flareSize: 0.8, ghostIntensity: 0.5, colorTint: [0.9, 0.94, 1.0], maxScreenOpacity: 0.55, exposure: 0.1 },
  MOON: { ...fbase, id: 'MOON', style: 'star', intensity: 0.5, flareSize: 0.6, ghostIntensity: 0.45, colorTint: [0.7, 0.82, 1.0], maxScreenOpacity: 0.5, exposure: 0.04, bloom: 0.08 },
  MIST: { ...fbase, id: 'MIST', style: 'star', intensity: 0.55, flareSize: 1.3, ghostIntensity: 0.35, colorTint: [1.0, 0.92, 0.78], maxScreenOpacity: 0.5, exposure: 0.05, bloom: 0.12 },
  LOWSUN: { ...fbase, id: 'LOWSUN', style: 'anamorphic', intensity: 0.9, flareSize: 0.9, ghostIntensity: 0.8, colorTint: [1.0, 0.66, 0.25], maxScreenOpacity: 0.8, exposure: 0.1, bloom: 0.2 },
};
/** A point light zone for window-light.js: profile + position (+ dir, default facing the camera). */
export function flareSource(profile, position, opts = {}) {
  return { ...FLARE_PROFILES[profile], position, dir: opts.dir || new THREE.Vector3(0, 0, 1), ...opts };
}

/** The texture library. Use with kit.texM(key, TEX.oak(1)). */
export const TEX = {
  planks: planksTex, paint: paintTex, terracotta: terracottaTex, redTile: redTileTex, oak: oakTex,
  darkWood: darkWoodTex, stained: stainedTex, blinds: blindsTex, stripes: stripeTex, ticking: tickingTex,
  shag: shagTex, carpet: carpetTex, jute: juteTex, plaid: plaidTex, quilt: quiltTex, coir: coirTex,
  paper: paperTex, leaf: leafTex, mirror: mirrorTex, roman: romanTex, art: artTex,
  view: townView, shaft: shaftTexture,
};

export const BOOK_COLS = [0x7a2a24, 0x2a4a5a, 0xc8a050, 0x3a5a3a, 0xd8d0c0, 0x5a3a5a, 0x2a2a30, 0x9a5a2a, 0x4a6a8a];

/** Scene states: hemisphere sky/ground + a directional fill + background. Lamps have a level per state. */
export const AMBIENT = {
  evening: { sky: 0x58586c, ground: 0x2a2018, hemi: 0.62, fill: 0xffd2a0, fillI: 0.28, bg: 0x0a0a12 },
  night: { sky: 0x2a3654, ground: 0x0c0a0a, hemi: 0.38, fill: 0x8aa4d8, fillI: 0.3, bg: 0x04060a },
  day: { sky: 0xdce2ea, ground: 0x8a7a66, hemi: 1.0, fill: 0xe8eef4, fillI: 0.55, bg: 0x6a7078 },
};

// ------------------------------------------------------------------ the kit
// (LocationKit; `FurnitureKit` is the same class under its old name)

export class LocationKit {
  /**
   * @param root  THREE.Object3D everything is added to (a scene or a group)
   * @param low   true → MeshLambertMaterial everywhere (weak GPUs / swiftshader), false → Standard
   * @param ambient  state table (defaults to AMBIENT); add your own states freely
   */
  constructor(root, { low = false, ambient = AMBIENT } = {}) {
    this.root = root;
    this.low = low;
    this.ambient = ambient;
    this.mats = new Map();
    this._batches = new Map();
    this.T = null;
    this.lamps = [];
    this.stateFx = [];
    this.flames = [];
    this.views = [];
    this.windowLights = [];   // light zones for window-light.js (windows, lamps, sun, moon)
    this.state = 'evening';
    this.time = 0;
    this.background = ambient.evening?.bg ?? 0x000000;
  }

  // ---------------------------------------------------------------- materials (cached by key)

  mat(key, params) {
    if (this.mats.has(key)) return this.mats.get(key);
    const M = this.low && !params.forceStandard ? THREE.MeshLambertMaterial : THREE.MeshStandardMaterial;
    const p = { ...params };
    delete p.forceStandard;
    if (M === THREE.MeshLambertMaterial) { delete p.roughness; delete p.metalness; delete p.envMapIntensity; }
    const m = new M(p);
    this.mats.set(key, m);
    return m;
  }
  M(key, color, o = {}) { return this.mat(`c-${key}`, { color, roughness: 0.75, metalness: 0, ...o }); }
  texM(key, map, o = {}) { return this.mat(`t-${key}`, { map, color: 0xffffff, roughness: 0.8, metalness: 0, ...o }); }
  /** A material that can glow (lamp shade, bulb) — its emissive is switched by a lamp. */
  glowM(key, color, emissive, o = {}) { return this.mat(`g-${key}`, { color, emissive, emissiveIntensity: 0, roughness: 0.8, ...o }); }
  glass() { return this.mat('glass', { color: 0xc8d4dc, roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.16, depthWrite: false }); }
  brass() { return this.M('brass', 0xb08840, { roughness: 0.32, metalness: 0.85, emissive: 0x1a1004 }); }
  white() { return this.M('trimWhite', 0xece8e0, { roughness: 0.55 }); }

  // ---------------------------------------------------------------- batching

  /**
   * Queue a geometry under a material. o: { sx, sy, sz, rx, ry, rz, order, uv: [su, sv] }.
   * Scale → rotate → translate → current local frame (withT). The geometry is mutated, so it
   * must be fresh or a clone — never a cached original.
   */
  _add(geo, mat, x = 0, y = 0, z = 0, o = {}) {
    if (o.sx || o.sy || o.sz) geo.scale(o.sx || 1, o.sy || 1, o.sz || 1);
    if (o.rx || o.ry || o.rz) geo.applyMatrix4(new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(o.rx || 0, o.ry || 0, o.rz || 0, o.order || 'XYZ')));
    geo.translate(x, y, z);
    if (this.T) geo.applyMatrix4(this.T);
    if (!geo.attributes.normal) geo.computeVertexNormals();
    if (o.uv) worldUV(geo, o.uv[0], o.uv[1]);
    let list = this._batches.get(mat);
    if (!list) this._batches.set(mat, (list = []));
    list.push(geo);
    return geo;
  }
  /** Run `fn` with a local frame: origin (x, y, z), turned by ry around y. Frames nest. */
  withT(x, z, ry, fn, y = 0) {
    const prev = this.T;
    const m = new THREE.Matrix4().makeRotationY(ry).setPosition(x, y, z);
    this.T = prev ? prev.clone().multiply(m) : m;
    fn();
    this.T = prev;
  }
  /** Local → world point under the current frame (for lights / sprites placed inside withT). */
  P(x, y, z) { const v = V3(x, y, z); if (this.T) v.applyMatrix4(this.T); return v; }

  /** Bevelled box (default for anything boxy). */
  bx(w, h, d, mat, x, y, z, o) { return this._add(bevelBox(w, h, d), mat, x, y, z, o); }
  /** Rounded box with radius r (o.seg = smoothness, default 2). */
  rb(w, h, d, r, mat, x, y, z, o = {}) { return this._add(cached(`rb|${w}|${h}|${d}|${r}|${o.seg || 2}`, () => roundedBox(w, h, d, Math.min(r, w / 2 - 0.001, h / 2 - 0.001, d / 2 - 0.001), o.seg || 2)), mat, x, y, z, o); }
  /** Cushion (puffed rounded box). o: { puff, seed, lump } + transform. */
  cush(w, h, d, r, mat, x, y, z, o = {}) { return this._add(cushionGeo(w, h, d, r, o.puff ?? 0.3, o.seed ?? 1, o.lump ?? 0.006), mat, x, y, z, o); }
  /** Plane facing +z (rotate with o.rx / o.ry). Offset ≥ 1 cm from any parallel surface. */
  pl(w, h, mat, x, y, z, o) { return this._add(new THREE.PlaneGeometry(w, h), mat, x, y, z, o); }
  cy(rt, rb, h, mat, x, y, z, o = {}) { return this._add(new THREE.CylinderGeometry(rt, rb, h, o.seg || 20, 1, !!o.open), mat, x, y, z, o); }
  sph(r, mat, x, y, z, o = {}) { return this._add(new THREE.SphereGeometry(r, o.ws || 16, o.hs || 12), mat, x, y, z, o); }
  /** Lathe from [[radius, y], …] (bottom → top). Radius is clamped ≥ 0.8 mm: no point on the axis. */
  lathe(pts, mat, x, y, z, o = {}) {
    const p = pts[0][1] > pts[pts.length - 1][1] ? [...pts].reverse() : pts;
    return this._add(new THREE.LatheGeometry(p.map(([r, py]) => new THREE.Vector2(Math.max(0.0008, r), py)), o.seg || 24), mat, x, y, z, o);
  }
  /** Rod between two local points. */
  rod(a, b, r, mat, o = {}) { return this._add(rodGeo(a, b, r, o.seg || (r < 0.012 ? 8 : 14), o.r2 ?? r), mat, 0, 0, 0, o); }
  /** Tube through local points (cables, wire, a hose). */
  tube(pts, r, mat, o = {}) {
    const curve = new THREE.CatmullRomCurve3(pts.map((p) => V3(...p)), !!o.closed, 'catmullrom', o.tension ?? 0.4);
    return this._add(new THREE.TubeGeometry(curve, o.seg || Math.max(12, pts.length * 8), r, o.rs || 8, !!o.closed), mat, 0, 0, 0, o);
  }
  torus(R, r, mat, x, y, z, o = {}) { return this._add(new THREE.TorusGeometry(R, r, o.rs || 8, o.ts || 28, o.arc || Math.PI * 2), mat, x, y, z, o); }
  /** Fabric draped over a box top at (x, y, z) — see drapeGeo for options. */
  drape(L, W, drop, mat, x, y, z, o = {}) { return this._add(drapeGeo(L, W, drop, o), mat, x, y, z, o); }

  /** Merge every queued geometry into one mesh per material. Call once at the end of a build. */
  flushBatches() {
    for (const [mat, list] of this._batches) {
      const mesh = new THREE.Mesh(mergeGeos(list), mat);
      if (mat.transparent) mesh.renderOrder = 1;
      mesh.matrixAutoUpdate = false;
      mesh.updateMatrix();
      this.root.add(mesh);
    }
    this._batches.clear();
    sanitizeNormals(this.root);
  }

  // ---------------------------------------------------------------- lights and states

  setupLights() {
    this.hemi = new THREE.HemisphereLight(0xffffff, 0x222222, 1);
    this.fill = new THREE.DirectionalLight(0xffffff, 0.3);
    this.fill.position.set(-2, 4, 6);
    this.root.add(this.hemi, this.fill);
  }
  /** Run fn(stateName) on every state switch (custom per-state tweaks: hide a prop at night…). */
  onState(fn) { this.stateFx.push(fn); }
  /**
   * A switchable lamp. `on` = level per state (0…1); `light` = a PointLight / SpotLight (its
   * intensity is the full-on value); `glows` = halo sprites; `mats` = [[material, emissiveIntensity
   * when fully on]]; `flare` = { pos } adds a lens-flare zone that shows while the lamp is lit.
   */
  lamp(id, { light = null, glows = [], mats = [], on = { evening: 1, night: 0, day: 0 }, flare = null } = {}) {
    if (light) { this.root.add(light); if (light.target) this.root.add(light.target); }
    for (const s of glows) if (!s.parent) this.root.add(s);
    const L = { id, light, base: light ? light.intensity : 0, glows: glows.map((s) => ({ s, sc: s.scale.clone() })), mats, on, level: 0, forced: null };
    this.lamps.push(L);
    // flare: { pos: world Vector3, opts } — a 'star' lens flare when the player walks up to the lit lamp
    if (flare) this.windowLights.push(flareSource('LAMP', flare.pos, { triggerDistance: 2.2, intensity: 0.5, flareSize: 0.55, ...flare.opts, enabled: () => L.level > 0.3 }));
    return L;
  }
  applyLamp(L, level) {
    L.level = level;
    if (L.light) L.light.intensity = L.base * level;
    for (const { s, sc } of L.glows) { s.visible = level > 0.01; s.scale.copy(sc).multiplyScalar(0.55 + 0.45 * Math.sqrt(level)); }
    for (const [m, k] of L.mats) m.emissiveIntensity = k * level;
  }
  /** Story hook: force a lamp on/off (level 0…1); null hands it back to the state. */
  setLamp(id, level) {
    const L = this.lamps.find((l) => l.id === id);
    if (!L) return;
    L.forced = level;
    this.applyLamp(L, level ?? L.on[this.state] ?? 0);
  }
  pointLight(color, intensity, distance, x, y, z, decay = 1.3) {
    const l = new THREE.PointLight(color, intensity, distance, decay);
    l.position.copy(this.P(x, y, z));
    return l;
  }
  halo(color, size, op, x, y, z) { const s = glow(color, size, op); s.position.copy(this.P(x, y, z)); return s; }
  /** Soft additive pool on the floor (or rotated onto a wall), visible only in the listed states. */
  statePool(color, x, y, z, w, d, op, states, rot = null) {
    const p = lightPool(color, w, d, op);
    if (rot) p.rotation.copy(rot); else p.rotation.x = -Math.PI / 2;
    p.position.copy(this.P(x, y, z));
    this.root.add(p);
    this.stateFx.push((s) => { p.visible = states.includes(s); });
    return p;
  }
  /** Switch the scene state: ambient, every lamp (unless forced), every state hook. */
  setState(name) {
    if (!this.ambient[name]) name = 'evening';
    this.state = name;
    const A = this.ambient[name];
    if (this.hemi) { this.hemi.color.setHex(A.sky); this.hemi.groundColor.setHex(A.ground); this.hemi.intensity = A.hemi; }
    if (this.fill) { this.fill.color.setHex(A.fill); this.fill.intensity = A.fillI; }
    this.background = A.bg;
    for (const L of this.lamps) this.applyLamp(L, L.forced ?? L.on[name] ?? 0);
    const tint = { day: 0xd8d6d0, evening: 0xffffff, night: 0xd0d4dc }[name] ?? 0xffffff;
    for (const v of this.views) { v.mat.map = v.fn(name, v.variant); v.mat.color.setHex(v.tint ?? tint); v.mat.needsUpdate = true; }
    for (const f of this.stateFx) f(name);
  }
  /** Per frame: candle flicker. */
  update(dt) {
    this.time += dt;
    const t = this.time;
    for (const f of this.flames) {
      const k = 0.85 + Math.sin(t * 9 + f.ph) * 0.06 + Math.sin(t * 23 + f.ph * 2) * 0.05;
      f.flame.scale.set(1, 1.8 * k, 1);
      if (f.halo.visible) f.halo.scale.setScalar(f.size * k);
    }
  }

  // ---------------------------------------------------------------- room shell
  // All batched, with world-space UVs: a texture covers `tile` metres, so it tiles evenly across
  // walls of any size (no stretching). Walls face +z (toward the camera); the near wall is not built.

  /** Floor rectangle at height y. */
  floorRect(x0, x1, z0, z1, mat, { tile = 1.28, y = 0 } = {}) {
    const g = new THREE.PlaneGeometry(x1 - x0, z1 - z0);
    g.rotateX(-Math.PI / 2);
    return this._add(g, mat, (x0 + x1) / 2, y, (z0 + z1) / 2, { uv: [tile, tile] });
  }
  /** Floor from a polygon [[x, z], …] with optional holes (a stairwell). */
  floorPoly(pts, mat, { holes = [], tile = 1.28, y = 0 } = {}) {
    const s = new THREE.Shape(pts.map(([x, z]) => new THREE.Vector2(x, -z)));
    for (const h of holes) s.holes.push(new THREE.Path(h.map(([x, z]) => new THREE.Vector2(x, -z))));
    const g = new THREE.ShapeGeometry(s);
    g.rotateX(-Math.PI / 2);   // shape y = −z → world z, facing up
    return this._add(g, mat, 0, y, 0, { uv: [tile, tile] });
  }
  /** Ceiling (facing down) from a polygon [[x, z], …] at height y, with optional holes. */
  ceilingPoly(pts, y, mat, { holes = [], tile = 2 } = {}) {
    const s = new THREE.Shape(pts.map(([x, z]) => new THREE.Vector2(x, z)));
    for (const h of holes) s.holes.push(new THREE.Path(h.map(([x, z]) => new THREE.Vector2(x, z))));
    const g = new THREE.ShapeGeometry(s);
    g.rotateX(Math.PI / 2);    // shape y → world z, facing down
    return this._add(g, mat, 0, y, 0, { uv: [tile, tile] });
  }
  /**
   * Back wall along x at depth z, height h, with rectangular openings [{ x0, x1, y0, y1 }] for
   * windows (y0 > 0) and doors (y0 = 0). Put windowUnit / panelDoor / brightWindow into the holes.
   */
  wall(x0, x1, h, z, mat, holes = [], { tile = 2 } = {}) {
    const s = new THREE.Shape();
    s.moveTo(x0, 0); s.lineTo(x1, 0); s.lineTo(x1, h); s.lineTo(x0, h); s.lineTo(x0, 0);
    for (const o of holes) { const p = new THREE.Path(); p.moveTo(o.x0, o.y0); p.lineTo(o.x0, o.y1); p.lineTo(o.x1, o.y1); p.lineTo(o.x1, o.y0); p.lineTo(o.x0, o.y0); s.holes.push(p); }
    return this._add(new THREE.ShapeGeometry(s), mat, 0, 0, z, { uv: [tile, tile] });
  }
  /** Any wall polygon in the xy plane at depth z (gables, walls under a slope): pts [[x, y], …]. */
  wallPoly(pts, z, mat, { holes = [], tile = 2, ry = 0 } = {}) {
    const s = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, y)));
    for (const o of holes) s.holes.push(new THREE.Path([[o.x0, o.y0], [o.x0, o.y1], [o.x1, o.y1], [o.x1, o.y0]].map(([x, y]) => new THREE.Vector2(x, y))));
    return this._add(new THREE.ShapeGeometry(s), mat, 0, 0, z, { uv: [tile, tile], ry });
  }
  /** Side wall at x from z0 to z1, facing +x (dir 1, the left end) or −x (dir −1, the right end). */
  sideWall(x, z0, z1, h, mat, dir, { tile = 2 } = {}) {
    return this._add(new THREE.PlaneGeometry(z1 - z0, h), mat, x, h / 2, (z0 + z1) / 2, { ry: dir > 0 ? Math.PI / 2 : -Math.PI / 2, uv: [tile, tile] });
  }
  /** A partition with thickness d at z (x0…x1): the front face with openings + reveals inside them. */
  partition(x0, x1, h, z, d, mat, holes = []) {
    this.wall(x0, x1, h, z + d / 2, mat, holes);
    for (const o of holes) {   // reveals inside each opening
      this.pl(d, o.y1 - o.y0, mat, o.x0, (o.y0 + o.y1) / 2, z, { ry: Math.PI / 2 });
      this.pl(d, o.y1 - o.y0, mat, o.x1, (o.y0 + o.y1) / 2, z, { ry: -Math.PI / 2 });
      if (o.y1 < h) this.pl(o.x1 - o.x0, d, mat, (o.x0 + o.x1) / 2, o.y1, z, { rx: Math.PI / 2 });
    }
  }
  /**
   * A sloped roof plane (attic): a strip from x0 to x1 whose lower edge is at (y0, z0) and upper
   * edge at (y1, z1). Faces the room (down / toward +z).
   */
  slope(x0, x1, y0, z0, y1, z1, mat, { tile = 2 } = {}) {
    const L = Math.hypot(y1 - y0, z1 - z0);
    const g = new THREE.PlaneGeometry(x1 - x0, L);
    return this._add(g, mat, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, { rx: Math.atan2(z1 - z0, y1 - y0), uv: [tile, tile] });
  }
  /** Skirting board and/or crown moulding along the back wall at z, over spans [[x0, x1], …]. */
  trims(spans, z, H, { skirt = true, crown = true, color = null } = {}) {
    const w = color ? this.M(`trim-${color}`, color, { roughness: 0.55 }) : this.white();
    for (const [a, b] of spans) {
      if (b - a < 0.05) continue;
      if (skirt) this.rb(b - a, 0.11, 0.025, 0.008, w, (a + b) / 2, 0.055, z + 0.013);
      if (crown) { this.rb(b - a, 0.07, 0.05, 0.015, w, (a + b) / 2, H - 0.035, z + 0.025); this.rb(b - a, 0.025, 0.08, 0.01, w, (a + b) / 2, H - 0.075, z + 0.02); }
    }
  }
  /** Wainscot: a lower wall band (panelling or tile texture) up to y with a chair rail on top. */
  wainscot(spans, z, y, mat, { rail = true, railColor = null } = {}) {
    const rm = railColor ? this.M(`rail-${railColor}`, railColor, { roughness: 0.5 }) : this.white();
    for (const [a, b] of spans) {
      this.rb(b - a, y, 0.015, 0.004, mat, (a + b) / 2, y / 2, z + 0.008, { uv: [1, 1] });
      if (rail) this.rb(b - a, 0.045, 0.035, 0.01, rm, (a + b) / 2, y, z + 0.018);
    }
  }
  /** Square pilaster / column with base and capital (fronts of corridors, porches). */
  column(x, z, h, mat, { w = 0.3, d = 0.3 } = {}) {
    this.rb(w, h - 0.2, d, 0.02, mat, x, h / 2, z);
    this.rb(w + 0.06, 0.1, d + 0.06, 0.02, mat, x, 0.05, z);
    this.rb(w + 0.08, 0.1, d + 0.08, 0.02, mat, x, h - 0.05, z);
  }
  /**
   * A straight flight of stairs rising along +x from x0 against the back wall (z0 = back, width
   * w toward +z): treads, white risers, a closed side panel (sideMat) under the flight, stringer,
   * balusters, handrail and newel. Returns railY(x) — the handrail height at x (for fairy lights,
   * a hand on the rail, the camera).
   */
  stairs(x0, z0, { n = 12, run = 0.2, H = 2.8, w = 0.88, tread = null, riser = null, sideMat = null, rail = true } = {}) {
    const rise = H / n, zc = z0 + w / 2;
    const oak = tread || this.texM('oakMid', TEX.oak(1), { roughness: 0.55 });
    const wm = riser || this.white();
    for (let i = 0; i < n; i++) {
      const xa = x0 + i * run, y = (i + 1) * rise;
      this.rb(run + 0.035, 0.035, w, 0.01, oak, xa + run / 2 - 0.015, y - 0.0175, zc);
      this.rb(0.02, rise - 0.03, w - 0.02, 0.004, wm, xa, y - rise / 2 - 0.02, zc);
    }
    if (sideMat) {
      const s = new THREE.Shape([new THREE.Vector2(x0, 0), new THREE.Vector2(x0 + n * run, 0), new THREE.Vector2(x0 + n * run, H - 0.03), new THREE.Vector2(x0, rise - 0.03)]);
      this._add(new THREE.ShapeGeometry(s), sideMat, 0, 0, z0 + w + 0.005, { uv: [2, 2] });
    }
    const L = Math.hypot(n * run, H), ang = Math.atan2(H, n * run);
    this.rb(L + 0.1, 0.2, 0.04, 0.01, wm, x0 + n * run / 2 + 0.02, H / 2 - 0.02, z0 + w + 0.02, { rz: ang });
    this.rb(L + 0.1, 0.16, 0.025, 0.008, wm, x0 + n * run / 2 + 0.02, H / 2 + 0.05, z0 + 0.013, { rz: ang });
    const railY = (x) => (x - x0) / run * rise + 0.92;
    if (rail) {
      for (let i = 0; i < n; i++) { const x = x0 + i * run + run / 2; this.rod([x, (i + 1) * rise, z0 + w - 0.04], [x, railY(x) - 0.02, z0 + w - 0.04], 0.012, wm); }
      this.rod([x0 + 0.02, railY(x0 + 0.02) + 0.05, z0 + w - 0.04], [x0 + n * run, railY(x0 + n * run), z0 + w - 0.04], 0.028, oak, { seg: 16 });
      this.rb(0.1, 1.2, 0.1, 0.02, oak, x0 + 0.03, 0.6, z0 + w - 0.04);
      this.lathe([[0.001, 0], [0.06, 0], [0.065, 0.04], [0.03, 0.07], [0.04, 0.1], [0.001, 0.12]], oak, x0 + 0.03, 1.2, z0 + w - 0.04);
    }
    return railY;
  }

  // ---------------------------------------------------------------- windows, views, light falling in

  /**
   * The painted view behind a window: a plane at depth z (put it 1.5–3 m behind the wall so it
   * parallaxes a little as the camera moves). view(time, variant) → texture, re-painted per state.
   * Make it much larger than the opening so no edge shows from any camera position.
   */
  viewPlane(w, h, x, y, z, { view = townView, variant = 'low', ry = 0, tint = null } = {}) {
    const mat = new THREE.MeshBasicMaterial({ map: view(this.state, variant), color: 0xffffff, fog: false });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), mat);
    m.position.copy(this.P(x, y, z)); m.rotation.y = ry;
    this.root.add(m);
    this.views.push({ mat, variant, fn: view, tint });
    return m;
  }
  /**
   * A window that lets real daylight in (corridors, wards, classrooms, a station): opening
   * x0…x1 × y0…y1 in the back wall at z, the view behind it, the glare of the glass, frame and
   * mullions, optional blinds, an additive light shaft falling onto the floor, a warm patch where
   * it lands, cold moonlit panes on the floor at night, and a light zone (exposure + lens flare)
   * for window-light.js. profile: WINDOW_PROFILES key or object. Cut the hole in the wall yourself.
   * World coordinates: call it outside withT.
   */
  brightWindow(x0, x1, y0, y1, z, { profile = 'A', view = townView, variant = 'low', blinds = false, fall = 2.6 } = {}) {
    const P = typeof profile === 'string' ? WINDOW_PROFILES[profile] : profile;
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, w = x1 - x0, h = y1 - y0;
    this.viewPlane(w + 2.4, h + 1.8, cx, cy, z - 1.6, { view, variant, tint: 0xe4dccc });
    const glareMat = new THREE.MeshBasicMaterial({ color: P.color, transparent: true, opacity: 0.22, blending: THREE.AdditiveBlending, depthWrite: false });
    const glare = new THREE.Mesh(new THREE.PlaneGeometry(w, h), glareMat);
    glare.position.set(cx, cy, z - 0.05); glare.renderOrder = 2; this.root.add(glare);
    const frame = this.M(P.old ? 'winWood' : 'winAlu', P.old ? 0x5a3c22 : 0xb8c0c4, P.old ? { roughness: 0.5 } : { metalness: 0.4, roughness: 0.35 });
    this.rb(w + 0.14, 0.08, 0.14, 0.015, frame, cx, y1 + 0.04, z);
    this.rb(w + 0.2, 0.06, 0.24, 0.015, frame, cx, y0 - 0.03, z + 0.05);
    for (const x of [x0 - 0.04, x1 + 0.04]) this.rb(0.08, h, 0.14, 0.015, frame, x, cy, z);
    const panes = P.old ? Math.max(2, Math.round(w / 0.45)) : 2;
    for (let k = 1; k < panes; k++) this.rb(0.04, h, 0.06, 0.01, frame, x0 + (w * k) / panes, cy, z - 0.02);
    if (P.old) this.rb(w, 0.04, 0.06, 0.01, frame, cx, y0 + h * 0.62, z - 0.02);
    if (blinds) {
      const bt = blindsTex().clone(); bt.needsUpdate = true; bt.repeat.set(w / 0.32, h * 0.7 / 0.08);
      this.pl(w, h * 0.7, this.mat(`bwBlind-${w.toFixed(2)}`, { map: bt, color: 0xffffff, transparent: true, alphaTest: 0.5, side: THREE.DoubleSide }), cx, y1 - h * 0.35, z + 0.04);
    }
    // the shaft falling in and its patch on the floor
    const shaftMat = new THREE.MeshBasicMaterial({ map: shaftTexture(), color: P.color, transparent: true, opacity: P.shaft * 1.6, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute([x0, y1, z + 0.05, x1, y1, z + 0.05, x0 + 0.6, 0.02, z + fall, x1 + 0.6, 0.02, z + fall], 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute([0, 1, 1, 1, 0, 0, 1, 0], 2));
    geo.setIndex([0, 2, 1, 1, 2, 3]);
    const shaft = new THREE.Mesh(geo, shaftMat); shaft.renderOrder = 3; this.root.add(shaft);
    const patch = lightPool(P.color, w + 0.8, 2.2, P.patch);
    patch.rotation.x = -Math.PI / 2; patch.position.set(cx + 0.5, 0.012, z + fall * 0.6); this.root.add(patch);
    // at night the moon lays the panes on the floor (cold, faint)
    const panesTex = canvasTexture(`fk-panes-${panes}`, 64, 64, (c, cw, ch) => {
      c.filter = 'blur(2px)';
      c.fillStyle = '#fff'; c.fillRect(6, 4, cw - 12, ch - 8);
      c.fillStyle = '#000';
      for (let k = 1; k < panes; k++) c.fillRect((cw * k) / panes - 2, 0, 4, ch);
      c.fillRect(0, ch * 0.38 - 2, cw, 4);
      c.globalCompositeOperation = 'destination-in';
      const g = c.createLinearGradient(0, 0, 0, ch); g.addColorStop(0, 'rgba(0,0,0,0.2)'); g.addColorStop(0.3, 'rgba(0,0,0,1)'); g.addColorStop(1, 'rgba(0,0,0,0.6)');
      c.fillStyle = g; c.fillRect(0, 0, cw, ch);
    });
    const moonM = new THREE.MeshBasicMaterial({ map: panesTex, color: 0x6a88c8, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
    const moon = new THREE.Mesh(new THREE.PlaneGeometry(w * 1.05, 1.5), moonM);
    moon.rotation.x = -Math.PI / 2; moon.position.set(cx + 0.35, 0.006, z + 1.25); moon.renderOrder = 2; this.root.add(moon);
    const zone = { ...P, position: V3(cx, cy + h * 0.15, z - 0.1), dir: V3(0, 0, 1), enabled: () => this.state !== 'night' };
    this.windowLights.push(zone);
    this.onState((st) => {
      const night = st === 'night', eve = st === 'evening';
      const k = eve ? 0.45 : 1;
      moonM.opacity = night ? 0.25 : 0;
      glareMat.opacity = night ? 0.14 : 0.22 * k; glareMat.color.set(night ? 0x5070b0 : P.color);
      shaftMat.opacity = (night ? 0.45 : k) * P.shaft * 1.6; shaftMat.color.set(night ? 0x5a78c0 : P.color);
      patch.material.opacity = (night ? 0.5 : k) * P.patch; patch.material.color.set(night ? 0x5a78c0 : P.color);
    });
    return zone;
  }

  // ---------------------------------------------------------------- ceiling lights

  /** Pendant: cord from the ceiling at height y, a fabric drum or glass dome shade, a lamp. */
  pendant(id, x, y, z, { drop = 0.7, shade = 0xe8dcc4, kind = 'drum', on = { evening: 1, night: 0, day: 0 }, intensity = 3.5, color = 0xffc488 } = {}) {
    const sy = y - drop;
    this.rod([x, y, z], [x, sy + 0.12, z], 0.004, this.M('cord', 0x2a2420));
    this.cy(0.04, 0.04, 0.02, this.M('canopy', 0xe8e4dc), x, y - 0.01, z, { seg: 20 });
    const sm = this.glowM(`pendant-${id}`, shade, 0xffc890, { side: THREE.DoubleSide });
    if (kind === 'dome') this.lathe([[0.02, 0.12], [0.08, 0.09], [0.16, 0.03], [0.19, 0]], sm, x, sy, z, { seg: 28 });
    else this.cy(0.2, 0.22, 0.24, sm, x, sy + 0.08, z, { open: true, seg: 28 });
    return this.lamp(id, {
      light: this.pointLight(color, intensity, 7, x, sy - 0.05, z + 0.1, 1.2),
      glows: [this.halo(0xffc890, 1.1, 0.3, x, sy + 0.02, z)], mats: [[sm, 1.1]], on,
      flare: { pos: this.P(x, sy, z) },
    });
  }
  /** Fluorescent ceiling panel (offices, schools, hospitals): housing, emissive tube, a spotlight down. */
  fluorescent(id, x, y, z, { w = 1.2, d = 0.3, color = 0xdfeaff, intensity = 9, range = 7, on = { evening: 1, night: 0.3, day: 1 } } = {}) {
    this.rb(w + 0.08, 0.06, d + 0.08, 0.01, this.M('fluoHousing', 0xb0b4b8, { roughness: 0.6 }), x, y, z);
    const tm = this.glowM(`fluo-${color}`, 0x202020, color, { side: THREE.DoubleSide });
    this.pl(w, d, tm, x, y - 0.035, z, { rx: Math.PI / 2 });
    const l = new THREE.SpotLight(color, intensity, range, 1.2, 0.9, 1.4);
    l.position.copy(this.P(x, y - 0.1, z)); l.target.position.copy(this.P(x, 0, z + 0.4));
    // the ceiling around a lit panel catches its light (else the ceiling reads pure black at night)
    const pool = lightPool(color, w * 3.2, d * 9, 0.32);
    pool.rotation.x = Math.PI / 2; pool.position.copy(this.P(x, y + 0.035, z)); this.root.add(pool);
    const L = this.lamp(id, { light: l, glows: [this.halo(color, w * 1.4, 0.16, x, y - 0.12, z + 0.1)], mats: [[tm, 2.2]], on });
    this.onState(() => { pool.visible = L.level > 0.01; pool.material.opacity = 0.32 * L.level; });
    return L;
  }
  /** Panel radiator under a window: fins, end caps, a valve. Local frame (wall at z = 0). */
  radiator(x, y, z, w = 1.2, { h = 0.6, color = 0xe8e6e0 } = {}) {
    const m = this.M(`radiator-${color}`, color, { roughness: 0.45 });
    const n = Math.max(4, Math.round(w / 0.06));
    for (let i = 0; i < n; i++) this.rb(0.045, h, 0.09, 0.015, m, x - w / 2 + (i + 0.5) * (w / n), y + h / 2, z + 0.08);
    for (const yy of [y + 0.04, y + h - 0.04]) this.cy(0.02, 0.02, w, m, x, yy, z + 0.08, { rz: Math.PI / 2, seg: 16 });
    this.rod([x + w / 2 + 0.04, y + 0.05, z + 0.08], [x + w / 2 + 0.04, 0, z + 0.08], 0.012, m);
    this.cy(0.025, 0.025, 0.05, this.M('valve', 0xc8ccd0, { metalness: 0.8, roughness: 0.3 }), x + w / 2 + 0.04, y + 0.1, z + 0.08, { seg: 16 });
  }
  /** Fire extinguisher on a wall bracket at height y. */
  extinguisher(x, y, z) {
    const red = this.M('extRed', 0xb81c18, { roughness: 0.35 });
    this.lathe([[0.001, 0], [0.075, 0], [0.08, 0.03], [0.08, 0.42], [0.06, 0.48], [0.025, 0.5], [0.001, 0.5]], red, x, y, z + 0.1, { seg: 20 });
    this.rb(0.06, 0.05, 0.04, 0.01, this.M('extHead', 0x2a2a2c, { roughness: 0.4 }), x, y + 0.53, z + 0.1);
    this.tube([[x + 0.03, y + 0.52, z + 0.12], [x + 0.11, y + 0.4, z + 0.16], [x + 0.09, y + 0.12, z + 0.17]], 0.008, this.M('hose', 0x141414));
    this.rb(0.14, 0.04, 0.06, 0.01, this.M('steel', 0x9aa0a6, { metalness: 0.8, roughness: 0.35 }), x, y + 0.3, z + 0.03);
    this.rb(0.2, 0.26, 0.004, 0.002, this.M('extSign', 0xc82020, { roughness: 0.6 }), x, y + 0.82, z + 0.004);
  }
  /** Lit EXIT sign (a lamp: on in every state by default). */
  exitSign(id, x, y, z, { text = 'EXIT', on = { evening: 1, night: 1, day: 1 } } = {}) {
    const tex = TX(`exit-${text}`, 40, 14, (ctx, w, h) => {
      ctx.fillStyle = '#1a6a3a'; ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = '#e8fff0'; ctx.font = 'bold 10px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(text, w / 2, h / 2 + 1);
    });
    this.rb(0.42, 0.16, 0.06, 0.01, this.M('exitBox', 0xe8e8e4, { roughness: 0.5 }), x, y, z + 0.03);
    const fm = this.mat(`exitFace-${text}`, { map: tex, color: 0xffffff, emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: 0 });
    this.pl(0.38, 0.13, fm, x, y, z + 0.062);
    return this.lamp(id, { glows: [this.halo(0x40ff90, 0.7, 0.12, x, y, z + 0.1)], mats: [[fm, 0.9]], on });
  }

  // ---------------------------------------------------------------- small props

  book(x, y, z, w, h, d, k, o = {}) {
    const m = this.M(`book-${k % BOOK_COLS.length}`, BOOK_COLS[k % BOOK_COLS.length], { roughness: 0.8 });
    this.rb(w, h, d, 0.006, m, x, y + h / 2, z, o);
    this.rb(Math.max(0.004, w - 0.008), h - 0.012, 0.004, 0.0015, this.M('pages', 0xe8e0cc), x, y + h / 2, z + d / 2 + 0.001, o.ry ? { ry: o.ry } : {});
  }
  /** A row of standing books from x0 (spines face +z), returns the end x. */
  bookRow(x0, y, z, n, seed, maxW = 1, d = 0.2) {
    const r = rng(seed);
    let x = x0;
    for (let i = 0; i < n; i++) {
      const w = 0.025 + r() * 0.03, h = 0.18 + r() * 0.08;
      if (x + w - x0 > maxW) break;
      const lean = i === n - 1 && r() < 0.5 ? -0.12 : 0;
      this.book(x + w / 2, y, z, w, h, d * (0.8 + r() * 0.2), Math.floor(r() * 99), lean ? { rz: lean } : {});
      x += w + 0.003;
    }
    return x;
  }
  /** Books lying in a stack; returns the top y. */
  bookStack(x, y, z, n, seed) {
    const r = rng(seed);
    let yy = y;
    for (let i = 0; i < n; i++) { const t = 0.03 + r() * 0.02; this.book(x + (r() - 0.5) * 0.03, yy, z, 0.16 + r() * 0.06, t, 0.22 + r() * 0.04, Math.floor(r() * 99), { ry: (r() - 0.5) * 0.3 }); yy += t; }
    return yy;
  }
  mug(x, y, z, color = 0xd8d0c0, ry = 0) {
    const m = this.M(`mug-${color}`, color, { roughness: 0.4 });
    this.lathe([[0.038, 0], [0.042, 0.005], [0.043, 0.095], [0.04, 0.095], [0.039, 0.012], [0.001, 0.012]], m, x, y, z);
    this.torus(0.025, 0.006, m, x + Math.cos(ry) * 0.045, y + 0.05, z - Math.sin(ry) * 0.045, { ry, ts: 16, rs: 6 });
    this.cy(0.037, 0.037, 0.004, this.M('coffee', 0x2a1408, { roughness: 0.2 }), x, y + 0.08, z, { seg: 16 });
  }
  /** Potted plant: lathe pot + crossed alpha leaf cards. kind 'palm' | 'pothos'. */
  plant(x, y, z, s = 1, kind = 'palm', potColor = 0xd8d0c4) {
    const pm = this.M(`pot-${potColor}`, potColor, { roughness: 0.6 });
    this.lathe([[0.001, 0], [0.12 * s, 0], [0.14 * s, 0.03 * s], [0.16 * s, 0.24 * s], [0.17 * s, 0.26 * s], [0.155 * s, 0.26 * s], [0.001, 0.24 * s]], pm, x, y, z);
    this.cy(0.15 * s, 0.15 * s, 0.01, this.M('soil', 0x2a1e14), x, y + 0.235 * s, z);
    const lm = this.mat(`leaf-${kind}`, { map: leafTex(kind), color: 0xffffff, transparent: true, alphaTest: 0.45, side: THREE.DoubleSide, roughness: 0.8 });
    const r = rng(Math.round(x * 100 + z * 10));
    const n = kind === 'palm' ? 9 : 6;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + r() * 0.4, tilt = kind === 'palm' ? 0.35 + r() * 0.5 : 0.1 + r() * 0.3;
      const L = (kind === 'palm' ? 0.9 : 0.4) * s * (0.7 + r() * 0.4);
      this.pl(L * 0.62, L, lm, x + Math.sin(a) * Math.sin(tilt) * L * 0.5, y + 0.24 * s + Math.cos(tilt) * L * 0.5, z + Math.cos(a) * Math.sin(tilt) * L * 0.5, { rx: tilt, ry: a, order: 'YXZ' });
    }
  }
  /** Framed picture hung on a wall at z (picture faces +z). mat = passe-partout width (0 = none). */
  framed(map, w, h, x, y, z, frameColor = 0x2a2420, mat = 0.03, key = null) {
    const fm = this.M(`pframe-${frameColor}`, frameColor, { roughness: 0.5 });
    const b = 0.03;
    this.rb(w + b * 2, b, 0.03, 0.008, fm, x, y + h / 2 + b / 2, z + 0.015);
    this.rb(w + b * 2, b, 0.03, 0.008, fm, x, y - h / 2 - b / 2, z + 0.015);
    this.rb(b, h, 0.03, 0.008, fm, x - w / 2 - b / 2, y, z + 0.015);
    this.rb(b, h, 0.03, 0.008, fm, x + w / 2 + b / 2, y, z + 0.015);
    if (mat) this.pl(w, h, this.M('passepartout', 0xece8de), x, y, z + 0.008);
    this.pl(w - mat * 2, h - mat * 2, this.texM(key || `pic-${map.uuid}`, map, { roughness: 0.5 }), x, y, z + 0.018);
  }
  /** A lit candle in a glass: flickering flame + halo, a lamp in the state system. */
  candle(id, x, y, z, { on = { evening: 1, night: 0, day: 0 }, h = 0.08, r = 0.035 } = {}) {
    this.lathe([[0.001, 0], [r, 0], [r + 0.004, h + 0.02], [r + 0.001, h + 0.02], [r - 0.003, 0.006], [0.001, 0.006]], this.mat('candleGlass', { color: 0xe8c8a0, roughness: 0.1, transparent: true, opacity: 0.45, depthWrite: false }), x, y, z);
    this.cy(r - 0.004, r - 0.004, h - 0.01, this.M('wax', 0xf0e6d4, { roughness: 0.6, emissive: 0x2a1a08 }), x, y + h / 2, z);
    const fm = this.glowM(`flame-${id}`, 0x000000, 0xffb050);
    const flame = new THREE.Mesh(new THREE.SphereGeometry(0.008, 12, 10), fm);
    flame.geometry.translate(0, 0.012, 0); flame.scale.set(1, 1.8, 1);
    flame.position.copy(this.P(x, y + h + 0.004, z));
    this.root.add(flame);
    const halo = this.halo(0xffa050, 0.3, 0.55, x, y + h + 0.03, z + 0.02);
    this.flames.push({ flame, halo, size: 0.3, ph: x * 13 + z * 7 });
    this.stateFx.push(() => { flame.visible = fm.emissiveIntensity > 0.01; });
    return this.lamp(id, { glows: [halo], mats: [[fm, 3]], on });
  }
  /** Fairy lights along a curve of local points: warm grains (one instanced mesh) + a few halos. */
  fairyLights(id, pts, count, { on = { evening: 1, night: 0, day: 0 }, halos = 3 } = {}) {
    const wpts = pts.map((p) => this.P(...p));
    const curve = new THREE.CatmullRomCurve3(wpts, false, 'catmullrom', 0.3);
    this.tube(pts, 0.002, this.M('wire', 0x2a2a22));
    const bm = this.glowM(`fairy-${id}`, 0x6a5a40, 0xffc070, { roughness: 0.4 });
    const im = new THREE.InstancedMesh(new THREE.SphereGeometry(0.009, 12, 10), bm, count);
    const mtx = new THREE.Matrix4();
    for (let i = 0; i < count; i++) { const p = curve.getPoint((i + 0.5) / count); mtx.makeTranslation(p.x, p.y - 0.008, p.z); im.setMatrixAt(i, mtx); }
    this.root.add(im);
    const glows = [];
    for (let i = 0; i < halos; i++) { const p = curve.getPoint((i + 0.5) / halos); const s = glow(0xffb060, 0.7, 0.22); s.position.set(p.x, p.y, p.z + 0.03); glows.push(s); }
    return this.lamp(id, { glows, mats: [[bm, 2.4]], on });
  }
  /** Turned leg (lathe) from y0 up by len. */
  turnedLeg(mat, x, y0, z, len, r = 0.03) {
    const L = len;
    this.lathe([[r * 0.7, 0], [r * 0.9, 0.04 * L], [r * 0.6, 0.12 * L], [r, 0.25 * L], [r * 0.7, 0.45 * L], [r * 0.9, 0.6 * L], [r * 1.1, 0.8 * L], [r * 1.1, L]], mat, x, y0, z, { seg: 16 });
  }

  // ---------------------------------------------------------------- openings (an object set into a wall at z = 0)

  /**
   * A window in the local frame: opening x -w/2…w/2, y y0…y1 in a wall at z = 0 (room on +z).
   * Casing, deep reveals, sashes, glass, sill. kind: 'double' (sash with muntins) | 'plain'.
   * blind: { kind: 'slats' | 'roman' | 'cell', cover: 0…1, color (roman) }.
   * The wall itself (with the hole) is yours; put a view plane behind it.
   */
  windowUnit(w, y0, y1, { depth = 0.16, kind = 'double', blind = null, muntins = [2, 2], frameColor = null } = {}) {
    const wm = frameColor ? this.M(`frame-${frameColor}`, frameColor, { roughness: 0.5 }) : this.white();
    const h = y1 - y0, cy = (y0 + y1) / 2;
    this.rb(w + 0.16, 0.08, 0.03, 0.01, wm, 0, y1 + 0.04, 0.015);
    for (const s of [-1, 1]) this.rb(0.08, h + 0.04, 0.03, 0.01, wm, s * (w / 2 + 0.04), cy, 0.015);
    const rev = this.M('reveal', 0xdcd6cc, { roughness: 0.8 });
    this.pl(w, depth, rev, 0, y1, -depth / 2, { rx: Math.PI / 2 });
    for (const s of [-1, 1]) this.pl(depth, h, rev, s * w / 2, cy, -depth / 2, { ry: -s * Math.PI / 2 });
    this.rb(w + 0.2, 0.035, depth + 0.1, 0.012, wm, 0, y0 - 0.017, -depth / 2 + 0.05);
    this.rb(w + 0.1, 0.06, 0.02, 0.008, wm, 0, y0 - 0.07, 0.012);
    const zS = -depth + 0.04, b = 0.045;
    this.rb(w, b, 0.05, 0.008, wm, 0, y1 - b / 2, zS); this.rb(w, b, 0.05, 0.008, wm, 0, y0 + b / 2, zS);
    for (const s of [-1, 1]) this.rb(b, h, 0.05, 0.008, wm, s * (w / 2 - b / 2), cy, zS);
    if (kind === 'double') {
      this.rb(w, 0.05, 0.07, 0.01, wm, 0, cy, zS);
      const [mx, my] = muntins;
      for (let i = 1; i < mx; i++) this.rb(0.018, h - 0.06, 0.03, 0.006, wm, -w / 2 + (w * i) / mx, cy, zS + 0.01);
      for (const half of [0, 1]) for (let j = 1; j < my; j++) this.rb(w - 0.06, 0.018, 0.03, 0.006, wm, 0, y0 + half * h / 2 + (h / 2 * j) / my, zS + 0.01);
    }
    this.pl(w - 0.04, h - 0.04, this.glass(), 0, cy, zS - 0.01);
    if (!blind) return;
    const cov = blind.cover ?? 0.4, bh = h * cov;
    if (blind.kind === 'slats') {
      const bt = blindsTex().clone(); bt.needsUpdate = true; bt.repeat.set(1, bh / 0.32 * 4);
      const bm = this.mat(`blind-${bh.toFixed(2)}`, { map: bt, color: 0xffffff, transparent: true, alphaTest: 0.5, side: THREE.DoubleSide, roughness: 0.6 });
      this.pl(w - 0.03, bh, bm, 0, y1 - bh / 2 - 0.02, -0.04);
      this.rb(w - 0.01, 0.045, 0.05, 0.01, wm, 0, y1 - 0.025, -0.04);
      this.rb(w - 0.03, 0.025, 0.04, 0.008, wm, 0, y1 - bh - 0.02, -0.04);
      this.rod([w * 0.35, y1 - 0.04, -0.02], [w * 0.35, y1 - bh - 0.25, -0.02], 0.003, this.M('cord', 0xd8d4c8));
    } else if (blind.kind === 'roman') {
      const fm = this.mat(`romanF-${blind.color}`, { map: romanTex(blind.color ?? 0x5a7a4a), color: 0xffffff, roughness: 0.95, side: THREE.DoubleSide });
      const drop = bh * 0.55, stack = bh - drop;
      this.rb(w + 0.08, 0.035, 0.05, 0.012, this.M('romanHead', 0xe8e0d0), 0, y1 + 0.01, 0.03);
      const folds = 4, fh = stack / folds;
      for (let i = 0; i < folds; i++) this.cush(w + 0.05 - i * 0.004, fh * 1.08, 0.05 + i * 0.012, 0.024, fm, 0, y1 - fh * (i + 0.5), 0.035 + i * 0.006, { puff: 0.35, seed: i + 3, lump: 0.004 });
      this.pl(w + 0.04, drop, fm, 0, y1 - stack - drop / 2, 0.03);
      this.rb(w + 0.05, 0.02, 0.025, 0.008, this.M('romanBatten', 0xc9b48e, { roughness: 0.6 }), 0, y1 - bh, 0.035);
      this.rod([w / 2 + 0.01, y1 - 0.02, 0.05], [w / 2 + 0.01, y1 - bh - 0.3, 0.05], 0.003, this.M('cord', 0xd8d4c8));
      this.sph(0.012, this.M('romanBatten', 0xc9b48e), w / 2 + 0.01, y1 - bh - 0.31, 0.05);
    } else {
      const cm = this.M('cellShade', 0xd8d0c0, { roughness: 0.95, emissive: 0x100c08 });
      this.rb(w - 0.02, bh, 0.035, 0.008, cm, 0, y1 - bh / 2, -0.05);
      for (let k = 1; k < bh / 0.05; k++) this.rb(w - 0.025, 0.006, 0.04, 0.002, this.M('cellLine', 0xb8ae9c), 0, y1 - k * 0.05, -0.05);
      this.rb(w - 0.02, 0.025, 0.04, 0.008, wm, 0, y1 - bh, -0.05);
    }
  }
  /** Six-panel door (or glazed top) with casing, reveals and a brass knob, in a wall at z = 0. */
  panelDoor(w, h, color, { glassTop = false } = {}) {
    const leafM = this.M(`door-${color}`, color, { roughness: 0.5 });
    const wm = this.white();
    this.rb(w + 0.18, 0.08, 0.03, 0.01, wm, 0, h + 0.04, 0.015);
    for (const s of [-1, 1]) this.rb(0.08, h + 0.04, 0.03, 0.01, wm, s * (w / 2 + 0.04), h / 2, 0.015);
    const rev = this.M('reveal', 0xdcd6cc, { roughness: 0.8 });
    for (const s of [-1, 1]) this.pl(0.14, h, rev, s * w / 2, h / 2, -0.07, { ry: -s * Math.PI / 2 });
    this.pl(w, 0.14, rev, 0, h, -0.07, { rx: Math.PI / 2 });
    this.rb(w - 0.01, h - 0.01, 0.045, 0.012, leafM, 0, h / 2, -0.05);
    const pw = (w - 0.24) / 2;
    for (const [y0, ph] of [[0.12, 0.62], [0.86, 0.5], [1.48, 0.42]]) for (const s of [-1, 1]) {
      if (glassTop && y0 > 1.4) continue;
      this.rb(pw, ph * (h / 2.1), 0.012, 0.01, leafM, s * (pw / 2 + 0.04), (y0 + ph / 2) * (h / 2.1), -0.022);
    }
    if (glassTop) {   // a glazed top: tinted glass, a muntin, a reflection streak
      this.pl(w - 0.24, 0.4, this.mat('doorGlass', { color: 0x6a7a84, roughness: 0.1, metalness: 0.3, emissive: 0x141c24 }), 0, h * 0.82, -0.026);
      this.rb(0.025, 0.4, 0.02, 0.006, leafM, 0, h * 0.82, -0.02);
      this.pl(0.04, 0.34, this.mat('doorGlassHi', { color: 0xffffff, transparent: true, opacity: 0.18, depthWrite: false }), -(w - 0.24) / 4, h * 0.82, -0.024, { rz: -0.4 });
    }
    const br = this.brass();
    this.sph(0.03, br, w / 2 - 0.1, 1.0, -0.005);
    this.cy(0.035, 0.035, 0.01, br, w / 2 - 0.1, 1.0, -0.025, { rx: Math.PI / 2 });
  }

  // ---------------------------------------------------------------- furniture builders
  // Every builder: (x, z, ry, options). Local frame: back at z = 0, front toward +z, floor y = 0.
  // They are recipes — copy one and change it rather than piling on options.

  /** Rug on the floor (w along x, d along z). tex: a texture or null for a plain colour. */
  rug(x, z, w, d, { tex = TEX.shag(), color = 0x8c8578, tile = 0.64, ry = 0 } = {}) {
    const m = tex ? this.texM(`rug-${tex.uuid}`, tex, { roughness: 1 }) : this.M(`rug-${color}`, color, { roughness: 1 });
    this.withT(x, z, ry, () => this.rb(w, 0.014, d, 0.006, m, 0, 0.007, 0, { uv: [tile, tile] }));
  }

  /** Sofa: plinth, seat + back cushions, arms, legs, throw pillows, optional throw. */
  sofa(x, z, ry = 0, { w = 2.0, color = 0x7d6e60, dark = 0x6a5c50, seats = Math.max(1, Math.round(w / 0.9)), pillows = [0xb8a890, 0x8a3a2a], throwTex = TEX.plaid(0), seed = 1 } = {}) {
    const fab = this.M(`sofa-${color}`, color, { roughness: 0.97 });
    const fab2 = this.M(`sofa-${dark}`, dark, { roughness: 0.97 });
    const legM = this.M('sofaLeg', 0x2a1c14, { roughness: 0.5 });
    const D = 0.9, inner = w - 0.4, sw = inner / seats;
    this.withT(x, z, ry, () => {
      this.rb(w, 0.22, D, 0.05, fab2, 0, 0.21, D / 2);
      for (const sx of [-1, 1]) for (const sz of [0.06, D - 0.06]) this.cy(0.025, 0.02, 0.1, legM, sx * (w / 2 - 0.06), 0.05, sz);
      for (let i = 0; i < seats; i++) {
        const cx = -inner / 2 + sw * (i + 0.5);
        this.cush(sw - 0.01, 0.17, 0.72, 0.06, fab, cx, 0.4, 0.52, { seed: seed + i, puff: 0.35 });
        this.cush(sw - 0.02, 0.5, 0.24, 0.1, fab, cx, 0.7, 0.15, { seed: seed + 10 + i, puff: 0.4, rx: -0.14 });
      }
      for (const s of [-1, 1]) this.cush(0.2, 0.5, D, 0.08, fab2, s * (w / 2 - 0.1), 0.42, D / 2, { seed: seed + 20, puff: 0.2 });
      pillows.forEach((c, i) => {
        const px = (i % 2 ? 1 : -1) * (inner / 2 - 0.25 - Math.floor(i / 2) * 0.45);
        this.cush(0.42, 0.42, 0.14, 0.07, this.M(`pillow-${c}`, c, { roughness: 0.95 }), px, 0.68, 0.26, { seed: seed + 30 + i, puff: 0.6, rx: -0.3, rz: (i % 2 ? -0.12 : 0.12) });
      });
      if (throwTex) {
        const plaid = this.texM(`throw-${throwTex.uuid}`, throwTex, { roughness: 0.95, side: THREE.DoubleSide });
        this.drape(0.62, 0.3, 0.42, plaid, inner / 2 - 0.45, 0.95, 0.12, { sides: [0, 0, 1, 1], uv: [0.3, 0.3], seed: seed + 4, r: 0.06, wrinkle: 0.015 });
      }
    });
  }

  /** Coffee table: top, lower shelf, four turned legs. */
  coffeeTable(x, z, ry = 0, { w = 1.05, d = 0.56, h = 0.46, wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.45 }) } = {}) {
    this.withT(x, z, ry, () => {
      this.rb(w, 0.05, d, 0.015, wood, 0, h - 0.025, 0);
      this.rb(w - 0.1, 0.025, d - 0.1, 0.01, wood, 0, 0.13, 0);
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) this.turnedLeg(wood, sx * (w / 2 - 0.06), 0, sz * (d / 2 - 0.06), h - 0.05, 0.028);
    });
    return h;   // top surface y
  }

  /** Open bookcase against the wall: sides, back, shelves, rows of books, a plant on top. */
  bookcase(x, z, ry = 0, { w = 0.42, h = 1.85, d = 0.3, shelves = 6, wood = this.texM('oakDark', TEX.oak(2), { roughness: 0.6 }), seed = 40 } = {}) {
    const step = (h - 0.08) / (shelves - 1 || 1);
    this.withT(x, z, ry, () => {
      for (const s of [-1, 1]) this.rb(0.025, h, d, 0.006, wood, s * (w / 2 - 0.0125), h / 2, d / 2);
      this.rb(w, h, 0.02, 0.005, wood, 0, h / 2, 0.01);
      for (let i = 0; i < shelves; i++) this.rb(w - 0.04, 0.022, d - 0.01, 0.006, wood, 0, 0.06 + i * step, d / 2);
      for (let i = 0; i < shelves - 2; i++) this.bookRow(-w / 2 + 0.03, 0.071 + i * step + 0.012, d / 2, 30, seed + i, w - (i === 2 ? 0.25 : 0.07), d * 0.66);
      this.plant(0, h, d / 2, 0.3, 'pothos', 0xe0d8c8);
    });
  }

  /** Torchiere floor lamp (uplight) — a lamp in the state system. */
  torchiere(id, x, z, { h = 1.72, on = { evening: 1, night: 0.7, day: 0 }, color = 0xffc488, intensity = 4.2 } = {}) {
    const lampM = this.M('lampMetal', 0x8a8478, { roughness: 0.35, metalness: 0.7 });
    const bowlM = this.glowM(`torchBowl-${id}`, 0xf0e8dc, 0xffd8a0, { side: THREE.DoubleSide });
    this.lathe([[0.001, 0], [0.16, 0], [0.16, 0.025], [0.04, 0.04], [0.001, 0.045]], lampM, x, 0, z);
    this.rod([x, 0.04, z], [x, h, z], 0.012, lampM);
    this.lathe([[0.02, 0], [0.1, 0.03], [0.18, 0.1], [0.2, 0.13]], bowlM, x, h, z, { seg: 28 });
    return this.lamp(id, {
      light: this.pointLight(color, intensity, 7, x + 0.05, h + 0.23, z + 0.25, 1.2),
      glows: [this.halo(0xffc890, 1.4, 0.32, x, h + 0.18, z + 0.05), this.halo(0xffb070, 3.0, 0.12, x, h + 0.83, z - 0.05)],
      mats: [[bowlM, 1.4]], on,
    });
  }

  /** Table lamp (ceramic base + fabric shade) standing on a surface at height y. */
  tableLamp(id, x, y, z, { on = { evening: 1, night: 1, day: 0 }, shade = 0xece4d4, base = 0xc8c4bc } = {}) {
    this.lathe([[0.001, 0], [0.06, 0], [0.09, 0.08], [0.08, 0.2], [0.03, 0.26], [0.012, 0.32], [0.001, 0.32]], this.M(`lampBase-${base}`, base, { roughness: 0.2, metalness: 0.3 }), x, y, z);
    const shadeM = this.glowM(`shade-${id}`, shade, 0xffc890, { side: THREE.DoubleSide });
    this.cy(0.13, 0.16, 0.22, shadeM, x, y + 0.4, z, { open: true, seg: 24 });
    return this.lamp(id, { light: this.pointLight(0xffc488, 2.6, 5, x + 0.15, y + 0.4, z + 0.15, 1.3), glows: [this.halo(0xffc890, 0.8, 0.26, x, y + 0.4, z + 0.05)], mats: [[shadeM, 0.9]], on });
  }

  /** Nightstand with a drawer and a ring pull; returns the top y. */
  nightstand(x, z, ry = 0, { wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.35 }) } = {}) {
    this.withT(x, z, ry, () => {
      this.rb(0.5, 0.6, 0.44, 0.02, wood, 0, 0.3, 0.22);
      this.rb(0.44, 0.2, 0.02, 0.006, wood, 0, 0.42, 0.45);
      this.torus(0.02, 0.004, this.brass(), 0, 0.4, 0.465, { ts: 16, rs: 6 });
    });
    return 0.6;
  }

  /**
   * Bed seen from the side: headboard at local x = -L/2 (slatted), footboard, rails, mattress,
   * a draped duvet with turned-back edge, pillows. Length along x, width along z, centred on z.
   */
  bed(x, z, ry = 0, { L = 2.1, W = 1.62, wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.35 }), duvet = TEX.stripes(), sheet = 0xf0eee8, seed = 3 } = {}) {
    const duv = this.texM(`duvet-${duvet.uuid}`, duvet, { roughness: 0.95, side: THREE.DoubleSide });
    const sh = this.M(`sheet-${sheet}`, sheet, { roughness: 0.95 });
    const hx = -L / 2;
    this.withT(x, z, ry, () => {
      this.rb(0.09, 1.35, W + 0.14, 0.03, wood, hx - 0.05, 0.675, 0);
      for (let k = 0; k < 4; k++) this.rb(0.02, 0.14, W - 0.1, 0.006, wood, hx, 0.75 + k * 0.17, 0);
      this.rb(0.13, 0.08, W + 0.2, 0.03, wood, hx - 0.05, 1.38, 0);
      this.rb(0.1, 0.8, W + 0.14, 0.03, wood, -hx + 0.05, 0.4, 0);
      this.rb(0.14, 0.07, W + 0.2, 0.03, wood, -hx + 0.05, 0.82, 0, { rz: 0.15 });
      for (const s of [-1, 1]) this.rb(L + 0.02, 0.24, 0.06, 0.02, wood, 0, 0.3, s * (W / 2 + 0.02));
      this.rb(L - 0.06, 0.26, W, 0.07, this.M('mattress', 0xe8e6e0, { roughness: 0.95 }), 0, 0.5, 0);
      this.drape(L * 0.77, W + 0.04, 0.3, duv, L * 0.08, 0.64, 0, { sides: [0, 1, 1, 1], uv: [0.64, 0.32], seed, wrinkle: 0.02, seg: [48, 30], r: 0.05 });
      this.cush(0.22, 0.07, W, 0.03, duv, -L * 0.27, 0.66, 0, { puff: 0.2, seed: seed + 9 });
      for (const pz of [-W / 4, W / 4]) {
        this.cush(0.5, 0.17, W * 0.46, 0.08, sh, hx + 0.28, 0.78, pz, { rz: 0.55, seed: seed + 10, puff: 0.5 });
        this.cush(0.45, 0.15, W * 0.43, 0.07, duv, hx + 0.46, 0.76, pz, { rz: 0.35, seed: seed + 11, puff: 0.5 });
      }
    });
  }

  /** Chest of drawers (2 × rows) with ring pulls and an optional mirror on the wall above. Returns top y. */
  dresser(x, z, ry = 0, { w = 1.3, h = 0.92, d = 0.5, rows = 4, mirror = true, wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.35 }) } = {}) {
    const dh = (h - 0.08) / rows;
    this.withT(x, z, ry, () => {
      this.rb(w, h, d, 0.02, wood, 0, h / 2 + 0.04, d / 2);
      this.rb(w + 0.06, 0.04, d + 0.04, 0.012, wood, 0, h + 0.055, d / 2);
      for (let j = 0; j < rows; j++) for (const s of [-1, 1]) {
        this.rb(w / 2 - 0.05, dh - 0.02, 0.02, 0.006, wood, s * (w / 4 + 0.005), 0.08 + dh / 2 + j * dh, d + 0.005);
        this.torus(0.025, 0.004, this.M('ringPull', 0xc8ccd0, { metalness: 0.9, roughness: 0.25 }), s * (w / 4 + 0.005), 0.11 + dh / 2 + j * dh, d + 0.02, { ts: 16, rs: 6 });
      }
      if (mirror) {
        this.rb(w * 0.63, 1.02, 0.04, 0.015, wood, 0, h + 0.7, 0.03);
        this.pl(w * 0.55, 0.92, this.texM('mirror', TEX.mirror(), { roughness: 0.1, metalness: 0.2 }), 0, h + 0.7, 0.052);
      }
    });
    return h + 0.075;
  }

  /** Desk with a drawer pedestal on the right and two legs on the left. Returns top y. */
  desk(x, z, ry = 0, { w = 1.2, d = 0.6, h = 0.78, wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.35 }) } = {}) {
    this.withT(x, z, ry, () => {
      this.rb(w, 0.04, d, 0.012, wood, 0, h - 0.02, d / 2);
      this.rb(0.42, h - 0.06, d - 0.04, 0.015, wood, w / 2 - 0.22, (h - 0.06) / 2 + 0.01, d / 2);
      for (let j = 0; j < 3; j++) {
        const y = 0.16 + j * (h - 0.1) / 3.3;
        this.rb(0.38, 0.2, 0.02, 0.006, wood, w / 2 - 0.22, y, d - 0.005);
        this.rb(0.08, 0.015, 0.015, 0.005, this.brass(), w / 2 - 0.22, y + 0.04, d + 0.012);
      }
      for (const sz of [0.04, d - 0.04]) this.rb(0.04, h - 0.04, 0.04, 0.01, wood, -w / 2 + 0.04, (h - 0.04) / 2, sz);
    });
    return h;
  }

  /** Dining / desk chair with a seat pad; front faces +z of its frame. Optional jacket over the back. */
  chair(x, z, ry = 0, { wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.35 }), pad = 0x4a2a24, jacket = null, seed = 20 } = {}) {
    this.withT(x, z, ry, () => {
      this.rb(0.44, 0.05, 0.42, 0.015, wood, 0, 0.46, 0);
      this.cush(0.4, 0.04, 0.38, 0.015, this.M(`chairPad-${pad}`, pad, { roughness: 0.9 }), 0, 0.5, 0, { seed });
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) this.rb(0.035, 0.45, 0.035, 0.01, wood, sx * 0.18, 0.225, sz * 0.17);
      for (const sx of [-1, 1]) this.rb(0.035, 0.45, 0.035, 0.01, wood, sx * 0.18, 0.7, -0.19);
      this.rb(0.42, 0.1, 0.025, 0.01, wood, 0, 0.88, -0.2);
      if (jacket != null) this.drape(0.38, 0.06, 0.3, this.M(`jacket-${jacket}`, jacket, { roughness: 0.95, side: THREE.DoubleSide }), 0, 0.94, -0.2, { sides: [0, 0, 1, 1], seed: seed + 1, r: 0.03 });
    });
  }

  /** Low TV unit with doors, a flat TV on a stand and a soundbar. */
  tvUnit(x, z, ry = 0, { w = 1.2, wood = this.texM('darkwood', TEX.darkWood(), { roughness: 0.45 }) } = {}) {
    const black = this.M('tvStand', 0x1a1a1c);
    this.withT(x, z, ry, () => {
      this.rb(w, 0.5, 0.42, 0.02, wood, 0, 0.32, 0.21);
      for (const s of [-1, 1]) this.rb(w / 2 - 0.04, 0.4, 0.015, 0.006, wood, s * (w / 4 - 0.01), 0.32, 0.42);
      for (const s of [-1, 1]) this.rb(0.1, 0.012, 0.012, 0.005, this.brass(), s * 0.05, 0.38, 0.435);
      for (const sx of [-1, 1]) for (const sz of [0.04, 0.38]) this.cy(0.02, 0.016, 0.07, wood, sx * (w / 2 - 0.05), 0.035, sz);
      this.rb(0.3, 0.02, 0.18, 0.006, black, 0, 0.58, 0.21);
      this.rb(0.05, 0.12, 0.03, 0.01, black, 0, 0.64, 0.21);
      this.rb(1.0, 0.6, 0.045, 0.012, this.M('tvBody', 0x121214, { roughness: 0.4 }), 0, 0.99, 0.2);
      this.pl(0.96, 0.56, this.M('tvScreen', 0x0c0e12, { roughness: 0.12, metalness: 0.3, emissive: 0x05070a }), 0, 0.99, 0.2235);   // just in front of the body's flat face — never coplanar
      this.rb(0.6, 0.06, 0.08, 0.02, black, 0, 0.6, 0.34);
    });
  }
}

export { LocationKit as FurnitureKit };
