// Sunset sky for the "sunset" lighting mode: a graded sky (deep blue overhead
// through orange to a hot band on the horizon), the sun where the scene's
// directional light comes from (LIGHT0, so it follows the sun keys), and fair-
// weather cumulus scattered across it: rounded heaps of puffs with flattish
// bases, lit by the low sun (warm bright edges toward it, cooler undersides),
// drifting very slowly. The puffs are kept large (several character cells
// each) so they read as lumps in the ASCII renderer rather than as noise.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.05, 0.08, 0.24);
uniform vec3 high : source_color = vec3(0.32, 0.22, 0.42);
uniform vec3 low : source_color = vec3(0.95, 0.45, 0.2);
uniform vec3 band : source_color = vec3(1.0, 0.62, 0.22);
uniform vec3 below : source_color = vec3(0.09, 0.06, 0.08);
uniform float sky_energy = 0.9;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.7, 0.45);
uniform vec3 cloud_shade : source_color = vec3(0.42, 0.36, 0.52);
uniform vec3 cloud_under : source_color = vec3(0.3, 0.24, 0.36);
uniform float cloud_energy = 1.0;
// Cloud drift (radians of azimuth per second).
uniform float drift = 0.0015;

const int CLOUDS = 14;
const int PUFFS = 6;

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// One cumulus: a heap of round puffs (radians of sky), the bottom cut flat.
// Returns coverage (0..1) and, in n, the surface normal of the puff the point
// is deepest in (for the shading).
float cumulus(vec2 p, float size, float seed, out vec2 n) {
	float best = -1.0;
	float cover = 0.0;
	n = vec2(0.0, 1.0);
	for (int k = 0; k < PUFFS; k++) {
		float fk = float(k);
		// Puffs along a low heap: big ones in the middle, smaller to the sides,
		// the middle ones higher (a rounded crown).
		float x = (fk / float(PUFFS - 1) - 0.5) * 2.0 * size * 1.3 + (hash1(seed + fk) - 0.5) * size * 0.35;
		float edge = abs(x) / (size * 1.3);
		float r = size * (0.62 - 0.32 * edge) * (0.8 + 0.4 * hash1(seed * 3.1 + fk));
		float y = r * 0.55 + size * 0.25 * (1.0 - edge) * hash1(seed * 7.7 + fk);
		vec2 c = vec2(x, y);
		float d = length(p - c);
		float depth = (r - d) / r;
		cover = max(cover, smoothstep(0.0, 0.06, depth));
		if (depth > best) {
			best = depth;
			n = (p - c) / max(d, 1e-4);
		}
	}
	// A flattish base.
	cover *= smoothstep(-0.02 * size, 0.04 * size, p.y);
	return cover;
}

void sky() {
	vec3 d = EYEDIR;
	float el = asin(clamp(d.y, -1.0, 1.0));
	float az = atan(d.x, -d.z);
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(-0.5, 0.25, 0.5));
	float sun_az = atan(sun.x, -sun.z);
	float sun_el = asin(clamp(sun.y, -1.0, 1.0));
	float toward_sun = 0.5 + 0.5 * cos(wrap_angle(az - sun_az)); // 1 facing the sun

	// The graded sky, warmer and brighter toward the sun.
	float t = clamp(el, 0.0, 1.5);
	vec3 col = mix(low, high, smoothstep(0.01, 0.16, t));
	col = mix(col, zenith, smoothstep(0.14, 0.55, t));
	col = mix(col, band, exp(-max(el, 0.0) * 28.0) * (0.55 + 0.45 * toward_sun));
	col *= mix(0.55, 1.15, toward_sun * (1.0 - t * 0.6));
	if (el < 0.0) {
		col = mix(band * 0.5, below, smoothstep(0.0, 0.08, -el));
	}
	// The sun: a hot disc with a wide glow.
	float cs = dot(d, sun);
	col += vec3(1.0, 0.7, 0.4) * pow(max(cs, 0.0), 40.0) * 0.7;
	col += vec3(1.0, 0.85, 0.6) * smoothstep(0.9993, 0.9997, cs) * 3.0;
	col *= sky_energy;

	// Fair-weather cumulus, scattered at varied sizes and heights.
	for (int i = 0; i < CLOUDS; i++) {
		float fi = float(i);
		float caz = hash1(fi * 1.37 + 0.2) * TAU + TIME * drift * (0.8 + 0.4 * hash1(fi + 9.0));
		float cel = 0.025 + 0.34 * hash1(fi * 2.91 + 0.7) * hash1(fi * 5.3 + 1.1);
		float size = (0.065 + 0.09 * hash1(fi * 4.17 + 0.3)) * (1.0 - 0.4 * clamp(cel / 0.4, 0.0, 1.0));
		vec2 p = vec2(wrap_angle(az - caz) * cos(el), el - cel);
		if (abs(p.x) > size * 2.6 || p.y < -size * 0.2 || p.y > size * 1.4) {
			continue;
		}
		vec2 n;
		float cover = cumulus(p, size, fi * 13.0 + 1.0, n);
		if (cover <= 0.0) {
			continue;
		}
		// Light from the low sun: sideways toward its azimuth, a little upward.
		float side = clamp(wrap_angle(sun_az - caz) * 2.0, -1.0, 1.0);
		vec2 l = normalize(vec2(side, 0.45 + clamp(sun_el - cel, -0.3, 0.3)));
		float lit = clamp(dot(n, l) * 0.6 + 0.45, 0.0, 1.0) * mix(0.65, 1.0, toward_sun);
		vec3 cc = mix(cloud_shade, cloud_lit, smoothstep(0.3, 0.9, lit));
		// Cooler, darker undersides.
		cc = mix(cloud_under, cc, smoothstep(0.0, size * 0.55, p.y));
		// A bright rim on the edges facing the sun.
		float rim = smoothstep(0.5, 0.95, dot(n, l)) * (1.0 - smoothstep(0.3, 0.9, cover));
		cc += cloud_lit * rim * 0.5;
		col = mix(col, cc * cloud_energy, cover);
	}
	COLOR = col;
}
