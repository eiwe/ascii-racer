// Car bodywork for the glint lighting mode: the kit's textured material plus a
// stylised highlight. The highlight is computed on a smooth ellipsoid fitted to
// the body (blended a little toward the real face normal), lit from a direction
// fixed relative to the camera, so there is always a small bright spot on the
// car that slides over the bodywork as the car turns instead of whole flat faces
// flashing on and off. It is emission: it ignores the sun and its shadows.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

// Ellipsoid in the mesh's own space.
uniform vec3 body_centre = vec3(0.0, 0.27, 0.0);
uniform vec3 body_half = vec3(0.26, 0.18, 0.44);
// Direction toward the highlight source, in view space (x right, y up, z toward the camera).
uniform vec3 source_view = vec3(-0.45, 0.75, 0.5);
// 0 = pure ellipsoid (smooth glide), 1 = the real faces (flat facets).
uniform float facet = 0.25;
uniform float sharpness = 60.0;
uniform float energy = 1.6;
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.85);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	vec3 q = (local_pos - body_centre) / body_half;
	vec3 n_local = normalize(q / body_half);
	vec3 n = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	n = normalize(mix(n, NORMAL, facet));
	vec3 h = normalize(normalize(source_view) + VIEW);
	float s = pow(max(dot(n, h), 0.0), sharpness);
	EMISSION = tint * energy * s;
}
