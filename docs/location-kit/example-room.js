import * as THREE from 'three';
import { LocationKit, TEX } from './location-kit.js';

/**
 * Example 1 — a flat, side-on: living room on the left, a door and stairs up in the middle, a
 * sleeping nook on the right. Shell (floor, back wall with a window and a door, side walls,
 * ceiling, mouldings), the window with blinds and the town behind it, furniture, lamps, states.
 *
 *   x −5 … −0.6  living: sofa under the window, rug + coffee table, torchiere, TV corner, bookcase
 *   x −0.4 … 0.6 front door
 *   x  0.8 … 3.2 stairs up along the back wall, photos and fairy lights on the rail
 *   x  3.4 … 6   bed, nightstand lamp, desk + chair
 */
export function buildRoom(root, { low = false } = {}) {
  const kit = new LocationKit(root, { low });
  const BACK = -2.8, H = 2.8, XL = -5.2, XR = 6.2;
  kit.setupLights();

  // ---- shell
  kit.floorRect(XL, XR, BACK, 2.5, kit.texM('planks', TEX.planks(0), { roughness: 0.6 }));
  const wallM = kit.texM('wallLiving', TEX.paint('living', [224, 212, 190]), { roughness: 0.95 });
  const holes = [{ x0: -3.4, x1: -1.8, y0: 0.9, y1: 2.3 }, { x0: -0.35, x1: 0.55, y0: 0, y1: 2.1 }];
  kit.wall(XL, XR, H, BACK, wallM, holes);
  kit.sideWall(XL, BACK, 2.5, H, wallM, 1);
  kit.sideWall(XR, BACK, 2.5, H, wallM, -1);
  kit.ceilingPoly([[XL, BACK], [XR, BACK], [XR, 2.5], [XL, 2.5]], H, kit.M('ceil', 0xe8e2d6, { roughness: 1, emissive: 0x16120c }));
  kit.trims([[XL, -0.35], [0.55, 0.8], [3.2, XR]], BACK, H, { crown: false });
  kit.trims([[XL, XR]], BACK, H, { skirt: false });

  // ---- window with slatted blinds + the view; door
  kit.withT(-2.6, BACK, 0, () => kit.windowUnit(1.6, 0.9, 2.3, { kind: 'double', muntins: [3, 2], blind: { kind: 'slats', cover: 0.3 } }));
  kit.viewPlane(6, 4, -2.6, 1.6, BACK - 2.4, { variant: 'low' });
  kit.withT(0.1, BACK, 0, () => kit.panelDoor(0.9, 2.1, 0x3a5a6a, { glassTop: true }));
  kit.rug(0.1, BACK + 0.45, 0.9, 0.5, { tex: TEX.coir(), tile: 0.9 });

  // ---- living
  kit.sofa(-2.6, BACK + 0.05, 0, { w: 2.2, seed: 1 });
  kit.rug(-2.6, -1.1, 3.0, 1.9);
  const top = kit.coffeeTable(-2.6, -0.9);
  kit.withT(-2.6, -0.9, 0, () => {
    kit.rb(0.36, 0.03, 0.26, 0.01, kit.M('tray', 0x2a1e18, { roughness: 0.4 }), -0.2, top + 0.015, -0.05);
    kit.candle('tableCandle', -0.26, top + 0.03, -0.07);
    kit.candle('tableCandle2', -0.12, top + 0.03, -0.01, { h: 0.12, r: 0.03 });
    kit.mug(0.3, top, 0.1, 0x3a5a6a, 0.6);
    kit.bookStack(0.25, top, -0.13, 2, 33);
  });
  kit.torchiere('torchiere', -4.8, BACK + 0.3);
  kit.tvUnit(-4.5, -1.3, Math.PI / 2 - 0.25);
  kit.bookcase(-1.05, BACK, 0);
  kit.plant(-4.2, 0, BACK + 0.35, 0.9, 'palm');
  kit.framed(TEX.art(0), 0.7, 0.45, -4.3, 1.75, BACK, 0x2a2420, 0.05);
  kit.pendant('livingPendant', -2.6, H, -1.0, { drop: 0.75, intensity: 2.2 });

  // ---- stairs up along the back wall
  const railY = kit.stairs(0.85, BACK, { n: 12, run: 0.2, H, sideMat: wallM });
  const pts = [];
  for (let i = 0; i <= 12; i++) { const x = 0.95 + i * 0.2; pts.push([x, railY(x) - 0.04 - (i % 2 ? 0.06 : 0), BACK + 0.87]); }
  kit.fairyLights('stairLights', pts, 34);
  kit.framed(TEX.art(2), 0.36, 0.28, 1.5, 1.75, BACK, 0x2a2018, 0.03);
  kit.framed(TEX.art(1), 0.24, 0.3, 2.1, 2.2, BACK, 0xe8e4dc, 0.02);
  // the stairwell opening above is dark; the lit attic glows down it in the evening
  kit.lamp('atticGlow', { glows: [kit.halo(0xffb878, 1.6, 0.3, 2.8, H - 0.1, BACK + 0.5)], on: { evening: 1, night: 0, day: 0 } });

  // ---- sleeping nook
  kit.bed(4.8, -1.6, 0, { L: 2.1, W: 1.5 });
  const ns = kit.nightstand(3.55, BACK + 0.1, 0);
  kit.tableLamp('bedLamp', 3.55, ns, BACK + 0.3, { on: { evening: 1, night: 1, day: 0 } });
  kit.bookStack(3.67, ns, BACK + 0.38, 2, 71);
  kit.framed(TEX.art(1), 0.6, 0.4, 4.8, 1.7, BACK, 0x1a1410, 0.03);

  // ---- general light per state
  kit.lamp('livingFill', { light: kit.pointLight(0xffb878, 1.3, 9, -2.4, 2.3, 0.2, 1.2), on: { evening: 1, night: 0, day: 0 } });
  kit.lamp('dayFill', { light: kit.pointLight(0xdfe6ee, 2.2, 10, -2.6, 2.0, -1.4, 1.0), on: { evening: 0, night: 0, day: 1 } });
  kit.lamp('moon', { light: kit.pointLight(0x7890c8, 1.6, 7, -2.6, 1.9, -2.2, 1.2), on: { evening: 0, night: 1, day: 0 } });
  for (const [st, c, op] of [['night', 0x5a74b8, 0.3], ['day', 0xc8d4e0, 0.16]]) kit.statePool(c, -2.3, 0.02, -1.2, 2.2, 1.6, op, [st]);
  kit.statePool(0xffb070, -2.8, 0.02, -1.0, 2.4, 1.6, 0.16, ['evening']);

  kit.flushBatches();
  kit.camera = { pos: [0.4, 1.45, 6.0], look: [0.4, 1.45, -1.4] };
  return kit;
}
