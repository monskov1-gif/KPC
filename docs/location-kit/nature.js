import * as THREE from 'three';
import { canvasTexture, rng, noise3, fbm3, smoothNormals } from './location-kit.js';

/** Concatenate non-indexed geometries with the same attribute set (keeps vertex colours). */
function mergeGeos(list) {
  const names = Object.keys(list[0].attributes);
  const out = new THREE.BufferGeometry();
  for (const name of names) {
    const size = list[0].attributes[name].itemSize;
    let len = 0;
    for (const g of list) len += g.attributes[name].count * size;
    const arr = new Float32Array(len);
    let o = 0;
    for (const g of list) { arr.set(g.attributes[name].array, o); o += g.attributes[name].count * size; }
    out.setAttribute(name, new THREE.BufferAttribute(arr, size));
  }
  return out;
}

/**
 * Outdoor locations (from "Blood of the North"). Natural shapes shared by the outdoor scenes and the cave: smooth eroded rocks (displaced,
 * smooth-shaded, vertex-coloured), snow-laden spruces built from instanced branch cards,
 * branching bare birches/aspens, ground with real relief. Everything is procedural and seeded.
 */

const lerp = (a, b, t) => a + (b - a) * t;
const sat = (v) => Math.max(0, Math.min(1, v));

// ------------------------------------------------------------------ rocks

/** Fine grain for rock surfaces (multiplied over the vertex colours). */
export function rockDetailTexture() {
  return canvasTexture('nat-rockdetail', 256, 256, (ctx, w, h) => {
    const r = rng(911);
    const img = ctx.createImageData(w, h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const n = fbm3(x / 22, y / 22, 0.5, 3, 4) * 0.55 + fbm3(x / 5, y / 5, 2.5, 5, 2) * 0.3 + r() * 0.15;
      const v = 150 + n * 105;
      const i = (y * w + x) * 4;
      img.data[i] = v; img.data[i + 1] = v * 0.98; img.data[i + 2] = v * 0.95; img.data[i + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    // hairline cracks
    ctx.strokeStyle = 'rgba(40,30,24,0.35)'; ctx.lineWidth = 1;
    for (let k = 0; k < 26; k++) {
      let x = r() * w, y = r() * h;
      ctx.beginPath(); ctx.moveTo(x, y);
      for (let s = 0; s < 8; s++) { x += (r() - 0.5) * 22; y += (r() - 0.3) * 14; ctx.lineTo(x, y); }
      ctx.stroke();
    }
  }, { aniso: 4 });
}

/**
 * A rock: an icosphere displaced by fractal noise, smooth shaded, with vertex colours
 * (darker in hollows, optional sandstone strata, optional snow on upward faces).
 *   opts: { detail, rough, strata, flat, snow, colA, colB, dark, sharp, stretch }
 */
export function rockGeometry(seed, opts = {}) {
  const { detail = 4, rough = 0.32, strata = 0, flat = -0.3, top = 9, snow = 0, sharp = 0, colA = 0x8a8278, colB = 0x6a6258, dark = 0.45 } = opts;
  const geo = new THREE.IcosahedronGeometry(1, detail);
  const p = geo.attributes.position;
  const disp = new Float32Array(p.count);
  const s = seed * 7.13;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    let d = 1 + (fbm3(x * 1.3 + s, y * 1.3, z * 1.3, seed, 4) - 0.5) * 2 * rough;
    d += (fbm3(x * 4 + s, y * 4, z * 4, seed + 3, 3) - 0.5) * 0.12 * (1 + sharp);
    if (sharp) d += Math.abs(noise3(x * 2.2 + s, y * 2.2, z * 2.2, seed + 9) - 0.5) * -0.35 * sharp;   // ridged facets
    if (strata) d += Math.sin(y * 13 + fbm3(x * 2 + s, y * 2, z * 2, seed + 5, 2) * 7) * 0.035 * strata;   // eroded layers
    disp[i] = d;
    let nx = x * d, ny = y * d, nz = z * d;
    if (ny < flat) ny = flat + (ny - flat) * 0.12;      // sits on the ground
    if (ny > top) ny = top + (ny - top) * 0.08;         // a worn, flat top (altar, ledge)
    p.setXYZ(i, nx, ny, nz);
  }
  smoothNormals(geo);
  const n = geo.attributes.normal;
  const cA = new THREE.Color(colA), cB = new THREE.Color(colB), cS = new THREE.Color(0xeef2f6), cSh = new THREE.Color(0xb4c2d2);
  const col = new Float32Array(p.count * 3);
  const bare = snow ? new Float32Array(p.count * 3) : null;
  const c = new THREE.Color();
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const t = fbm3(x * 2.4 + 11, y * 2.4, z * 2.4, seed + 1, 3);
    c.copy(cA).lerp(cB, sat(t * 1.6 - 0.3));
    if (strata) c.multiplyScalar(0.86 + 0.22 * (0.5 + 0.5 * Math.sin(y * 13 + t * 6)));
    const hollow = sat((1 - disp[i]) * 3 + 0.5);                  // recesses are darker
    c.multiplyScalar(lerp(1.06, 1 - dark, hollow * hollow));
    if (y < flat + 0.08) c.multiplyScalar(0.62);                  // contact shadow at the base
    if (bare) { bare[i * 3] = c.r; bare[i * 3 + 1] = c.g; bare[i * 3 + 2] = c.b; }
    if (snow) {
      const up = n.getY(i) + (fbm3(x * 5, y * 5, z * 5, seed + 7, 2) - 0.5) * 0.5;
      const k = sat((up - (1 - snow)) * 4);
      if (k > 0) c.lerp(up > 0.9 ? cS : cSh, k);
    }
    col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  if (bare) geo.userData.snowCols = { on: col.slice(), off: bare };
  return geo;
}

/** Toggle the snow caps baked into a rock's vertex colours (November vs December). */
export function setRockSnow(geo, on) {
  const sc = geo.userData.snowCols;
  if (!sc || geo.userData.snowOn === on) return;
  geo.userData.snowOn = on;
  geo.attributes.color.array.set(on ? sc.on : sc.off);
  geo.attributes.color.needsUpdate = true;
}

/** A material for rocks: vertex colours × fine grain. */
export function rockMaterial(low, extra = {}) {
  const M = low ? THREE.MeshLambertMaterial : THREE.MeshStandardMaterial;
  const p = { vertexColors: true, map: rockDetailTexture(), color: 0xffffff, ...extra };
  if (!low) { p.roughness = extra.roughness ?? 0.92; p.metalness = 0; } else { delete p.roughness; }
  return new M(p);
}

// ------------------------------------------------------------------ bark

export function barkTexture(kind = 'spruce') {
  return canvasTexture(`nat-bark-${kind}`, 64, 256, (ctx, w, h) => {
    const r = rng(kind.length * 31 + 7);
    if (kind === 'birch') {
      ctx.fillStyle = '#d8d4cc'; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < 900; i++) { ctx.fillStyle = r() < 0.5 ? 'rgba(255,255,250,0.5)' : 'rgba(150,146,140,0.25)'; ctx.fillRect(r() * w, r() * h, 1 + r() * 4, 1); }
      for (let i = 0; i < 26; i++) {           // black lenticels and scars
        const y = r() * h, x = r() * w, L = 4 + r() * 22;
        ctx.fillStyle = `rgba(28,24,22,${0.6 + r() * 0.4})`;
        ctx.fillRect(x, y, L, 1 + r() * 2.5);
        if (r() < 0.3) { ctx.beginPath(); ctx.ellipse(x, y, 3 + r() * 4, 4 + r() * 6, 0, 0, 7); ctx.fill(); }
      }
      return;
    }
    const mossy = kind === 'mossy';
    ctx.fillStyle = mossy ? '#3a3a30' : '#3e3832'; ctx.fillRect(0, 0, w, h);
    // vertical plates separated by dark fissures
    for (let x = 0; x < w; x += 3 + r() * 5) {
      const wd = 3 + r() * 6;
      for (let y = 0; y < h; y += 6 + r() * 14) {
        const hh = 8 + r() * 24, v = 60 + r() * 40;
        ctx.fillStyle = `rgb(${v + 4},${v},${v - 4})`;
        ctx.fillRect(x, y, wd, hh);
        ctx.fillStyle = 'rgba(255,240,220,0.08)'; ctx.fillRect(x, y, 1, hh);
      }
      ctx.fillStyle = 'rgba(14,10,8,0.7)'; ctx.fillRect(x + wd, 0, 1 + r(), h);
    }
    if (mossy) for (let i = 0; i < 500; i++) { const g = 90 + r() * 70; ctx.fillStyle = `rgba(${g * 0.7},${g},${g * 0.45},${0.35 + r() * 0.4})`; ctx.fillRect(r() * w, r() * h, 1 + r() * 4, 1 + r() * 3); }
  }, { aniso: 4 });
}

// ------------------------------------------------------------------ spruces

/**
 * One tier of a spruce seen from the side: drooping branches with needle sprays, snow lying on
 * their upper sides. The card's top centre is the trunk.
 */
export function spruceCardTexture(variant = 0, snow = 1) {
  return canvasTexture(`nat-sprucecard-${variant}-${snow}`, 256, 128, (ctx, w, h) => {
    const r = rng(1000 + variant * 37);
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const greens = ['#121e17', '#16241b', '#1b2b20', '#203226', '#263a2c'];
    const branches = [];
    for (const side of [-1, 1]) {
      const n = 5 + Math.floor(r() * 2);
      for (let k = 0; k < n; k++) {
        const y0 = 3 + k * (h * 0.1) + r() * 5;
        const len = (w * 0.48) * (0.78 + r() * 0.22) * (1 - k * 0.05);
        branches.push({ side, y0, len, droop: 0.1 + r() * 0.16, lift: 0.06 + r() * 0.05 });
      }
    }
    // a branch rises a little from the trunk, then sags towards its tip
    const pt = (b, t) => [cx + b.side * b.len * t, b.y0 - b.len * b.lift * t + b.len * b.droop * t * t];
    const spray = (x, y, dir, len, dens) => {
      for (let q = 0; q < dens; q++) {
        ctx.strokeStyle = greens[Math.floor(r() * greens.length)];
        ctx.lineWidth = 1 + r() * 1.4;
        const dx = dir * (1 + r() * len * 0.35), dy = len * (0.35 + r() * 0.65);
        ctx.beginPath(); ctx.moveTo(x, y); ctx.quadraticCurveTo(x + dx * 0.6, y + dy * 0.3, x + dx, y + dy); ctx.stroke();
      }
    };
    for (const b of branches) {
      // hanging branchlets (the "curtain" of a northern spruce) with needle sprays
      for (let t = 0.05; t < 1; t += 0.03) {
        const [x, y] = pt(b, t);
        spray(x, y, b.side, (1 - t * 0.5) * (12 + r() * 9), 4);
        if (r() < 0.35) {
          const L = 6 + r() * 10;
          const ex = x + b.side * L * 0.8, ey = y + L * 0.5;
          ctx.strokeStyle = '#1e1a14'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(ex, ey); ctx.stroke();
          spray(ex, ey, b.side, 8 + r() * 6, 3);
        }
      }
      ctx.strokeStyle = '#2a2018'; ctx.lineWidth = 2;
      ctx.beginPath();
      for (let t = 0; t <= 1; t += 0.05) { const [x, y] = pt(b, t); t === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y); }
      ctx.stroke();
      for (let i = 0; i < 30; i++) { const t = 0.3 + r() * 0.7; const [x, y] = pt(b, t); ctx.fillStyle = 'rgba(70,98,76,0.5)'; ctx.fillRect(x + (r() - 0.5) * 8, y + r() * 9, 2, 1); }
    }
    // snow lying along the top of each branch (December): long pillows, blue-grey undersides
    if (snow > 0) {
      const rs = rng(2000 + variant);
      for (const b of branches) {
        const load = rs();                                  // some branches carry a lot, some almost none
        if (load < 0.25) continue;
        let t = 0.15 + rs() * 0.2;
        while (t < 0.95) {
          const run = 0.08 + rs() * 0.22 * load;            // a clump spans a stretch of the branch
          const [x0, y0] = pt(b, t), [x1, y1] = pt(b, Math.min(0.97, t + run));
          const th = (1.6 + rs() * 3.2) * (0.5 + snow * 0.6) * (0.6 + load * 0.6) * (1 - t * 0.3);
          const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, L = Math.hypot(x1 - x0, y1 - y0) / 2 + th, ang = Math.atan2(y1 - y0, x1 - x0);
          ctx.save(); ctx.translate(cx, cy); ctx.rotate(ang);
          ctx.fillStyle = '#8fa0b4'; ctx.beginPath(); ctx.ellipse(0, th * 0.35, L, th * 0.75, 0, 0, 7); ctx.fill();
          ctx.fillStyle = '#e2e9f0'; ctx.beginPath(); ctx.ellipse(0, -th * 0.1, L * 0.95, th * 0.62, 0, 0, 7); ctx.fill();
          ctx.fillStyle = '#fbfdff'; ctx.beginPath(); ctx.ellipse(-L * 0.2, -th * 0.4, L * 0.5, th * 0.25, 0, 0, 7); ctx.fill();
          // a few drips of green showing through
          for (let k = 0; k < 3; k++) { ctx.fillStyle = greens[Math.floor(rs() * greens.length)]; ctx.fillRect((rs() - 0.5) * L * 1.6, th * 0.3, 2, 3 + rs() * 4); }
          ctx.restore();
          t += run + 0.06 + rs() * 0.22;
        }
      }
    }
  }, { aniso: 4 });
}

/** Switch a stand between bare-green (November) and snow-laden (December) branches. */
export function setStandSnow(stand, snow) {
  const u = stand.userData;
  if (!u?.cardMat || u.snow === snow) return;
  u.snow = snow;
  u.cardMat.map = spruceCardTexture(u.variant, snow);
  u.cardMat.needsUpdate = true;
}

/**
 * A stand of spruces as two instanced meshes (trunks + branch cards): hundreds of trees in two draw
 * calls. trees: [{ x, z, s, kind: 'young'|'tall', seed }].
 */
export function spruceStand(trees, { low = false, snow = 1, variant = 0, tint = 0xffffff, bark = 'spruce', fog = true } = {}) {
  const g = new THREE.Group();
  const cards = [];
  const trunks = [];
  for (const t of trees) {
    const r = rng(t.seed ?? Math.round(t.x * 131 + t.z * 71 + 9));
    const s = t.s;
    const H = (t.kind === 'tall' ? 13 + r() * 6 : 6.2 + r() * 2.4) * s;
    const crownBase = t.kind === 'tall' ? H * (0.42 + r() * 0.16) : 0.25 * s;
    const R = (t.kind === 'tall' ? 1.5 : 1.35) * s * (0.85 + r() * 0.3);
    trunks.push({ x: t.x, y: t.y || 0, z: t.z, h: H * 0.96, r: (t.kind === 'tall' ? 0.12 : 0.09) * s * (0.75 + r() * 0.5), lean: (r() - 0.5) * 0.06 });
    if (t.snag) continue;                                   // a dead snag: just the bare trunk
    const tiers = Math.max(7, Math.round((H - crownBase) / (0.3 * s)));       // tiers overlap: no stacked 'plates'
    for (let k = 0; k < tiers; k++) {
      const f = k / tiers;
      const y = crownBase + (H - crownBase) * f;
      if (t.kind === 'young' && k > 1 && r() < 0.18) continue;          // a missing whorl: young spruces are ragged
      const width = R * 2 * Math.pow(1 - f, 0.92) * (t.kind === 'young' ? 0.65 + r() * 0.7 : 0.85 + r() * 0.3) + 0.25 * s;
      const height = width * (0.55 + r() * 0.18);
            // two cards turned towards the camera (never edge-on), a narrower one across for depth
      const shade = 0.82 + r() * 0.3 - (1 - f) * 0.08;
      for (const [yaw, ww] of [[-0.45 + (r() - 0.5) * 0.3, 1], [0.45 + (r() - 0.5) * 0.3, 0.92], [Math.PI / 2 + (r() - 0.5) * 0.4, 0.7]]) cards.push({ x: t.x + (t.kind === 'young' ? (r() - 0.5) * 0.12 * s : 0), y: (t.y || 0) + y + height * 0.9, z: t.z, yaw, w: width * ww, h: height, shade });
    }
    // the leader
    cards.push({ x: t.x, y: (t.y || 0) + H + 0.4 * s, z: t.z, yaw: r() * 3, w: 0.35 * s, h: 0.6 * s, shade: 1 });
  }
  // branch cards: top-centre origin, normals bent outward and up so a tier shades like a cone
  const cardGeo = new THREE.PlaneGeometry(1, 1, 2, 1);
  cardGeo.translate(0, -0.5, 0);
  const cp = cardGeo.attributes.position, cn = cardGeo.attributes.normal;
  for (let i = 0; i < cp.count; i++) { const v = new THREE.Vector3(cp.getX(i) * 1.1, 1.0 + cp.getY(i) * 0.3, 0.55).normalize(); cn.setXYZ(i, v.x, v.y, v.z); }
  const tex = spruceCardTexture(variant, snow);
  const M = low ? THREE.MeshLambertMaterial : THREE.MeshStandardMaterial;
  const cardMat = new M({ map: tex, alphaTest: 0.42, side: THREE.DoubleSide, color: tint, fog, ...(low ? {} : { roughness: 0.95 }) });
  const cim = new THREE.InstancedMesh(cardGeo, cardMat, cards.length);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), col = new THREE.Color();
  cards.forEach((c, i) => {
    q.setFromEuler(e.set(0, c.yaw, 0));
    m.compose(new THREE.Vector3(c.x, c.y, c.z), q, new THREE.Vector3(c.w, c.h, 1));
    cim.setMatrixAt(i, m);
    cim.setColorAt(i, col.setScalar(c.shade));
  });
  g.add(cim);
  const trunkGeo = new THREE.CylinderGeometry(0.45, 1, 1, 10, 4, true);
  trunkGeo.translate(0, 0.5, 0);
  const tp = trunkGeo.attributes.position;
  for (let i = 0; i < tp.count; i++) { const y = tp.getY(i); const k = 1 + (y < 0.08 ? (0.08 - y) * 9 : 0); tp.setX(i, tp.getX(i) * k); tp.setZ(i, tp.getZ(i) * k); }   // root flare
  trunkGeo.computeVertexNormals();
  const bt = barkTexture(bark).clone(); bt.needsUpdate = true; bt.repeat.set(2, 3);
  const trunkMat = new M({ map: bt, color: 0xffffff, fog, ...(low ? {} : { roughness: 1 }) });
  const tim = new THREE.InstancedMesh(trunkGeo, trunkMat, trunks.length);
  trunks.forEach((t, i) => {
    q.setFromEuler(e.set(t.lean, i * 1.7, t.lean * 0.6));
    m.compose(new THREE.Vector3(t.x, t.y - 0.15, t.z), q, new THREE.Vector3(t.r, t.h + 0.15, t.r));
    tim.setMatrixAt(i, m);
  });
  g.add(tim);
  g.userData = { cardMat, trunkMat, variant, snow };
  return g;
}

// ------------------------------------------------------------------ bare trees

function branchGeo(from, to, r0, r1, seg = 5) {
  const dir = new THREE.Vector3().subVectors(to, from);
  const L = dir.length();
  const geo = new THREE.CylinderGeometry(r1, r0, L, seg, 1, false).toNonIndexed();
  geo.translate(0, L / 2, 0);
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize());
  geo.applyQuaternion(q);
  geo.translate(from.x, from.y, from.z);
  return geo;
}

/** A leafless birch/aspen with real branching (one merged mesh per tree). */
export function bareTreeGeometry(seed, { height = 5.2, leaves = 0 } = {}) {
  const r = rng(seed);
  const trunkParts = [], twigParts = [];
  const grow = (from, dir, len, rad, depth) => {
    const segs = depth === 0 ? 4 : 2;
    let p = from.clone(), d = dir.clone();
    for (let s = 0; s < segs; s++) {
      const jit = depth === 0 ? 0.05 : 0.25;
      d.x += (r() - 0.5) * jit; d.z += (r() - 0.5) * jit; d.normalize();
      const q = p.clone().addScaledVector(d, len / segs);
      const r0 = rad * (1 - s / segs * 0.35), r1 = rad * (1 - (s + 1) / segs * 0.35);
      (depth === 0 ? trunkParts : twigParts).push(branchGeo(p, q, r0, r1, depth === 0 ? 8 : depth === 1 ? 5 : 3));
      if (depth < 3) {
        const kids = depth === 0 ? (s >= 1 ? 2 + Math.floor(r() * 2) : 0) : (r() < 0.75 ? 1 + Math.floor(r() * 2) : 0);
        for (let k = 0; k < kids; k++) {
          const a = r() * Math.PI * 2;
          const nd = new THREE.Vector3(Math.cos(a) * 0.9, 0.55 + r() * 0.6, Math.sin(a) * 0.9).normalize().lerp(d, depth === 0 ? 0.3 : 0.45).normalize();
          const at = p.clone().lerp(q, r());
          grow(at, nd, len * (depth === 0 ? 0.42 : 0.55) * (0.7 + r() * 0.5), r1 * (depth === 0 ? 0.45 : 0.6), depth + 1);
        }
      }
      p = q;
    }
  };
  grow(new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 1, 0), height, 0.1, 0);
  const strip = (g) => { g.deleteAttribute('uv'); return g; };
  const trunk = mergeGeos(trunkParts.map((g) => g));
  const twigs = mergeGeos(twigParts.map(strip));
  return { trunk, twigs };
}

/** A bare tree as a group: white bark trunk + dark twigs; optional last yellow leaves. */
export function bareTree(seed, { low = false, height = 5.2, kind = 'birch', leaves = 0.0, fog = true } = {}) {
  const { trunk, twigs } = bareTreeGeometry(seed, { height });
  const M = low ? THREE.MeshLambertMaterial : THREE.MeshStandardMaterial;
  const g = new THREE.Group();
  const bt = barkTexture('birch');
  g.add(new THREE.Mesh(trunk, new M({ map: bt, color: kind === 'birch' ? 0xffffff : 0xb4b8a8, fog, ...(low ? {} : { roughness: 0.9 }) })));
  g.add(new THREE.Mesh(twigs, new M({ color: 0x3a302a, fog, ...(low ? {} : { roughness: 1 }) })));
  if (leaves > 0) {
    const r = rng(seed + 5);
    const lp = [];
    const tw = twigs.attributes.position;
    for (let i = 0; i < tw.count; i += 9) if (r() < leaves && tw.getY(i) > height * 0.45) lp.push(tw.getX(i), tw.getY(i), tw.getZ(i));
    if (lp.length) {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(lp, 3));
      g.add(new THREE.Points(geo, new THREE.PointsMaterial({ color: 0xc8a040, size: 0.07, fog })));
    }
  }
  return g;
}

// ------------------------------------------------------------------ ground

/**
 * A ground plane with relief: h(x, z) gives the height. Vertex colours shade slopes.
 */
export function reliefGround(w, d, segW, segD, height, colorAt) {
  const geo = new THREE.PlaneGeometry(w, d, segW, segD);
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) p.setY(i, height(p.getX(i), p.getZ(i)));
  geo.computeVertexNormals();
  if (colorAt) {
    const col = new Float32Array(p.count * 3), c = new THREE.Color();
    const n = geo.attributes.normal;
    for (let i = 0; i < p.count; i++) { colorAt(c, p.getX(i), p.getY(i), p.getZ(i), n.getY(i)); col.set([c.r, c.g, c.b], i * 3); }
    geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  }
  return geo;
}

/** Soft vertical light shaft texture (for sun rays through the trees). */
export function shaftTexture() {
  return canvasTexture('nat-shaft', 64, 256, (ctx, w, h) => {
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

/** Soft cloud puff for fog banks and river steam. */
export function mistTexture(seed = 1) {
  return canvasTexture(`nat-mist-${seed}`, 128, 64, (ctx, w, h) => {
    const img = ctx.createImageData(w, h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const dx = (x / w - 0.5) * 2, dy = (y / h - 0.5) * 2;
      const fall = sat(1 - (dx * dx + dy * dy * 1.4));
      const n = fbm3(x / 18, y / 12, seed, seed, 4);
      const a = fall * fall * sat(n * 1.6 - 0.35);
      const i = (y * w + x) * 4;
      img.data[i] = 255; img.data[i + 1] = 255; img.data[i + 2] = 255; img.data[i + 3] = a * 255;
    }
    ctx.putImageData(img, 0, 0);
  }, { color: false });
}
