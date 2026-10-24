// Дуга взмаха (удар героя): светлый серп по кругу, бежит от начала к концу и гаснет (progress 0→1).
// Квадрат лежит в плоскости XZ; дуга — полукольцо перед героем (+Z узла).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.x, -p.y);                 // −π…π, 0 — «вперёд»
	float ring = smoothstep(0.62, 0.8, r) * (1.0 - smoothstep(0.86, 0.98, r));
	float sweep = (a + 1.7) / 3.4;             // доля дуги 0…1 (сектор ±97°)
	float head = progress * 1.3;
	float trail = smoothstep(head - 0.55, head, sweep) * (1.0 - smoothstep(head, head + 0.04, sweep));
	float inside = step(0.0, sweep) * step(sweep, 1.0);
	float fade = 1.0 - smoothstep(0.6, 1.0, progress);
	float a_out = ring * trail * inside * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0), smoothstep(0.75, 0.82, r) * 0.6) * a_out * 1.6;
	ALPHA = a_out;
}
