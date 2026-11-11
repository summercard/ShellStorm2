shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 pool_color : source_color;
uniform float pool_alpha = 0.26;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.58, 1.0, length(p));
	ALBEDO = pool_color.rgb;
	EMISSION = pool_color.rgb * 0.35;
	ALPHA = pool_alpha * edge;
}
