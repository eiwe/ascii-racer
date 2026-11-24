// Occluder with a see-through halo: the track's vertex-coloured material
// (same as its StandardMaterial3D: albedo tint x sRGB vertex colour, Burley
// diffuse, Schlick-GGX specular 0.5, roughness 1), plus a round opening that
// shows whatever this geometry hides of a target (the car) from the camera.
//
// A fragment is cut away when all of these hold:
//   - it is within halo_radius of the line from the target toward the camera
//     (a cylinder for orthographic cameras, the line to the eye otherwise),
//   - it is nearer the camera than a point halo_radius behind the target (the
//     target counts as a ball of that radius, so the hole is a full circle on
//     screen rather than cut flat at the target's depth),
//   - it is more than halo_margin above the target (so the surface the target
//     stands on is never cut: on top of a bridge nothing opens).
// Between halo_radius - halo_softness and halo_radius the cut is dithered with
// a pattern fixed to the target, and what is kept there (and a band of
// halo_softness / 2 just outside the hole) is darkened toward the inside: the
// hole is ringed by sparse, dim glyphs in ASCII rather than a hard cut, and
// reads as an opening even where what shows through looks like the occluder.
// halo_radius <= 0 turns it off. The parameters
// are global uniforms (project.godot [shader_globals]), so every occluder
// using this shader follows the same target; HaloOccluder sets them.
//
// Shadow passes must not use this material (the cut would follow the light's
// view): give occluders a separate shadow-only copy with a plain material.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

global uniform vec3 halo_target;
global uniform float halo_radius;
global uniform float halo_softness;
global uniform float halo_margin;
global uniform float halo_dither;

void vertex() {
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

// 4x4 ordered dither threshold (0..1) for an integer cell.
float bayer4(ivec2 c) {
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[(c.y & 3) * 4 + (c.x & 3)] + 0.5) / 16.0;
}

void fragment() {
	float shade = 1.0;
	if (halo_radius > 0.0) {
		vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 t = (VIEW_MATRIX * vec4(halo_target, 1.0)).xyz; // target in view space
		bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
		// Direction from the target toward the camera, in view space.
		vec3 to_cam = ortho ? vec3(0.0, 0.0, 1.0) : normalize(-t);
		vec3 d = VERTEX - t;
		float along = dot(d, to_cam); // > 0: nearer the camera than the target
		vec3 across = d - to_cam * along;
		float r = length(across);
		float outline = halo_radius + halo_softness * 0.5;
		if (along > -halo_radius && world.y > halo_target.y + halo_margin && r < outline) {
			float inner = halo_radius - halo_softness;
			if (r < inner) {
				discard;
			}
			if (r < halo_radius) {
				// Rim: keep fragments more often toward the outside edge. The pattern
				// is laid out across the view, anchored to the target, in halo_dither cells.
				float keep = (r - inner) / max(halo_softness, 1e-4);
				ivec2 cell = ivec2(floor(across.xy / halo_dither));
				if (keep < bayer4(cell)) {
					discard;
				}
			}
			shade = mix(0.3, 1.0, smoothstep(inner, outline, r));
		}
	}
	ALBEDO = albedo.rgb * COLOR.rgb * shade;
	METALLIC = metallic;
	SPECULAR = specular;
	ROUGHNESS = roughness;
}
