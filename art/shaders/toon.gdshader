// Аниме-шейдер персонажей: плоская светотень (две зоны с мягкой границей), цветная тень, контровой свет.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool use_vertex_color = false;
uniform bool use_alpha_scissor = false;
uniform vec4 shade_color : source_color = vec4(0.80, 0.66, 0.74, 1.0);
uniform float shade_threshold = 0.42;
uniform float shade_softness = 0.06;
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.88, 1.0);
uniform float rim_strength = 0.28;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
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
	EMISSION = rim_color.rgb * rim * rim_strength * base.rgb;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl * ATTENUATION);
	// Теневая сторона получает лишь слабый цветной отсвет: иначе свет сзади (контровой) заливает модель.
	vec3 tone = mix(shade_color.rgb * 0.3, vec3(1.0), band);
	DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI;
}
