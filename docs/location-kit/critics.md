# Critic loop for visual work

Rule: every visual change is judged by critic agents that score screenshots 0–10. **No score below 6**
is accepted; the target is 7. Redo and re-shoot until the critics pass it.

## The loop

1. Make the change → screenshot every affected place: each state (day / evening / night), the wide
   gameplay view, and close-ups of the new pieces.
2. Tile the shots into grids (PIL) so one critic sees the whole location: `grid_day.png`,
   `grid_night.png`, `grid_close.png`.
3. Launch critics in parallel, one per topic (e.g. "living room", "bedroom + lamps"), as background
   sub-agents (`subagent_type: general-purpose`). Critics only look and score; they never edit files.
4. From the answers: everything below 7 is analysed; everything below 6 **must** be redone. Fix the
   lowest scores first.
5. Re-shoot → the next round covers only the topics that were below the bar. Repeat until it passes.
6. Report to the owner as a table "round 1 → round 2 → …" per topic.

**Before believing a critic, check it is not a test artefact**: a character missing because the
scene starts with them lying in bed, a light that hasn't faded in yet, a camera that's still moving.
Force those states in the test JS instead of "fixing" the scene.

## Critic prompt template

```
You are a strict art director / game-visual critic. Score screenshots of <project: genre, engine,
camera, art style>. Setting: <location, time of day, what must read at a glance>.
<Round N: previous scores were …; the fixes since: …>

Look at these images with the Read tool:
1. <absolute path> — <what's in it, left to right>
2. …

Requirements from the brief: <the owner's requirements, as a list>.

Give scores 0–10 for: (a) furniture form and materials (no primitive/low-poly look, soft things soft),
(b) lighting and mood per state, (c) composition and readability from the game camera,
(d) believability / lived-in detail, (e) technical artefacts (z-fighting, stretched or repeated
textures, black blocks, floating or sunk objects, clipping).
For each score below 7, list the 3–5 most important concrete, actionable fixes (specific elements,
positions in the frame, colours, sizes). Be concise (max ~300 words). Do not edit any files.
```

Adjust the axes to the task (e.g. "the lamp flare vs the reference image"), but always keep
(e) technical artefacts. When matching a reference, put the reference and our render side by side
in one image.

## How to shoot

- Static server from the folder with the page: `python3 -m http.server 8765 &`
  (don't `pkill -f http.server` in a shared shell — it can kill the shell itself). After a container
  restart, start it again and check the PNG modification times, or "new" shots will be old ones.
- Playwright with its preinstalled Chromium: `export PWPATH=$(npm root -g)/playwright`; don't run
  `playwright install` if a browser is already provided.
- `node shoot.mjs http://localhost:8765/preview.html /tmp/shots/r1 '[{"name":"room_eve","state":"evening","params":{"scene":"room"}},{"name":"room_night","state":"night","params":{"scene":"room"}},{"name":"corridor","state":"day","params":{"scene":"corridor","px":"-4.6,-1.6"}},{"name":"stairs","cam":[1.6,1.6,1.8],"look":[2.2,1.3,-2.4],"params":{"scene":"room"}}]'
  — in a real project point it at the game page and pass `js` to place the player / force the state.
- Shoot **sequentially**: software GL (swiftshader) runs at a few fps; parallel browsers time out.
  Heavy outdoor scenes with bloom can exceed the screenshot timeout there — add `"low":"1"`.
- Walk the player past every bright window and lamp (`px`) — the flare and exposure response is
  part of what the critics judge.
- Smooth effects (fades, light ramps) don't reach their final value in a short test — force them in
  the shot's `js`.
- Grid: `python3 -c "from PIL import Image; …"` — paste shots into one image, ≤ 2 columns, so text
  in the frame stays legible to the critic.

## Lessons the critics taught (apply before the first round)

- A cylinder "log" or a box "sofa" always reads as a pipe / a block — bevel, puff, drape.
- z-fighting of a screen or picture on a flat slab is caught every time — offset every overlay.
- The same texture across rooms / halls reads as fake — vary tone and seed.
- Planes seen edge-on read as strips; give things thickness.
- Zero normals → black blocks under bloom; sanitize normals after the build.
- Horizontal uniform stripes read as "wallpaper" — vary spacing, add diagonal layering.
- Vertex-colour relief reads as a blurry backdrop — bake detail into a texture from a height map.
- Objects that should be grounded must sit on the ground (raycast the terrain/floor, don't guess y).
- A critic catches what the builder agent calls "done" — always run the round, even when sure.
- Builder agents working on separate files in parallel go fast, but commit often: long runs get cut off.
