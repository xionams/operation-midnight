shader_type spatial;
// Straight alpha blending, and LIT rather than unshaded.
//
// The first version used blend_mul, on the reasoning that soot takes
// light away from the ground rather than replacing it. It rendered every
// mark as a visible dark rectangle: the whole quad washed the terrain,
// not just the burn inside it. Whatever Godot's mul blending does with a
// fragment whose ALBEDO is white, it is not "leave the destination
// alone", so the transparent margin of every quad was still darkening.
//
// With blend_mix, alpha 0 draws nothing. That is unambiguous, and the
// cost of the change is only that a burn no longer takes the colour of
// whatever it lies on.
//
// Lit, so the mark is shaded by the same sun as the ground around it -
// unshaded soot stays bright inside a building's shadow and floats.
// depth_draw_never keeps it from fighting the ground plane it lies on.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D mark_tex : source_color, filter_linear_mipmap;

// The same visibility grid the terrain reads. A scorch mark is evidence
// that something happened, so it must obey fog exactly as the thing that
// made it does - otherwise a burn glimpsed through the shroud reports a
// battle the player has not earned the right to know about.
uniform sampler2D fog_tex : filter_linear;
uniform float map_size = 220.0;

const float EXPLORED_SHADE = 0.392; // 100/255

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 mark = texture(mark_tex, UV);

	vec2 fog_uv = (world_position.xz + map_size * 0.5) / map_size;
	float shade = 0.0;
	if (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 && fog_uv.y >= 0.0 && fog_uv.y <= 1.0) {
		shade = texture(fog_tex, fog_uv).r;
	}
	// Full strength only where currently watched; remembered ground keeps
	// a trace, matching how the terrain itself dims behind the shroud.
	float known = smoothstep(0.0, EXPLORED_SHADE, shade);
	float lit = mix(0.45, 1.0, smoothstep(EXPLORED_SHADE, 1.0, shade));

	ALBEDO = mark.rgb;
	ALPHA = mark.a * known * lit;
	// Soot is matt. Without this the mark picks up a specular sheen the
	// surrounding terrain does not have, and reads as a wet patch.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
