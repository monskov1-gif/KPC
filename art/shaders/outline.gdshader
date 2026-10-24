// Контур «перевёрнутой оболочкой»: задние грани, раздутые по нормали, одним тёмным цветом.
// Для лица учитывает прозрачные прорези глаз (иначе в глазах была бы тёмная заливка).
shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.32, 0.2, 0.26, 1.0);
uniform float thickness = 0.0035;
uniform sampler2D mask_tex : hint_default_white;
uniform bool use_mask = false;
// Толщина по вершинам (альфа цвета вершины): у кончиков прядей и на лице тоньше, по силуэту — полная.
uniform bool use_vertex_width = false;
// Постоянная толщина на экране: вдали контур не тоньше волоска, вблизи не жирнее (0 — в метрах, как раньше).
uniform float screen_scale = 0.0;
// Кожа: контур закрытых одеждой областей тоже не рисуется (как в toon.gdshader).
uniform bool use_regions = false;
uniform int hide_regions = 0;
varying float region_a;

#include "res://art/shaders/wind.gdshaderinc"

void vertex() {
	region_a = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = thickness * (use_vertex_width ? COLOR.a : 1.0);
	if (screen_scale > 0.0) {
		float dist = length((VIEW_MATRIX * vec4(wp, 1.0)).xyz);
		w *= clamp(dist / screen_scale, 0.6, 2.2);
	}
	VERTEX += NORMAL * w + (inverse(MODEL_MATRIX) * vec4(wind_offset(wp, TIME), 0.0)).xyz;
}

uniform float mask_margin = 0.045;   // контур не рисуется и рядом с прорезями глаз (иначе — толстая «подводка»)

void fragment() {
	if (use_regions && ((hide_regions >> int(round(region_a * 10.0))) & 1) == 1) {
		discard;
	}
	if (use_mask) {
		float a = texture(mask_tex, UV).a;
		a = min(a, texture(mask_tex, UV + vec2(mask_margin, 0.0)).a);
		a = min(a, texture(mask_tex, UV - vec2(mask_margin, 0.0)).a);
		a = min(a, texture(mask_tex, UV + vec2(0.0, mask_margin)).a);
		a = min(a, texture(mask_tex, UV - vec2(0.0, mask_margin)).a);
		if (a < 0.5) {
			discard;
		}
	}
	ALBEDO = outline_color.rgb;
}
