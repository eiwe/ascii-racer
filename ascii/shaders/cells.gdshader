// Cell pass. Drawn on a ColorRect exactly (grid.x * 3) x grid.y texels: one
// texel per cell per data slot, interleaved (cell x * 3 + slot).
//   slot 0: primary glyph   RGB = ink, A = glyph index / 255
//   slot 1: overstruck glyph RGB = ink, A = glyph index / 255 (0 = none)
//   slot 2: background      RGB = colour
// Each cell maps to the scene/gbuffer textures by UV: cell (x, y) covers
// [x, x + 1] * pitch_uv horizontally and likewise vertically.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

const int M_RAMP = 0;
const int M_EDGES = 1;
const int M_SHAPE = 2;
const int M_OVERSTRIKE = 3;
const int M_HATCH = 4;

uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D gbuf_tex : filter_nearest, repeat_disable;
// n x 2 RGBAF: row 0 = shape[0..3], row 1 = shape[4], shape[5], coverage.
uniform sampler2D glyph_data : filter_nearest, repeat_disable;

uniform ivec2 grid = ivec2(1, 1);
uniform vec2 pitch_uv = vec2(0.01, 0.02);
// Pitch in output pixels; only its aspect matters (edge orientation).
uniform vec2 pitch_px = vec2(8.0, 16.0);
uniform int method = 0;

// Camera info for decoding the gbuffer.
uniform float far_plane = 100.0;
uniform bool ortho = true;
// View-space units per UV unit (ortho), or per UV unit per unit of depth (perspective).
uniform vec2 world_per_uv = vec2(10.0, 10.0);
// World up expressed in view space.
uniform vec3 view_up = vec3(0.0, 1.0, 0.0);
// Distance fade (view depth, world units): geometry dissolves into the void
// between fade_begin and fade_end. fade_end = 0 turns it off (the default).
uniform float fade_begin = 0.0;
uniform float fade_end = 0.0;
// Overlay cell layer (AsciiOverlay): (grid.x * 2) x grid.y texels; texel 2x =
// ink RGB + glyph index + 1 (0 = none), texel 2x + 1 = background RGB + cover.
uniform bool overlay_on = false;
uniform sampler2D overlay_tex : filter_nearest, repeat_disable;

uniform float exposure = 1.0;
uniform float contrast = 1.0;
uniform float gamma = 1.0;
uniform int color_mode = 0;
uniform vec3 mono_ink = vec3(0.45, 1.0, 0.55);
uniform float color_boost = 0.8;
uniform float bg_strength = 0.0;

uniform int ramp_lut[64];
// Glyph indices of: - / | \ _ '
uniform int line_glyphs[6];
uniform float depth_threshold = 0.06;
uniform float normal_threshold = 0.25;
uniform float overstrike_boost = 1.5;
uniform float shape_contrast = 2.0;
uniform float shape_flat_threshold = 0.2;
uniform float shape_ink_penalty = 1.5;
uniform float shape_ramp_bias = 0.04;
// Glyph indices of the ramp (sorted by coverage), 0-padded; index 0 (space) is always in it.
uniform int ramp_glyphs[32];
// Candidate glyph indices for shape matching.
uniform int shape_glyphs[128];
uniform int shape_count = 0;

uniform int hatch_top[8];
uniform int hatch_left[8];
uniform int hatch_right[8];
uniform int hatch_front[8];
// Lengths of the four hatch ramps (top, left, right, front).
uniform ivec4 hatch_len = ivec4(1);

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

// Is there a silhouette or crease between neighbouring samples a and b?
// step = view-space displacement from a to b (at unit depth for perspective).
// nearer: -1 if a is in front, +1 if b is in front, 0 if neither (crease).
bool pair_edge(vec4 a, vec4 b, vec2 step, out float nearer) {
	nearer = 0.0;
	bool va = a.w < 0.0;
	bool vb = b.w < 0.0;
	if (va && vb) {
		return false;
	}
	if (va || vb) {
		nearer = va ? 1.0 : -1.0;
		return true;
	}
	vec2 st = ortho ? step : step * 0.5 * (a.w + b.w);
	float dd = b.w - a.w;
	// Depth change a planar surface through either sample would produce.
	float pa = dot(a.xy, st) / max(a.z, 0.2);
	float pb = dot(b.xy, st) / max(b.z, 0.2);
	float residual = min(abs(dd - pa), abs(dd - pb));
	if (residual > depth_threshold) {
		nearer = dd > 0.0 ? -1.0 : 1.0;
		return true;
	}
	return 1.0 - dot(a.xyz, b.xyz) > normal_threshold;
}

vec3 ink_of(vec3 c) {
	if (color_mode == 1) {
		return mono_ink;
	}
	float m = max(max(c.r, c.g), c.b);
	vec3 full = c / max(m, 1e-4);
	return mix(c, full, color_boost);
}

int hatch_pick(int fam, float l) {
	int n = fam == 0 ? hatch_len.x : fam == 1 ? hatch_len.y : fam == 2 ? hatch_len.z : hatch_len.w;
	int i = clamp(int(l * float(n - 1) + 0.5), 0, n - 1);
	if (fam == 0) return hatch_top[i];
	if (fam == 1) return hatch_left[i];
	if (fam == 2) return hatch_right[i];
	return hatch_front[i];
}

// One slot of a cell with the overlay layer applied over the scene's choice.
vec4 overlay_cell(ivec2 cell, int slot, int g0, vec3 ink, int g1, vec3 ink1, vec3 bg) {
	vec4 o_ink = texelFetch(overlay_tex, ivec2(cell.x * 2, cell.y), 0);
	vec4 o_bg = texelFetch(overlay_tex, ivec2(cell.x * 2 + 1, cell.y), 0);
	float cover = o_bg.a;
	ink *= 1.0 - cover;
	ink1 *= 1.0 - cover;
	bg = mix(bg, o_bg.rgb, cover);
	if (cover >= 0.999) {
		g0 = 0;
		g1 = 0;
	}
	int og = int(o_ink.a * 255.0 + 0.5);
	if (og > 0) {
		g0 = og - 1;
		ink = o_ink.rgb;
		g1 = 0;
	}
	if (slot == 0) {
		return vec4(ink, float(g0) / 255.0);
	} else if (slot == 1) {
		return vec4(ink1, float(g1) / 255.0);
	}
	return vec4(bg, 1.0);
}

void fragment() {
	ivec2 t = ivec2(floor(UV * vec2(float(grid.x * 3), float(grid.y))));
	int slot = t.x % 3;
	ivec2 cell = ivec2(t.x / 3, t.y);
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

	// --- gbuffer: 5x5 samples at pitch/3 spacing; the inner 3x3 belong to this cell ---
	vec4 g[25];
	int inner_void = 0;
	vec3 nsum = vec3(0.0);
	for (int j = 0; j < 5; j++) {
		for (int i = 0; i < 5; i++) {
			vec4 s = gb(cc + vec2(float(i - 2), float(j - 2)) * pitch_uv / 3.0);
			g[j * 5 + i] = s;
			if (i >= 1 && i <= 3 && j >= 1 && j <= 3) {
				if (s.w < 0.0) {
					inner_void++;
				} else {
					nsum += s.xyz;
				}
			}
		}
	}

	float keep = 1.0;
	if (fade_end > 0.0) {
		float d = g[12].w < 0.0 ? fade_end : g[12].w;
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
		if (slot == 2) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
		if (overlay_on) {
			COLOR = overlay_cell(cell, slot, 0, vec3(0.0), 0, vec3(0.0), vec3(0.0));
		}
	} else {
		// --- edges: discontinuous neighbour pairs, orientation by PCA of their midpoints ---
		vec2 sp = pitch_uv / 3.0 * world_per_uv;
		float w = 0.0;
		vec2 m1 = vec2(0.0);
		vec3 m2 = vec3(0.0); // xx, yy, xy
		int owned = 0;
		vec2 own_sum = vec2(0.0);
		float seg_y = pitch_px.y / 3.0;
		float seg_x = pitch_px.x / 3.0;
		bool want_edges = method == M_EDGES || method == M_OVERSTRIKE;
		if (want_edges) {
			for (int j = 0; j < 5; j++) {
				for (int i = 0; i < 4; i++) {
					float nearer;
					if (!pair_edge(g[j * 5 + i], g[j * 5 + i + 1], vec2(sp.x, 0.0), nearer)) {
						continue;
					}
					vec2 m = vec2(float(i - 2) + 0.5, float(j - 2)) / 3.0;
					vec2 p = m * pitch_px;
					w += 1.0;
					m1 += p;
					m2 += vec3(p.x * p.x, p.y * p.y + seg_y * seg_y / 12.0, p.x * p.y);
					bool own = j >= 1 && j <= 3 && ((i == 1 || i == 2) || (i == 0 && nearer >= 0.0) || (i == 3 && nearer < 0.0));
					if (own) {
						owned++;
						own_sum += m;
					}
				}
			}
			for (int j = 0; j < 4; j++) {
				for (int i = 0; i < 5; i++) {
					float nearer;
					if (!pair_edge(g[j * 5 + i], g[(j + 1) * 5 + i], vec2(0.0, -sp.y), nearer)) {
						continue;
					}
					vec2 m = vec2(float(i - 2), float(j - 2) + 0.5) / 3.0;
					vec2 p = m * pitch_px;
					w += 1.0;
					m1 += p;
					m2 += vec3(p.x * p.x + seg_x * seg_x / 12.0, p.y * p.y, p.x * p.y);
					bool own = i >= 1 && i <= 3 && ((j == 1 || j == 2) || (j == 0 && nearer >= 0.0) || (j == 3 && nearer < 0.0));
					if (own) {
						owned++;
						own_sum += m;
					}
				}
			}
		}
		int edge_glyph = 0;
		if (owned > 0) {
			vec2 mean = m1 / w;
			float cxx = m2.x / w - mean.x * mean.x;
			float cyy = m2.y / w - mean.y * mean.y;
			float cxy = m2.z / w - mean.x * mean.y;
			float theta = 0.5 * atan(2.0 * cxy, cxx - cyy); // y down
			float a = degrees(theta);
			vec2 om = own_sum / float(owned);
			if (abs(a) < 35.0) {
				// Where the line crosses this cell's centre column decides the glyph height.
				// |theta| < 35 deg, so cos(theta) > 0.8: no division hazard.
				float y0 = (mean.y - mean.x * tan(theta)) / pitch_px.y;
				y0 = mix(y0, om.y, 0.5);
				// Low lines print '_'; shallow slopes may also use ' high up, giving _.-' runs.
				bool sloped = abs(a) > 12.0;
				edge_glyph = y0 > 0.18 ? line_glyphs[4] : (sloped && y0 < -0.22) ? line_glyphs[5] : line_glyphs[0];
			} else if (abs(a) > 72.0) {
				edge_glyph = line_glyphs[2];
			} else {
				edge_glyph = a > 0.0 ? line_glyphs[3] : line_glyphs[1];
			}
		}

		vec3 ink = ink_of(fg);
		int g0 = ramp_lut[clamp(int(lum * 63.0 + 0.5), 0, 63)];
		int g1 = 0;
		vec3 ink1 = ink;

		if (method == M_EDGES) {
			if (edge_glyph != 0) {
				g0 = edge_glyph;
				ink = min(ink * 1.15, vec3(1.0));
			}
		} else if (method == M_OVERSTRIKE) {
			g1 = edge_glyph;
			ink1 = min(ink * overstrike_boost, vec3(1.0));
			if (color_mode == 1) {
				ink1 = min(mono_ink * overstrike_boost, vec3(1.0));
				ink = mono_ink * 0.8;
			}
		} else if (method == M_SHAPE) {
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
		} else if (method == M_HATCH) {
			vec3 n = normalize(nsum + vec3(0.0, 0.0, 1e-4));
			float up = dot(n, view_up);
			int fam = 0;
			if (up < 0.7) {
				vec3 tg = cross(view_up, n);
				float ag = degrees(atan(-tg.y, tg.x));
				if (ag > 90.0) ag -= 180.0;
				if (ag <= -90.0) ag += 180.0;
				fam = abs(ag) < 12.0 ? 3 : ag > 0.0 ? 1 : 2;
			}
			g0 = hatch_pick(fam, lum);
		}

		// Distance fade: ink is normalised in brightness, so dim it here.
		ink *= keep;
		ink1 *= keep;
		if (slot == 0) {
			COLOR = vec4(ink, float(g0) / 255.0);
		} else if (slot == 1) {
			COLOR = vec4(ink1, float(g1) / 255.0);
		} else {
			vec3 bg = color_mode == 1 ? mono_ink * luma(avg) : avg;
			COLOR = vec4(bg * bg_strength, 1.0);
		}
		if (overlay_on) {
			vec3 bg = color_mode == 1 ? mono_ink * luma(avg) : avg;
			COLOR = overlay_cell(cell, slot, g0, ink, g1, ink1, bg * bg_strength);
		}
	}
}
