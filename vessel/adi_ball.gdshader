shader_type spatial;
// Yedek yapay ufuk (ADI) küresi: üst yarı gök, alt yarı yer, beyaz ufuk çizgisi ve
// pilota bakan tarafta 10° aralıklı yunuslama çizgileri. Küre, ufka göre döndürülür.

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(lp);
	float lat = degrees(asin(clamp(n.y, -1.0, 1.0)));
	float lon = degrees(atan(n.x, n.z));      // 0: pilota bakan taraf (+z)
	vec3 col = n.y > 0.0 ? vec3(0.13, 0.42, 0.8) : vec3(0.42, 0.26, 0.11);
	float horizon = 1.0 - smoothstep(0.6, 1.4, abs(lat));
	float m = mod(lat + 5.0, 10.0) - 5.0;
	float ladder = (1.0 - smoothstep(0.35, 0.8, abs(m))) * step(abs(lon), 14.0 + step(abs(abs(lat) - 30.0), 1.0) * 6.0) * step(4.0, abs(lat));
	col = mix(col, vec3(0.95), max(horizon, ladder));
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	EMISSION = col * 0.15;
}
