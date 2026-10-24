// Лицо: тень по карте порогов света (SDF, tools/art/face_sdf.py) — как в Genshin / Zenless / Wuthering Waves:
// не по геометрии носа и губ (грязные пятна), а чистыми аниме-формами, которые плавно ползут при повороте света.
// Направления головы (head_forward, head_right — в мире) каждый кадр задаёт CharacterModel.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sdf_tex : hint_default_white, filter_linear, repeat_disable;
uniform bool use_alpha_scissor = true;
uniform vec4 shade_color : source_color = vec4(0.95, 0.8, 0.8, 1.0);
uniform float shade_softness = 0.025;
uniform vec3 head_forward = vec3(0.0, 0.0, 1.0);
uniform vec3 head_right = vec3(-1.0, 0.0, 0.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.88, 1.0);
uniform float rim_strength = 0.18;

varying vec3 hf_view;
varying vec3 hr_view;

void vertex() {
	hf_view = normalize((VIEW_MATRIX * vec4(head_forward, 0.0)).xyz);
	hr_view = normalize((VIEW_MATRIX * vec4(head_right, 0.0)).xyz);
}

void fragment() {
	vec4 base = albedo * texture(albedo_tex, UV);
	if (use_alpha_scissor && base.a < 0.5) {
		discard;
	}
	ALBEDO = base.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength * base.rgb;
}

void light() {
	// свет в плоскости головы: угол от «спереди» (0) до «сзади» (1), сторона — справа или слева от героя
	vec3 up = normalize(cross(hr_view, hf_view));
	vec3 lh = LIGHT - up * dot(LIGHT, up);
	float lit;
	if (length(lh) < 0.05) {
		lit = 1.0;                                  // свет сверху — лицо освещено
	} else {
		lh = normalize(lh);
		float ang = acos(clamp(dot(lh, hf_view), -1.0, 1.0)) / PI;
		vec2 suv = dot(lh, hr_view) > 0.0 ? UV : vec2(1.0 - UV.x, UV.y);
		float t = texture(sdf_tex, suv).r;
		lit = smoothstep(ang - shade_softness, ang + shade_softness, t);
	}
	lit *= ATTENUATION;
	DIFFUSE_LIGHT += mix(shade_color.rgb * 0.3, vec3(1.0), lit) * LIGHT_COLOR / PI;
}
