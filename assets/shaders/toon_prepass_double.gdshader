shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_disabled, depth_prepass_alpha;

#include "res://assets/shaders/toon_core.gdshaderinc"

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = tex.rgb;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = toon_rim(NORMAL, VIEW) + toon_ambient(ALBEDO);
	ALPHA = tex.a;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(ALBEDO, NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
