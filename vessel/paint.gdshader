shader_type spatial;
// Uçak boyası: düz / kamuflaj / sivil (üst-alt iki renk + şerit) / çöl deseni ve ince panel çizgileri.
// Desen, parçanın kendi uzayındaki konumdan üretilir (uçak dönünce desen kaymaz).
render_mode cull_disabled;

uniform int scheme = 0;                 // 0 düz, 1 kamuflaj, 2 sivil, 3 çöl
uniform vec3 color1 : source_color = vec3(0.56, 0.61, 0.66);
uniform vec3 color2 : source_color = vec3(0.45, 0.49, 0.54);
uniform vec3 color3 : source_color = vec3(0.3, 0.33, 0.36);
uniform float dark = 0.0;               // paint_dark: biraz koyu ton
uniform float panel_lines = 1.0;

varying vec3 lp;
varying vec3 wn;
instance uniform float inner_sign = 0.0;   // yalnız açık kokpit kabuğu: iç yüzü boyanmaz

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
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 c = color1;
	if (scheme == 1) {
		// sol-sağ simetrik (gerçek uçaklardaki gibi) ve her parçada leke görünecek sıklıkta
		vec3 q = vec3(abs(lp.x), lp.y, lp.z) + vec3(0.0, 0.0, 3.7);
		float n = noise(q * 0.8) * 0.65 + noise(q * 1.9) * 0.35;
		c = n > 0.6 ? color3 : (n > 0.43 ? color2 : color1);
	} else if (scheme == 2) {
		// üst beyaz (color1), alt renk (color2), ortada ince şerit (color3)
		float up = normalize(wn).y;
		c = up < -0.35 ? color2 : color1;
		if (abs(lp.y + 0.05) < 0.07 && abs(normalize(wn).y) < 0.6) {
			c = color3;
		}
	} else if (scheme == 3) {
		vec3 q = vec3(abs(lp.x), lp.y, lp.z);
		float n = noise(q * 0.6 + vec3(3.0)) + noise(q * 1.4) * 0.35;
		c = n > 0.78 ? color2 : color1;
	}
	c *= (1.0 - dark * 0.22);
	// panel çizgileri: gövde boyunca ~1.2 m ve çevresel; kanatta kiriş yönünde
	float lines = 0.0;
	float rivet = 0.0;
	float hatch = 0.0;
	if (panel_lines > 0.5) {
		vec2 g = vec2(lp.x * 0.6, lp.z * 0.83);
		float dz = abs(fract(g.y + 0.5) - 0.5);
		float dx = abs(fract(g.x + 0.5) - 0.5);
		lines = max(1.0 - smoothstep(0.004, 0.012, dz), (1.0 - smoothstep(0.003, 0.009, dx)) * 0.6);
		// her panel biraz farklı ton (yamalı gerçek uçak görüntüsü)
		vec3 cell = floor(vec3(g.x + 0.5, lp.y * 0.7, g.y + 0.5));
		c *= 0.965 + hash(cell) * 0.07;
		// perçin sıraları: çizgilerin iki yanında 12 cm arayla
		float along = fract(lp.x * 8.0 + lp.y * 8.0);
		float row = abs(dz - 0.03);
		rivet = (1.0 - smoothstep(0.004, 0.008, row)) * (1.0 - smoothstep(0.12, 0.2, abs(along - 0.5)));
		// servis kapakları: bazı panellerde küçük dikdörtgen
		float hr = hash(cell + vec3(7.0, 3.0, 1.0));
		if (hr > 0.72) {
			vec2 inp = vec2(fract(g.x + 0.5), fract(g.y + 0.5)) - vec2(0.3 + hr * 0.3, 0.5);
			vec2 hs = vec2(0.12, 0.18);
			vec2 e = abs(inp) - hs;
			float edge = abs(max(e.x, e.y));
			hatch = (1.0 - smoothstep(0.004, 0.01, edge)) * step(max(e.x, e.y), 0.01);
		}
	}
	// kir / yıpranma: düşük frekanslı lekeler ve hava akışı yönünde (geriye) akıntı izleri
	float grime = noise(lp * vec3(0.9, 0.9, 0.25)) * noise(lp * 2.7 + vec3(11.0));
	float streak = noise(vec3(lp.x * 9.0, lp.y * 9.0, lp.z * 0.35)) * smoothstep(-0.2, -0.8, normalize(wn).y);
	c *= 1.0 - grime * 0.12 - streak * 0.08;
	ALBEDO = c * (1.0 - lines * 0.35 - hatch * 0.3) + vec3(rivet * 0.03);
	// normal: ağ sarımına güvenme (ters sarımlı gövde tüplerinde Godot normali içe çeviriyordu →
	// gövde koyu mavi görünüyordu). Gerçek dış normali al; arkadan bakılıyorsa (iç yüz) çevir.
	vec3 nv = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	bool inside = dot(nv, VIEW) < 0.0;
	NORMAL = inside ? -nv : nv;
	// açık kokpit kabuğunun iç yüzü (kokpitten görünür): boya değil koyu iç astar
	if (inner_sign > 0.0 && inside) {
		ALBEDO = vec3(0.13, 0.135, 0.14);
	}
	// boya metal değil: düşük metallik, ince vernik (aksi halde gökyüzünü ayna gibi yansıtıp deseni siliyordu)
	METALLIC = 0.06 + rivet * 0.5;
	ROUGHNESS = 0.58 + lines * 0.15 + grime * 0.15 - rivet * 0.25;
	CLEARCOAT = 0.12 * (1.0 - grime);
	CLEARCOAT_ROUGHNESS = 0.3;
}
