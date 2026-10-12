shader_type spatial;
// Kasaba binası cephesi: kat (3.2 m) ve pencere aralığı (3.4 m) örnek ölçekten hesaplanır,
// her binada pencereler kat kat dizilir. Duvar rengi örnek renginden; gece rastgele pencereler yanar.

uniform float night = 0.0;
varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 scl;
varying vec3 wall_col;
varying float rnd;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wall_col = COLOR.rgb;
	rnd = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
}

void fragment() {
	bool side = abs(local_normal.y) < 0.5;
	float along_m = abs(local_normal.x) > 0.5 ? (local_pos.z + 0.5) * scl.z : (local_pos.x + 0.5) * scl.x;
	float up_m = (local_pos.y + 0.5) * scl.y;
	float bay = fract(along_m / 3.4);
	float floor_f = fract(up_m / 3.2);
	float fl = floor(up_m / 3.2);
	float win = step(0.25, bay) * step(bay, 0.75) * step(0.3, floor_f) * step(floor_f, 0.78);
	// zemin katta kapı\/vitrin gibi daha geniş; en üstte parapet
	win *= step(0.6, up_m) * step(up_m, scl.y - 0.5);
	win = side ? win : 0.0;
	float lit = step(0.55, fract(rnd * 13.0 + floor(along_m / 3.4) * 0.37 + fl * 0.71));
	vec3 wall = wall_col * (0.92 + 0.08 * step(0.5, fract(fl * 0.5)));
	// kat arası silme çizgisi
	float band = side ? (1.0 - smoothstep(0.0, 0.06, abs(floor_f - 0.02))) * 0.15 : 0.0;
	vec3 roof_col = vec3(0.32, 0.3, 0.28);
	vec3 c = side ? mix(wall * (1.0 - band), vec3(0.1, 0.13, 0.16), win * 0.85) : roof_col;
	ALBEDO = c;
	ROUGHNESS = mix(0.88, 0.15, win);
	METALLIC = win * 0.3;
	EMISSION = vec3(1.0, 0.75, 0.42) * win * lit * night * 2.6;
}
