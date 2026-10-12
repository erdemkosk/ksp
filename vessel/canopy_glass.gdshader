shader_type spatial;
// premul_alpha: cam saydam kalırken yansıma ve güneş parlaması güçlü kalır
render_mode blend_premul_alpha, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.62, 0.66, 0.55);   // hafif altın-yeşil kaplama
uniform vec3 frame_color : source_color = vec3(0.32, 0.35, 0.39);
uniform float frame_width = 0.012;
uniform float bow_front = -0.40;   // ön çerçeve yayının küre-yerel z konumu
uniform float bow_back = 0.30;

varying vec3 local_pos;

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
		float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		float fresnel = pow(1.0 - facing, 4.0);
		ALBEDO = tint * 0.08;
		ROUGHNESS = 0.015;
		METALLIC = 0.0;
		SPECULAR = 1.0;
		// içeriden bakınca daha şeffaf
		float base = FRONT_FACING ? 0.10 : 0.04;
		ALPHA = mix(base, 0.75, fresnel);
	}
}
