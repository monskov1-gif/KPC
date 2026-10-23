import * as THREE from 'three';
import { LocationKit, glowTexture, fbm3, canvasTexture } from './location-kit.js';
import { spruceStand, bareTree, rockGeometry, rockMaterial, reliefGround, mistTexture, shaftTexture, barkTexture, setStandSnow, setRockSnow } from './nature.js';

/**
 * Example 3 — an outdoor location, side-on: a forest edge in late autumn / first snow.
 * Relief ground with vertex-coloured slopes, a path, layered spruce stands (hundreds of trees in a
 * few draw calls), bare birches, snow-capped rocks, mist banks between the layers, sun shafts,
 * fog for depth, and a low-sun lens flare zone. States: 'day' (overcast), 'evening' (dusk), 'night'.
 */
export function buildForest(root, { low = false } = {}) {
  const kit = new LocationKit(root, {
    low,
    ambient: {
      day: { sky: 0xdfe6ee, ground: 0x6a6458, hemi: 1.1, fill: 0xfff2e0, fillI: 0.7, bg: 0xb8c4cc },
      evening: { sky: 0x8a90b8, ground: 0x3a3a48, hemi: 0.7, fill: 0xc8c0e0, fillI: 0.35, bg: 0x6a5a6e },   // snow stays cool; warmth only in the sky
      night: { sky: 0x22304e, ground: 0x0a0a0c, hemi: 0.35, fill: 0x8aa4d8, fillI: 0.35, bg: 0x0a0e18 },
    },
  });
  kit.setupLights();
  const r = (() => { let a = 7; return () => ((a = (a * 16807) % 2147483647) / 2147483647); })();
  // the path wanders a little; it is trodden down (a shallow trough) and the far side climbs
  const pathZ = (x) => -1.2 + Math.sin(x * 0.21) * 0.35 + Math.sin(x * 0.07 + 1) * 0.3;
  const groundH = (x, z) => (fbm3(x * 0.08, 0, z * 0.08, 3, 3) - 0.5) * 1.4 + (fbm3(x * 0.7, 0, z * 0.7, 9, 2) - 0.5) * 0.14
    + Math.max(0, -z - 6) * 0.25 - Math.max(0, 1 - Math.abs(z - pathZ(x)) / 0.9) * 0.1;

  // ---- ground: snow on the flats, earth on the slopes, a trodden path
  const snow = new THREE.Color(0xeef2f6), shade = new THREE.Color(0xa8b8cc), earth = new THREE.Color(0x5a5048), grass = new THREE.Color(0x9a8a62), path = new THREE.Color(0x6e665c);
  const sat = (v) => Math.max(0, Math.min(1, v));
  const geo = reliefGround(60, 30, low ? 110 : 180, low ? 60 : 100, (x, z) => groundH(x, z - 8), (c, x, y, z, ny) => {
    const wz = z - 8;
    c.copy(snow).lerp(shade, sat((0.985 - ny) * 6) * 0.8 + (fbm3(x * 0.5, 0, wz * 0.5, 51, 3) - 0.5) * 0.35);
    c.lerp(earth, sat((0.93 - ny) * 7) * 0.55);
    const patchy = fbm3(x * 0.45, 0, wz * 0.45, 61, 3);                        // thin first snow: grass shows through
    if (patchy > 0.58) c.lerp(grass, sat((patchy - 0.58) * 6) * 0.75);
    const d = Math.abs(wz - pathZ(x)) / (0.55 + fbm3(x * 0.9, 0, 1, 71, 2) * 0.3);  // trodden band, ragged edges
    if (d < 1) c.lerp(path, (1 - d * d) * 0.8 * (0.75 + fbm3(x * 3, 0, wz * 3, 73, 2) * 0.5));
  });
  geo.translate(0, 0, -8);
  root.add(new THREE.Mesh(geo, kit.mat('ground', { color: 0xffffff, roughness: 0.95, vertexColors: true })));

  // ---- trees: far wall, middle stand, near trees; birches between
  const far = [], mid = [], near = [];
  for (let x = -28; x < 28; x += 0.7 + r() * 0.8) for (let row = 0; row < 3; row++) {
    if (r() < 0.18) continue;                                       // gaps: never a regular wall
    const z = -9 - row * 3.4 - r() * 3.2;
    far.push({ x: x + (r() - 0.5) * 0.9, z, s: 0.6 + r() * 0.8, kind: r() < 0.6 ? 'tall' : 'young', y: groundH(x, z) });
  }
  for (let x = -26; x < 26; x += 3.5 + r() * 3) { const z = -5.5 - r() * 2.5; mid.push({ x, z, s: 0.6 + r() * 0.4, kind: 'tall', y: groundH(x, z) }); }
  for (let x = -24; x < 24; x += 3 + r() * 4) { const z = -2.6 - r() * 0.6; near.push({ x, z, s: 0.18 + r() * 0.16, kind: 'young', y: groundH(x, z) }); }
  const stands = [spruceStand(far, { low, snow: 1, variant: 2, tint: 0xe4e8ec }), spruceStand(mid, { low, snow: 1, variant: 1, tint: 0xf0f0f0 }), spruceStand(near, { low, snow: 1, variant: 0, bark: 'mossy' })];
  root.add(...stands);
  for (let i = 0; i < 7; i++) {
    const x = -20 + r() * 40, z = -5 - r() * 3;
    const t = bareTree(100 + i, { low, height: 4.6 + r(), kind: i % 2 ? 'aspen' : 'birch', leaves: 0.15 });
    t.position.set(x, groundH(x, z), z); root.add(t);
  }

  // ---- rocks with snow caps along the path
  const rockM = rockMaterial(low);
  const rocks = [];
  for (let i = 0; i < 14; i++) {
    const g = rockGeometry(300 + i, { detail: 3, rough: 0.5, sharp: 0.6, strata: 0.5, flat: -0.3, snow: 0.7, colA: 0x5e5a56, colB: 0x3e3a36 });
    const m = new THREE.Mesh(g, rockM);
    const x = -18 + r() * 36, z = -2.2 - r() * 1.8, sc = 0.2 + r() * 0.5;
    m.scale.set(sc, sc * (0.6 + r() * 0.4), sc); m.rotation.y = r() * 6;
    m.position.set(x, groundH(x, z) - sc * 0.3, z);   // sink a third into the ground, never float
    root.add(m); rocks.push(g);
  }

  // ---- foreground: snowbanks at the sides, stumps, fallen branches, dry grass through the snow
  const driftM = kit.mat('drift', { color: 0xffffff, roughness: 1, vertexColors: true });
  for (const [x, z, sx, sz] of [[-6.5, 1.4, 1.6, 0.9], [-3.8, 2.4, 1.1, 0.6], [5.6, 1.8, 1.9, 1.0], [2.2, 3.0, 0.9, 0.5], [-9, 0.6, 1.4, 0.8], [9, 0.4, 1.5, 0.8]]) {
    const m = new THREE.Mesh(rockGeometry(500 + Math.round(x * 3), { detail: 3, rough: 0.25, flat: -0.45, colA: 0xf2f4f6, colB: 0xd8e2ec, dark: 0.15, snow: 0 }), driftM);
    m.scale.set(sx, 0.35, sz); m.position.set(x, groundH(x, z) - 0.08, z); root.add(m);
  }
  const bark = kit.mat('bark', { map: barkTexture('mossy'), color: 0xd8d0c8, roughness: 1 });
  const snowCap = kit.M('snowCap', 0xf2f4f6, { roughness: 1 });
  for (const [x, z, rad] of [[-4.6, 0.9, 0.22], [3.6, 1.3, 0.17], [-1.6, -3.4, 0.2]]) {
    kit.lathe([[rad * 1.6, 0], [rad * 1.15, 0.06], [rad, 0.16], [rad, 0.34], [rad * 0.96, 0.36]], bark, x, groundH(x, z) - 0.04, z, { seg: 18 });
    kit.cush(rad * 1.9, 0.05, rad * 1.9, 0.024, snowCap, x, groundH(x, z) + 0.33, z, { puff: 0.5, seed: Math.round(x * 7) });
  }
  for (let i = 0; i < 7; i++) {                                         // fallen branches: bent tubes, not cylinders
    const x = -10 + r() * 20, z = 0.3 + r() * 1.6, a = r() * 6, L = 0.8 + r() * 0.9, y = groundH(x, z) + 0.02;
    kit.tube([[x, y, z], [x + Math.cos(a) * L * 0.5, y + 0.05, z + Math.sin(a) * L * 0.3], [x + Math.cos(a) * L, y + 0.01, z + Math.sin(a) * L * 0.5]], 0.018 + r() * 0.015, bark, { rs: 6 });
  }
  const tuftGeo = new THREE.PlaneGeometry(0.22, 0.26, 1, 1); tuftGeo.translate(0, 0.12, 0);
  const tuftTex = canvasTexture('fk-tuft', 16, 16, (ctx, w, h) => {
    for (let i = 0; i < 9; i++) { ctx.strokeStyle = ['#a89068', '#8a7650', '#c0a878'][i % 3]; ctx.beginPath(); ctx.moveTo(8 + (i - 4) * 0.6, h); ctx.lineTo(1 + i * 1.7, 1 + (i % 3) * 2); ctx.stroke(); }
  }, { nearest: true });
  const tuftM = kit.mat('tuft', { map: tuftTex, color: 0xffffff, transparent: true, alphaTest: 0.4, side: THREE.DoubleSide, roughness: 1 });
  const nT = low ? 260 : 520, tufts = new THREE.InstancedMesh(tuftGeo, tuftM, nT), mt = new THREE.Matrix4(), e = new THREE.Euler(), qq = new THREE.Quaternion();
  for (let i = 0; i < nT; i++) {
    let x, z; do { x = -24 + r() * 48; z = -6 + r() * 9; } while (fbm3(x * 0.45, 0, z * 0.45, 61, 3) < 0.5 && r() < 0.8);   // mostly where the grass shows
    const sc = 0.7 + r() * 0.9;
    mt.compose(new THREE.Vector3(x, groundH(x, z) - 0.02, z), qq.setFromEuler(e.set(0, r() * Math.PI, 0)), new THREE.Vector3(sc, sc, sc));
    tufts.setMatrixAt(i, mt);
  }
  root.add(tufts);

  // ---- mist banks between the layers, sun shafts
  const mists = [];
  for (let i = 0; i < 6; i++) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(18 + r() * 14, 3 + r() * 2), new THREE.MeshBasicMaterial({ map: mistTexture(1 + (i % 3)), color: 0xe4e8ee, transparent: true, opacity: 0.32, depthWrite: false, fog: false }));
    m.position.set(-20 + i * 8, 0.8 + r() * 0.8, -7 - (i % 3) * 3); root.add(m); mists.push(m);
  }
  const shaftM = new THREE.MeshBasicMaterial({ map: shaftTexture(), color: 0xfff0d0, transparent: true, opacity: 0.14, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
  for (let i = 0; i < 5; i++) { const s = new THREE.Mesh(new THREE.PlaneGeometry(0.9 + r() * 1.2, 11), shaftM); s.position.set(1 + i * 1.8, 4.2, -7 - r() * 3); s.rotation.z = -0.3; root.add(s); }   // falling from the sun through one gap
  const sunGlow = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(), color: 0xffe0b0, transparent: true, opacity: 0.6, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  sunGlow.scale.set(10, 10, 1); sunGlow.position.set(7, 8.5, -24); root.add(sunGlow);
  kit.windowLights.push({ ...FLARE_SUN, position: sunGlow.position.clone(), dir: new THREE.Vector3(0, 0, 1), always: true, enabled: () => kit.state !== 'night' });

  // ---- per state: fog colour/density, mist, shafts, the sun; snow can be switched off for autumn
  root.fog = null;
  kit.onState((st) => {
    const fogC = { day: 0xc8d2da, evening: 0x7a7090, night: 0x0c1220 }[st];
    kit.fog = new THREE.Fog(fogC, 5, st === 'night' ? 22 : 30);
    shaftM.opacity = st === 'day' ? 0.14 : st === 'evening' ? 0.08 : 0;
    sunGlow.visible = st !== 'night';
    sunGlow.material.color.set(st === 'evening' ? 0xffa070 : 0xffe0b0);
    for (const m of mists) m.material.color.set(st === 'night' ? 0x3a4660 : 0xe4e8ee);
  });
  kit.setSnow = (on) => { for (const s of stands) setStandSnow(s, on ? 1 : 0); for (const g of rocks) setRockSnow(g, on); };
  kit.groundAt = groundH;   // characters / props stand on the relief: y = kit.groundAt(x, z)
  kit.flushBatches();
  kit.camera = { pos: [0, 1.5, 7.2], look: [0, 1.6, -3] };
  return kit;
}

const FLARE_SUN = { id: 'LOWSUN', style: 'anamorphic', intensity: 0.6, flareSize: 0.9, ghostIntensity: 0.6, colorTint: [1.0, 0.8, 0.5], maxScreenOpacity: 0.6, exposure: 0.06, bloom: 0.12, triggerDistance: 3, fadeDistance: 2, starburstIntensity: 0, ringIntensity: 0, ghostCount: 6, ghostSpacing: 0.4, ghostTints: [[1, 0.8, 0.5]] };
