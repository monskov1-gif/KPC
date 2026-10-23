// Ветер (живой мир): листва колышется, бельё на верёвке качается от точки крепления вниз.
// wind — размах (м); wind_pin_top < 1e5 — высота крепления: выше неё ничего не двигается, ниже — тем сильнее,
// чем дальше от неё (на wind_span метрах размах полный). Фаза зависит от места — деревья качаются вразнобой.
uniform float wind = 0.0;
uniform float wind_pin_top = 1e6;
uniform float wind_span = 0.6;

vec3 wind_offset(vec3 world_pos, float t) {
	if (wind <= 0.0) {
		return vec3(0.0);
	}
	float w = wind;
	if (wind_pin_top < 1e5) {
		w *= clamp((wind_pin_top - world_pos.y) / wind_span, 0.0, 1.0);
	}
	float ph = t * 1.7 + world_pos.x * 0.35 + world_pos.z * 0.27;
	float gust = 0.65 + 0.35 * sin(t * 0.37 + world_pos.x * 0.05);
	return vec3(sin(ph), 0.0, cos(ph * 0.83) * 0.6) * w * gust;
}
