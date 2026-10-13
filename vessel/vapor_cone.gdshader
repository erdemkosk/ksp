shader_type spatial;
// Buhar konisi (Prandtl–Glauert yoğuşması): Mach ~0.95–1.05'te gövdenin en kalın yerinde oluşan
// beyaz yoğuşma kabuğu. Ağ: ekseni +z olan, önü dar arkası geniş döndürme gövdesi (z 0..1).
//   • ön kenar keskin (şok cephesi), arkaya doğru dağılır
//   • akışla geriye kayan türbülanslı yoğunluk, kenardan bakınca (sığ açı) daha kalın görünür
//   • güneşe dönük yüz parlak, gölge yüz hafif gri-mavi
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 0.0;          // 0..1 (AeroFx: Mach, nem, irtifa)
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // dünya uzayında güneşe doğru

varying vec3 lp;
varying vec3 wn;

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

void vertex() {
	lp = VERTEX;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float z = clamp(lp.z, 0.0, 1.0);
	float front = smoothstep(0.0, 0.05, z);            // keskin şok cephesi
	float tail = 1.0 - smoothstep(0.2, 1.0, z);        // arkaya doğru dağılır
	float ang = atan(lp.y, lp.x);
	// açısal ve eksenel türbülans; desen akışla geriye kayar
	vec3 q = vec3(cos(ang) * 1.6, sin(ang) * 1.6, z * 5.0 - TIME * 7.0);
	float n = noise(q * 1.7) * 0.55 + noise(q * 4.3 + vec3(7.0)) * 0.3 + noise(q * 11.0) * 0.15;
	// ince boylamasına çizgiler (akış çizgileri)
	float streak = 0.75 + 0.25 * noise(vec3(cos(ang) * 14.0, sin(ang) * 14.0, z * 1.5 - TIME * 3.0));
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), VIEW)), 1.4);
	float a = 2.4 * intensity * front * tail * (0.45 + 0.55 * smoothstep(0.25, 0.75, n)) * streak * (0.55 + 0.45 * rim);
	float lit = 0.72 + 0.28 * clamp(dot(wn, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(vec3(0.78, 0.82, 0.88), vec3(1.0), lit) * lit;
	ALPHA = clamp(a, 0.0, 0.9);
}
