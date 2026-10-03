// The moment the camera passes through the ground: bands of strata sweep past the lens.
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 0.0;   // 0 = invisible, 1 = full
uniform float travel = 0.0;                          // scroll position of the strata
uniform vec3 c0 : source_color = vec3(0.29, 0.24, 0.2);
uniform vec3 c1 : source_color = vec3(0.42, 0.33, 0.26);
uniform vec3 c2 : source_color = vec3(0.2, 0.2, 0.25);
uniform vec3 c3 : source_color = vec3(0.13, 0.12, 0.15);

float hash(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void fragment() {
	vec2 px = floor(FRAGCOORD.xy / 6.0);
	float y = px.y * 6.0 / 720.0 + travel;
	float band = floor(y * 9.0);
	float jag = hash(band + floor(px.x / 5.0) * 0.13) * 0.06;
	float k = fract(y * 9.0 + jag);
	vec3 col = mix(c0, c1, step(0.5, hash(band)));
	col = mix(col, c2, step(0.8, k));
	col = mix(col, c3, step(0.93, k));
	// Edges of the wipe: ragged pixel fringe.
	float edge = smoothstep(0.0, 0.15, amount) * (1.0 - step(amount, hash(px.x * 0.37 + px.y * 0.11) * 0.25));
	COLOR = vec4(col, edge * amount);
}
