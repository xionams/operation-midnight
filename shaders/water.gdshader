shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// The sea. One pass, no textures, no screen reads: it has to run on the
// Compatibility renderer and on Android.
//
// Depth comes from the mesh rather than the depth buffer. main.gd builds
// the surface as a grid and bakes into COLOR:
//   r  depth under the surface, 0 at the waterline .. 1 at open sea
//   g  shore contact, 1 where the surface meets the beach
// so the shallows, the foam line and the transparency all follow the
// real seabed that Water.surface_height shapes, on every renderer.
//
// Fog of war is applied exactly as on the ground (fog_terrain.gdshader):
// the unexplored sea converges on the same near-black as unexplored land.

uniform sampler2D fog_tex : filter_linear;
uniform float map_size = 220.0;
uniform vec3 unexplored_color : source_color = vec3(0.017, 0.024, 0.014);
uniform float unexplored_brightness = 0.07;
// 0.45, where the terrain shader uses 0.34. Not a weaker fog - the same
// fog, corrected for what it is multiplying. Water's albedo is far
// darker than grass, so the identical multiplier that leaves explored
// land readable takes explored sea to near-black, and a player could not
// tell remembered ocean from unexplored void. Fog still hides units and
// still darkens; it simply no longer hides the map.
uniform float explored_brightness = 0.45;

// Lifted from (0.035, 0.105, 0.150) / (0.120, 0.330, 0.340). The old
// deep colour peaked at 0.15 in its brightest channel, so open sea under
// anything less than full visibility read as a flat void rather than as
// water - hulls, wakes and torpedo tracks all had to carry the frame on
// their own. Still unmistakably deep water, just no longer near-black.
uniform vec3 deep_color : source_color = vec3(0.055, 0.150, 0.215);
uniform vec3 shallow_color : source_color = vec3(0.155, 0.405, 0.410);
// A sky tint at grazing angles. Two dot products and a power - the
// cheapest thing that makes a flat plane read as a surface, which is
// what the sea was missing more than it was missing brightness.
uniform vec3 sky_tint : source_color = vec3(0.42, 0.58, 0.70);
uniform float sky_strength = 0.30;
uniform vec3 foam_color : source_color = vec3(0.86, 0.90, 0.88);
uniform float deep_alpha = 0.86;
uniform float shallow_alpha = 0.55;
uniform float wave_strength = 0.22;

const float EXPLORED_SHADE = 0.392;

varying vec3 world_position;
varying vec2 baked;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	baked = COLOR.rg;
}

// Cheap value noise for foam break-up.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Slope of a sum of travelling sines: the swell's normal, analytically.
vec2 swell_slope(vec2 p, float t) {
	vec2 s = vec2(0.0);
	vec2 d1 = normalize(vec2(1.0, 0.35));
	vec2 d2 = normalize(vec2(-0.45, 1.0));
	vec2 d3 = normalize(vec2(0.8, -0.7));
	s += d1 * cos(dot(d1, p) * 0.55 + t * 1.1) * 0.55;
	s += d2 * cos(dot(d2, p) * 0.9 - t * 1.4) * 0.35;
	s += d3 * cos(dot(d3, p) * 2.1 + t * 2.3) * 0.18;
	return s;
}

void fragment() {
	vec2 uv = (world_position.xz + map_size * 0.5) / map_size;
	float shade = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		shade = texture(fog_tex, uv).r;
	}
	float known = smoothstep(0.0, EXPLORED_SHADE, shade);
	float brightness = mix(unexplored_brightness, explored_brightness, known);
	brightness = mix(brightness, 1.0, smoothstep(EXPLORED_SHADE, 1.0, shade));

	float t = TIME;
	float depth = clamp(baked.r, 0.0, 1.0);
	float shore = clamp(baked.g, 0.0, 1.0);

	// Normal: swell, calmer in the shallows so the beach edge stays crisp.
	vec2 slope = swell_slope(world_position.xz, t) * wave_strength * (0.45 + 0.55 * depth);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, 0.85, depth));

	// Foam: a broken, breathing line where the sea meets the sand.
	float breath = 0.5 + 0.5 * sin(t * 1.2 + world_position.x * 0.15 + world_position.z * 0.1);
	float grain = noise(world_position.xz * 1.4 + vec2(t * 0.35, -t * 0.2));
	float foam = smoothstep(0.55 - 0.25 * breath, 0.95, shore) * smoothstep(0.35, 0.7, grain + shore * 0.4);
	water = mix(water, foam_color, foam * 0.85);

	// Grazing angles pick up the sky, straight-down angles do not, so the
	// sea gains a gradient across the frame instead of being one value.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	water = mix(water, sky_tint, fresnel * sky_strength * (1.0 - foam));

	ALBEDO = mix(unexplored_color, water * brightness, known);
	ROUGHNESS = mix(0.06, 0.4, foam);
	SPECULAR = 0.55 * known;
	METALLIC = 0.0;
	// See the seabed and a submerged hull through the shallows; open sea
	// and anything unexplored are opaque.
	float a = mix(shallow_alpha, deep_alpha, depth);
	a = max(a, foam);
	ALPHA = mix(1.0, a, known);
}
