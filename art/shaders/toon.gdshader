// Аниме-шейдер персонажей: плоская светотень (две зоны с мягкой границей), цветная тень, контровой свет.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_color = false;
uniform bool use_alpha_scissor = false;
uniform vec4 shade_color : source_color = vec4(0.80, 0.66, 0.74, 1.0);
uniform float shade_threshold = 0.42;
uniform float shade_softness = 0.06;
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.88, 1.0);
uniform float rim_strength = 0.28;
uniform float emission_boost = 0.0;   // самосвечение (окна, фонари локаций)
// Кожа: области тела под одеждой не рисуются (альфа цвета вершин = номер области / 20, биты маски — CharacterModel).
uniform bool use_regions = false;
uniform int hide_regions = 0;

// Бровь поверх чёлки (как в аниме-играх, docs/MODEL_STUDY.md «Видео»): вершины сдвигаются к камере на view_bias
// метров — прядь в паре сантиметров перед бровью её не закрывает, а голова (толще) по-прежнему закрывает сзади.
uniform float view_bias = 0.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz += normalize(-vp.xyz) * view_bias;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec4 base = albedo * texture(albedo_tex, UV);
	if (use_vertex_color) {
		base.rgb *= vcol.rgb;
	}
	ALBEDO = base.rgb;
	if (use_regions && ((hide_regions >> int(round(vcol.a * 20.0))) & 1) == 1) {
		discard;
	}
	if (use_alpha_scissor && base.a < 0.5) {
		discard;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength * base.rgb + base.rgb * emission_boost;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl * ATTENUATION);
	// Теневая сторона получает лишь слабый цветной отсвет: иначе свет сзади (контровой) заливает модель.
	vec3 tone = mix(shade_color.rgb * 0.3, vec3(1.0), band);
	DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI;
}
