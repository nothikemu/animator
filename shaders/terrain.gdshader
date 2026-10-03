// Terrain / prop blocks: pixel-art atlas, vertex-colour AO, emissive glints,
// and the cut: everything in front of the cut line sinks and crumbles away.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D atlas_emit : source_color, filter_nearest;
uniform float emit_strength = 2.4;
uniform bool cuttable = true;
instance uniform float fade = 1.0;

global uniform float cut_amount;
global uniform float cut_z;
global uniform float glow_level;

varying vec3 wpos;
varying float sink;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sink = 0.0;
	if (cuttable && cut_amount > 0.0 && wpos.z > cut_z + 0.01) {
		// Ground nearer the cut goes first; the far foreground follows.
		float d = wpos.z - cut_z;
		float k = clamp(cut_amount * 1.8 - d * 0.035, 0.0, 1.0);
		sink = k;
		VERTEX.y -= k * k * 14.0;
	}
}

void fragment() {
	if (cuttable && cut_amount > 0.0 && wpos.z > cut_z + 0.01) {
		float n = hash2(floor(wpos.xz * 4.0));
		if (n < sink * 1.15) {
			discard;
		}
	}
	if (fade < 0.999) {
		// Ordered-dither dissolve (roofs and front walls of the cutaway house).
		vec2 sp = floor(FRAGCOORD.xy / 2.0);
		float d = fract(sin(dot(sp, vec2(12.9898, 78.233))) * 43758.5453);
		if (d > fade) {
			discard;
		}
	}
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = 0.94;
	SPECULAR = 0.25;
	vec3 e = texture(atlas_emit, UV).rgb;
	EMISSION = e * emit_strength * (0.6 + 0.4 * glow_level);
}
