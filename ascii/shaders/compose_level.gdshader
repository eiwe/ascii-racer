// Compose pass for the phone's level display (AsciiRenderer.level_max > 0):
// the world's cells form an over-sized grid (margin cells on every side of
// the visible one), shown rotated about the screen centre so the world stays
// level while the phone rolls; the overlay cells (lights, HUD, menus) stay
// aligned with the screen. Used only while the level display is on; the
// normal path is compose.gdshader with the overlay merged in the cell pass.
//
// At rot = (1, 0) every pixel is the same as compose.gdshader with the overlay
// merged in cells.gdshader: world cell c + margin is visible cell c, glyphs are
// sampled at texel centres, and the overlay's cover and glyphs apply per cell
// as overlay_cell() does there.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D cell_tex : filter_nearest, repeat_disable; // world cells (wgrid)
uniform sampler2D atlas_tex : filter_linear, repeat_disable; // linear: rotated glyphs
uniform sampler2D overlay_tex : filter_nearest, repeat_disable; // visible cells (grid)
uniform bool overlay_on = false;
uniform ivec2 grid = ivec2(1, 1); // visible cells
uniform ivec2 wgrid = ivec2(1, 1); // world cells
uniform ivec2 margin = ivec2(0, 0); // world cells left / above the visible grid
uniform ivec2 pitch = ivec2(8, 16);
uniform ivec2 box = ivec2(8, 16);
uniform int atlas_cols = 16;
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform vec2 out_size = vec2(1600.0, 900.0);
uniform vec2 rot = vec2(1.0, 0.0); // cos, sin of the display angle

// Overlay texels of a visible cell (zero outside the grid or with the overlay off).
vec4 ov_ink(ivec2 v) {
	if (!overlay_on || v.x < 0 || v.y < 0 || v.x >= grid.x || v.y >= grid.y) {
		return vec4(0.0);
	}
	return texelFetch(overlay_tex, ivec2(v.x * 2, v.y), 0);
}

vec4 ov_bg(ivec2 v) {
	if (!overlay_on || v.x < 0 || v.y < 0 || v.x >= grid.x || v.y >= grid.y) {
		return vec4(0.0);
	}
	return texelFetch(overlay_tex, ivec2(v.x * 2 + 1, v.y), 0);
}

void fragment() {
	ivec2 p = ivec2(floor(UV * out_size));
	vec2 centre = out_size * 0.5;
	vec2 off = vec2(margin * pitch);
	// The world point shown at this pixel (screen offset turned by -angle).
	vec2 d = vec2(p) + 0.5 - centre;
	vec2 q = centre + off + vec2(rot.x * d.x - rot.y * d.y, rot.y * d.x + rot.x * d.y);
	ivec2 wbase = ivec2(floor(q / vec2(pitch)));
	ivec2 lead = (box - pitch) / 2;
	vec3 ink = vec3(0.0);
	float cov_max = 0.0;
	// World glyphs, rotated. A glyph whose cell centre lands in a visible cell
	// with an overlay glyph or full cover is replaced; partial cover dims it.
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 c = wbase + ivec2(dx, dy);
			if (c.x < 0 || c.y < 0 || c.x >= wgrid.x || c.y >= wgrid.y) {
				continue;
			}
			vec2 local = q - vec2(c * pitch - lead);
			if (local.x < 0.0 || local.y < 0.0 || local.x >= float(box.x) || local.y >= float(box.y)) {
				continue;
			}
			vec4 cd = texelFetch(cell_tex, ivec2(c.x * 2, c.y), 0);
			int idx = int(cd.a * 255.0 + 0.5);
			if (idx == 0) {
				continue;
			}
			vec3 cink = cd.rgb;
			if (overlay_on) {
				vec2 wc = (vec2(c) + 0.5) * vec2(pitch) - off - centre;
				vec2 sc = centre + vec2(rot.x * wc.x + rot.y * wc.y, -rot.y * wc.x + rot.x * wc.y);
				ivec2 v = ivec2(floor(sc / vec2(pitch)));
				float cover = ov_bg(v).a;
				if (cover >= 0.999 || int(ov_ink(v).a * 255.0 + 0.5) > 0) {
					continue;
				}
				cink *= 1.0 - cover;
			}
			vec2 org = vec2(ivec2(idx % atlas_cols, idx / atlas_cols) * box);
			// Linear between texels; exactly the texel at angle 0 (local is then on texel centres).
			vec2 lc = clamp(local, vec2(0.5), vec2(box) - 0.5);
			float cov = texture(atlas_tex, (org + lc) / atlas_size).r;
			ink = max(ink, cink * cov);
			cov_max = max(cov_max, cov);
		}
	}
	vec3 bg = vec3(0.0);
	if (wbase.x >= 0 && wbase.y >= 0 && wbase.x < wgrid.x && wbase.y < wgrid.y) {
		bg = texelFetch(cell_tex, ivec2(wbase.x * 2 + 1, wbase.y), 0).rgb;
	}
	// Overlay, screen-aligned: cover on the background of this pixel's cell,
	// then its glyphs (up to 3 x 3 boxes, as in compose.gdshader).
	if (overlay_on) {
		ivec2 base = p / pitch;
		vec4 ob = ov_bg(base);
		bg = mix(bg, ob.rgb, ob.a);
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				ivec2 v = base + ivec2(dx, dy);
				ivec2 local = p - (v * pitch - lead);
				if (local.x < 0 || local.y < 0 || local.x >= box.x || local.y >= box.y) {
					continue;
				}
				vec4 oi = ov_ink(v);
				int og = int(oi.a * 255.0 + 0.5) - 1; // the overlay stores glyph + 1
				if (og <= 0) {
					continue;
				}
				ivec2 org = ivec2(og % atlas_cols, og / atlas_cols) * box;
				float cov = texelFetch(atlas_tex, org + local, 0).r;
				ink = max(ink, oi.rgb * cov);
				cov_max = max(cov_max, cov);
			}
		}
	}
	COLOR = vec4(bg * (1.0 - cov_max) + ink, 1.0);
}
