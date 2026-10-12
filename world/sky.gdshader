shader_type sky;
// Gökyüzü: gündüz / gün batımı / gece geçişleri, güneş, ay, yıldızlar, bulut katmanı,
// yükseldikçe kararan gök ve uzaydan atmosfer halkası. Yükseklik açıları kameranın
// yerel "yukarı"sına göre hesaplanır (küre gezegen).

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith_color : source_color = vec3(0.16, 0.35, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.65, 0.76, 0.88);
uniform vec3 sun_tint : source_color = vec3(1.0);
uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform vec3 local_east = vec3(1.0, 0.0, 0.0);
uniform vec3 local_north = vec3(0.0, 0.0, -1.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 star_axis = vec3(0.0, 0.42, -0.9);
uniform float star_angle = 0.0;
uniform float night = 0.0;          // 0 gündüz, 1 tam gece
uniform float space = 0.0;          // 0 yer, 1 uzay (yükseklikle)
uniform float horizon_dip = 0.0;    // ufkun eğimi (radyan, yükseklikle büyür)
uniform float coverage = 0.4;
uniform float darkness = 0.0;
uniform float cloud_fade = 1.0;     // bulut katmanının üstüne çıkınca gökte bulut kalmaz

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec3 rotate(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void sky() {
	vec3 d = EYEDIR;
	float y = dot(d, local_up);
	float sun_y = dot(sun_dir, local_up);

	// ufuk çizgisi yükseldikçe aşağı iner
	float yh = y + horizon_dip;
	vec3 col;
	if (yh >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(min(yh / (1.0 + horizon_dip), 1.0), 0.45));
	} else {
		col = horizon_color * 0.55;
	}
	// uzayda gök kararır, ufukta ince atmosfer halkası kalır
	float limb = exp(-abs(yh) * 30.0);
	col = mix(col, zenith_color * 0.03 + horizon_color * limb * 0.9 * (1.0 - night), space);

	// güneş: hale ve disk
	float sd = dot(d, sun_dir);
	vec3 sun_col = sun_tint * LIGHT0_ENERGY;
	float clear = 1.0 - smoothstep(0.55, 0.95, coverage) * (1.0 - space);
	col += sun_col * pow(max(sd, 0.0), 5.0) * 0.22 * (1.0 - coverage * 0.6) * (1.0 - space * 0.8);
	col += sun_col * pow(max(sd, 0.0), 60.0) * 0.6 * clear;
	if (yh > -0.02) {
		col += sun_tint * smoothstep(0.99965, 0.99985, sd) * 25.0 * clear * smoothstep(-0.05, 0.0, sun_y + horizon_dip);
	}

	// yıldızlar (göksel küreyle birlikte döner)
	float star_vis = max(night, space) * (1.0 - coverage * (1.0 - space)) * smoothstep(-0.02, 0.05, yh);
	if (star_vis > 0.01) {
		vec3 sdir = rotate(d, star_axis, -star_angle);
		vec3 g = sdir * 260.0;
		vec3 cell = floor(g);
		float h = hash(cell);
		if (h > 0.985) {
			float dist = length(fract(g) - 0.5);
			float bright = (h - 0.985) / 0.015;
			vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), hash(cell + 7.0));
			col += tint * smoothstep(0.22, 0.0, dist) * bright * bright * 2.5 * star_vis;
		}
	}

	// ay
	float md = dot(d, moon_dir);
	float moon = smoothstep(0.99955, 0.9997, md) * smoothstep(-0.03, 0.02, yh);
	col = mix(col, vec3(0.85, 0.87, 0.9) * (0.6 + 0.4 * night), moon * (1.0 - coverage * 0.8));
	col += vec3(0.5, 0.55, 0.65) * pow(max(md, 0.0), 300.0) * 0.15 * night;

	// bulut katmanı (gök kubbesine izdüşüm, yerel çerçevede)
	if (yh > 0.0 && space < 0.95) {
		vec2 dx = vec2(dot(d, local_east), dot(d, local_north));
		vec2 uv = dx / (yh + 0.08) * 0.32;
		float n = texture(cloud_noise, uv).r * 0.55
			+ texture(cloud_noise, uv * 2.7 + vec2(0.31, 0.17)).r * 0.3
			+ texture(cloud_noise, uv * 7.3 + vec2(0.77, 0.41)).r * 0.15;
		float c = smoothstep(1.0 - coverage - 0.08, 1.0 - coverage + 0.28, n);
		c *= smoothstep(0.0, 0.1, yh);
		c = min(c + coverage * coverage * 0.5 * smoothstep(0.0, 0.1, yh), 1.0);
		c *= (1.0 - space) * cloud_fade;

		float day_light = clamp(1.0 - night, 0.04, 1.0);
		vec3 cloud = mix(vec3(1.0), vec3(0.66, 0.69, 0.74), smoothstep(0.45, 0.95, n));
		cloud = mix(cloud, vec3(0.30, 0.32, 0.35), darkness);
		cloud *= (sun_tint * 0.55 + 0.45) * day_light;
		cloud += sun_col * pow(max(sd, 0.0), 10.0) * 0.6 * (1.0 - darkness);
		col = mix(col, cloud, c);
	}

	COLOR = col;
}
