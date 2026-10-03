// Billboard pixel sprites for characters, plants and props.
// * Y-axis billboard in the vertex shader (stays upright under the tilted camera)
// * sprite-sheet frames, horizontal flip
// * alpha scissor (crisp edges), optional emission map (glowroots, lamps, Barnaby's moss)
// * stylised light: banded diffuse + a rim when lit from behind, so characters separate
//   from the background without losing their hand-made pixels.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert;

uniform sampler2D sheet : source_color, filter_nearest;
uniform sampler2D emit_sheet : source_color, filter_nearest;
uniform bool has_emit = false;
uniform vec2 frames = vec2(1.0, 1.0);      // columns, rows
instance uniform float frame = 0.0;
instance uniform bool flip = false;
uniform bool billboard = true;
uniform float emit_strength = 2.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float rim_strength = 0.65;
uniform float sway = 0.0;                  // plants: top sways in the cave draught
instance uniform float fade = 1.0;                  // dissolve for appear/disappear
uniform bool cuttable = true;

global uniform float world_time;
global uniform float glow_level;
global uniform vec2 wind;
global uniform float cut_amount;
global uniform float cut_z;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (sway > 0.0) {
		float h = clamp(UV.y < 0.5 ? 1.0 - UV.y * 2.0 : 0.0, 0.0, 1.0);
		float s = sin(world_time * 1.3 + origin.x * 0.7 + origin.z * 0.4) * sway;
		VERTEX.x += s * h * (1.0 - UV.y);
	}
	if (billboard) {
		// Rotate the quad around Y to face the camera (fixed-Y billboard).
		vec3 cam = (INV_VIEW_MATRIX[3].xyz);
		vec3 to_cam = cam - origin;
		to_cam.y = 0.0;
		to_cam = normalize(to_cam + vec3(0.0001));
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		vec3 world = origin + right * VERTEX.x * sc.x + vec3(0.0, 1.0, 0.0) * VERTEX.y * sc.y;
		MODELVIEW_MATRIX = VIEW_MATRIX;
		VERTEX = world;
		NORMAL = to_cam;
		MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX);
	}
	wpos = billboard ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (cuttable && cut_amount > 0.0 && origin.z > cut_z + 0.01) {
		float k = clamp(cut_amount * 1.8 - (origin.z - cut_z) * 0.035, 0.0, 1.0);
		if (billboard) {
			VERTEX.y -= k * k * 14.0;
		} else {
			VERTEX.y -= k * k * 14.0 / max(length(MODEL_MATRIX[1].xyz), 0.001);
		}
	}
}

void fragment() {
	vec2 uv = UV;
	if (flip) {
		uv.x = 1.0 - uv.x;
	}
	float col = mod(frame, frames.x);
	float row = floor(frame / frames.x);
	vec2 suv = (vec2(col, row) + uv) / frames;
	vec4 c = texture(sheet, suv);
	if (c.a < 0.5) {
		discard;
	}
	if (fade < 1.0 && hash2(floor(suv * vec2(textureSize(sheet, 0)))) > fade) {
		discard;
	}
	vec3 albedo = c.rgb * tint.rgb;
	albedo = mix(albedo, flash_color.rgb, flash_color.a);
	ALBEDO = albedo;
	if (has_emit) {
		// Weight by alpha: the importer's "fix alpha border" fills transparent texels' RGB.
		vec4 e = texture(emit_sheet, suv);
		EMISSION = e.rgb * e.a * emit_strength * (0.55 + 0.45 * glow_level);
	}
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.0);
}

void light() {
	// Banded diffuse: two steps keep the pixel art readable under coloured lights.
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	float band = wrap > 0.55 ? 1.0 : (wrap > 0.28 ? 0.62 : 0.38);
	vec3 l = LIGHT_COLOR * ATTENUATION / PI;
	// (The engine multiplies DIFFUSE_LIGHT by albedo after the light loop.)
	DIFFUSE_LIGHT += l * band;
	// Rim: lights behind the sprite outline it in their own colour (not albedo-tinted).
	float back = clamp(-ndl, 0.0, 1.0);
	SPECULAR_LIGHT += l * back * back * rim_strength * 0.25;
}
