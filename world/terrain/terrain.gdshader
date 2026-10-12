shader_type spatial;
render_mode cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 planet_center = vec3(0.0, -600000.0, 0.0);
uniform vec3 planet_axis = vec3(0.0, 0.42, -0.9);
// Hava durumu: yağmurda zemin koyulaşır ve parlar
uniform float wetness = 0.0;
uniform float snow_line = 1350.0;

varying vec3 planet_pos;     // gezegen merkezine göre konum
varying float height;        // deniz seviyesinden yükseklik (m)
varying float slope;         // 0 düz, 1 dikey
varying float forest;

vec3 srgb(vec3 c) { return pow(c, vec3(2.2)); }

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Tarla deseni: yerel teğet düzlemde döndürülmüş ızgara; her hücre bir ürün, aralarda çit,
// içinde ekin sıraları. Döndürüp: alan, renk, sınır payı
vec4 fields(vec3 p, vec3 up) {
	// yüzey koordinatı: oyun bölgesinde yukarı ≈ +y, gezegen merkezli x/z yeterli teğet koordinat
	// (p yukarıyla aynı doğrultuda olduğundan teğet eksenlerle iz düşümü sıfır olurdu)
	vec2 q = p.xz;
	// bölgesel yön: büyük ölçekte tarla blokları farklı açılarda
	vec2 region = floor(q / 1400.0);
	float ang = (hash21(region) - 0.5) * 1.2;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 r = rot * q;
	vec2 size = vec2(160.0 + hash21(region + 3.1) * 140.0, 90.0 + hash21(region + 7.7) * 80.0);
	vec2 cell = floor(r / size);
	vec2 f = fract(r / size);
	float crop = hash21(cell + region * 17.0);
	vec3 c;
	if (crop < 0.28) c = vec3(0.70, 0.62, 0.30);       // olgun buğday
	else if (crop < 0.5) c = vec3(0.36, 0.48, 0.18);   // yeşil ekin
	else if (crop < 0.66) c = vec3(0.42, 0.33, 0.22);  // sürülmüş toprak
	else if (crop < 0.82) c = vec3(0.52, 0.58, 0.26);  // açık yeşil / çayır
	else c = vec3(0.60, 0.55, 0.32);                     // anız
	// ekin sıraları (hücre içinde tek yönde)
	float rows = 0.5 + 0.5 * sin(r.x * 1.9 + crop * 30.0);
	c *= 0.9 + rows * 0.12 * step(0.5, fract(crop * 7.0));
	// çit / sınır: hücre kenarına yakın koyu, ince şerit
	vec2 edge = min(f, 1.0 - f) * size;
	float hedge = 1.0 - smoothstep(1.5, 4.0, min(edge.x, edge.y));
	return vec4(srgb(c), hedge);
}

// Gezegen üzerinde dikiş yapmayan doku örneklemesi (triplanar)
float tri(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise_tex, p.yz / scale).r * w.x
		+ texture(noise_tex, p.xz / scale).r * w.y
		+ texture(noise_tex, p.xy / scale).r * w.z;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_pos = world - planet_center;
	height = UV2.x;
	slope = UV2.y;
	forest = COLOR.r;
}

void fragment() {
	vec3 up = normalize(planet_pos);
	vec3 p = planet_pos;
	float n1 = tri(p, up, 2048.0);
	float n2 = tri(p, up, 256.0);
	float n3 = tri(p, up, 32.0);
	float n4 = tri(p, up, 8.0);
	float h = height;

	vec3 grass_a = srgb(vec3(0.33, 0.46, 0.19));
	vec3 grass_b = srgb(vec3(0.45, 0.50, 0.24));
	vec3 dry = srgb(vec3(0.58, 0.53, 0.33));
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	col = mix(col, dry, smoothstep(0.55, 0.75, n2 * 0.6 + n1 * 0.4) * 0.6);

	// iklim: ekvatordan uzaklaştıkça daha soğuk ve yeşil-kahve, kutuplarda kar
	float lat = abs(dot(up, planet_axis));
	col = mix(col, srgb(vec3(0.62, 0.55, 0.36)), smoothstep(0.15, 0.0, lat) * 0.5);

	// tarım alanları: düz, alçak, ormansız, bölgesel gürültüyle kümelenmiş
	float farm = smoothstep(0.16, 0.06, slope) * smoothstep(3.0, 12.0, h) * (1.0 - smoothstep(300.0, 500.0, h));
	farm *= smoothstep(0.3, 0.45, n1) * (1.0 - smoothstep(0.1, 0.4, forest));
	if (farm > 0.01) {
		vec4 fc = fields(p, up);
		vec3 fcol = mix(fc.rgb, srgb(vec3(0.17, 0.25, 0.11)), fc.a * 0.8);
		col = mix(col, fcol, farm * 0.85);
	}
	vec3 forest_col = srgb(vec3(0.20, 0.30, 0.14));
	col = mix(col, forest_col, smoothstep(0.1, 0.5, forest + (n2 - 0.5) * 0.35) * 0.7);

	vec3 sand = srgb(vec3(0.78, 0.72, 0.55));
	col = mix(sand, col, smoothstep(1.5, 5.0, h + (n3 - 0.5) * 3.0));

	vec3 rock = srgb(mix(vec3(0.42, 0.40, 0.37), vec3(0.55, 0.52, 0.48), n2));
	float rock_amt = smoothstep(0.22, 0.4, slope + (n2 - 0.5) * 0.15);
	rock_amt = max(rock_amt, smoothstep(900.0, 1300.0, h + n1 * 300.0) * 0.8);
	col = mix(col, rock, rock_amt);

	vec3 snow = srgb(vec3(0.93, 0.95, 0.98));
	float line = snow_line - smoothstep(0.6, 0.9, lat) * 1500.0;
	float snow_amt = smoothstep(line, line + 150.0, h + (n1 - 0.5) * 400.0) * (1.0 - smoothstep(0.45, 0.7, slope));
	col = mix(col, snow, snow_amt);

	vec3 seabed = srgb(vec3(0.55, 0.52, 0.42));
	col = mix(col, seabed, smoothstep(0.0, -4.0, h));

	col *= 0.86 + 0.18 * n3 + 0.08 * (n4 - 0.5);
	col *= 1.0 - wetness * 0.35 * (1.0 - snow_amt);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.45, wetness * (1.0 - snow_amt)) - snow_amt * 0.3;
	SPECULAR = 0.3;
}
