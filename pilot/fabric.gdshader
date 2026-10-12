shader_type spatial;
// Uçuş tulumu kumaşı: düz renk yerine kıvrım gölgeleri (düşük frekans), dokuma pürüzü
// (yüksek frekans), dikiş izleri ve kenarda kumaş parlaklığı (sheen). Desen parçanın kendi
// uzayından üretilir: poz değişince kaymaz.

uniform vec3 base : source_color = vec3(0.36, 0.38, 0.28);
uniform float folds = 1.0;          // kıvrım gölgesi şiddeti
uniform float seam_spacing = 0.18;  // dikiş aralığı (m); 0 = dikiş yok
uniform float sheen = 0.22;

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
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	// kıvrımlar: bir yönde uzamış gürültü (kumaş kırışığı gibi)
	float fold = noise(vec3(lp.x * 14.0, lp.y * 4.0, lp.z * 14.0)) * 0.6 + noise(lp * 31.0) * 0.4;
	float grain = noise(lp * 260.0);
	vec3 c = base * (0.86 + fold * 0.22 * folds) * (0.97 + grain * 0.06);
	// dikişler: belli aralıklarla ince koyu çizgi
	float seam = 0.0;
	if (seam_spacing > 0.0) {
		float d = abs(fract(lp.y / seam_spacing + 0.5) - 0.5) * seam_spacing;
		seam = 1.0 - smoothstep(0.0015, 0.004, d);
	}
	c *= 1.0 - seam * 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c + base * rim * sheen;
	ROUGHNESS = 0.86 - fold * 0.08;
	SPECULAR = 0.28;
}
