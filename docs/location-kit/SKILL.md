---
name: location-kit
description: Build complete three.js game locations — interiors (walls with windows and doors, floors, ceilings, attics, stairs, mouldings, furniture, props) and outdoors (relief ground, spruce stands, bare trees, rocks, mist, fog) — with a day/evening/night light-state system, lamps, window views, daylight shafts, exposure and lens flares when the player passes a light, then verify every visual change with a 0–10 screenshot critic loop. Use when asked to build, extend, furnish, light or judge a 3D location or scene.
---

# Location kit — whole locations, lit, checked by critics

| file | what |
|---|---|
| `location-kit.js` | the core: `LocationKit` class — shell, windows & views, lamps & states, furniture, props, textures, light profiles |
| `window-light.js` | `WindowLight` — exposure/bloom response + 2D lens-flare overlay when the player nears a bright window/lamp; `LookLayers` adapter |
| `nature.js` | outdoors: `rockGeometry`, `spruceStand`, `bareTree`, `reliefGround`, `mistTexture`, `shaftTexture`, snow toggles |
| `example-room.js` | a flat: walls with a window + door, stairs, living room, bed nook, lamps, three states |
| `example-corridor.js` | institutional corridor: daylight windows with shafts, fluorescents, wainscot, pilasters, doorway into a lit room |
| `example-forest.js` | forest edge in first snow: relief ground, layered stands, rocks, mist, fog, sun flare |
| `preview.html` | bench: `?scene=room|corridor|forest&state=…&cam=…&look=…&px=…&low=1`, bloom + flares, ← → walk a marker |
| `shoot.mjs` | Playwright screenshots for the critic loop |
| `critics.md` | the critic loop: prompt template, scoring, how to shoot, lessons learned |

**Read the three examples before building** — they are the style guide in code. Start a new
location by copying the closest example.

## Install

Copy the three `.js` modules into the project (e.g. `src/world/kit/`). They depend only on `three`
(r150+; the preview also uses `three/addons/` for bloom). If the project resolves three
differently, change the first `import` of each file.

```js
import { LocationKit, TEX } from './kit/location-kit.js';
import { WindowLight, LookLayers } from './kit/window-light.js';

const kit = new LocationKit(group, { low: isWeakGPU });  // group = this location's root
kit.setupLights();                                       // hemisphere + fill, driven by states
// … build: shell → openings → furniture → lamps → general light (see below)
kit.flushBatches();                                      // ALWAYS last: one mesh per material + normals fixed
kit.setState('evening');                                 // also sets kit.background (and kit.fog if you set it in onState)

const look = new LookLayers(gl, { bloomPass });          // or your post chain's own { setLayer, clearLayer }
const windowLight = new WindowLight({ renderer: look, canvas: gl.domElement, low });
// every frame:
kit.update(dt);
windowLight.update(dt, { world: kit, player, camera });  // kit.windowLights holds the light zones
look.apply();
```

The canvas' parent must be `position: relative` (the flare overlay is absolutely positioned over it).
`player` is anything with `.position`; the flare dims where it overlaps the player.

## Space and camera

- Metres, y up, floor y = 0. **Side-on dollhouse view**: x runs along the location, the camera sits
  on +z looking at the back wall at `z = BACK` (≈ −2.8…−4), the near wall is cut away. Walls face +z.
- Typical framing: camera ≈ 6–8 m in front, 1.6–2.4 m high, looking at y ≈ 1.2–1.3, fov ≈ 38–40;
  it follows the player in x and is clamped to the location's ends. On entering a location, snap
  the camera (no glide from the previous shot).
- The gameplay strip is z ≈ −2…+0.8: keep it free, put furniture against the back wall and along
  the sides, keep anything at z > 1 low (it sits between the camera and the player).
- Foreground pieces (columns, door jambs, a trolley near the camera) add depth, but must fade/hide
  when they cover the player.
- A location publishes (your engine reads it): walk areas `[{ minX, maxX, minZ, maxZ }]`, camera
  clamp `{ minX, maxX }`, circle colliders `{ x, z, r }` for big furniture, `doors` with spawn
  points, named `spots` (where a character sits/stands, with `seatY`) and `anchors` (Vector3 for
  speech bubbles / hints). Widen walk areas and camera clamp together when extending a location.
- Local frames: `kit.withT(x, z, ry, () => …)` — inside, a piece's back is at z = 0 and its front at
  +z. Frames nest. `kit.P(x, y, z)` converts local → world.

## Building order

1. **Shell** — `floorRect` / `floorPoly` (with a stairwell hole), `wall(x0, x1, h, z, mat, holes)`
   (holes `{x0, x1, y0, y1}`: windows y0 > 0, doors y0 = 0), `wallPoly` (gables, walls under a
   slope), `sideWall` (the two ends), `ceilingPoly` (with holes), `slope` (attic roof), `partition`
   (thick wall with reveals), `trims` (skirting / crown), `wainscot` (tile or panel band + rail),
   `column`, `stairs` (returns `railY(x)`). All batched with **world-space UVs** (`tile` metres per
   texture repeat) — textures never stretch.
2. **Openings** — in the holes: `windowUnit(w, y0, y1, { kind, muntins, blind: { kind: 'slats'|'roman'|'cell', cover } })`
   inside `withT(cx, BACK, 0, …)`, plus `viewPlane(...)` 1.5–3 m behind the wall, much larger than the
   opening. Or `brightWindow(x0, x1, y0, y1, BACK, { profile: 'A'|'B'|'C'|'D', blinds })` — view,
   glass glare, frame, a light shaft onto the floor, the floor patch, moonlit panes at night and a
   light zone, all in one call (world coords, outside `withT`). Doors: `panelDoor(w, h, color, { glassTop })`.
3. **Furniture** — builders `(x, z, ry, options)`: `sofa`, `coffeeTable`, `bookcase`, `bed`,
   `nightstand`, `dresser`, `desk`, `chair`, `tvUnit`, `rug`. Several return the top y. To make a new
   piece, copy the closest builder; don't pile on options.
4. **Props on surfaces** — `bookRow`, `bookStack`, `mug`, `plant`, `framed`, `candle`, `fairyLights`.
   Place them on the returned top y; cluster them; they tell the story of who lives here.
5. **Lamps** — `torchiere`, `tableLamp`, `pendant`, `fluorescent`, `candle`, `fairyLights`, or a raw
   `lamp(id, { light, glows, mats, on: { evening, night, day }, flare: { pos } })`.
6. **General light per state** — a few `lamp(...)` records with only a `pointLight` (warm bounce in
   the evening, cool daylight fill by day, moon by night), plus `statePool(...)` fake bounce patches
   (moonlight on the floor under the window, daylight on the sofa).
7. `flushBatches()`, then register colliders / doors / spots / anchors for your engine.

## The state system

- `kit.ambient` = `{ evening, night, day }` → hemisphere sky/ground/intensity, fill colour/intensity,
  background. Override or add states per location (`new LocationKit(root, { ambient })`).
- Every lamp has a level per state; `setLamp(id, level|null)` lets the story force one on/off.
- `onState(fn)` for anything else (fog, mist colour, hide a prop at night, swap a texture).
- **Evening** — the cosy default: warm lamps, warm bounce, lit windows across the street.
- **Night** — dark and quiet but readable: one or two warm lamps on low, cold moon fill, cold
  window patches on the floor; never pure black, never blue soup.
- **Day** — overcast, soft grey-white fill, lamps off, the windows are the light source.

## Light rules

- Nothing clips to white: window views ≤ `#E4DCCC` on screen, glass glare ≤ 0.22 additive, halos
  0.1–0.4 opacity, lamp shades' emissive 0.4–1.4, exposure from windows ≤ +0.42.
- The window response eases in over ~1 s as the player approaches — never a flash.
- Flares are not one style: `zoom` (default; bright window: starburst, hexes, a green sparkle,
  rainbow arcs), `star` (point sources: lamp, moon, sun in mist), `anamorphic` (low sun, headlights:
  long horizontal streak). Profiles: `WINDOW_PROFILES` A warm old · B cold modern · C blinds
  (streaks) · D very strong; `FLARE_PROFILES` LAMP · PALE · MOON · MIST · LOWSUN. `always: true` for
  sun/moon. Only the strongest source gets the full ghost chain.
- Globes and lamp shades must not bloom like windows. Fluorescents are cold and flat; lamps warm.
- With bloom, every halo and emissive doubles — check the shot with bloom on.

## Outdoors (`nature.js`)

- Ground: `reliefGround(w, d, segW, segD, h(x, z), colorAt)` — vertex colours by slope (snow on flats,
  earth on slopes, a trodden path); keep `h` as a function and expose it (`kit.groundAt`) so
  characters, rocks and props **stand on the relief** (or raycast the ground meshes only).
- Trees: `spruceStand([{ x, z, s, kind: 'tall'|'young', y }], { variant, tint, snow, bark })` —
  hundreds of trees in two draw calls; layer 3 stands (far wall, middle, near) with lighter tints
  for distance. `bareTree(seed, { kind: 'birch'|'aspen', leaves })` between them.
- Rocks: `rockGeometry(seed, { rough, flat, strata, snow, colA, colB })` + `rockMaterial(low)`; sink
  them a little into the ground. `setRockSnow` / `setStandSnow` switch first snow ↔ bare autumn.
- Depth: `THREE.Fog` per state, mist planes (`mistTexture`) between the layers, additive sun shafts
  (`shaftTexture`), a sun/moon glow sprite with an `always` flare zone.

## Rules (each one was learned from a failed critic round)

1. **No raw primitives.** `rb`/`bx`/`cush` for boxes; ≥ 16×12 segments for spheres, ≥ 16 for
   cylinders. A box sofa or a cylinder log always reads as "a block / a pipe".
2. **Soft things are soft** — cushions puff, fabric drapes and folds, pillows tilt. Vary `seed`.
3. **Never mutate cached geometry** — `cached()`/`bevelBox()` return clones; clone in your own caches.
4. **No coplanar surfaces** — pictures, screens, labels, paper sit ≥ 1–2 mm in front of what they lie on.
5. **Planes only for genuinely flat things**, never edge-on to the camera (reads as a strip).
6. **Pixel register** — canvas textures at 1 texel ≈ 1 cm, nearest filtering, seeded `rng`; window
   views and backdrops go through `pixelate`. Don't reuse one texture for every room — vary tone/seed.
   Horizontal uniform stripes read as wallpaper; vertex-colour relief reads as blur — bake detail.
7. **Normals** — zero/NaN normals become black blocks under bloom. `flushBatches()` sanitizes the
   kit's meshes; run `sanitizeNormals(root)` over meshes you add yourself.
8. **Batch static, separate dynamic** — anything that moves, animates or toggles is its own mesh.
9. **Materials are cached by key** — reuse keys; when you flip `material.transparent`, set
   `material.needsUpdate = true` (three bakes opacity into the shader).
10. **Extend, don't rewrite** — add a new wing/room as a module that installs methods onto the scene
    class; keep the original rooms and every scripted event working.
11. **Every visual change goes through the critic loop** (`critics.md`): screenshot all states and
    close-ups, score 0–10, redo while any score is below 6 (target 7), report "before → after".

## Performance

One draw call per material after `flushBatches()`; reuse material keys. `{ low: true }` →
Lambert materials (weak mobile GPUs, swiftshader screenshots). Instanced meshes for repeats
(`fairyLights`, `spruceStand`). Canvas textures 32–128 px (views 768×512).
