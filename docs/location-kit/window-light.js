import * as THREE from 'three';

/**
 * Window light: the "walking past a bright window" response (from "Blood of the North").
 *
 * Usage:
 *   const look = new LookLayers(gl, { bloomPass });          // or your own { setLayer, clearLayer }
 *   const wl = new WindowLight({ renderer: look, canvas: gl.domElement, low });
 *   // per frame, after the camera moved:
 *   wl.update(dt, { world: kit, player, camera });           // kit.windowLights = the zones
 *   look.apply();                                            // pushes exposure / bloom offsets
 * The canvas' parent must be position: relative (the flare overlay is absolutely positioned over it).
 * `player` = anything with .position (Vector3) and optionally .root.visible — the flare dims over it.
 *
 * Every scene may publish `world.windowLights`: a list of WindowLightZone +
 * WindowLensFlareSource descriptions (WINDOW_PROFILES / FLARE_PROFILES in location-kit.js):
 *   position, dir, triggerDistance, fadeDistance, exposure, bloom, color,
 *   flareSize, starburstIntensity, ghostIntensity, ghostCount, ghostSpacing,
 *   ringIntensity, colorTint, ghostTints, streaks, maxScreenOpacity, enabled().
 *
 * 1. Exposure / bloom: a smooth weight from the player's distance to the window
 *    (never a flash — it eases in and out over ~1 s) is pushed into the
 *    renderer as an additive post layer.
 * 2. Lens flare: a 2D overlay canvas (screen blend) above the 3D view. The
 *    starburst sits on the window's screen position; ghosts, a ring and (for
 *    blinds) streaks lie on the line from the source through the screen
 *    centre, so they slide as the camera follows the player. Each new pass past a
 *    window reseeds the ghost layout a little, so it never repeats exactly.
 *    Nothing is ever drawn full white, and whatever overlaps the player is dimmed —
 *    when he stands in front of the window he shadows the flare itself.
 *
 * Flare styles (`z.style`), so not every light flares the same way:
 *   'zoom'       (default) the hospital zoom lens: starburst, hexes, sparkle, rainbow arcs.
 *   'star'       a point source (lamp, sun through mist, moon): a hot core with a few long spikes,
 *                then along the axis small orange discs, a green disc and one big thin hollow ring.
 *   'anamorphic' a low sun / headlights: a fan of rays, one long horizontal streak across the frame,
 *                octagonal amber ghosts, a dotted red arc and small rainbow slivers.
 * `always: true` lights it regardless of distance (sun, moon); `enabled()` still gates it.
 */
export class WindowLight {
  constructor({ renderer, settings = null, canvas, low = undefined }) {
    this.renderer = renderer;
    this.settings = settings;
    this.low = low ?? !!renderer.isLow;
    const c = this.canvas = document.createElement('canvas');
    c.className = 'flare-layer';
    Object.assign(c.style, { position: 'absolute', inset: '0', width: '100%', height: '100%', pointerEvents: 'none', mixBlendMode: 'screen', display: 'none' });
    canvas.insertAdjacentElement('afterend', c);
    this.ctx = c.getContext('2d');
    this.state = new WeakMap(); // zone → { w, seed, rot, ghosts }
    this.v = new THREE.Vector3();
    this.shown = false;
  }

  zoneState(z) {
    let s = this.state.get(z);
    if (!s) { s = { w: 0, pass: false }; this.state.set(z, s); this.reseed(z, s); }
    return s;
  }

  /**
   * A new pass past the window: lay the ghost chain out again with a little
   * jitter (positions on the axis, sizes, which hexes show, ray rotation), so
   * it never repeats exactly. Layout after a real anamorphic-free zoom lens:
   * big faint hexes near the source, a chromatic spot, small hexes and dots
   * along the axis, and past the centre a sparkle, a blue spot and a rainbow arc.
   */
  reseed(z, s) {
    const R = Math.random, j = (v, k = 0.12) => v * (1 + (R() - 0.5) * 2 * k);
    if (z.style === 'star') {
      s.rot = R() * Math.PI; s.spin = (R() - 0.5) * 0.3;
      s.ghosts = [
        { type: 'disc', t: j(0.32), r: j(0.03), tint: [1.0, 0.55, 0.35], a: 0.55 },
        { type: 'disc', t: j(0.5), r: j(0.07), tint: [1.0, 0.62, 0.3], a: 0.45 },
        { type: 'dot', t: j(0.58), r: 0.006, tint: [0.6, 1.0, 0.7], a: 0.8 },
        { type: 'disc', t: j(0.66), off: 0.01, r: j(0.045), tint: [0.55, 0.9, 1.0], a: 0.3 },
        { type: 'disc', t: j(0.82), r: j(0.12), tint: [0.45, 0.85, 0.35], a: 0.4 },
        { type: 'hollow', t: j(1.02, 0.05), r: j(0.2, 0.06), tint: [0.95, 0.85, 0.55], a: 0.55 },
        { type: 'dot', t: j(1.2), r: 0.004, tint: [1, 0.9, 0.7], a: 0.6 },
      ].slice(0, this.low ? 5 : 7);
      return;
    }
    if (z.style === 'anamorphic') {
      s.rot = R() * Math.PI; s.spin = (R() - 0.5) * 0.2;
      s.ghosts = [
        { type: 'oct', t: j(0.42), r: j(0.03), tint: [1.0, 0.7, 0.25], a: 0.7 },
        { type: 'oct', t: j(0.55), r: j(0.05), tint: [1.0, 0.45, 0.2], a: 0.45 },
        { type: 'oct', t: j(0.68), r: j(0.032), tint: [1.0, 0.72, 0.3], a: 0.65 },
        { type: 'oct', t: j(0.8), r: j(0.03), tint: [1.0, 0.68, 0.3], a: 0.6 },
        { type: 'oct', t: j(0.93), r: j(0.035), tint: [1.0, 0.7, 0.32], a: 0.55 },
        { type: 'redarc', t: j(0.75, 0.05), r: j(0.62, 0.05), a: 0.5 },
        ...Array.from({ length: this.low ? 3 : 6 }, () => ({ type: 'sliver', t: 0.2 + R() * 1.2, off: (R() - 0.5) * 0.5, r: 0.03 + R() * 0.04, ang: R() * Math.PI, a: 0.35 + R() * 0.3 })),
      ];
      return;
    }
    const T = z.ghostTints;
    const tint = (i) => T[i % T.length];
    s.rot = R() * Math.PI;
    s.spin = (R() - 0.5) * 0.6;
    const all = [
      { type: 'hex', t: j(0.5), r: j(0.15), tint: [0.85, 0.55, 0.32], a: 0.34 },
      { type: 'sparkle', t: j(2.0, 0.05), r: j(0.075), tint: [0.55, 1.0, 0.55], a: 0.9 },
      { type: 'ring', t: 0, r: j(0.22, 0.08), a: 1 },
      { type: 'glow', t: j(2.12, 0.06), r: j(0.2), tint: [0.3, 0.9, 0.45], a: 0.3 },
      { type: 'hex', t: j(0.6), r: j(0.1), tint: [0.6, 0.66, 0.32], a: 0.4 },
      { type: 'chroma', t: j(0.6), off: -j(0.2), r: j(0.045), a: 0.45 },
      { type: 'spot', t: j(1.85, 0.06), off: -0.03, r: j(0.03), tint: [0.45, 0.4, 1.0], a: 0.7 },
      { type: 'hex', t: j(0.4), r: j(0.07), tint: tint(1), a: 0.36 },
      { type: 'gstreak', t: 0, r: j(0.14), tint: [0.7, 1.0, 0.4], a: 0.2 },
      { type: 'hex', t: j(0.66), r: j(0.2), tint: [0.75, 0.5, 0.36], a: 0.16 },
      { type: 'hex', t: j(1.3), r: j(0.022), tint: tint(0), a: 0.45 },
      { type: 'hex', t: j(1.6), r: j(0.024), tint: tint(2), a: 0.4 },
      ...[0.9, 1.05, 1.2, 1.42, 1.7].map((t, i) => ({ type: 'dot', t: j(t, 0.04), r: 0.004 + (i % 2) * 0.002, tint: [1, 0.78 - i * 0.04, 0.45], a: 0.55 })),
      { type: 'sparkle', t: j(2.45, 0.05), off: 0.06, r: j(0.05), tint: [0.6, 1.0, 0.5], a: 0.5 },
    ];
    // fewer elements for the soft profiles / low quality: keep the strongest ones
    const n = Math.max(4, Math.round(all.length * Math.min(1, z.ghostCount / 8) * (this.low ? 0.75 : 1)));
    // priority: what makes it read as a lens flare goes first
    const order = all.map((_, i) => i); // listed in priority order
    const pick = new Set(order.slice(0, n));
    s.ghosts = all.filter((g, i) => pick.has(i));
  }

  /** Pre-rendered flare elements (built once per colour, drawn scaled each frame). */
  sprite(key, size, draw) {
    this.sprites ??= new Map();
    let c = this.sprites.get(key);
    if (!c) {
      c = document.createElement('canvas');
      c.width = c.height = size;
      const g = c.getContext('2d');
      g.globalCompositeOperation = 'lighter';
      draw(g, size);
      this.sprites.set(key, c);
    }
    return c;
  }

  /** active = false hides everything (menus, cutscenes); keyScene = true calms it down (dialogue). */
  update(dt, { world, player: pl, julian, camera, keyScene = false, active = true }) {
    const player = pl ?? julian;
    const zones = (active && world?.windowLights) || [];
    let exposure = 0, bloom = 0;
    const tint = [0, 0, 0];
    const draws = [];
    const k = 1 - Math.exp(-dt * 1.4); // ~1 s ease
    for (const z of zones) {
      const s = this.zoneState(z);
      let target = 0;
      if (z.always && (!z.enabled || z.enabled())) target = 1;
      else if (player && (!z.enabled || z.enabled())) {
        const dx = player.position.x - z.position.x, dz = player.position.z - (z.position.z + z.dir.z * 2.0);
        const d = z.dir.x ? Math.abs(dx) * 0.7 + Math.abs(player.position.z - z.position.z) * 0.15 : Math.hypot(dx, dz * 0.35);
        target = 1 - smooth(z.triggerDistance, z.triggerDistance + z.fadeDistance, d);
      }
      if (s.w < 0.02 && target > 0.02 && !s.pass) { this.reseed(z, s); s.pass = true; }
      if (s.w < 0.01 && target < 0.01) s.pass = false;
      s.w += (target - s.w) * k;
      if (s.w < 0.004) continue;
      exposure += s.w * z.exposure;
      bloom += s.w * z.bloom;
      const ct = z.colorTint;
      for (let i = 0; i < 3; i++) tint[i] += s.w * (ct[i] - 0.9) * 0.08;
      draws.push([z, s]);
    }
    const fx = this.settings?.get?.('effects') ?? 1;
    const calm = keyScene ? 0.35 : 1;
    if (exposure > 0.001) this.renderer.setLayer('windowLight', { exposure: Math.min(0.42, exposure) * (0.6 + 0.4 * calm), bloom: Math.min(0.8, bloom) * calm, tint });
    else this.renderer.clearLayer('windowLight');
    this.draw(draws, camera, player, fx * calm);
  }

  draw(draws, camera, player, gain) {
    const c = this.canvas;
    if (!draws.length || gain <= 0.01 || !camera) {
      if (this.shown) { this.ctx.clearRect(0, 0, c.width, c.height); c.style.display = 'none'; this.shown = false; }
      return;
    }
    const sc = this.low ? 0.5 : 0.75;
    const W = Math.max(2, Math.round((c.clientWidth || innerWidth) * sc)), Hh = Math.max(2, Math.round((c.clientHeight || innerHeight) * sc));
    if (c.width !== W || c.height !== Hh) { c.width = W; c.height = Hh; }
    if (!this.shown) { c.style.display = 'block'; this.shown = true; }
    const g = this.ctx;
    g.clearRect(0, 0, W, Hh);
    g.globalCompositeOperation = 'lighter';
    const toScreen = (p) => {
      this.v.copy(p).project(camera);
      return { x: (this.v.x * 0.5 + 0.5) * W, y: (-this.v.y * 0.5 + 0.5) * Hh, z: this.v.z, nx: this.v.x, ny: this.v.y };
    };
    // the player's screen box (flare elements over him are dimmed)
    let jb = null;
    if (player?.root?.visible !== false && player?.position) {
      const a = toScreen(new THREE.Vector3(player.position.x, 0, player.position.z));
      const b = toScreen(new THREE.Vector3(player.position.x, 1.85, player.position.z));
      const hw = Math.abs(a.y - b.y) * 0.24;
      jb = { x0: a.x - hw, x1: a.x + hw, y0: b.y, y1: a.y };
    }
    const overJ = (x, y, r) => jb && x + r > jb.x0 && x - r < jb.x1 && y + r > jb.y0 && y - r < jb.y1;
    // ghosts thin out near the player (within ~80 px of his box) and nearly vanish over him
    const margin = 80 * sc;
    const nearJ = (x, y, r) => {
      if (!jb) return 1;
      const dx = Math.max(jb.x0 - x, 0, x - jb.x1), dy = Math.max(jb.y0 - y, 0, y - jb.y1);
      const d = Math.hypot(dx, dy) - r * 0.5;
      return 0.2 + 0.8 * smooth(0, margin, d);
    };
    const camPos = camera.position;
    // one lens, one dominant flare: the strongest window gets the full chain,
    // the others only a softer core (stacked flares wash the frame to white)
    const top = draws.reduce((m, d) => (d[1].w * d[0].intensity > m[1].w * m[0].intensity ? d : m), draws[0]);
    for (const [z, s] of draws) {
      const minor = s !== top[1];
      const S = toScreen(z.position);
      if (S.z > 1 || S.z < -1) continue;
      const facing = z.dir.x * (camPos.x - z.position.x) + z.dir.z * (camPos.z - z.position.z);
      if (facing <= 0) continue;
      const edge = 1 - smooth(0.85, 1.05, Math.max(Math.abs(S.nx), Math.abs(S.ny))); // the window must be in the frame
      // the player standing in front of the window shadows the source
      const occl = overJ(S.x, S.y, 0) ? 0.3 : 1;
      const A = Math.min(z.maxScreenOpacity, s.w * z.intensity * edge * occl * gain) * (minor ? 0.45 : 1);
      if (A < 0.01) continue;
      const U = Hh; // unit: screen height
      const put = (img, x, y, r, a, rot = 0) => {
        if (a < 0.004) return;
        g.globalAlpha = Math.min(1, a);
        if (rot) { g.save(); g.translate(x, y); g.rotate(rot); g.drawImage(img, -r, -r, r * 2, r * 2); g.restore(); }
        else g.drawImage(img, x - r, y - r, r * 2, r * 2);
      };
      // --- source: halo + core + starburst
      const ct = z.colorTint;
      if (z.style === 'star' || z.style === 'anamorphic') { this.drawStyled(z, s, S, A, U, W, Hh, put, nearJ, minor); continue; }
      put(this.halo(ct), S.x, S.y, U * 0.26 * z.flareSize, A * 0.5);
      if (z.starburstIntensity > 0) put(this.burst(z.id, ct), S.x, S.y, U * 0.4 * z.flareSize, A * Math.min(1, 0.6 * z.starburstIntensity), s.rot + S.nx * s.spin);
      put(this.core(ct), S.x, S.y, U * 0.1 * z.flareSize, A * 0.8);
      if (minor) continue;
      // --- streaks through blinds: thin horizontal lines
      if (z.streaks) for (let i = -2; i <= 2; i++) {
        const lw = U * (0.55 - Math.abs(i) * 0.09) * z.flareSize;
        g.globalAlpha = Math.min(1, A * 0.5 * (1 - Math.abs(i) * 0.25));
        g.drawImage(this.streak(ct), S.x - lw, S.y + i * U * 0.02 - U * 0.006, lw * 2, U * 0.012);
      }
      // --- the ghost chain along source → centre (and past it)
      const vx = W / 2 - S.x, vy = Hh / 2 - S.y;
      const len = Math.hypot(vx, vy) || 1, px = -vy / len, py = vx / len;
      const gi = z.ghostIntensity * 1.1; // ghosts sit over a lit room, not over black
      const sp = s.ghosts.find((q) => q.type === 'sparkle');
      const spark = sp && { x: S.x + vx * sp.t + px * (sp.off || 0) * U, y: S.y + vy * sp.t + py * (sp.off || 0) * U };
      // faint veiling glare over the whole frame
      g.globalAlpha = 1; g.fillStyle = rgba(ct, 0.035 * A); g.fillRect(0, 0, W, Hh);
      for (const gh of s.ghosts) {
        const x = S.x + vx * gh.t + px * (gh.off || 0) * U, y = S.y + vy * gh.t + py * (gh.off || 0) * U;
        const r = U * gh.r * z.flareSize;
        const a = A * gi * gh.a * nearJ(x, y, r);
        switch (gh.type) {
          case 'hex': put(this.hex(gh.tint), x, y, r, a * 0.8, s.rot * 0.2); break;
          case 'dot': put(this.core(gh.tint), x, y, Math.max(1.5, r), a); break;
          case 'chroma': put(this.chroma(), x, y, r, a, Math.atan2(vy, vx)); break;
          case 'spot': put(this.halo(gh.tint), x, y, r, a); put(this.core(gh.tint), x, y, r * 0.35, a * 0.6); break;
          case 'sparkle': put(this.sparkle(gh.tint), x, y, r, a, s.rot * 0.5 + 0.4); break;
          case 'glow': put(this.halo(gh.tint), x, y, r, a); break;
          case 'ring': {
            // thin arcs wrapped round the far side of the green sparkle
            if (!(z.ringIntensity > 0) || !spark) break;
            const ux = vx / len, uy = vy / len;
            put(this.ring(), spark.x + ux * r * 0.35, spark.y + uy * r * 0.35, r, a * z.ringIntensity * 0.8, Math.atan2(vy, vx));
            break;
          }
          case 'gstreak': {
            // the long green streak off the source, up and to the side of the axis
            const ang = Math.atan2(vy, vx) - 1.25;
            put(this.gstreak(), S.x + Math.cos(ang) * r * 0.9, S.y + Math.sin(ang) * r * 0.9, r, a, ang);
            break;
          }
        }
      }
    }
    g.globalAlpha = 1;
    g.globalCompositeOperation = 'source-over';
  }

  /** The 'star' and 'anamorphic' flares (see the header). */
  drawStyled(z, s, S, A, U, W, Hh, put, nearJ, minor) {
    const g = this.ctx, ct = z.colorTint, F = z.flareSize;
    const vx = W / 2 - S.x, vy = Hh / 2 - S.y;
    const len = Math.hypot(vx, vy) || 1, px = -vy / len, py = vx / len;
    if (z.style === 'star') {
      put(this.halo(ct), S.x, S.y, U * 0.3 * F, A * 0.55);
      put(this.spikes(ct), S.x, S.y, U * 0.22 * F, A * 0.85, s.rot * 0.15 + S.nx * s.spin);
      put(this.core(ct), S.x, S.y, U * 0.06 * F, A);
    } else {
      put(this.halo(ct), S.x, S.y, U * 0.42 * F, A * 0.7);
      put(this.fan(ct), S.x, S.y, U * 0.5 * F, A * 0.75, s.rot * 0.1 + S.nx * s.spin);
      put(this.core(ct), S.x, S.y, U * 0.09 * F, A);
      // the long horizontal streak right through the source, and a fainter wide one
      const lw = W * 0.9 * F;
      g.globalAlpha = Math.min(1, A * 0.55); g.drawImage(this.hstreak(ct), S.x - lw, S.y - U * 0.012, lw * 2, U * 0.024);
      g.globalAlpha = Math.min(1, A * 0.22); g.drawImage(this.hstreak(ct), S.x - lw * 0.6, S.y - U * 0.05, lw * 1.2, U * 0.1);
    }
    if (minor) return;
    g.globalAlpha = 1; g.fillStyle = rgba(ct, 0.03 * A); g.fillRect(0, 0, W, Hh);   // veiling glare
    const gi = z.ghostIntensity;
    for (const gh of s.ghosts) {
      const x = S.x + vx * gh.t + px * (gh.off || 0) * U, y = S.y + vy * gh.t + py * (gh.off || 0) * U;
      const r = U * gh.r * F;
      const a = A * gi * gh.a * nearJ(x, y, r);
      switch (gh.type) {
        case 'disc': put(this.disc(gh.tint), x, y, r, a); break;
        case 'hollow': put(this.hollow(gh.tint), x, y, r, a); break;
        case 'dot': put(this.core(gh.tint), x, y, Math.max(1.5, r), a); break;
        case 'oct': put(this.oct(gh.tint), x, y, r, a, 0.2); break;
        case 'sliver': put(this.sliver(), x, y, r, a, gh.ang); break;
        case 'redarc': put(this.redarc(), S.x + vx * gh.t, S.y + vy * gh.t, r, a, Math.atan2(vy, vx)); break;
      }
    }
  }

  // ---------------------------------------------------------------- sprites

  /** A few long thin spikes (6 + 2 faint), a point-source star. */
  spikes(t) {
    return this.sprite(`spikes-${t}`, 256, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(1px)';
      for (let i = 0; i < 8; i++) {
        const ang = (i / 8) * Math.PI * 2 + 0.2, L = h * (i % 2 ? 0.45 : 0.98), w = i % 2 ? 1.2 : 2.2;
        const dx = Math.cos(ang), dy = Math.sin(ang);
        const lg = g.createLinearGradient(h, h, h + dx * L, h + dy * L);
        lg.addColorStop(0, rgba(t, 0.95)); lg.addColorStop(0.3, rgba(t, 0.35)); lg.addColorStop(1, rgba(t, 0));
        g.fillStyle = lg; g.beginPath(); g.moveTo(h - dy * w, h + dx * w); g.lineTo(h + dx * L, h + dy * L); g.lineTo(h + dy * w, h - dx * w); g.closePath(); g.fill();
      }
      g.filter = 'none';
    });
  }

  /** A dense fan of rays (low sun): many fine rays of uneven length, warm. */
  fan(t) {
    return this.sprite(`fan-${t}`, 512, (g, n) => {
      const h = n / 2;
      let seed = 4242;
      const R = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
      g.filter = 'blur(1.5px)';
      for (let i = 0; i < 140; i++) {
        const ang = R() * Math.PI * 2, L = h * (0.25 + R() * 0.75), w = 0.6 + R() * 1.8;
        const dx = Math.cos(ang), dy = Math.sin(ang);
        const lg = g.createLinearGradient(h, h, h + dx * L, h + dy * L);
        lg.addColorStop(0, rgba(t, 0.5)); lg.addColorStop(0.4, rgba(t, 0.14)); lg.addColorStop(1, rgba(t, 0));
        g.fillStyle = lg; g.beginPath(); g.moveTo(h - dy * w, h + dx * w); g.lineTo(h + dx * L, h + dy * L); g.lineTo(h + dy * w, h - dx * w); g.closePath(); g.fill();
      }
      g.filter = 'none';
    });
  }

  /** A filled ghost disc with a slightly brighter rim. */
  disc(t) {
    return this.sprite(`disc-${t}`, 128, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(2px)';
      const gr = g.createRadialGradient(h, h, 0, h, h, h * 0.86);
      gr.addColorStop(0, rgba(t, 0.25)); gr.addColorStop(0.8, rgba(t, 0.38)); gr.addColorStop(0.95, rgba(t, 0.6)); gr.addColorStop(1, rgba(t, 0));
      g.fillStyle = gr; g.beginPath(); g.arc(h, h, h * 0.88, 0, Math.PI * 2); g.fill();
      g.filter = 'none';
    });
  }

  /** A big thin hollow ring. */
  hollow(t) {
    return this.sprite(`hollow-${t}`, 512, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(2px)';
      g.strokeStyle = rgba(t, 0.55); g.lineWidth = 4; g.beginPath(); g.arc(h, h, h * 0.9, 0, Math.PI * 2); g.stroke();
      g.strokeStyle = rgba(t, 0.18); g.lineWidth = 12; g.beginPath(); g.arc(h, h, h * 0.86, 0, Math.PI * 2); g.stroke();
      g.filter = 'none';
    });
  }

  /** Octagonal aperture ghost (amber, soft edge, brighter rim). */
  oct(t) {
    return this.sprite(`oct-${t}`, 128, (g, n) => {
      const h = n / 2, r = h * 0.84;
      const path = () => { g.beginPath(); for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2 + Math.PI / 8; const x = h + Math.cos(a) * r, y = h + Math.sin(a) * r; if (i) g.lineTo(x, y); else g.moveTo(x, y); } g.closePath(); };
      g.filter = 'blur(2px)';
      const gr = g.createRadialGradient(h, h, 0, h, h, r);
      gr.addColorStop(0, rgba(t, 0.45)); gr.addColorStop(0.85, rgba(t, 0.55)); gr.addColorStop(1, rgba(t, 0.8));
      g.fillStyle = gr; path(); g.fill();
      g.filter = 'none';
    });
  }

  /** Long horizontal anamorphic streak: hot middle, tinted, fading to the ends. */
  hstreak(t) {
    return this.sprite(`hstreak-${t}`, 512, (g, n) => {
      const gr = g.createLinearGradient(0, 0, n, 0);
      gr.addColorStop(0, rgba(t, 0)); gr.addColorStop(0.35, rgba(t, 0.35)); gr.addColorStop(0.5, 'rgba(255,250,235,0.95)'); gr.addColorStop(0.65, rgba(t, 0.35)); gr.addColorStop(1, rgba(t, 0));
      g.fillStyle = gr;
      const vg = g.createLinearGradient(0, 0, 0, n);
      g.fillRect(0, n * 0.4, n, n * 0.2);
      g.globalCompositeOperation = 'destination-in';
      vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(0.5, 'rgba(0,0,0,1)'); vg.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = vg; g.fillRect(0, 0, n, n);
    });
  }

  /** A large dotted red arc with a faint rainbow fringe, open towards the source. */
  redarc() {
    return this.sprite('redarc', 512, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(1.5px)';
      for (let k = 0; k < 180; k++) {
        const a = -1.3 + (k / 180) * 2.6;
        const x = h + Math.cos(a) * h * 0.9, y = h + Math.sin(a) * h * 0.9;
        g.fillStyle = `rgba(230,40,60,${0.55 * Math.cos(a * 0.6)})`; g.fillRect(x - 2.5, y - 1.5, 5, 3);
      }
      for (const [c, dr] of [['rgba(255,180,80,0.18)', -8], ['rgba(120,220,255,0.14)', 8]]) {
        g.strokeStyle = c; g.lineWidth = 3; g.beginPath(); g.arc(h, h, h * 0.9 + dr, -1.1, 1.1); g.stroke();
      }
      g.filter = 'none';
    });
  }

  /** Small rainbow sliver (chromatic streak). */
  sliver() {
    return this.sprite('sliver', 128, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(1px)';
      const cols = ['rgba(255,80,80,0.7)', 'rgba(255,220,80,0.7)', 'rgba(90,255,140,0.7)', 'rgba(80,170,255,0.7)', 'rgba(170,100,255,0.6)'];
      cols.forEach((c, i) => { g.fillStyle = c; g.beginPath(); g.ellipse(h, h - 4 + i * 2, h * 0.9, 1.4, 0, 0, Math.PI * 2); g.fill(); });
      g.globalCompositeOperation = 'destination-in';
      const lg = g.createLinearGradient(0, 0, n, 0); lg.addColorStop(0, 'rgba(0,0,0,0)'); lg.addColorStop(0.5, 'rgba(0,0,0,1)'); lg.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = lg; g.fillRect(0, 0, n, n);
    });
  }

  /** Wide soft halo. */
  halo(t) {
    return this.sprite(`halo-${t}`, 128, (g, n) => {
      const h = n / 2, gr = g.createRadialGradient(h, h, 0, h, h, h);
      gr.addColorStop(0, rgba(t, 0.6)); gr.addColorStop(0.2, rgba(t, 0.3)); gr.addColorStop(0.5, rgba(t, 0.08)); gr.addColorStop(1, rgba(t, 0));
      g.fillStyle = gr; g.fillRect(0, 0, n, n);
    });
  }

  /** Hot core: white middle, tinted rim. */
  core(t) {
    return this.sprite(`core-${t}`, 64, (g, n) => {
      const h = n / 2, gr = g.createRadialGradient(h, h, 0, h, h, h);
      gr.addColorStop(0, 'rgba(255,252,246,1)'); gr.addColorStop(0.35, 'rgba(255,246,230,0.95)'); gr.addColorStop(0.6, rgba(t, 0.45)); gr.addColorStop(1, rgba(t, 0));
      g.fillStyle = gr; g.fillRect(0, 0, n, n);
    });
  }

  /** Starburst: a dozen long thin rays and many short fine ones, a few tinted green/yellow. */
  burst(id, t) {
    return this.sprite(`burst-${id}`, 512, (g, n) => {
      const h = n / 2;
      let seed = id.charCodeAt(0) * 97;
      const R = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
      const ray = (ang, len, wid, col) => {
        const dx = Math.cos(ang), dy = Math.sin(ang);
        const gr = g.createLinearGradient(h, h, h + dx * len, h + dy * len);
        gr.addColorStop(0, col(0.8)); gr.addColorStop(0.15, col(0.42)); gr.addColorStop(0.5, col(0.12)); gr.addColorStop(1, col(0));
        g.fillStyle = gr;
        g.beginPath();
        g.moveTo(h - dy * wid, h + dx * wid); g.lineTo(h + dx * len, h + dy * len); g.lineTo(h + dy * wid, h - dx * wid);
        g.closePath(); g.fill();
      };
      g.filter = 'blur(2px)';
      const main = 20;
      for (let i = 0; i < main; i++) {
        const ang = (i / main) * Math.PI * 2 + (R() - 0.5) * 0.2;
        const len = h * (i % 2 ? 0.3 + R() * 0.35 : 0.55 + R() * 0.45);
        const green = R() < 0.15;
        ray(ang, len, 1.6 + R() * 1.4, (a) => (green ? rgba([0.75, 1.0, 0.45], a * 0.8) : rgba(t, a)));
      }
      for (let i = 0; i < 60; i++) ray(R() * Math.PI * 2, h * (0.12 + R() * 0.4), 0.6 + R() * 0.6, (a) => rgba(t, a * 0.4));
      g.filter = 'none';
    });
  }

  /** A ghost of the aperture: a hexagon with a brighter rim and soft edges. */
  hex(t) {
    return this.sprite(`hex-${t}`, 128, (g, n) => {
      const h = n / 2, r = h * 0.82;
      const path = () => {
        g.beginPath();
        for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2 + Math.PI / 6; const x = h + Math.cos(a) * r, y = h + Math.sin(a) * r; if (i) g.lineTo(x, y); else g.moveTo(x, y); }
        g.closePath();
      };
      g.filter = 'blur(4px)';
      const gr = g.createRadialGradient(h, h, 0, h, h, r);
      gr.addColorStop(0, rgba(t, 0.3)); gr.addColorStop(0.8, rgba(t, 0.42)); gr.addColorStop(1, rgba(t, 0.6));
      g.fillStyle = gr; path(); g.fill();
      g.strokeStyle = rgba(t, 0.3); g.lineWidth = 3; path(); g.stroke();
      g.filter = 'none';
    });
  }

  /** Chromatic spot: red on one side, a cyan fringe on the other. */
  chroma() {
    return this.sprite('chroma', 128, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(3px)';
      g.fillStyle = 'rgba(255,70,90,0.85)'; g.beginPath(); g.ellipse(h - 6, h, h * 0.42, h * 0.62, 0, 0, Math.PI * 2); g.fill();
      g.fillStyle = 'rgba(120,255,200,0.35)'; g.beginPath(); g.ellipse(h + 16, h, h * 0.3, h * 0.58, 0, 0, Math.PI * 2); g.fill();
      g.filter = 'none';
    });
  }

  /** The far sparkle: a small hot point with a thin four-point star. */
  sparkle(t) {
    return this.sprite(`sparkle-${t}`, 256, (g, n) => {
      const h = n / 2;
      const gr = g.createRadialGradient(h, h, 0, h, h, h * 0.4);
      gr.addColorStop(0, 'rgba(255,255,240,0.95)'); gr.addColorStop(0.2, rgba(t, 0.8)); gr.addColorStop(1, rgba(t, 0));
      g.fillStyle = gr; g.fillRect(0, 0, n, n);
      g.filter = 'blur(1px)';
      for (const [ang, len] of [[0, 1], [Math.PI / 2, 0.55], [Math.PI, 1], [Math.PI * 1.5, 0.55], [Math.PI / 4, 0.3], [Math.PI * 1.25, 0.3]]) {
        const dx = Math.cos(ang), dy = Math.sin(ang), L = h * 0.98 * len;
        const lg = g.createLinearGradient(h, h, h + dx * L, h + dy * L);
        lg.addColorStop(0, rgba(t, 0.95)); lg.addColorStop(1, rgba(t, 0));
        g.fillStyle = lg; g.beginPath(); g.moveTo(h - dy * 2.5, h + dx * 2.5); g.lineTo(h + dx * L, h + dy * L); g.lineTo(h + dy * 2.5, h - dx * 2.5); g.closePath(); g.fill();
      }
      g.filter = 'none';
    });
  }

  /** Rainbow arcs (parts of rings): thin, soft, a little desaturated; brightest away from the source. */
  ring() {
    return this.sprite('ring2', 512, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(3px)';
      const bands = [[245, 90, 70], [235, 190, 80], [120, 235, 120], [80, 180, 240], [150, 110, 240]];
      for (const [R0, off, a0, a1] of [[0.86, 0, -1.2, 1.3], [0.74, 3, -0.9, 1.6], [0.62, 6, -0.5, 1.1]]) {
        bands.forEach((c, i) => {
          g.strokeStyle = `rgba(${c[0]},${c[1]},${c[2]},${R0 === 0.86 ? 0.5 : 0.3})`;
          g.lineWidth = 3;
          g.beginPath(); g.arc(h - off, h + off, h * R0 - i * 3.5, a0, a1); g.stroke();
        });
      }
      g.filter = 'none';
      g.globalCompositeOperation = 'destination-in';
      const cg = g.createConicGradient(0, h, h);
      cg.addColorStop(0, 'rgba(0,0,0,1)'); cg.addColorStop(0.2, 'rgba(0,0,0,0.6)'); cg.addColorStop(0.32, 'rgba(0,0,0,0)');
      cg.addColorStop(0.68, 'rgba(0,0,0,0)'); cg.addColorStop(0.8, 'rgba(0,0,0,0.6)'); cg.addColorStop(1, 'rgba(0,0,0,1)');
      g.fillStyle = cg; g.fillRect(0, 0, n, n);
    });
  }

  /** Elongated soft green streak. */
  gstreak() {
    return this.sprite('gstreak', 256, (g, n) => {
      const h = n / 2;
      g.filter = 'blur(4px)';
      const gr = g.createLinearGradient(0, h, n, h);
      gr.addColorStop(0, 'rgba(150,255,90,0)'); gr.addColorStop(0.5, 'rgba(170,255,110,0.7)'); gr.addColorStop(1, 'rgba(150,255,90,0)');
      g.fillStyle = gr; g.beginPath(); g.ellipse(h, h, h * 0.9, h * 0.07, 0, 0, Math.PI * 2); g.fill();
      g.filter = 'none';
    });
  }

  /** Horizontal streak for light through blinds. */
  streak(t) {
    return this.sprite(`streak-${t}`, 256, (g, n) => {
      const gr = g.createLinearGradient(0, 0, n, 0);
      gr.addColorStop(0, rgba(t, 0)); gr.addColorStop(0.5, rgba(t, 0.9)); gr.addColorStop(1, rgba(t, 0));
      g.fillStyle = gr; g.fillRect(0, n * 0.35, n, n * 0.3);
    });
  }

  dispose() { this.canvas.remove(); this.renderer.clearLayer('windowLight'); }
}

function smooth(a, b, x) { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); }

function rgba(t, a) { return `rgba(${(t[0] * 255) | 0},${(t[1] * 255) | 0},${(t[2] * 255) | 0},${a})`; }

/**
 * Exposure / bloom offsets from WindowLight (and any other effect) applied to a plain three.js
 * renderer: layers add up, `apply()` writes base + sum into toneMappingExposure and the bloom
 * pass strength (if you have one). Replace with your own post chain's equivalent if it has one.
 */
export class LookLayers {
  constructor(gl, { bloomPass = null, exposure = gl.toneMappingExposure, bloom = bloomPass?.strength ?? 0 } = {}) {
    this.gl = gl; this.bloomPass = bloomPass; this.base = { exposure, bloom }; this.layers = new Map();
  }
  get isLow() { return false; }
  setLayer(name, values) { this.layers.set(name, values); }
  clearLayer(name) { this.layers.delete(name); }
  apply() {
    let e = this.base.exposure, b = this.base.bloom;
    for (const l of this.layers.values()) { e += (l.exposure || 0) * this.base.exposure; b += l.bloom || 0; }
    this.gl.toneMappingExposure = e;
    if (this.bloomPass) this.bloomPass.strength = Math.max(0, b);
  }
}
