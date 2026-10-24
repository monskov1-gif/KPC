// Океан титульного экрана: волны суммой синусоид (Герстнер-подобные гребни), дом-отель «плывёт» — волны
// бегут навстречу (drift), за корпусом пенный след. Аниме-стиль: две зоны света, цветная глубина,
// пена на гребнях и у корпуса, искры солнца.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.09, 0.32, 0.46, 1.0);
uniform vec4 mid_color : source_color = vec4(0.18, 0.55, 0.66, 1.0);
uniform vec4 crest_color : source_color = vec4(0.52, 0.86, 0.86, 1.0);
uniform vec4 foam_color : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform vec4 horizon_tint : source_color = vec4(0.98, 0.78, 0.74, 1.0);
uniform vec2 drift = vec2(0.0, 0.55);          // как будто дом плывёт: волны бегут к корме
uniform vec3 hull_center = vec3(0.0, 0.0, 0.0);
uniform vec2 hull_half = vec2(3.2, 4.2);        // полуразмеры корпуса по x и z
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;

varying float wave_h;
varying vec3 wpos;

float waves(vec2 p, float t, out vec2 grad) {
	vec4 dir_a = vec4(normalize(vec2(1.0, 0.35)), normalize(vec2(-0.6, 1.0)));
	vec4 dir_b = vec4(normalize(vec2(0.2, -1.0)), normalize(vec2(1.0, -0.8)));
	vec4 freq = vec4(0.32, 0.55, 0.9, 1.6);
	vec4 amp = vec4(0.32, 0.18, 0.09, 0.04);
	vec4 spd = vec4(0.9, 1.3, 1.7, 2.4);
	float h = 0.0;
	grad = vec2(0.0);
	vec2 d[4] = vec2[](dir_a.xy, dir_a.zw, dir_b.xy, dir_b.zw);
	for (int i = 0; i < 4; i++) {
		float ph = dot(d[i], p) * freq[i] + t * spd[i];
		// острые гребни: синус, поднятый к пику
		float s = sin(ph) * 0.5 + 0.5;
		h += amp[i] * (pow(s, 1.6) * 2.0 - 1.0);
		grad += amp[i] * 1.6 * pow(max(s, 1e-3), 0.6) * cos(ph) * freq[i] * d[i];
	}
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wpos.xz + drift * TIME;
	vec2 g;
	float h = waves(p, TIME, g);
	// у корпуса вода спокойнее (не пробивает дно дома)
	vec2 q = abs(wpos.xz - hull_center.xz) - hull_half;
	float inside = 1.0 - smoothstep(-0.5, 1.5, max(q.x, q.y));
	h *= 1.0 - inside * 0.7;
	VERTEX.y += h;
	wave_h = h;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(NORMAL, v), 0.0, 1.0), 3.0);
	float t = clamp(wave_h * 1.4 + 0.45, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb, mid_color.rgb, t);
	col = mix(col, crest_color.rgb, smoothstep(0.65, 1.0, t) * 0.6);
	// дальняя вода отражает тёплый закат
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	col = mix(col, horizon_tint.rgb, clamp(fres * 0.35 + smoothstep(40.0, 160.0, dist) * 0.45, 0.0, 0.55));
	// пена: гребни + след за кормой и по бортам
	vec2 p = wpos.xz + drift * TIME;
	float n = texture(foam_noise, p * 0.11).r;
	float crest = smoothstep(0.36, 0.46, wave_h + (n - 0.5) * 0.14);
	vec2 rel = wpos.xz - hull_center.xz;
	vec2 q = abs(rel) - hull_half;
	float edge = max(q.x, q.y);
	float ring = (1.0 - smoothstep(0.0, 0.5, abs(edge - 0.15))) * step(-0.2, edge);
	float wake = smoothstep(0.0, 1.0, rel.y / 18.0) * (1.0 - smoothstep(0.0, 1.0 + rel.y * 0.12, abs(rel.x) - hull_half.x * 0.6));
	wake *= 1.0 - smoothstep(10.0, 24.0, rel.y);
	float foam = max(crest, max(ring * 0.85, wake * 0.6)) * smoothstep(0.45, 0.7, n + 0.1);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = smoothstep(0.42, 0.5, ndl);
	DIFFUSE_LIGHT += mix(vec3(0.62, 0.66, 0.82), vec3(1.0), band) * LIGHT_COLOR * ATTENUATION / PI * 0.85;
	// искры солнца на воде — резкий блик, а не размытое пятно
	vec3 hlf = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, hlf), 0.0), 900.0);
	SPECULAR_LIGHT += step(0.5, spec) * LIGHT_COLOR * 0.8 * ATTENUATION;
}
