shader_type spatial;
// Jet / roket lülesi (EngineModule bu malzemeyi lüle ağlarına takar):
//   • kalıcı titanyum ısı renkleri: çıkışa doğru saman → altın → mor → mavi, ağız is ve oksitle koyu
//     (uçak eskidikçe belirginleşir: temper)
//   • sıcaklık (heat): lüle ağzı ve içi koyu kırmızıdan turuncu-sarıya parlar; içeriden (arka yüz)
//     bakınca daha sıcak. Motor kapanınca heat yavaşça düşer, lüle soğur.
render_mode cull_disabled;

uniform vec3 metal : source_color = vec3(0.33, 0.34, 0.36);
instance uniform float heat = 0.0;                  // 0 soğuk … 1 art yakıcı / roket
instance uniform vec2 z_range = vec2(0.0, 1.0);     // ağ uzayında lülenin ön ucu ve çıkış ağzı
instance uniform float temper = 0.6;                // kalıcı ısı renginin şiddeti

varying vec3 lp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// kara cisim ışıması: koyu kırmızı → turuncu → sarımsı beyaz
vec3 blackbody(float t) {
	vec3 a = mix(vec3(0.45, 0.02, 0.0), vec3(1.0, 0.32, 0.04), smoothstep(0.0, 0.55, t));
	return mix(a, vec3(1.0, 0.82, 0.5), smoothstep(0.55, 1.0, t));
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = clamp((lp.z - z_range.x) / max(z_range.y - z_range.x, 0.001), 0.0, 1.0);
	float n = noise(lp * 7.0) * 0.55 + noise(lp * 19.0) * 0.45;
	float tt = t + (n - 0.5) * 0.14;
	// ısı renk bantları (oksit tabakası kalınlığı sıcaklıkla artar)
	vec3 tc = metal;
	tc = mix(tc, vec3(0.7, 0.6, 0.4), smoothstep(0.22, 0.38, tt));    // saman
	tc = mix(tc, vec3(0.64, 0.45, 0.2), smoothstep(0.38, 0.52, tt));   // altın
	tc = mix(tc, vec3(0.38, 0.22, 0.42), smoothstep(0.52, 0.66, tt));  // mor
	tc = mix(tc, vec3(0.22, 0.3, 0.5), smoothstep(0.66, 0.8, tt));     // mavi
	tc = mix(tc, vec3(0.13, 0.13, 0.15), smoothstep(0.86, 1.0, tt));   // ağız: is ve koyu oksit
	ALBEDO = mix(metal, tc, clamp(temper, 0.0, 1.0));
	METALLIC = 0.85;
	ROUGHNESS = 0.3 + 0.3 * smoothstep(0.6, 1.0, tt);
	// sıcaklık ağza doğru artar; lülenin içi (arka yüz) dıştan daha sıcak görünür
	float inside = FRONT_FACING ? 0.0 : 1.0;
	float h = clamp(heat, 0.0, 1.0) * smoothstep(0.3, 1.0, t) * (0.5 + 0.5 * inside);
	h *= 0.85 + 0.15 * n;   // sıcak bölge lekeli
	EMISSION = blackbody(h) * h * h * (2.0 + 5.0 * inside);
}
