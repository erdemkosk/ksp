shader_type spatial;
// Kokpit iç yüzeyleri: mat koyu gri boya, panel dikişleri, köşe vidaları, hafif doku ve kenar
// aşınması. Kokpit ışığı açıkken panel "yazıları" (ince şeritler) arkadan aydınlanır.

uniform vec3 base_color : source_color = vec3(0.22, 0.23, 0.25);
uniform float panel_light = 0.0;
varying vec3 lp;
varying vec3 ln;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	ln = NORMAL;
	lp = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	// yüzey düzleminde 2B koordinat
	vec3 an = abs(ln);
	vec2 uv = an.x > 0.5 ? lp.zy : (an.y > 0.5 ? lp.xz : lp.xy);
	vec2 cell = uv / vec2(0.11, 0.075);          // 11 x 7.5 cm alt paneller
	vec2 f = fract(cell);
	vec2 id = floor(cell);
	float seam = 1.0 - smoothstep(0.0, 0.035, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	// köşe vidaları
	vec2 corner = min(f, 1.0 - f);
	float screw = 1.0 - smoothstep(0.035, 0.06, length(corner - vec2(0.09)));
	// yazı şeritleri (bazı alt panellerde, üst kenarda)
	float has_text = step(0.45, hash(id));
	float text = has_text * step(0.15, f.x) * step(f.x, 0.15 + 0.5 * hash(id + 3.0)) * step(0.78, f.y) * step(f.y, 0.86);
	text *= step(0.4, fract(f.x * 23.0 + hash(id) * 5.0));
	float n = hash(floor(uv * 400.0)) * 0.04;
	vec3 c = base_color * (0.95 + n) * (1.0 - seam * 0.35) + vec3(screw * 0.06) + vec3(text * 0.2);
	ALBEDO = c;
	ROUGHNESS = 0.82 - screw * 0.3;
	METALLIC = screw * 0.6;
	EMISSION = vec3(0.75, 1.0, 0.8) * text * panel_light * 1.6;
}
