// Вода локаций: полупрозрачная бирюза с мягкими волнами и светлыми бликами-«штрихами» в аниме-стиле.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform vec4 deep : source_color = vec4(0.27, 0.52, 0.62, 0.82);
uniform vec4 shallow : source_color = vec4(0.55, 0.8, 0.82, 0.7);
uniform vec4 foam : source_color = vec4(0.94, 0.98, 1.0, 1.0);
uniform float wave_height = 0.04;
uniform float speed = 0.6;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.9 + TIME * speed) * wave_height + cos(wpos.z * 1.1 + TIME * speed * 0.8) * wave_height;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec4 c = mix(deep, shallow, fres);
	// блики: тонкие светлые полосы, которые плывут по воде
	float s = sin(wpos.x * 2.3 + wpos.z * 0.7 + TIME * speed * 1.7) * sin(wpos.z * 1.9 - TIME * speed);
	float glint = smoothstep(0.93, 0.98, s);
	ALBEDO = mix(c.rgb, foam.rgb, glint * 0.8);
	ALPHA = mix(c.a, 1.0, glint * 0.6);
	ROUGHNESS = 0.3;
	SPECULAR = 0.4;
}
