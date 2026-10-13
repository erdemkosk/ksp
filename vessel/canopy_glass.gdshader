shader_type spatial;
// premul_alpha: cam saydam kalırken yansıma ve güneş parlaması güçlü kalır
render_mode blend_premul_alpha, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.62, 0.66, 0.55);   // hafif altın-yeşil kaplama
uniform vec3 frame_color : source_color = vec3(0.32, 0.35, 0.39);
uniform float frame_width = 0.012;
uniform float bow_front = -0.40;   // ön çerçeve yayının küre-yerel z konumu
uniform float bow_back = 0.30;

varying vec3 local_pos;
instance uniform float rain = 0.0;     // damla yoğunluğu (CockpitModule biriktirir)
instance uniform float streak = 0.0;   // 0 duran damla, 1 hızla geriye akan çizgi

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Yağmur damlası maskesi (0..1): hücre başına en fazla bir damla, hızda geriye uzar ve kayar.
float drops(vec3 lp, float amount, float stretch, float t) {
	vec2 uv = vec2(lp.x * 2.0, lp.z) * 26.0 + vec2(0.0, lp.y * 8.0);
	float m = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = uv * (layer == 0 ? 1.0 : 1.7) + vec2(float(layer) * 7.3, 0.0);
		vec2 cell = floor(q);
		float r = h21(cell);
		if (r > amount * 0.42 * (1.0 - stretch * 0.55)) continue;   // hızda hava akışı damlaları siler
		vec2 f = fract(q) - 0.5;
		// hızda damla geriye (+z) kayar ve boyuna uzar
		float slide = fract(t * stretch * (0.4 + r) + r * 13.0);
		f.y -= (slide - 0.5) * stretch * 0.8;
		f += (vec2(h21(cell + 3.1), h21(cell + 5.7)) - 0.5) * 0.5;
		f.y /= 1.0 + stretch * 1.8;
		float size = 0.08 + h21(cell + 9.2) * 0.12;
		m = max(m, 1.0 - smoothstep(size * 0.6, size, length(f)));
	}
	return m;
}

void vertex() {
	local_pos = VERTEX;   // ölçeklenmemiş küre koordinatı (±0.5)
}

void fragment() {
	// Çerçeve: iki yay + alt kenar rayı
	// ön cam çerçevesi (göz siperinin üstü) ve pilotun arkasındaki yay
	float bow = min(abs(local_pos.z - bow_front), abs(local_pos.z - bow_back));
	float frame = 1.0 - smoothstep(frame_width, frame_width + 0.004, bow);
	frame = max(frame, 1.0 - smoothstep(-0.03, -0.02, local_pos.y));
	if (frame > 0.5) {
		ALBEDO = frame_color;
		ROUGHNESS = 0.45;
		METALLIC = 0.3;
		ALPHA = 1.0;
	} else {
		float drop = rain > 0.01 ? drops(local_pos, rain, streak, TIME) : 0.0;
		float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		float fresnel = pow(1.0 - facing, 4.0);
		ALBEDO = tint * 0.08;
		ROUGHNESS = 0.015;
		METALLIC = 0.0;
		SPECULAR = 1.0;
		// içeriden bakınca çok daha şeffaf: aşağı (yayın diplerine) bakarken yansıma kokpiti
		// gri bir perdeyle örtüyordu. Dışarıdan bakınca tam yansıma kalır.
		if (FRONT_FACING) {
			ALPHA = mix(0.10, 0.75, fresnel);
		} else {
			ALPHA = mix(0.02, 0.12, fresnel);
			SPECULAR = 0.35;
		}
		// damla: hafif buğulu, parlak kenarlı su (ışığı kırar), cam içinden bakınca da görünür
		ALPHA = max(ALPHA, drop * 0.22 + rain * 0.02);
		ALBEDO = mix(ALBEDO, vec3(0.8, 0.85, 0.9), drop * 0.25);
		ROUGHNESS = mix(ROUGHNESS, 0.08, drop);
		SPECULAR = max(SPECULAR, drop);
	}
}
