shader_type spatial;
// Egzoz arkasındaki sıcak hava dalgalanması: arkadaki görüntüyü gürültüyle kırar.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
instance uniform float power = 1.0;

void fragment() {
	float t = UV.y;
	float edge = abs(dot(NORMAL, VIEW));
	vec2 n = texture(noise_tex, vec2(UV.x * 2.0, t * 2.5 - TIME * 3.0)).rg - 0.5;
	n += (texture(noise_tex, vec2(UV.x * 5.0 + 0.3, t * 6.0 - TIME * 7.0)).rg - 0.5) * 0.5;
	float strength = 0.018 * power * edge * (1.0 - t) * smoothstep(0.0, 0.08, t);
	ALBEDO = texture(screen_tex, SCREEN_UV + n * strength).rgb;
	ALPHA = smoothstep(0.0, 0.15, edge) * (1.0 - t) * clamp(power * 2.0, 0.0, 1.0);
}
