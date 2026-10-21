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

void fragment() {
	if (use_mask && texture(mask_tex, UV).a < 0.5) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}
