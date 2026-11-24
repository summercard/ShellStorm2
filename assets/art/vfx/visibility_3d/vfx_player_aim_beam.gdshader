shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.11, 0.16, 0.92);
uniform float fade_start : hint_range(0.0, 0.95) = 0.60;
varying float along;

void vertex() {
	// The unit quad's local +Y points toward the tip.
	along = VERTEX.y + 0.5;
}

void fragment() {
	float taper = 1.0 - smoothstep(fade_start, 1.0, along);
	float side = abs(UV.x * 2.0 - 1.0) / max(taper, 0.0001);
	float core = 1.0 - smoothstep(0.14, 0.44, side);
	float fringe = 1.0 - smoothstep(0.36, 1.0, side);
	ALBEDO = beam_color.rgb * (0.85 + 0.40 * core);
	ALPHA = beam_color.a * taper * max(core, 0.32 * fringe);
}
