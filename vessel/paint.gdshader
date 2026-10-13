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
varying vec3 ln;                           // ağın kendi uzayındaki normal
instance uniform float inner_sign = 0.0;   // yalnız açık kokpit kabuğu: iç yüzü boyanmaz
// Yıpranma (VesselBuilder._apply_weathering yazar): 0 fabrikadan yeni … 1 çok eskimiş
instance uniform float wear = 0.0;
// Is kaynağı (lüle ağzı / namlu) ağ uzayında: xyz konum, w şiddet; soot_r etki yarıçapı (ağ birimi)
instance uniform vec4 soot_src = vec4(0.0);
instance uniform float soot_r = 1.0;
// Uçağın ileri (-Z) ve yukarı yönü ağ uzayında: hücum kenarı aşınması ve üst/alt yüzey ayrımı
// uçak dönse de (ters uçuşta) değişmesin diye dünya normali yerine bunlar kullanılır.
instance uniform vec3 fwd_m = vec3(0.0, 0.0, -1.0);
instance uniform vec3 up_m = vec3(0.0, 1.0, 0.0);
// Yapı zorlanması (StressFx yazar): rgb renk, a şiddet — %70 sarı, %90 kırmızı, %100 yanıp söner
instance uniform vec4 stress_glow = vec4(0.0);
// Kanat bükülmesi (yalnız görüntü, StressFx yazar): xyz ağ uzayında bükülme yönü × katsayı,
// w gövde ekseninin ağ uzayındaki x'i (kanat kökü)
instance uniform vec4 flex = vec4(0.0);

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
	ln = NORMAL;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// yük altında kanat ucu kalkar: kökten uzaklığın karesiyle (desen lp'de sabit kalır)
	if (flex.x != 0.0 || flex.y != 0.0 || flex.z != 0.0) {
		float d = min(abs(VERTEX.x - flex.w), 12.0);
		VERTEX += flex.xyz * d * d;
	}
}

void fragment() {
	vec3 nl = normalize(ln);
	float upn = dot(nl, normalize(up_m));     // +1 üst yüzey, -1 alt yüzey (uçağa göre)
	float fwdn = dot(nl, normalize(fwd_m));   // +1 rüzgara bakan (hücum kenarı, burun)
	vec3 c = color1;
	if (scheme == 1) {
		// sol-sağ simetrik (gerçek uçaklardaki gibi) ve her parçada leke görünecek sıklıkta
		vec3 q = vec3(abs(lp.x), lp.y, lp.z) + vec3(0.0, 0.0, 3.7);
		float n = noise(q * 0.8) * 0.65 + noise(q * 1.9) * 0.35;
		c = n > 0.6 ? color3 : (n > 0.43 ? color2 : color1);
	} else if (scheme == 2) {
		// üst beyaz (color1), alt renk (color2), ortada ince şerit (color3)
		c = upn < -0.35 ? color2 : color1;
		if (abs(lp.y + 0.05) < 0.07 && abs(upn) < 0.6) {
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
		// eskidikçe paneller yamalı görünür (farklı zamanlarda rötuşlanmış boya)
		c *= 0.965 + hash(cell) * (0.07 + 0.16 * wear) - 0.06 * wear * step(0.8, hash(cell + vec3(3.0)));
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
	// kir / yıpranma: düşük frekanslı lekeler ve hava akışı yönünde (geriye) akıntı izleri;
	// uçak eskidikçe (wear) hepsi belirginleşir
	float grime = noise(lp * vec3(0.9, 0.9, 0.25)) * noise(lp * 2.7 + vec3(11.0));
	float streak = noise(vec3(lp.x * 9.0, lp.y * 9.0, lp.z * 0.35)) * smoothstep(-0.2, -0.8, upn);
	c *= 1.0 - grime * (0.12 + 0.45 * wear) - streak * (0.08 + 0.22 * wear);
	// kir akıntısı: her yüzeyde akış yönünde (geriye) uzayan ince koyu izler
	float runs = smoothstep(0.55, 0.85, noise(vec3(lp.x * 11.0, lp.y * 11.0, lp.z * 0.6))) * smoothstep(0.4, 0.9, noise(lp * 0.7 + vec3(5.0)));
	c *= 1.0 - runs * 0.3 * wear;
	// alt yüzeyde yağ / hidrolik akıntısı: kahverengimsi, geriye uzayan lekeler
	float oil = smoothstep(0.55, 0.8, noise(vec3(lp.x * 5.0, lp.y * 5.0, lp.z * 0.5) + vec3(4.0))) * smoothstep(-0.1, -0.7, upn);
	c = mix(c, vec3(0.13, 0.1, 0.07), oil * wear * 0.55);
	// güneşte solma: üst yüzeyler eskidikçe soluklaşır
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(lum) * 1.06, wear * 0.35 * smoothstep(0.1, 0.9, upn));
	// boya atması: rüzgara bakan kenarlarda (hücum kenarı, burun) ve seyrek çiziklerde çıplak alüminyum
	float cn = noise(lp * 16.0) * 0.6 + noise(lp * 43.0) * 0.4;
	float edge = smoothstep(0.35, 0.95, fwdn);
	// sürtünme / çizik: üst yüzeyde (bakım ekibinin bastığı yerler) ve her yerde seyrek
	float scuff = step(cn, wear * (0.1 + 0.12 * smoothstep(0.5, 0.95, upn)));
	float chip = max(step(cn, edge * wear * 0.85), scuff) * (1.0 - lines);
	// is: motor lülesi ve namlu çevresi kararır (kaynağa yakın daha koyu, lekeli)
	float sd = length(lp - soot_src.xyz) / max(soot_r, 0.001);
	float soot = clamp(soot_src.w * exp(-sd * sd * 1.6) * (0.65 + 0.35 * noise(lp * 3.1)), 0.0, 0.9);
	c = mix(c, vec3(0.5, 0.51, 0.53), chip);
	c = mix(c, vec3(0.045, 0.04, 0.035), soot);
	// panel derzlerinde kir birikir
	float line_dirt = lines * (0.35 + 0.4 * wear);
	ALBEDO = c * (1.0 - line_dirt - hatch * 0.3) + vec3(rivet * 0.03);
	// normal: ağ sarımına güvenme (ters sarımlı gövde tüplerinde Godot normali içe çeviriyordu →
	// gövde koyu mavi görünüyordu). Gerçek dış normali al; arkadan bakılıyorsa (iç yüz) çevir.
	vec3 nv = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	bool inside = dot(nv, VIEW) < 0.0;
	NORMAL = inside ? -nv : nv;
	// kabuğun iç yüzü (kokpitten ya da açık gövdeden görünür): boya değil koyu iç astar
	if (inside) {
		ALBEDO = vec3(0.13, 0.135, 0.14);
	} else if (stress_glow.a > 0.0) {
		ALBEDO = mix(ALBEDO, stress_glow.rgb, stress_glow.a * 0.55);
		EMISSION = stress_glow.rgb * stress_glow.a * 1.2;
	}
	// boya metal değil: düşük metallik, ince vernik (aksi halde gökyüzünü ayna gibi yansıtıp deseni siliyordu)
	METALLIC = 0.06 + rivet * 0.5 + chip * 0.75;
	ROUGHNESS = clamp(0.58 + lines * 0.15 + grime * 0.15 - rivet * 0.25 + wear * 0.12 + soot * 0.3 - chip * 0.3, 0.05, 1.0);
	CLEARCOAT = 0.12 * (1.0 - grime) * (1.0 - wear * 0.8) * (1.0 - soot);
	SPECULAR = 0.3;   // koyu boyada sığ açıda gökyüzü yansıması kanadı başka renk gösteriyordu
	CLEARCOAT_ROUGHNESS = 0.3;
}
