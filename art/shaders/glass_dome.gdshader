// Стеклянный купол окна (титульный экран): прозрачное стекло с лёгким голубым оттенком, яркий край
// по Френелю, большой изогнутый «аниме-блик» сверху-слева с точкой рядом, косые полосы и мерцающие искры.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform vec4 tint : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform float base_alpha = 0.05;
uniform float rim_alpha = 0.42;
uniform vec3 light_dir = vec3(-0.45, 0.62, 0.65);   // откуда блик (в координатах камеры)

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - nv, 2.2);
	float l = dot(NORMAL, normalize(light_dir));
	// блик-«серп» (отражение окна неба) и маленькая точка рядом
	float crescent = smoothstep(0.80, 0.84, l) * (1.0 - smoothstep(0.90, 0.93, l));
	float spot = smoothstep(0.975, 0.985, dot(NORMAL, normalize(light_dir + vec3(0.18, -0.12, 0.0))));
	vec2 s = SCREEN_UV;
	// косые блики в экранных координатах (как нарисованные полосы на стекле) — только на верхней части купола
	float d = s.x * 0.8 + s.y;
	float upper = smoothstep(0.35, 0.9, UV.y);
	float streak = (smoothstep(0.012, 0.0, abs(fract(d * 1.6 - 0.18) - 0.5) - 0.02) * 0.4
		+ smoothstep(0.006, 0.0, abs(fract(d * 1.6 - 0.27) - 0.5) - 0.006) * 0.3) * upper;
	float spark = pow(max(0.0, sin(UV.x * 140.0 + TIME * 0.9) * sin(UV.y * 120.0 - TIME * 0.7)), 60.0);
	float hl = clamp(crescent * 0.75 + spot + streak + spark, 0.0, 1.0);
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(fres * 0.8 + hl, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(base_alpha + fres * rim_alpha + hl * 0.6, 0.0, 0.85);
}
