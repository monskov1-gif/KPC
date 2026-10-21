// Контур «перевёрнутой оболочкой»: задние грани, раздутые по нормали, одним тёмным цветом.
shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.32, 0.2, 0.26, 1.0);
uniform float thickness = 0.0035;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
