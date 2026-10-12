shader_type spatial;
// premul_alpha: sığ su saydam kalırken gökyüzü yansıması ve güneş parlaması güçlü kalır
render_mode blend_premul_alpha, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D wave_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 planet_center = vec3(0.0, -600000.0, 0.0);
uniform vec3 planet_axis = vec3(0.0, 0.42, -0.9);
uniform float waves = 1.0;        // hava durumuyla dalga şiddeti (0.4 sakin … 2.2 fırtına)
uniform float darkness = 0.0;     // kapalı havada su koyulaşır
uniform vec2 wind_dir = vec2(0.6, 0.8);
// Elle hesaplanan keskin gök yansıması için (SkyController günceller)
uniform vec3 sky_zenith : source_color = vec3(0.15, 0.34, 0.70);
uniform vec3 sky_horizon : source_color = vec3(0.64, 0.76, 0.89);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_strength = 1.0;

varying vec3 planet_pos;
varying float wave_h;
varying float fade;
varying float sea_depth;   // köşedeki deniz tabanı derinliği (m), arazi üreticisinden

// Dört yönlü dalga toplamı; xy = eğim, z = yükseklik. Derin su dağılımı: ω = sqrt(g k)
vec3 wave_sum(vec2 uv, float t, float amp) {
	vec3 r = vec3(0.0);
	vec2 dirs[4] = vec2[](wind_dir, normalize(wind_dir + vec2(0.5, -0.3)), normalize(wind_dir + vec2(-0.6, 0.2)), normalize(vec2(-wind_dir.y, wind_dir.x)));
	float lens[4] = float[](48.0, 31.0, 19.0, 11.0);
	float amps[4] = float[](0.9, 0.5, 0.28, 0.12);
	for (int i = 0; i < 4; i++) {
		float k = 6.2831 / lens[i];
		float w = sqrt(9.81 * k);
		float ph = dot(dirs[i], uv) * k - w * t;
		float a = amps[i] * amp;
		r.z += a * sin(ph);
		r.xy += dirs[i] * a * k * cos(ph);
	}
	return r;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_pos = world - planet_center;
	vec3 up = normalize(planet_pos);
	vec3 east = normalize(cross(planet_axis, up));
	vec3 north = cross(up, east);
	vec2 uv = vec2(dot(planet_pos, east), dot(planet_pos, north));
	float dist = length(world - CAMERA_POSITION_WORLD);
	fade = 1.0 - smoothstep(400.0, 3000.0, dist);
	vec3 w = wave_sum(uv, TIME, waves);
	wave_h = w.z;
	sea_depth = max(-UV2.x, 0.0);
	VERTEX += up * w.z * fade;
}

void fragment() {
	vec3 up = normalize(planet_pos);
	vec3 east = normalize(cross(planet_axis, up));
	vec3 north = cross(up, east);
	vec2 uv = vec2(dot(planet_pos, east), dot(planet_pos, north));

	// büyük dalgalar (analitik) + rüzgar dalgacıkları (doku eğimi)
	vec3 w = wave_sum(uv, TIME, waves) * fade;
	vec2 grad = w.xy;
	float e = 0.6;
	vec2 r1 = uv / 23.0 + TIME * wind_dir * 0.03;
	vec2 r2 = uv / 9.0 - TIME * wind_dir.yx * 0.05;
	float h0 = texture(wave_tex, r1).r + texture(wave_tex, r2).r * 0.5;
	float hx = texture(wave_tex, r1 + vec2(e / 23.0, 0.0)).r + texture(wave_tex, r2 + vec2(e / 9.0, 0.0)).r * 0.5;
	float hy = texture(wave_tex, r1 + vec2(0.0, e / 23.0)).r + texture(wave_tex, r2 + vec2(0.0, e / 9.0)).r * 0.5;
	// doku değeri 0..1 → metre: dalgacık genliği ~5–20 cm
	float ripple = (0.05 + waves * 0.07) * (1.0 - smoothstep(800.0, 6000.0, length(VERTEX)));
	grad += vec2(hx - h0, hy - h0) / e * ripple;
	// gölgelendirme için eğim abartılır (geometri değil): dalga deseni her mesafede okunur
	grad *= 1.6;
	vec3 n = normalize(up - grad.x * east - grad.y * north);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float cam_dist = length(VERTEX);
	// su kalınlığı: dikey derinlik + bakış açısıyla uzayan yol (sığ yerde turkuaz ve saydam)
	vec3 v_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float thickness = sea_depth / max(dot(v_dir, up), 0.15);

	vec3 deep = vec3(0.01, 0.07, 0.16);
	vec3 shallow = vec3(0.03, 0.30, 0.30);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 25.0, thickness));
	// dalga tepelerinde ışık geçirgenliği (yeşilimsi turkuaz)
	col += vec3(0.0, 0.10, 0.08) * clamp(wave_h * fade / max(waves, 0.3), 0.0, 1.0);
	// dalga deseni görünür olsun: tepeler açık, çukurlar ve eğimli yüzler koyu
	float crest_t = clamp(wave_h * fade / max(waves * 0.9, 0.3) * 0.5 + 0.5, 0.0, 1.0);
	col *= mix(0.5, 1.45, crest_t);
	col *= mix(0.65, 1.0, pow(clamp(dot(n, up), 0.0, 1.0), 6.0));
	col *= 1.0 - darkness * 0.5;

	// köpük: kıyıda ve fırtınada dalga tepelerinde
	float foam_n = texture(wave_tex, uv / 6.0 + TIME * 0.04).r;
	float shore = (1.0 - smoothstep(0.0, 1.0 + waves, thickness)) * smoothstep(0.35, 0.6, foam_n);
	float crest = smoothstep(0.55, 0.9, wave_h * fade / max(waves, 0.3)) * smoothstep(0.8, 1.8, waves) * smoothstep(0.4, 0.7, foam_n);
	float foam = clamp(shore + crest, 0.0, 1.0);
	col = mix(col, vec3(0.85, 0.9, 0.92), foam * 0.85);

	// Keskin gök yansıması + güneş pırıltısı (motorun bulanık yansıma haritası yerine).
	// Her dalga gökyüzünün farklı bir yüksekliğini yansıttığı için desen net görünür.
	vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v_world, n);
	float r_el = dot(r, up);
	vec3 sky_r = mix(sky_horizon, sky_zenith, pow(clamp(r_el, 0.0, 1.0), 0.5));
	sky_r = mix(sky_r, sky_horizon * 0.6, smoothstep(0.0, -0.2, r_el));   // ufkun altı (kendi dalgaları)
	float cos_t = clamp(dot(n, v_world), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - cos_t, 5.0);
	float rough = clamp(waves - 1.0, 0.0, 1.0);
	float glitter = pow(max(dot(r, sun_dir), 0.0), mix(900.0, 250.0, rough)) * mix(60.0, 12.0, rough);
	glitter += pow(max(dot(r, sun_dir), 0.0), 220.0) * 0.25;
	vec3 reflection = (sky_r * fresnel + sun_color * glitter * sun_strength) * (1.0 - foam);

	ALBEDO = col;
	EMISSION = reflection;
	ALPHA = mix(0.35, 1.0, smoothstep(0.0, 6.0, thickness));
	ALPHA = max(ALPHA, max(foam, fresnel));
	ROUGHNESS = 0.4 + foam * 0.5;
	SPECULAR = 0.0;   // yansımayı yukarıda kendimiz hesapladık
	METALLIC = 0.0;
}
