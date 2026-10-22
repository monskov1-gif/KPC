// Контур «перевёрнутой оболочкой»: задние грани, раздутые по нормали, одним тёмным цветом.
// Для лица учитывает прозрачные прорези глаз (иначе в глазах была бы тёмная заливка).
shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.32, 0.2, 0.26, 1.0);
uniform float thickness = 0.0035;
uniform sampler2D mask_tex : hint_default_white;
uniform bool use_mask = false;

void vertex() {
	VERTEX += NORMAL * thickness;
}

uniform float mask_margin = 0.045;   // контур не рисуется и рядом с прорезями глаз (иначе — толстая «подводка»)

void fragment() {
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
