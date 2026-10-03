// Undercroft field planes. One shader, three modes:
//   mode 0 = water: each cell filled from its floor up to the simulated level, with a moving
//            pixel surface line, flow foam and depth darkening.
//   mode 1 = gas:   soft coloured wisps from species fractions (sour = sickly yellow-green,
//            stale = grey-blue, damp = violet), animated, quantised to the 16 px/cell grid.
//   mode 2 = heat overlay: temperature colour map over everything.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D field_nearest : filter_nearest;   // per-cell data (exact)
uniform sampler2D field_linear : filter_linear;     // per-cell data (smooth)
uniform sampler2D mask : filter_nearest;            // a = 1 for open cells
uniform vec2 grid_size = vec2(48.0, 24.0);
uniform int mode = 0;
uniform float alpha_scale = 1.0;
uniform float strength = 1.0;

global uniform float world_time;

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

void fragment() {
	// UV (0,0) = top-left cell. Quantise to 16 px per cell to match the pixel art.
	vec2 cellf = UV * grid_size;
	vec2 q = (floor(cellf * 16.0) + 0.5) / 16.0;
	vec2 cell = floor(cellf);
	vec2 cuv = (cell + 0.5) / grid_size;
	float open = texture(mask, cuv).a;
	if (mode == 0) {
		if (open < 0.5) { discard; }
		float fill = clamp(texture(field_nearest, cuv).r, 0.0, 1.0);
		float above = texture(field_nearest, cuv - vec2(0.0, 1.0 / grid_size.y)).r;
		if (above > 0.05) { fill = 1.0; }
		float local_y = 1.0 - fract(q.y);           // 0 at cell floor, 1 at ceiling
		float wave = (noise(vec2(q.x * 3.0 + world_time * 0.8, world_time * 0.5)) - 0.5) * 0.12 * step(above, 0.05);
		if (fill < 0.02 || local_y > fill + wave) { discard; }
		float depth = clamp(cell.y / grid_size.y, 0.0, 1.0);
		vec3 deep = vec3(0.07, 0.18, 0.28);
		vec3 shallow = vec3(0.2, 0.45, 0.6);
		vec3 col = mix(shallow, deep, depth * 0.8 + (1.0 - fill) * 0.1);
		// Surface line.
		if (local_y > fill + wave - 0.08 && above < 0.05) { col = vec3(0.55, 0.82, 0.88); }
		float flow = texture(field_nearest, cuv).g;
		float foam = step(0.75, noise(q * 5.0 + vec2(0.0, -world_time * 3.0))) * clamp(flow * 20.0, 0.0, 1.0);
		col = mix(col, vec3(0.8, 0.92, 0.95), foam * 0.6);
		ALBEDO = col;
		ALPHA = 0.88 * alpha_scale;
	} else if (mode == 1) {
		if (open < 0.5) { discard; }
		vec4 g = texture(field_linear, UV);
		float sour = g.r;
		float stale = g.g;
		float damp = g.b;
		float total = sour + stale + damp;
		if (total < 0.004) { discard; }
		vec2 drift = vec2(world_time * 0.25, -world_time * 0.12);
		float n = noise(q * 0.9 + drift) * 0.6 + noise(q * 2.3 - drift * 1.7) * 0.4;
		vec3 col = (vec3(0.71, 0.72, 0.29) * sour + vec3(0.55, 0.59, 0.66) * stale + vec3(0.65, 0.55, 0.84) * damp) / max(total, 0.0001);
		float a = clamp(total * 2.2 * strength, 0.0, 0.85) * (0.45 + 0.75 * n);
		a = floor(a * 6.0) / 6.0;
		ALBEDO = col;
		ALPHA = a * alpha_scale;
	} else {
		vec4 h = texture(field_linear, UV);
		float t = h.r;     // 0 = -20 C, 1 = 120 C
		vec3 cold = vec3(0.15, 0.3, 0.75);
		vec3 mild = vec3(0.25, 0.6, 0.35);
		vec3 warm = vec3(0.95, 0.75, 0.2);
		vec3 hot = vec3(0.95, 0.25, 0.1);
		vec3 col = t < 0.28 ? mix(cold, mild, t / 0.28) : (t < 0.5 ? mix(mild, warm, (t - 0.28) / 0.22) : mix(warm, hot, clamp((t - 0.5) / 0.4, 0.0, 1.0)));
		// Contour stripes make bands readable without relying on colour alone.
		float band = step(0.5, fract(t * 10.0 + 0.02 * floor(q.x * 4.0)));
		ALBEDO = col * (0.85 + 0.15 * band);
		ALPHA = 0.55 * alpha_scale;
	}
}
