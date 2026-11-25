// G-buffer twin for the Compatibility renderer (the web build), which has no
// normal buffer for gbuffer.gdshader to read. Every visible mesh gets a twin
// with this material on AsciiRenderer.GBUFFER_LAYER, seen only by the g-buffer
// camera; it writes the same thing the Forward+ quad does, straight from the
// geometry:
//   R, G = view-space normal x, y (packed *0.5+0.5)
//   B    = linear view depth / far_plane (the camera's clear colour gives 1.0)
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_back, depth_draw_opaque;

uniform float far_plane = 100.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	ALBEDO = vec3(n.xy * 0.5 + 0.5, clamp(-VERTEX.z / far_plane, 0.0, 0.9999));
}
