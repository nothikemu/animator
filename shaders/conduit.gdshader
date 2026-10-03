// Pipes and wires in the cross-section. Flow is visible: bright pulses travel along a pipe
// that carries water, sparks along a powered wire. Damaged segments pulse red.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.61, 0.48, 0.24);
uniform vec3 flow_color : source_color = vec3(0.5, 0.85, 0.9);
instance uniform float flow = 0.0;          // 0..1 how much is moving
instance uniform float highlight = 0.0;     // overlay emphasis
uniform bool is_wire = false;

global uniform float world_time;

void fragment() {
	// UV.x runs along the segment chain (world distance), COLOR.r = damage (1 = burst).
	float damage = COLOR.r;
	vec3 col = base_color * (0.75 + 0.25 * COLOR.g);
	float pulse = step(0.82, fract(UV.x * (is_wire ? 2.0 : 1.2) - world_time * (is_wire ? 3.0 : 1.4)));
	vec3 emit = flow_color * pulse * flow * (is_wire ? 2.5 : 1.4);
	if (damage > 0.01) {
		float throb = 0.5 + 0.5 * sin(world_time * 6.0);
		col = mix(col, vec3(0.9, 0.2, 0.12), damage * 0.8);
		emit += vec3(0.9, 0.15, 0.08) * damage * throb * 0.9;
	}
	ALBEDO = col;
	EMISSION = emit + base_color * highlight * 0.6;
	ROUGHNESS = 0.45;
	METALLIC = 0.4;
}
