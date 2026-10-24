// Лицо: тень по карте порогов света (SDF, tools/art/face_sdf.py) — как в Genshin / Zenless / Wuthering Waves:
// не по геометрии носа и губ (грязные пятна), а чистыми аниме-формами, которые плавно ползут при повороте света.
// Направления головы (head_forward, head_right — в мире) каждый кадр задаёт CharacterModel.
// Сменное лицо (src/visual/face_rig.gd): кожа с прорезями глаз нужной формы (albedo_tex) + макияж по маскам
// (румянец, тени вокруг глаз) + рот выражения из общего атласа — цвета и сила задаёт стиль лица.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sdf_tex : hint_default_white, filter_linear, repeat_disable;
uniform bool use_alpha_scissor = true;
uniform vec4 shade_color : source_color = vec4(0.95, 0.8, 0.8, 1.0);
uniform float shade_softness = 0.025;
// свет почти спереди (до ~25°) лицо не затеняет: иначе по щеке шла вертикальная полоса, на носу — клин
uniform float shade_start = 0.14;
uniform vec3 head_forward = vec3(0.0, 0.0, 1.0);
uniform vec3 head_right = vec3(-1.0, 0.0, 0.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.88, 1.0);
uniform float rim_strength = 0.18;

// макияж: R — румянец, G — тени вокруг глаз
uniform bool use_makeup = false;
uniform sampler2D makeup_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 blush_color : source_color = vec4(0.95, 0.59, 0.63, 1.0);
uniform float blush_amount = 0.3;
uniform vec4 eyeshadow_color : source_color = vec4(0.82, 0.52, 0.52, 1.0);
uniform float eyeshadow_amount = 0.3;
// рот: клетка атласа 4×2 (R — линия, G — губы, B — рот внутри) на прямоугольнике mouth_rect (центр, полуразмер в UV)
uniform bool use_mouth = false;
uniform sampler2D mouth_tex : hint_default_black, filter_linear, repeat_disable;
uniform int mouth_cell = 0;
uniform vec4 mouth_rect = vec4(0.5, 0.84, 0.05, 0.03);
uniform vec4 lip_color : source_color = vec4(0.9, 0.55, 0.58, 1.0);
uniform float lip_amount = 0.5;
uniform vec4 mouth_line_color : source_color = vec4(0.56, 0.3, 0.34, 1.0);
uniform vec4 mouth_inner_color : source_color = vec4(0.42, 0.16, 0.2, 1.0);

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
	vec3 col = base.rgb;
	if (use_makeup) {
		vec4 mk = texture(makeup_tex, UV);
		col = mix(col, col * blush_color.rgb, clamp(mk.r * blush_amount, 0.0, 1.0));
		col = mix(col, col * eyeshadow_color.rgb, clamp(mk.g * eyeshadow_amount, 0.0, 1.0));
	}
	if (use_mouth) {
		vec2 local = (UV - mouth_rect.xy) / (mouth_rect.zw * 2.0) + 0.5;
		if (local.x > 0.0 && local.x < 1.0 && local.y > 0.0 && local.y < 1.0) {
			vec2 cell = vec2(float(mouth_cell % 4), float(mouth_cell / 4));
			vec4 m = texture(mouth_tex, (cell + local) / vec2(4.0, 2.0));
			col = mix(col, col * lip_color.rgb, clamp(m.g * lip_amount, 0.0, 1.0));
			col = mix(col, mouth_inner_color.rgb, m.b);
			col = mix(col, mouth_line_color.rgb, m.r);
		}
	}
	ALBEDO = col;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength * col;
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
		ang = clamp((ang - shade_start) / (1.0 - shade_start), 0.0, 1.0);
		vec2 suv = dot(lh, hr_view) > 0.0 ? UV : vec2(1.0 - UV.x, UV.y);
		float t = texture(sdf_tex, suv).r;
		lit = smoothstep(ang - shade_softness, ang + shade_softness, t);
	}
	lit *= ATTENUATION;
	// тень на лице мягче, чем на одежде: тёплая, а не грязно-серая
	DIFFUSE_LIGHT += mix(shade_color.rgb * 0.55, vec3(1.0), lit) * LIGHT_COLOR / PI;
}
