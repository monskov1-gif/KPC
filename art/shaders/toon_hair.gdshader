// Волосы-«карты»: двусторонние, полупрозрачные пряди (альфа-отсечение), цвет корни→кончики из вершин,
// плоская светотень и аниме-блик сверху.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D strands : source_color, hint_default_white;
uniform vec4 shade_color : source_color = vec4(0.58, 0.64, 0.86, 1.0);
uniform float shade_threshold = 0.45;
uniform float alpha_cut = 0.45;
uniform float rim_strength = 0.35;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 t = texture(strands, UV);
	if (t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb * vcol.rgb;
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(1.0, 0.95, 0.95) * rim * rim_strength * ALBEDO;
}

void light() {
	float ndl = abs(dot(NORMAL, LIGHT)) * 0.5 + 0.5;
	float band = smoothstep(shade_threshold - 0.06, shade_threshold + 0.06, ndl * ATTENUATION);
	DIFFUSE_LIGHT += mix(shade_color.rgb * 0.3, vec3(1.0), band) * LIGHT_COLOR / PI;
}
