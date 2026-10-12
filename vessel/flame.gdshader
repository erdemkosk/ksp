shader_type spatial;
// Jet alevi (eklemeli karışım). Aynı shader iki katmanda kullanılır:
// dış alev (turuncu, uzun) ve sıcak çekirdek (beyaz-mavi, kısa).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color_near : source_color = vec3(1.0, 0.85, 0.65);
uniform vec3 color_far : source_color = vec3(1.0, 0.38, 0.08);
uniform float intensity = 2.5;
uniform float diamond_count = 7.0;
instance uniform float power = 1.0;          // 0..1 motor gücü
instance uniform float afterburner = 0.0;    // 0..1

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float t = UV.y;   // 0 = lüle, 1 = alev ucu
	// türbülanslı titreme
	float flicker = 0.82 + 0.18 * sin(TIME * 53.0 + UV.x * 37.0) * sin(TIME * 21.0 + t * 9.0);
	flicker += (hash(vec2(floor(TIME * 40.0), floor(UV.x * 12.0))) - 0.5) * 0.12;
	// şok elmasları: afterburner'da belirgin parlak halkalar
	float d = abs(sin(t * diamond_count * 3.14159 - TIME * 0.5));
	float diamonds = mix(1.0, 0.45 + 1.1 * pow(d, 6.0), afterburner * (1.0 - t));
	vec3 col = mix(color_near, color_far, smoothstep(0.0, 0.7, t));
	float falloff = pow(1.0 - t, mix(2.2, 1.3, afterburner));
	// kenarlar yumuşak, merkez yoğun (silindirin ekrana bakan yüzü)
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	// alev ekseni boyunca (arkadan) bakınca koni parlak bir disk gibi görünmesin
	vec3 axis_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float end_on = abs(dot(axis_view, VIEW));
	edge *= 1.0 - smoothstep(0.55, 0.95, end_on) * 0.85;
	ALBEDO = col * falloff * diamonds * edge * intensity * power * flicker;
}
