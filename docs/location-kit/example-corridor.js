import * as THREE from 'three';
import { LocationKit, TEX, TX, rng, rgb } from './location-kit.js';

/**
 * Example 2 — an institutional corridor (school / hospital / station), side-on: bright windows
 * that let daylight fall onto the floor (shafts, patches, lens flare when you walk past),
 * fluorescent panels, a tiled wainscot with a rail, pilasters, a partition with a doorway into a
 * room behind, benches, a notice board. Day is the main state; night keeps two panels on low.
 */
export function buildCorridor(root, { low = false } = {}) {
  const kit = new LocationKit(root, { low });
  const BACK = -3.2, H = 3.1, XL = -8, XR = 8;
  kit.setupLights();

  // ---- textures for this place (1 texel ≈ 1 cm): lino floor, ceiling tiles, wall tiles
  // 30 cm lino tiles, each a slightly different tint, flecks, scuffs, dark joints
  const lino = TX('lino', 60, 60, (ctx, w, h) => {
    const r = rng(5);
    for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) {
      const v = (r() - 0.5) * 16, warm = (i + j) % 2 ? 6 : -4;
      ctx.fillStyle = rgb(136 + v + warm, 144 + v, 140 + v - warm); ctx.fillRect(i * 30, j * 30, 30, 30);
      for (let k = 0; k < 120; k++) { const q = (r() - 0.5) * 34; ctx.fillStyle = rgb(136 + v + q, 144 + v + q, 140 + v + q, 0.6); ctx.fillRect(i * 30 + r() * 30, j * 30 + r() * 30, 1, 1); }
    }
    for (let k = 0; k < 5; k++) { ctx.fillStyle = 'rgba(40,40,40,0.18)'; ctx.fillRect(r() * w, r() * h, 4 + r() * 8, 1); }
    ctx.fillStyle = 'rgba(40,50,50,0.5)'; for (const t of [0, 30]) { ctx.fillRect(0, t, w, 1); ctx.fillRect(t, 0, 1, h); }
  });
  const tiles = TX('wallTiles', 32, 32, (ctx, w, h) => {
    const r = rng(9);
    ctx.fillStyle = '#b8c4bc'; ctx.fillRect(0, 0, w, h);
    for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) { ctx.fillStyle = rgb(110 + r() * 14, 140 + r() * 14, 128 + r() * 10); ctx.fillRect(i * 16 + 1, j * 16 + 1, 15, 15); }
  });
  const ceilT = TX('ceilTiles', 60, 60, (ctx, w, h) => {
    const r = rng(13);
    ctx.fillStyle = '#d4d6d0'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 300; i++) { ctx.fillStyle = `rgba(80,80,70,${r() * 0.25})`; ctx.fillRect(r() * w, r() * h, 1, 1); }
    ctx.fillStyle = '#9a9c96'; ctx.fillRect(0, 0, w, 1); ctx.fillRect(0, 0, 1, h);
  });

  // ---- shell
  kit.floorRect(XL, XR, BACK, 2.5, kit.texM('lino', lino, { roughness: 0.25, metalness: 0.05 }), { tile: 0.6 });
  const wallM = kit.texM('wallPaint', TEX.paint('corridor', [214, 216, 204]), { roughness: 0.9 });
  const windows = [[-5.6, -3.8], [-1.8, 0.0], [4.6, 6.4]];
  const door = { x0: 1.9, x1: 2.9, y0: 0, y1: 2.2 };
  kit.wall(XL, XR, H, BACK, wallM, [...windows.map(([x0, x1]) => ({ x0, x1, y0: 1.0, y1: 2.6 })), door]);
  kit.sideWall(XL, BACK, 2.5, H, wallM, 1);
  kit.sideWall(XR, BACK, 2.5, H, wallM, -1);
  kit.ceilingPoly([[XL, BACK], [XR, BACK], [XR, 2.5], [XL, 2.5]], H, kit.texM('ceil', ceilT, { roughness: 1 }), { tile: 0.6 });
  const spans = [[XL, door.x0], [door.x1, XR]];
  kit.wainscot(spans, BACK, 1.0, kit.texM('tiles', tiles, { roughness: 0.4 }), { railColor: 0x6a7a72 });
  kit.trims(spans, BACK, H, { crown: false, color: 0x5a625e });

  // ---- daylight windows (A warm old frames, B cold modern) — each builds its own light zone
  kit.brightWindow(-5.6, -3.8, 1.0, 2.6, BACK, { profile: 'A' });
  kit.brightWindow(-1.8, 0.0, 1.0, 2.6, BACK, { profile: 'C', blinds: true });
  kit.brightWindow(4.6, 6.4, 1.0, 2.6, BACK, { profile: 'B' });

  // ---- the doorway into a room behind: a lit classroom glimpsed through it
  kit.withT(2.4, BACK, 0, () => kit.panelDoor(1.0, 2.2, 0x8a6a48));
  kit.wall(door.x0 - 0.3, door.x1 + 0.3, H, BACK - 2.0, kit.M('roomBack', 0xc8c0a8, { roughness: 1 }));
  kit.floorRect(door.x0 - 0.3, door.x1 + 0.3, BACK - 2.0, BACK, kit.texM('lino', lino), { tile: 0.64 });
  kit.lamp('roomLight', { light: kit.pointLight(0xfff0d8, 1.6, 4, 2.4, 2.4, BACK - 1.0), on: { evening: 1, night: 0, day: 1 } });

  // ---- pilasters between the windows, fluorescent panels, benches, notice board
  for (const x of [-6.8, -2.9, 1.2, 7.2]) kit.column(x, BACK + 0.15, H, kit.M('pilaster', 0xc8ccc2, { roughness: 0.8 }));
  [-4.7, -0.9, 5.5].forEach((x, i) => kit.fluorescent(`fluo${i}`, x, H - 0.04, -1.2, { on: { evening: 1, night: i === 1 ? 0.35 : 0, day: 0.6 } }));
  const benchM = kit.texM('benchOak', TEX.oak(1), { roughness: 0.5 });
  const steel = kit.M('steel', 0x9aa0a6, { metalness: 0.8, roughness: 0.35 });
  for (const bx of [-4.7, 5.5]) kit.withT(bx, BACK + 0.15, 0, () => {
    kit.rb(1.6, 0.05, 0.4, 0.015, benchM, 0, 0.45, 0.25);
    kit.rb(1.6, 0.3, 0.04, 0.015, benchM, 0, 0.75, 0.05, { rx: -0.1 });
    for (const s of [-1, 1]) { kit.rb(0.04, 0.45, 0.36, 0.01, steel, s * 0.7, 0.225, 0.25); kit.rb(0.04, 0.4, 0.04, 0.01, steel, s * 0.7, 0.68, 0.06); }
  });
  const cork = TX('cork', 90, 60, (ctx, w, h) => {
    const r = rng(17);
    ctx.fillStyle = '#a8804e'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 400; i++) { ctx.fillStyle = `rgba(${r() < 0.5 ? '70,44,20' : '210,170,110'},0.4)`; ctx.fillRect(r() * w, r() * h, 1, 1); }
    const cols = ['#eeece6', '#f0e0a0', '#d0e0f0', '#f0c8c8'];
    for (let i = 0; i < 14; i++) { const x = 2 + (i % 5) * 17 + r() * 4, y = 3 + Math.floor(i / 5) * 19 + r() * 3; ctx.fillStyle = cols[i % 4]; ctx.fillRect(x, y, 14, 18); ctx.fillStyle = 'rgba(40,40,50,0.5)'; for (let k = 4; k < 16; k += 2) ctx.fillRect(x + 2, y + k, 6 + r() * 6, 1); ctx.fillStyle = '#c82020'; ctx.fillRect(x + 6, y + 1, 2, 2); }
  });
  kit.framed(cork, 0.9, 0.6, 3.75, 1.75, BACK, 0x6a4a2a, 0);
  // the things every such corridor has: radiators under the windows, an extinguisher, the exit sign
  for (const [x0, x1] of windows) kit.radiator((x0 + x1) / 2, 0.15, BACK, (x1 - x0) * 0.8, { h: 0.5 });
  kit.extinguisher(-7.4, 0.35, BACK);
  kit.exitSign('exit', 2.4, 2.45, BACK);
  // a clock between the windows
  kit.cy(0.16, 0.16, 0.04, kit.M('clockRim', 0x2a2a2c, { roughness: 0.4 }), -6.2, 2.75, BACK + 0.02, { rx: Math.PI / 2, seg: 28 });
  kit.cy(0.14, 0.14, 0.01, kit.M('clockFace', 0xf0eee6, { roughness: 0.6 }), -6.2, 2.75, BACK + 0.045, { rx: Math.PI / 2, seg: 28 });
  kit.rb(0.012, 0.09, 0.006, 0.002, kit.M('clockHand', 0x141414), -6.222, 2.79, BACK + 0.054, { rz: 0.5 });
  kit.rb(0.012, 0.12, 0.006, 0.002, kit.M('clockHand', 0x141414), -6.143, 2.731, BACK + 0.058, { rz: -1.9 });

  // ---- ambient per state: day is bright, the evening corridor is lit only by the panels
  kit.ambient = { ...kit.ambient, day: { sky: 0xe4e8ea, ground: 0x8a8a80, hemi: 1.1, fill: 0xf0f2f4, fillI: 0.6, bg: 0x8a9096 } };
  kit.flushBatches();
  kit.camera = { pos: [0, 1.5, 6.6], look: [0, 1.55, -1.6] };
  return kit;
}
