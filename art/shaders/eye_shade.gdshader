// Полупрозрачная тень верхнего века на радужке и белке (docs/MODEL_STUDY.md «Видео», 2AM): у линии века
// плотнее, книзу сходит на нет; по краям ленты — мягко. Не тёмно-серая, а цветная (тёмно-сине-лиловая).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 albedo : source_color = vec4(0.2, 0.18, 0.4, 1.0);
uniform float strength = 0.7;

void fragment() {
	ALBEDO = albedo.rgb;
	float fade = pow(1.0 - clamp(UV.y, 0.0, 1.0), 0.9);
	float ends = smoothstep(0.0, 0.1, UV.x) * smoothstep(1.0, 0.9, UV.x);
	ALPHA = strength * fade * ends;
}
