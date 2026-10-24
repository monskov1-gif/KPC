// Виньетка и лёгкий тёплый тон по краям кадра (как в ZZZ-разборе, docs/MODEL_STUDY.md «Видео»):
// взгляд — к центру, края мягко темнеют и теплеют. Поверх 3D, не ловит мышь.
shader_type canvas_item;

uniform float strength = 0.38;
uniform vec4 edge_tint : source_color = vec4(0.42, 0.26, 0.34, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	d.x *= 1.15;
	float v = smoothstep(0.32, 0.86, length(d));
	COLOR = vec4(edge_tint.rgb, v * strength);
}
