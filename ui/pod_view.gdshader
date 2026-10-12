shader_type canvas_item;
// Hedefleme podu görüntüsü: 0 TV, 1 IR beyaz-sıcak, 2 IR siyah-sıcak, 3 gece görüşü.
uniform int mode = 0;
uniform float time = 0.0;

float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + time * 37.0) * 43758.5453); }

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 o;
	if (mode == 0) {
		// TV: hafif soluk, keskin kontrast
		o = mix(vec3(l), c, 0.55);
		o = (o - 0.5) * 1.15 + 0.5;
	} else if (mode == 1 || mode == 2) {
		// IR: parlaklık ısı gibi; gökyüzü soğuk, zemin ılık, kontrast eğrisi
		float h = smoothstep(0.05, 0.85, l * 0.8 + (1.0 - UV.y) * 0.0);
		h = pow(h, 1.3);
		if (mode == 2) h = 1.0 - h;
		o = vec3(h) * 0.92 + 0.04;
		o += (rnd(UV * 400.0) - 0.5) * 0.03;
	} else {
		// gece görüşü: yüksek kazanç, yeşil fosfor, gren, kenar kararması
		float g = clamp(l * 3.2, 0.0, 1.0);
		g += (rnd(UV * 300.0) - 0.5) * 0.18;
		o = vec3(0.25, 1.0, 0.35) * g;
		float vig = 1.0 - smoothstep(0.35, 0.75, length(UV - 0.5));
		o *= vig;
	}
	// tarama çizgileri
	o *= 0.94 + 0.06 * step(0.5, fract(UV.y * 180.0));
	COLOR = vec4(o, 1.0);
}
