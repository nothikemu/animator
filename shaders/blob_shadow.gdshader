// Soft, pixel-stepped contact shadow under characters and props.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float strength = 0.55;
global uniform float cut_amount;
global uniform float cut_z;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = (1.0 - smoothstep(0.35, 1.0, d)) * strength;
	a = floor(a * 4.0) / 4.0;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (cut_amount > 0.0 && wp.z > cut_z + 0.01) {
		discard;
	}
	ALBEDO = vec3(0.03, 0.02, 0.06);
	ALPHA = a;
}
