// Cell pass. Drawn on a ColorRect exactly (grid.x * 2) x grid.y texels: one
// texel per cell per data slot, interleaved (cell x * 2 + slot).
//   slot 0: glyph       RGB = ink, A = glyph index / 255
//   slot 1: background  RGB = colour
// The glyph is chosen by shape: six sub-cell tones are matched against every
// candidate glyph's 2 x 3 ink distribution; flat cells use the tone ramp.
// Each cell maps to the scene/gbuffer textures by UV: cell (x, y) covers
// [x, x + 1] * pitch_uv horizontally and likewise vertically.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D gbuf_tex : filter_nearest, repeat_disable;
// n x 2 RGBAF: row 0 = shape[0..3], row 1 = shape[4], shape[5], coverage.
uniform sampler2D glyph_data : filter_nearest, repeat_disable;

uniform ivec2 grid = ivec2(1, 1);
uniform vec2 pitch_uv = vec2(0.01, 0.02);

// Camera info for decoding the gbuffer.
uniform float far_plane = 100.0;
// Distance fade (view depth, world units): geometry dissolves into the void
// between fade_begin and fade_end. fade_end = 0 turns it off (the default).
uniform float fade_begin = 0.0;
uniform float fade_end = 0.0;
// Overlay cell layer (AsciiOverlay): (grid.x * 2) x grid.y texels; texel 2x =
// ink RGB + glyph index + 1 (0 = none), texel 2x + 1 = background RGB + cover.
uniform bool overlay_on = false;
uniform sampler2D overlay_tex : filter_nearest, repeat_disable;
// Shadow hatching (off by default): light_tex is the scene rendered as
// lighting only. Fully shadowed cells get hatch_glyph on every
// hatch_period-th diagonal in hatch_ink; cells on the lit/shadow boundary get
// the glyph shaped like the lit part.
uniform bool hatch_on = false;
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform float hatch_threshold = 0.35;
uniform int hatch_glyph = 0;
uniform vec3 hatch_ink = vec3(0.35, 0.55, 1.0);
uniform int hatch_period = 3;
uniform ivec2 hatch_origin = ivec2(0); // cell of the world origin (ortho), so the hatching stays on the ground
uniform int hatch_edge_glyphs[16];
uniform int hatch_edge_count = 0;

uniform float exposure = 1.0;
uniform float contrast = 1.0;
uniform float gamma = 1.0;
uniform int color_mode = 0;
uniform vec3 mono_ink = vec3(0.45, 1.0, 0.55);
uniform float color_boost = 0.8;
uniform float bg_strength = 0.0;

uniform int ramp_lut[64];
uniform float shape_contrast = 2.0;
uniform float shape_flat_threshold = 0.2;
uniform float shape_ink_penalty = 1.5;
uniform float shape_ramp_bias = 0.04;
// Glyph indices of the ramp (sorted by coverage), 0-padded; index 0 (space) is always in it.
uniform int ramp_glyphs[32];
// Candidate glyph indices for shape matching.
uniform int shape_glyphs[128];
uniform int shape_count = 0;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float tone(float l) {
	l = clamp((l * exposure - 0.5) * contrast + 0.5, 0.0, 1.0);
	return pow(l, 1.0 / gamma);
}

// xyz = view-space normal, w = linear depth in world units, or -1 for background.
vec4 gb(vec2 uv) {
	vec3 t = texture(gbuf_tex, uv).rgb;
	if (t.b >= 0.99995) {
		return vec4(0.0, 0.0, 1.0, -1.0);
	}
	vec2 nxy = t.xy * 2.0 - 1.0;
	float nz = sqrt(max(0.0, 1.0 - dot(nxy, nxy)));
	return vec4(nxy, nz, t.b * far_plane);
}

vec3 ink_of(vec3 c) {
	if (color_mode == 1) {
		return mono_ink;
	}
	float m = max(max(c.r, c.g), c.b);
	vec3 full = c / max(m, 1e-4);
	return mix(c, full, color_boost);
}

// Line glyph (hatch_edge_glyphs) whose ink best matches a lit (1) / shadow (0) mask.
int match_mask(float m0, float m1, float m2, float m3, float m4, float m5) {
	float best_d = 1e9;
	int best = 0;
	for (int ci = 0; ci < hatch_edge_count; ci++) {
		int gi = hatch_edge_glyphs[ci];
		vec4 ga = texelFetch(glyph_data, ivec2(gi, 0), 0);
		vec4 gb2 = texelFetch(glyph_data, ivec2(gi, 1), 0);
		vec3 d0 = ga.xyz - vec3(m0, m1, m2);
		vec3 d1 = vec3(ga.w, gb2.xy) - vec3(m3, m4, m5);
		vec3 w0 = mix(vec3(1.0), vec3(shape_ink_penalty), step(0.0, d0));
		vec3 w1 = mix(vec3(1.0), vec3(shape_ink_penalty), step(0.0, d1));
		float d = dot(w0 * d0, d0) + dot(w1 * d1, d1);
		if (d < best_d) {
			best_d = d;
			best = gi;
		}
	}
	return best;
}

// One slot of a cell with the overlay layer applied over the scene's choice.
vec4 overlay_cell(ivec2 cell, int slot, int g0, vec3 ink, vec3 bg) {
	vec4 o_ink = texelFetch(overlay_tex, ivec2(cell.x * 2, cell.y), 0);
	vec4 o_bg = texelFetch(overlay_tex, ivec2(cell.x * 2 + 1, cell.y), 0);
	float cover = o_bg.a;
	ink *= 1.0 - cover;
	bg = mix(bg, o_bg.rgb, cover);
	if (cover >= 0.999) {
		g0 = 0;
	}
	int og = int(o_ink.a * 255.0 + 0.5);
	if (og > 0) {
		g0 = og - 1;
		ink = o_ink.rgb;
	}
	if (slot == 0) {
		return vec4(ink, float(g0) / 255.0);
	}
	return vec4(bg, 1.0);
}

void fragment() {
	ivec2 t = ivec2(floor(UV * vec2(float(grid.x * 2), float(grid.y))));
	int slot = t.x % 2;
	ivec2 cell = ivec2(t.x / 2, t.y);
	vec2 c0 = vec2(cell) * pitch_uv;
	vec2 cc = c0 + 0.5 * pitch_uv;

	// --- colour: 2x3 sub-regions, 2x2 bilinear taps each ---
	float sub[6];
	vec3 csum = vec3(0.0);
	// Luminance-weighted colour: the ink takes the colour of the bright part of
	// the cell (what the glyph depicts), not a mix with the dark background.
	vec3 cwsum = vec3(0.0);
	float lsum = 0.0;
	for (int sy = 0; sy < 3; sy++) {
		for (int sx = 0; sx < 2; sx++) {
			float s = 0.0;
			for (int ty = 0; ty < 2; ty++) {
				for (int tx = 0; tx < 2; tx++) {
					vec2 f = vec2((float(sx) + (float(tx) + 0.5) * 0.5) * 0.5,
							(float(sy) + (float(ty) + 0.5) * 0.5) / 3.0);
					vec3 col = texture(scene_tex, c0 + f * pitch_uv).rgb;
					float l = luma(col);
					csum += col;
					cwsum += col * l;
					lsum += l;
					s += l;
				}
			}
			sub[sy * 2 + sx] = tone(s * 0.25);
		}
	}
	vec3 avg = csum / 24.0;
	vec3 fg = lsum > 1e-4 ? cwsum / lsum : avg;
	float lum = tone(luma(avg));

	// --- gbuffer: 3x3 samples at pitch/3 spacing over the cell: all background = void ---
	int inner_void = 0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			if (gb(cc + vec2(float(i), float(j)) * pitch_uv / 3.0).w < 0.0) {
				inner_void++;
			}
		}
	}
	float centre_depth = gb(cc).w;

	float keep = 1.0;
	if (fade_end > 0.0) {
		float d = centre_depth < 0.0 ? fade_end : centre_depth;
		keep = 1.0 - smoothstep(fade_begin, fade_end, d);
		if (keep <= 0.0) {
			inner_void = 9;
		}
		lum *= keep;
		avg *= keep;
		fg *= keep;
		for (int k = 0; k < 6; k++) {
			sub[k] *= keep;
		}
	}

	if (inner_void == 9) {
		COLOR = vec4(0.0);
		if (slot == 1) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
		if (overlay_on) {
			COLOR = overlay_cell(cell, slot, 0, vec3(0.0), vec3(0.0));
		}
	} else {
		vec3 ink = ink_of(fg);
		int g0 = ramp_lut[clamp(int(lum * 63.0 + 0.5), 0, 63)];
		{
			float mx = 0.0;
			float mn = 1.0;
			for (int k = 0; k < 6; k++) {
				mx = max(mx, sub[k]);
				mn = min(mn, sub[k]);
			}
			float s[6];
			for (int k = 0; k < 6; k++) {
				s[k] = mx > 1e-3 ? pow(sub[k] / mx, shape_contrast) * mx : 0.0;
			}
			float best_d = 1e9;
			int best = 0;
			for (int ci = 0; ci < shape_count; ci++) {
				int gi = shape_glyphs[ci];
				vec4 ga = texelFetch(glyph_data, ivec2(gi, 0), 0);
				vec4 gb2 = texelFetch(glyph_data, ivec2(gi, 1), 0);
				// Positive difference = glyph puts ink where the image is darker.
				vec3 d0 = ga.xyz - vec3(s[0], s[1], s[2]);
				vec3 d1 = vec3(ga.w, gb2.xy) - vec3(s[3], s[4], s[5]);
				vec3 w0 = mix(vec3(1.0), vec3(shape_ink_penalty), step(0.0, d0));
				vec3 w1 = mix(vec3(1.0), vec3(shape_ink_penalty), step(0.0, d1));
				float d = dot(w0 * d0, d0) + dot(w1 * d1, d1);
				bool in_ramp = gi == 0;
				for (int r = 0; r < 32; r++) {
					in_ramp = in_ramp || ramp_glyphs[r] == gi;
				}
				d += in_ramp ? 0.0 : shape_ramp_bias;
				if (d < best_d) {
					best_d = d;
					best = gi;
				}
			}
			if (mx - mn >= shape_flat_threshold) {
				g0 = best;
			}
		}

		if (hatch_on) {
			// Lighting at the six sub-cell sample points: lit (1) or shadow (0).
			float lm[6];
			int lit = 0;
			for (int sy = 0; sy < 3; sy++) {
				for (int sx = 0; sx < 2; sx++) {
					vec2 f = vec2((float(sx) + 0.5) * 0.5, (float(sy) + 0.5) / 3.0);
					float l = luma(texture(light_tex, c0 + f * pitch_uv).rgb);
					lm[sy * 2 + sx] = l >= hatch_threshold ? 1.0 : 0.0;
					lit += l >= hatch_threshold ? 1 : 0;
				}
			}
			if (lit == 0) {
				// In shadow: sparse diagonal hatching in a cool ink.
				int hp = max(hatch_period, 1);
				ivec2 hc = cell - hatch_origin;
				int diag = ((hc.x + hc.y * 2) % hp + hp) % hp;
				g0 = diag == 0 ? hatch_glyph : 0;
				ink = hatch_ink * mix(0.45, 1.0, clamp(lum * 2.5, 0.0, 1.0));
			} else if (lit < 6) {
				// On the boundary: a glyph shaped like the lit part, in the lit ink.
				g0 = match_mask(lm[0], lm[1], lm[2], lm[3], lm[4], lm[5]);
			}
		}

		// Distance fade: ink is normalised in brightness, so dim it here.
		ink *= keep;
		if (slot == 0) {
			COLOR = vec4(ink, float(g0) / 255.0);
		} else {
			vec3 bg = color_mode == 1 ? mono_ink * luma(avg) : avg;
			COLOR = vec4(bg * bg_strength, 1.0);
		}
		if (overlay_on) {
			vec3 bg = color_mode == 1 ? mono_ink * luma(avg) : avg;
			COLOR = overlay_cell(cell, slot, g0, ink, bg * bg_strength);
		}
	}
}
