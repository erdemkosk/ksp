shader_type spatial;
// Ev duvarı: gündüz düz sıva, gece rastgele pencereler sıcak ışıkla yanar.

uniform float night = 0.0;
varying vec3 local_pos;
varying vec3 local_normal;
varying float instance_rand;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	instance_rand = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
}

void fragment() {
	vec3 wall = vec3(0.70, 0.62, 0.50);
	float along = abs(local_normal.x) > 0.5 ? local_pos.z : local_pos.x;
	float side = abs(local_normal.y) > 0.5 ? 0.0 : 1.0;
	// iki pencere / cephe, yüksekliğin ortasında
	float wx = step(0.3, fract(along * 2.0 + 0.5)) * step(fract(along * 2.0 + 0.5), 0.7);
	float wy = step(0.35, local_pos.y) * step(local_pos.y, 0.7);
	float window = wx * wy * side;
	float lit = step(0.35, fract(instance_rand * 7.0 + floor(along * 2.0 + 0.5) * 0.37));
	ALBEDO = mix(wall, vec3(0.12, 0.14, 0.16), window * 0.8);
	ROUGHNESS = mix(0.9, 0.2, window);
	EMISSION = vec3(1.0, 0.72, 0.38) * window * lit * night * 3.0;
}
