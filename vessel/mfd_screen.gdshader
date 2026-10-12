shader_type spatial;
// Kokpit MFD camı: SubViewport dokusu, hafif parlama (bloom için >1), tarama çizgileri,
// kenar kararması ve camın üstünde ince bir yansıma.
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D screen_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float brightness = 1.3;

void fragment() {
	vec3 c = texture(screen_tex, UV).rgb;
	float scan = 0.93 + 0.07 * sin(UV.y * 256.0 * 3.14159);
	vec2 d = UV - 0.5;
	float vig = 1.0 - dot(d, d) * 0.7;
	// camdaki çapraz yansıma şeridi
	float sheen = smoothstep(0.25, 0.0, abs(UV.x + UV.y * 0.6 - 0.45)) * 0.035;
	ALBEDO = c * brightness * scan * vig + vec3(0.012, 0.02, 0.02) + vec3(sheen);
}
