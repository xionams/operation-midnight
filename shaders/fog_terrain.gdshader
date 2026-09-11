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

	ALBEDO = mix(unexplored_color, base_color * brightness, known);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.0;
}
