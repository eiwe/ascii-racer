// The opponent's bodywork: the kit's shared colormap with its warm saturated
// colours (the speedster's orange-red panels) pushed to a deep, clean red, so
// the car reads as red next to the green player car even as characters.
// Greys, dark trim, glass and the wheels are left as they are. The colormap
// itself is untouched.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
// Target red (hue 0..1), saturation and brightness scale for repainted texels.
uniform float hue = 0.995;
uniform float saturation = 0.9;
uniform float value_scale = 0.92;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo.rgb;
	vec3 hsv = rgb2hsv(c);
	bool warm = hsv.y > 0.4 && (hsv.x < 0.12 || hsv.x > 0.9);
	if (warm) {
		c = hsv2rgb(vec3(hue, max(hsv.y, saturation), hsv.z * value_scale));
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
