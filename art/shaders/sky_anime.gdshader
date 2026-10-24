// Небо в аниме-стиле: мягкий градиент «золотого часа» (персик у горизонта → сирень → голубой зенит),
// солнце с ореолом, пушистые облака из шума с розовым низом, плывут. Не белое пустое небо.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.36, 0.56, 0.86);
uniform vec3 upper : source_color = vec3(0.62, 0.7, 0.93);
uniform vec3 lilac : source_color = vec3(0.86, 0.76, 0.9);
uniform vec3 horizon : source_color = vec3(1.0, 0.82, 0.7);
uniform vec3 below : source_color = vec3(0.55, 0.62, 0.78);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.96);
uniform vec3 cloud_shadow : source_color = vec3(0.96, 0.72, 0.76);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.52;
uniform float cloud_speed = 0.004;
uniform float stars = 0.0;            // ночь: звёзды
uniform float sun_glow = 0.45;

void sky() {
	float y = EYEDIR.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon, lilac, smoothstep(0.0, 0.12, y));
		col = mix(col, upper, smoothstep(0.1, 0.35, y));
		col = mix(col, zenith, smoothstep(0.3, 0.9, y));
	} else {
		col = mix(horizon, below, smoothstep(0.0, -0.3, y));
	}
	// солнце и ореол
	float sd = dot(EYEDIR, LIGHT0_DIRECTION);
	col += vec3(1.0, 0.86, 0.66) * pow(max(sd, 0.0), 12.0) * sun_glow;
	col = mix(col, vec3(1.0, 0.98, 0.92), smoothstep(0.9993, 0.9997, sd));
	if (stars > 0.0 && y > 0.0) {
		vec3 q = floor(EYEDIR * 260.0);
		float h = fract(sin(dot(q, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + h * 40.0);
		col += vec3(0.9, 0.92, 1.0) * step(0.9965, h) * tw * stars * smoothstep(0.05, 0.3, y);
	}
	// облака: проекция на купол, два слоя шума
	if (y > 0.01) {
		vec2 uv = EYEDIR.xz / (y + 0.18) * 0.32;
		float t = TIME * cloud_speed;
		float n = texture(cloud_noise, uv + vec2(t, t * 0.4)).r * 0.65 + texture(cloud_noise, uv * 2.3 - vec2(t * 1.7, 0.0)).r * 0.35;
		float c = smoothstep(cloud_cover, cloud_cover + 0.12, n);
		float shade = smoothstep(cloud_cover + 0.04, cloud_cover + 0.3, texture(cloud_noise, uv + vec2(t, t * 0.4) + vec2(0.0, 0.02)).r);
		vec3 cc = mix(cloud_shadow, cloud_light, shade);
		c *= smoothstep(0.01, 0.12, y);
		col = mix(col, cc, c * 0.92);
	}
	COLOR = col;
}
