// Full-screen quad drawn only by the GBuffer camera. Exports, as colour into a
// float (use_hdr_2d) target:
//   R, G = view-space normal x, y (packed *0.5+0.5; z is reconstructed, >= 0)
//   B    = linear view depth / far_plane, exactly 1.0 where nothing was drawn.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform float far_plane = 100.0;

void vertex() {
	// Godot 4.3+ reversed-Z: the near plane is at clip z = 1.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float raw = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float lin = -view.z / view.w;
	vec3 n = texture(normal_tex, SCREEN_UV).xyz * 2.0 - 1.0;
	n = normalize(n);
	// raw == 0 is the far plane in reversed-Z: background.
	float d = raw <= 0.0 ? 1.0 : clamp(lin / far_plane, 0.0, 0.9999);
	ALBEDO = vec3(n.xy * 0.5 + 0.5, d);
}
