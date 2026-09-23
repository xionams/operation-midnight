shader_type spatial;

// Strategic visibility fog, not atmospheric fog. The whole effect is one
// texture lookup per fragment against the same low-resolution grid the
// gameplay uses, so what the player sees and what the rules allow can
// never drift apart.
//
// The fog texture stores three states as luminance:
//   0.0   never seen        - near black, terrain unreadable
//   0.39  seen before       - dark, terrain remembered
//   1.0   currently watched - full brightness
//
// Linear filtering across 2m cells is what softens the boundary, so the
// reveal has a gradient edge instead of hard circles, at no extra cost.

uniform sampler2D fog_tex : filter_linear;
uniform float map_size = 220.0;
uniform vec3 base_color : source_color = vec3(0.24, 0.34, 0.2);
uniform float unexplored_brightness = 0.07;
// Every unexplored surface resolves to this ONE colour rather than to a
// dimmed version of its own. Scaling each surface by a brightness factor
// keeps their relative differences, so a light concrete road stayed
// visibly brighter than dark terrain and drew the whole road network
// through the shroud. Converging on a shared colour is what actually
// hides a thing.
uniform vec3 unexplored_color : source_color = vec3(0.017, 0.024, 0.014);
uniform float explored_brightness = 0.34;
uniform float roughness_value = 0.9;

// --- Ground surfacing -------------------------------------------------
//
// This shader paints the battlefield AND every piece of flat scenery
// (pads, roads) from the same fog source. Only the battlefield wants a
// texture, so the samplers default to white and `textured` gates them:
// a scenery material that sets neither is shaded exactly as before.
//
// Two scales, because one cannot work. Tiled small a texture visibly
// repeats; tiled large it is mush. `macro_tex` carries where the ground
// CHANGES - grass into dry patch into worn dirt - at ~96m, and
// `detail_tex` carries grain at ~8m for the close zoom.
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float textured = 0.0;
uniform float macro_scale = 96.0;
uniform float detail_scale = 8.0;
uniform float normal_strength = 0.7;

const float EXPLORED_SHADE = 0.392; // 100/255

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_position.xz + map_size * 0.5) / map_size;

	float shade;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		// The visual skirt beyond the playable area is never "known".
		shade = 0.0;
	} else {
		shade = texture(fog_tex, uv).r;
	}

	float known = smoothstep(0.0, EXPLORED_SHADE, shade);
	float brightness = mix(unexplored_brightness, explored_brightness, known);
	brightness = mix(brightness, 1.0,
		smoothstep(EXPLORED_SHADE, 1.0, shade));

	vec3 surface = base_color;
	float grain = 0.5;
	if (textured > 0.5) {
		// base_color, macro and grain COMPOSE, which is what lets one
		// shader serve both jobs. The battlefield sets base_color white
		// and lets macro_tex carry the terrain colours; a concrete pad
		// keeps its own base_color, leaves macro_tex at its default white
		// and sets only the detail sheet. Neither case special-cases the
		// other.
		vec3 macro = texture(macro_tex, world_position.xz / macro_scale).rgb;
		grain = texture(detail_tex, world_position.xz / detail_scale).r;
		surface = base_color * macro * (0.55 + 0.9 * grain);
		NORMAL_MAP = texture(normal_tex, world_position.xz / detail_scale).rgb;
		// Fade the relief out with visibility. A normal map picked out by
		// the sun inside the shroud would draw terrain the player has not
		// earned the right to see, which is the whole point of the fog.
		NORMAL_MAP_DEPTH = normal_strength * known;
	}

	ALBEDO = mix(unexplored_color, surface * brightness, known);
	// Rougher in the hollows, tighter on the high grain, so the sun does
	// not sheet off the whole plane at one angle.
	ROUGHNESS = clamp(roughness_value - 0.18 * (grain - 0.5), 0.0, 1.0);
	SPECULAR = 0.0;
}
