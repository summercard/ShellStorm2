shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas_texture : source_color, filter_linear, repeat_disable;
uniform int mode = 1;
uniform int atlas_slot = 0;
uniform int next_slot = 0;
uniform float brightness = 0.24;
uniform float snow_amount = 1.0;
uniform float openness = 1.0;
uniform float roll = 0.0;
uniform float signal_clock = 0.0;
uniform vec2 eye_offset = vec2(0.0);
uniform vec4 card_color : source_color = vec4(1.0);

vec3 channel(int slot, vec2 uv) {
	vec2 cell = vec2(float(slot % 4), float(slot / 4));
	return texture(atlas_texture, (cell + clamp(uv, vec2(0.004), vec2(0.996))) / vec2(4.0, 3.0)).rgb;
}
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	vec2 uv = UV;
	float t = signal_clock;
	float band = 1.0 - smoothstep(0.014, 0.034, abs(uv.y - fract(t * 0.33)));
	vec2 art = uv + vec2(band * 0.04 * sin(t * 31.0), 0.0);
	float pulse = 1.0;
	vec3 tint = vec3(1.0);
	if (mode == 6) {
		pulse = 1.0 + 0.10 * sin(t * 11.0); art.y += sin(t * 13.0) * 0.023;
	} else if (mode == 7) {
		pulse = 1.0 + 0.19 * max(0.0, sin(t * 17.0)); art = (art - 0.5) / pulse + 0.5; art.y += 0.062 * abs(sin(t * 12.0)); tint = vec3(1.05, 0.87, 0.61);
	} else if (mode == 8) {
		pulse = 0.86 + 0.22 * abs(sin(t * 24.0)); art.x += (hash21(vec2(floor(art.y * 10.0), floor(t * 13.0))) - 0.5) * 0.10; tint = vec3(1.15, 0.52, 0.59);
	} else if (mode == 9) {
		pulse = 0.83 + 0.11 * sin(t * 7.0); art.x = (art.x - 0.5) * 1.27 + 0.5 + 0.055 * sin(t * 4.0); tint = vec3(0.77, 0.54, 1.02);
	}
	vec3 c = channel(atlas_slot, art) * tint * pulse;
	if (mode == 1) {
		c = vec3(0.0);
	} else if (mode == 2) {
		vec2 p = uv - vec2(0.5);
		float eye_shape = abs(p.y) / max(openness, 0.025) + 0.97 * p.x * p.x;
		float eye = (1.0 - smoothstep(0.155, 0.176, eye_shape)) * (1.0 - smoothstep(0.385, 0.405, abs(p.x)));
		float pupil = 1.0 - smoothstep(0.081, 0.093, length((p - eye_offset) * vec2(1.15, 1.0)));
		float glint = 1.0 - smoothstep(0.018, 0.027, length(p - eye_offset - vec2(-0.028, -0.027)));
		c = vec3(0.055, 0.017, 0.12) + eye * (vec3(0.91, 0.69, 0.98) * (1.0 - 0.92 * pupil) + glint * 0.72);
	} else if (mode == 3) {
		vec2 p = uv - vec2(0.5, 0.53);
		float edge = max(abs(p.x) * 1.1 - (p.y + 0.29) * 0.65, max(p.y - 0.24, -p.y - 0.29));
		float mark = (1.0 - smoothstep(0.035, 0.046, abs(p.x))) * max(step(-0.135, p.y) * step(p.y, 0.055), step(0.103, p.y) * step(p.y, 0.156));
		float fill = 1.0 - smoothstep(-0.006, 0.004, edge);
		float rim = 1.0 - smoothstep(0.008, 0.024, abs(edge));
		c = vec3(0.14, 0.018, 0.007) + (rim * 0.73 + fill * 0.51) * vec3(1.12, 0.42, 0.022);
		c *= 1.0 - mark * 0.91;
	} else if (mode == 4) {
		float y = uv.y + roll;
		vec2 scroll_uv = vec2(uv.x, fract(y));
		c = channel(y >= 1.0 ? next_slot : atlas_slot, scroll_uv);
		c *= 0.78 + 0.22 * sin(3.14159 * scroll_uv.y);
	} else if (mode == 5) {
		vec3 glyph = channel(atlas_slot, uv);
		float signal = smoothstep(0.18, 0.66, dot(glyph, vec3(0.30, 0.55, 0.15)));
		float inset = step(0.065, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
		c = mix(card_color.rgb * (0.66 + 0.28 * inset), vec3(0.021, 0.013, 0.073), signal);
	}
	float grain = hash21(floor(uv * vec2(174.0, 117.0)) + vec2(floor(t * 29.0), floor(t * 29.0) * 1.23));
	vec3 static_pattern = vec3(0.07, 0.11, 0.19) + pow(grain, 3.3) * vec3(0.57, 0.69, 0.79);
	c = mix(c, static_pattern, snow_amount);
	float scan = 0.89 + 0.11 * sin(uv.y * 620.0 + t * 15.0);
	float vignette = 1.0 - 0.55 * dot(uv - 0.5, uv - 0.5);
	ALBEDO = c * scan * vignette * brightness;
	EMISSION = ALBEDO * 0.55;
}
