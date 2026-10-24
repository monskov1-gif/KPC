// Радужка сменного лица (src/visual/face_rig.gd): своя текстура героя или перекраска в цвета стиля
// (верх темнее, низ светлее — «монета» по видео 2AM), радуга по кругу, узор в зрачке (атлас 4×2:
// бабочка, сердце, звезда, цветок, искры, луна, вихрь) с мягким мерцанием. UV диска: центр (0.5, 0.5).
shader_type spatial;
render_mode cull_back;

uniform sampler2D iris_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform float tint_amount = 0.0;
uniform vec4 color_top : source_color = vec4(0.25, 0.3, 0.55, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.6, 0.72, 0.95, 1.0);
uniform float rainbow = 0.0;
uniform sampler2D pattern_tex : hint_default_black, filter_linear_mipmap;
uniform int pattern_cell = 0;          // 0 — без узора
uniform vec4 pattern_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float pattern_size = 0.3;      // полуразмер узора в UV диска
uniform float sparkle = 0.0;           // «сказочное» мерцание

void fragment() {
	vec4 tex = texture(iris_tex, UV);
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	vec3 col = tex.rgb;
	if (tint_amount > 0.0) {
		float lum = dot(tex.rgb, vec3(0.3, 0.55, 0.15));
		vec3 grad = mix(color_top.rgb, color_bottom.rgb, smoothstep(0.15, 0.85, UV.y));
		col = mix(col, grad * (0.55 + lum * 0.9), tint_amount);
	}
	if (rainbow > 0.0) {
		float h = fract(atan(d.y, d.x) / 6.2831853 + 0.5 + TIME * 0.03);
		vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
		float lum = dot(tex.rgb, vec3(0.3, 0.55, 0.15));
		col = mix(col, rgb * (0.45 + lum * 0.8), rainbow * smoothstep(0.2, 0.45, r));
	}
	if (pattern_cell > 0) {
		vec2 local = d / (pattern_size * 2.0) + 0.5;
		if (local.x > 0.0 && local.x < 1.0 && local.y > 0.0 && local.y < 1.0) {
			vec2 cell = vec2(float(pattern_cell % 4), float(pattern_cell / 4));
			float a = texture(pattern_tex, (cell + local) / vec2(4.0, 2.0)).a;
			float tw = 0.85 + 0.15 * sin(TIME * 2.3);
			col = mix(col, pattern_color.rgb * tw, a);
		}
	}
	if (sparkle > 0.0) {
		float s = pow(max(0.0, sin(UV.x * 61.0 + TIME * 1.7) * sin(UV.y * 53.0 - TIME * 1.3)), 24.0);
		col += vec3(1.0, 0.95, 1.0) * s * sparkle * smoothstep(0.3, 0.6, r);
	}
	ALBEDO = col;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	EMISSION = col * 0.12;
}

void light() {
	// глаз почти не затеняется (иначе тусклый): ровный свет с лёгкой объёмностью
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI * (0.8 + 0.2 * clamp(dot(NORMAL, LIGHT), 0.0, 1.0));
}
