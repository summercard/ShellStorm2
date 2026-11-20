shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D screen_atlas : source_color, filter_linear, repeat_disable;
instance uniform vec2 canvas_center = vec2(0.5);
instance uniform float phase = 0.0;
instance uniform float power = 0.0;
instance uniform float tear = 0.0;
instance uniform float scroll = 0.0;
// x: 0 original cyan, 1 cool blue, 2 blue-violet. y: transient signal tear.
instance uniform vec2 deck_feed = vec2(0.0);
instance uniform float gun_alert = 0.0;

void fragment() {
	vec2 canvas_uv = canvas_center + (UV2 - 0.5) * 0.2;
	if (phase < 0.5 && deck_feed.y > 0.0) {
		float row = floor(canvas_uv.y * 24.0);
		float slice = step(0.69, fract(row * 0.618));
		canvas_uv.x += sin(row * 3.37) * 0.028 * slice * deck_feed.y;
	}
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
	ALBEDO = vec3(0.012, 0.017, 0.022);
	METALLIC = 0.20;
	ROUGHNESS = 0.41;
	vec3 glow = texture(screen_atlas, mix(bounds.xy, bounds.zw, canvas_uv)).rgb;
	if (phase < 0.5) {
		if (deck_feed.x > 1.5) {
			glow = vec3(glow.r * 0.85 + glow.b * 0.51, glow.g * 0.50, glow.b * 0.96);
		} else if (deck_feed.x > 0.5) {
			glow = vec3(glow.r * 0.90 + glow.b * 0.18, glow.g * 0.70, glow.b);
		}
	}
	vec3 alarm = vec3(1.0, 0.24, 0.045);
	float scan = 0.80 + 0.20 * sin(canvas_uv.y * 26.0);
	glow = mix(glow, alarm * (0.25 + max(glow.r, max(glow.g, glow.b))), gun_alert * 0.68);
	EMISSION = glow * power * (1.5 + 0.65 * gun_alert * scan);
}
