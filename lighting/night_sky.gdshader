// Night sky for the "night" lighting mode: a dark blue gradient with a faint
// glow on the horizon (so the skyline still reads against it), the moon where
// the scene's directional light comes from (LIGHT0, so it follows the sun
// keys), and sparse stars. Stars are placed on a fixed grid over the sky
// (azimuth x elevation), so they stay put as the camera turns; they are small
// bright dots, and the renderer draws sky cells from the fill ramp only
// (AsciiRenderer.sky_ramp_only) so a star is one dot-like glyph rather than a
// letter shape.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.02, 0.03, 0.09);
uniform vec3 horizon : source_color = vec3(0.1, 0.14, 0.3);
uniform vec3 below : source_color = vec3(0.02, 0.025, 0.04);
uniform vec3 moon_color : source_color = vec3(0.92, 0.95, 1.0);
uniform vec3 star_color : source_color = vec3(0.75, 0.8, 1.0);
// Stars are brighter than white so a dot a fraction of a cell across still
// lifts its cell to a visible fill glyph.
uniform float star_energy = 2.2;
// Moon radius and its glow (radians).
uniform float moon_radius = 0.06;
uniform float moon_glow = 0.35;
// Star grid cells (radians) and how many cells hold a star (0..1).
uniform float star_cell = 0.11;
uniform float star_density = 0.3;
uniform float star_radius = 0.0045;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float el = asin(clamp(d.y, -1.0, 1.0));
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.7, el));
	if (el < 0.0) {
		col = mix(horizon * 0.6, below, smoothstep(0.0, 0.06, -el));
	} else {
		// Stars: one candidate per grid cell, at a random spot in it.
		float az = atan(d.x, -d.z);
		// Cells narrow in azimuth toward the zenith: widen them so stars stay spread.
		float az_cell = star_cell / max(cos(el), 0.15);
		vec2 g = vec2(az / az_cell, el / star_cell);
		vec2 c = floor(g);
		float on = step(1.0 - star_density, hash2(c));
		vec2 spot = c + 0.2 + 0.6 * vec2(hash2(c + 17.3), hash2(c + 41.9));
		vec2 dd = (g - spot) * vec2(az_cell * cos(el), star_cell);
		float bright = 0.45 + 0.55 * hash2(c + 7.1);
		float star = on * bright * (1.0 - smoothstep(star_radius * 0.4, star_radius, length(dd)));
		col = mix(col, star_color * star_energy, star * smoothstep(0.03, 0.12, el));
	}
	// The moon: a disc with a soft halo, where the moonlight comes from.
	if (LIGHT0_ENABLED) {
		float a = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		col += moon_color * 0.25 * exp(-a / moon_glow * 3.0);
		col = mix(col, moon_color, 1.0 - smoothstep(moon_radius * 0.85, moon_radius, a));
	}
	COLOR = col;
}
