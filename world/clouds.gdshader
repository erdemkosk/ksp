shader_type spatial;
// Hacimsel bulutlar: gezegeni saran bulut kabuğu boyunca ışın yürütme (raymarching).
// Kameraya bağlı tam ekran dörtgen olarak çizilir; sahne derinliğini okuyup
// bulutları arazinin/uçağın önüne veya arkasına doğru yerleştirir.
// İçlerinden geçilebilir: kamera bulutun içindeyken yoğunluk hemen başlar.
render_mode unshaded, blend_premul_alpha, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler3D shape_tex : repeat_enable, filter_linear;
uniform sampler3D detail_tex : repeat_enable, filter_linear;

uniform vec3 planet_center = vec3(0.0, -600000.0, 0.0);
uniform float planet_radius = 600000.0;
uniform float cloud_base = 1500.0;
uniform float cloud_top = 3800.0;
uniform float coverage = 0.45;
uniform float density = 0.035;
uniform float darkness = 0.0;
uniform vec3 wind_offset = vec3(0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_strength = 1.0;
uniform vec3 sky_zenith : source_color = vec3(0.15, 0.34, 0.70);
uniform vec3 sky_horizon : source_color = vec3(0.64, 0.76, 0.89);
uniform float max_distance = 60000.0;

const int STEPS = 56;
const int LIGHT_STEPS = 5;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

vec2 sphere_hits(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) return vec2(-1.0);
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float cloud_density(vec3 p, bool cheap) {
	float r = length(p);
	float h = (r - planet_radius - cloud_base) / (cloud_top - cloud_base);
	if (h < 0.0 || h > 1.0) return 0.0;
	// kümülüs profili: tabanı düz, tepesi yuvarlak
	float profile = smoothstep(0.0, 0.08, h) * smoothstep(1.0, 0.55, h);
	vec3 q = p + wind_offset;
	// büyük ölçekli kaplama + kabarık gövde (ters hücresel gürültü)
	float big = texture(shape_tex, q / 22000.0).r;
	float shape = 1.0 - texture(shape_tex, q / 4200.0).g;
	float base = mix(big, shape, 0.55);
	float c = clamp((base - (1.0 - coverage)) / max(coverage, 0.05), 0.0, 1.0) * profile;
	if (c <= 0.0) return 0.0;
	if (!cheap) {
		// kenarları aşındır
		float detail = texture(detail_tex, q / 650.0).r;
		c = clamp(c - detail * 0.35 * (1.0 - c), 0.0, 1.0);
	}
	return c * density;
}

float hg(float cos_t, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cos_t, 1.5));
}

void fragment() {
	// görüş ışını (dünya) ve sahne mesafesi
	vec4 near_v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 rd_view = normalize(near_v.xyz / near_v.w);
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(rd_view, 0.0)).xyz);
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	float scene_dist = 1e9;
	if (raw_depth > 0.0000001) {
		vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
		scene_dist = length(sv.xyz / sv.w);
	}
	vec3 ro = CAMERA_POSITION_WORLD - planet_center;

	float r_in = planet_radius + cloud_base;
	float r_out = planet_radius + cloud_top;
	float cam_r = length(ro);
	vec2 outer = sphere_hits(ro, rd, r_out);
	if (outer.y < 0.0) discard;
	vec2 inner = sphere_hits(ro, rd, r_in);
	float t0;
	float t1;
	if (cam_r < r_in) {
		t0 = inner.y;
		t1 = outer.y;
	} else if (cam_r < r_out) {
		t0 = 0.0;
		t1 = (inner.x > 0.0) ? inner.x : outer.y;
	} else {
		t0 = outer.x;
		t1 = (inner.x > 0.0) ? inner.x : outer.y;
	}
	// gezegenin kendisi ışını keserse (ufkun altı) orada dur
	vec2 ground = sphere_hits(ro, rd, planet_radius);
	if (ground.x > 0.0) t1 = min(t1, ground.x);
	t1 = min(t1, min(scene_dist, max_distance));
	t0 = max(t0, 0.0);
	if (t1 <= t0) discard;

	float seg = t1 - t0;
	float step_len = seg / float(STEPS);
	float jitter = hash12(FRAGCOORD.xy + fract(TIME) * 37.0);
	float cos_sun = dot(rd, sun_dir);
	float phase = mix(hg(cos_sun, 0.6), hg(cos_sun, -0.25), 0.3) * 4.0 * PI;

	float transmittance = 1.0;
	vec3 light = vec3(0.0);
	float t = t0 + step_len * jitter;
	for (int i = 0; i < STEPS; i++) {
		if (t > t1 || transmittance < 0.02) break;
		vec3 p = ro + rd * t;
		float d = cloud_density(p, false);
		if (d > 0.0) {
			// güneşe doğru gölge
			float shadow = 0.0;
			float ls = (cloud_top - cloud_base) / float(LIGHT_STEPS) * 0.6;
			for (int j = 1; j <= LIGHT_STEPS; j++) {
				shadow += cloud_density(p + sun_dir * ls * float(j), true);
			}
			float sun_t = exp(-shadow * ls * 1.4);
			float powder = 1.0 - exp(-d * step_len * 2.0);
			vec3 up = normalize(p);
			float h = clamp((length(p) - planet_radius - cloud_base) / (cloud_top - cloud_base), 0.0, 1.0);
			vec3 ambient = mix(sky_horizon * 0.6, sky_zenith * 0.9 + sky_horizon * 0.3, h) * (1.0 - darkness * 0.7);
			vec3 sun_l = sun_color * sun_strength * sun_t * phase * mix(1.0, powder * 2.0, 0.5);
			vec3 scatter = (sun_l + ambient) * (1.0 - darkness * 0.6);
			float a = exp(-d * step_len);
			light += transmittance * scatter * (1.0 - a);
			transmittance *= a;
		}
		t += step_len;
	}
	float alpha = 1.0 - transmittance;
	if (alpha < 0.003) discard;
	// uzak bulutlar havanın rengine karışır
	float haze = 1.0 - exp(-t0 / 45000.0);
	light = mix(light, sky_horizon * alpha, haze * 0.7);
	ALBEDO = light;
	ALPHA = alpha;
}
