// Мини-карта: круглое окно на карту локации (текстура клеток), повёрнутую по камере.
// Карта: RGB — цвет суши, A — есть ли клетка. За краем проходимого — мягкий фон; по кругу — молочный ободок.
shader_type canvas_item;

uniform sampler2D map_tex : filter_linear, repeat_disable;
uniform vec2 center_uv = vec2(0.5);        // герой в координатах карты
uniform vec2 span = vec2(0.2);             // сколько карты (доля по осям) видно от центра до края круга
uniform float yaw = 0.0;                   // поворот камеры (рад)
uniform vec4 bg : source_color = vec4(0.80, 0.86, 0.90, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform float ready = 1.0;                 // 0 — карта ещё строится (только фон)

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float c = cos(yaw);
	float s = sin(yaw);
	// экран → мир (x, z): вверх по экрану — вперёд по камере
	vec2 w = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	vec2 uv = center_uv + w * span;
	vec4 m = texture(map_tex, uv);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float a = m.a * inside * ready;
	vec3 col = mix(bg.rgb, m.rgb, a);
	// лёгкая виньетка внутрь и ободок
	col = mix(col, col * 0.92, smoothstep(0.55, 0.95, r));
	col = mix(col, rim.rgb, smoothstep(0.9, 0.94, r));
	float alpha = 1.0 - smoothstep(0.985, 1.0, r);
	COLOR = vec4(col, alpha * 0.96);
}
