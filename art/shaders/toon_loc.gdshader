// Аниме-шейдер локаций (location-kit): пиксельные текстуры 1 тексель ≈ 1 см — фильтр «ближайший» с мипмапами,
// мягче граница света и тени, чем у персонажей; цвет вершин — мягкая «окклюзия» у низа предметов.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform bool use_vertex_color = true;
uniform bool use_alpha_scissor = false;
uniform vec4 shade_color : source_color = vec4(0.72, 0.68, 0.86, 1.0);
uniform float shade_threshold = 0.42;
uniform float shade_softness = 0.16;
uniform float rim_strength = 0.08;
uniform float emission_boost = 0.0;

varying vec4 vcol;

#include "res://art/shaders/wind.gdshaderinc"

void vertex() {
	vcol = COLOR;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wind_offset(wp, TIME), 0.0)).xyz;
}

void fragment() {
	vec4 base = albedo * texture(albedo_tex, UV);
	if (use_vertex_color) {
		base.rgb *= vcol.rgb;
	}
	ALBEDO = base.rgb;
	if (use_alpha_scissor && base.a < 0.5) {
		discard;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base.rgb * (rim * rim_strength + emission_boost);
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl * ATTENUATION);
	vec3 tone = mix(shade_color.rgb * 0.38, vec3(1.0), band);
	DIFFUSE_LIGHT += tone * LIGHT_COLOR * ATTENUATION / PI;
}
