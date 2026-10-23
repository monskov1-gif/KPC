// Лучи света из окон и пятна на полу (location-kit: shaft / lightPool): аддитивно, без освещения, мягкая альфа.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex : source_color, hint_default_white, filter_linear;
uniform float strength = 1.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = vcol.rgb * t.a * vcol.a * strength;
}
