shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D screen_atlas : source_color, filter_linear, repeat_disable;
instance uniform vec2 canvas_center = vec2(0.5);
instance uniform float phase = 0.0;
instance uniform float power = 0.0;
instance uniform float tear = 0.0;
instance uniform float scroll = 0.0;

void fragment() {
	vec2 canvas_uv = canvas_center + (UV2 - 0.5) * 0.2;
	canvas_uv.x += tear * sin(canvas_uv.y * 170.0 + TIME * 46.0);
	canvas_uv.y += scroll + sin(TIME * 0.8) * 0.006;
	canvas_uv = fract(canvas_uv);
	float split = 1.0 - 0.5255;
	vec4 bounds = vec4(0.004, 0.004, 0.496, split - 0.004);
	if (phase >= 0.5 && phase < 1.5) {
		bounds.xz += vec2(0.5);
	} else if (phase >= 1.5) {
		bounds.yw = vec2(split + 0.004, 0.996);
		if (phase >= 2.5) {
			bounds.xz += vec2(0.5);
		}
	}
	vec3 glow = texture(screen_atlas, mix(bounds.xy, bounds.zw, canvas_uv)).rgb;
	ALBEDO = vec3(0.012, 0.017, 0.022);
	METALLIC = 0.20;
	ROUGHNESS = 0.41;
	EMISSION = glow * power * 1.5;
}
