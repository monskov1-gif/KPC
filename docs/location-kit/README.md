# location-kit — Claude Code skill

Drop this folder into another project as `.claude/skills/location-kit/` (Claude Code picks the skill
up from `SKILL.md`), or attach the files to a chat and say: "read SKILL.md and build the location
with this kit, checking every visual change with critics.md".

Open `preview.html` through any static server
(`python3 -m http.server`) to look around: buttons for scene and state, ← → walk the marker past
windows and lamps (exposure + lens flares react), drag to orbit, wheel to zoom.
