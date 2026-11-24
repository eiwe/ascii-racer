// Compose pass: for every output pixel, find the cells whose glyph boxes
// cover it (up to 3x3 when squeezed), fetch their slot data and the glyph
// atlas, and overprint them with per-channel max over the cell background.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D cell_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform ivec2 grid = ivec2(1, 1);
uniform ivec2 pitch = ivec2(8, 16);
uniform ivec2 box = ivec2(8, 16);
uniform int atlas_cols = 16;
uniform vec2 out_size = vec2(1600.0, 900.0);

void fragment() {
	ivec2 p = ivec2(floor(UV * out_size));
	ivec2 base = p / pitch;
	// Glyph box of cell c starts at c * pitch - lead (centred on the cell).
	ivec2 lead = (box - pitch) / 2;
	vec3 ink = vec3(0.0);
	float cov_max = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 c = base + ivec2(dx, dy);
			if (c.x < 0 || c.y < 0 || c.x >= grid.x || c.y >= grid.y) {
				continue;
			}
			ivec2 local = p - (c * pitch - lead);
			if (local.x < 0 || local.y < 0 || local.x >= box.x || local.y >= box.y) {
				continue;
			}
			for (int s = 0; s < 2; s++) {
				vec4 d = texelFetch(cell_tex, ivec2(c.x * 3 + s, c.y), 0);
				int idx = int(d.a * 255.0 + 0.5);
				if (idx == 0) {
					continue;
				}
				ivec2 org = ivec2(idx % atlas_cols, idx / atlas_cols) * box;
				float cov = texelFetch(atlas_tex, org + local, 0).r;
				ink = max(ink, d.rgb * cov);
				cov_max = max(cov_max, cov);
			}
		}
	}
	vec3 bg = vec3(0.0);
	if (base.x < grid.x && base.y < grid.y) {
		bg = texelFetch(cell_tex, ivec2(base.x * 3 + 2, base.y), 0).rgb;
	}
	COLOR = vec4(bg * (1.0 - cov_max) + ink, 1.0);
}
