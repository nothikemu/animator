// Still underground water: dark, deep, pixel-quantised ripples that catch the glow.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx, depth_draw_always;

uniform vec3 deep_color : source_color = vec3(0.05, 0.11, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.36, 0.45);
uniform vec3 glint_color : source_color = vec3(0.34, 0.88, 0.83);
uniform float alpha = 0.86;
uniform float pixel = 16.0;

global uniform float world_time;
global uniform float glow_level;
global uniform float cut_amount;
global uniform float cut_z;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (cut_amount > 0.0 && wpos.z > cut_z + 0.01) {
		VERTEX.y -= clamp(cut_amount * 1.8 - (wpos.z - cut_z) * 0.035, 0.0, 1.0) * 6.0;
	}
}

void fragment() {
	if (cut_amount > 0.0 && wpos.z > cut_z + 0.01 && hash2(floor(wpos.xz * 4.0)) < cut_amount * 1.4) {
		discard;
	}
	// Quantise to the world pixel grid so the water matches the pixel art.
	vec2 q = floor(UV * pixel) / pixel;
	float t = world_time * 0.35;
	float n = noise(q * 1.7 + vec2(t, t * 0.6)) * 0.6 + noise(q * 4.3 - vec2(t * 0.8, t * 0.3)) * 0.4;
	float band = floor(n * 4.0) / 4.0;
	vec3 col = mix(deep_color, shallow_color, band * 0.55);
	// Sparse glints of reflected bioluminescence.
	float g = step(0.93, noise(q * 6.0 + vec2(-t * 1.3, t)));
	col += glint_color * g * 0.6 * glow_level;
	// Shore foam from vertex colour alpha.
	float foam = COLOR.a * step(0.6, noise(q * 5.0 + t)) * 0.35;
	col = mix(col, vec3(0.55, 0.7, 0.68), foam);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	SPECULAR = 0.65;
	METALLIC = 0.0;
	EMISSION = glint_color * g * 0.5 * glow_level;
}
