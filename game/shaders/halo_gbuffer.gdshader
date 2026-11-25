// G-buffer twin (see ascii/shaders/gbuffer_twin.gdshader) for occluders with
// the see-through halo, used only under the Compatibility renderer (the web
// build): the same output, with the same hole cut as halo_occluder.gdshader so
// the g-buffer sees through the bridge where the picture does. The cut below
// is a copy of that shader's (keep the two in step); the rim's darkening is
// colour only, so it is not needed here.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_back, depth_draw_opaque;

uniform float far_plane = 100.0;

global uniform vec3 halo_target;
global uniform float halo_radius;
global uniform float halo_softness;
global uniform float halo_margin;
global uniform float halo_dither;

float bayer4(ivec2 c) {
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[(c.y & 3) * 4 + (c.x & 3)] + 0.5) / 16.0;
}

void fragment() {
	if (halo_radius > 0.0) {
		vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 t = (VIEW_MATRIX * vec4(halo_target, 1.0)).xyz;
		bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
		vec3 to_cam = ortho ? vec3(0.0, 0.0, 1.0) : normalize(-t);
		vec3 d = VERTEX - t;
		float along = dot(d, to_cam);
		vec3 across = d - to_cam * along;
		float r = length(across);
		float outline = halo_radius + halo_softness * 0.5;
		if (along > -halo_radius && world.y > halo_target.y + halo_margin && r < outline) {
			float inner = halo_radius - halo_softness;
			if (r < inner) {
				discard;
			}
			if (r < halo_radius) {
				float keep = (r - inner) / max(halo_softness, 1e-4);
				ivec2 cell = ivec2(floor(across.xy / halo_dither));
				if (keep < bayer4(cell)) {
					discard;
				}
			}
		}
	}
	vec3 n = normalize(NORMAL);
	ALBEDO = vec3(n.xy * 0.5 + 0.5, clamp(-VERTEX.z / far_plane, 0.0, 0.9999));
}
