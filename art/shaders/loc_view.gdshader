// Вид за окном (location-kit: viewPlane): нарисованная картинка без освещения, пиксельная, с лёгкой дымкой.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, hint_default_white, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = texture(tex, UV).rgb * tint.rgb;
}
