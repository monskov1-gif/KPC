// Пряди-оболочки (hair_clumps.py): цвет из вершин (корни → кончики, тыльная сторона — тень), плоская светотень
// с цветной тенью, аниме-блик «нимб» — полоса поперёк прядей у макушки, рваная по краю; блик гаснет в тени.
shader_type spatial;

uniform vec4 shade_color : source_color = vec4(0.55, 0.62, 0.9, 1.0);
uniform float shade_threshold = 0.46;
uniform float shade_softness = 0.04;
uniform vec4 ring_color : source_color = vec4(0.92, 1.0, 0.98, 1.0);
uniform float ring_y = 1.5;          // высота «нимба» в координатах модели (м); задаёт CharacterModel по росту
uniform float ring_width = 0.018;
uniform float ring_strength = 0.5;
uniform float rim_strength = 0.22;

varying vec4 vcol;
varying vec2 uv;
varying float model_y;

void vertex() {
	vcol = COLOR;
	uv = UV;
	model_y = VERTEX.y;
}

void fragment() {
	ALBEDO = vcol.rgb;
	// «нимб»: по длине пряди, края зубчатые (по ширине), сильнее там, где прядь смотрит на камеру
	// «нимб» — одна полоса вокруг головы на высоте ring_y; край рваный по прядям, к краям пряди гаснет
	float jag = 0.45 * sin(uv.x * 9.0 + uv.y * 40.0) * ring_width;
	float band = 1.0 - smoothstep(ring_width * 0.5, ring_width, abs(model_y - ring_y + jag));
	band *= smoothstep(0.0, 0.25, uv.x) * smoothstep(1.0, 0.75, uv.x);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = ring_color.rgb * band * ring_strength * facing * 0.6;
	float rim = pow(1.0 - facing, 3.0);
	EMISSION += vcol.rgb * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl * ATTENUATION);
	DIFFUSE_LIGHT += mix(shade_color.rgb * 0.32, vec3(1.0), band) * LIGHT_COLOR / PI;
}
