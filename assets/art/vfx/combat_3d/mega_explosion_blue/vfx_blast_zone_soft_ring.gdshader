shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D ring_texture : source_color, filter_linear, repeat_disable;
uniform vec4 ring_color : source_color = vec4(1.0);
uniform float ring_opacity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	if (radius >= 1.0) { discard; }
	// Move the source annulus toward the boundary while retaining the original soft texture.
	vec2 radial = UV - vec2(0.5);
	vec2 sample_uv = vec2(0.5) + radial * (0.74 + 0.22 * radius);
	float mask = texture(ring_texture, sample_uv).a;
	mask = max(mask, smoothstep(0.90, 0.965, radius) * 0.44);
	ALBEDO = ring_color.rgb;
	ALPHA = mask * ring_opacity * (1.0 - smoothstep(0.965, 1.0, radius));
}
