shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D screen_texture : source_color, filter_linear;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.4;
uniform float scan_speed = 0.12;
uniform float scan_phase = 0.0;
// x = room signal state (0 retains the original display), y = L/C/R, z = single burst envelope.
instance uniform vec4 signal_picture = vec4(0.0);

float line_mark(float distance_to_line, float width) {
	return 1.0 - smoothstep(width, width + 0.006, abs(distance_to_line));
}

float box_mark(vec2 p, vec2 half_size) {
	return 1.0 - smoothstep(0.0, 0.006, max(abs(p.x) - half_size.x, abs(p.y) - half_size.y));
}

void fragment() {
	if (signal_picture.x < 0.5) {
		vec3 content = texture(screen_texture, UV).rgb;
		float phase = fract(TIME * scan_speed + scan_phase);
		float band = line_mark(UV.y - phase, 0.018);
		ALBEDO = content * (0.94 + 0.06 * sin(UV.y * 1300.0));
		EMISSION = content * (emission_strength + band * 0.28);
	} else {
		float state = signal_picture.x;
		float slot = signal_picture.y;
		float strength = signal_picture.z;
		bool main_screen = abs(slot - 1.0) < 0.1;
		float timer = TIME + slot * 0.83;
		float page = mod(floor(timer / 3.0) + slot, 4.0);
		float wipe = smoothstep(0.0, 0.22, mod(timer, 3.0));
		float row = floor(UV.y * 20.0);
		float tear = step(0.77, fract(row * 0.618 + floor(timer * 6.0) * 0.381));
		vec2 uv = clamp(UV + vec2(strength * tear * 0.065 * sin(row * 2.1), 0.0), vec2(0.005), vec2(0.995));
		vec2 p = (uv - vec2(0.50, 0.47)) * vec2(1.60, 1.0);
		float radius = length(p);
		vec3 ink = vec3(0.25, 0.72, 0.84);
		float glyph = 0.0;
		float art = 0.20;
		if (page < 0.5) { // Monitoring: viewfinder and existing content.
			vec2 corner = abs(p) - vec2(0.50, 0.29);
			glyph = max(box_mark(corner - vec2(-0.048, 0.0), vec2(0.058, 0.010)), box_mark(corner - vec2(0.0, -0.044), vec2(0.010, 0.056)));
			art = 0.68;
		} else if (page < 1.5) { // Scan: broad rings and a rotating sweep.
			vec2 beam = vec2(cos(timer * 2.4), sin(timer * 2.4));
			float sweep = max(0.0, dot(p / max(radius, 0.001), beam));
			glyph = 0.75 * max(line_mark(radius - 0.26, 0.011), line_mark(radius - 0.14, 0.008));
			glyph = max(glyph, sweep * sweep * sweep * (1.0 - smoothstep(0.25, 0.30, radius)) * 0.76);
			ink = vec3(0.24, 0.81, 0.66);
		} else if (page < 2.5) { // Diagnostics: broad stepped bars plus wave trace.
			float cell = floor(uv.x * 11.0);
			float height = 0.16 + 0.26 * (0.50 + 0.50 * sin(cell * 1.43 + timer * 0.9));
			float bars = step(0.22, fract(uv.x * 11.0)) * step(uv.y, 0.72) * step(0.72 - height, uv.y);
			float wave = 0.47 + 0.095 * sin(uv.x * 27.0 + timer * 3.8);
			glyph = max(bars * 0.50, line_mark(uv.y - wave, 0.012));
			ink = vec3(0.49, 0.62, 0.95);
		} else { // Status frame: a spare lock symbol, not a fake combat prompt.
			glyph = max(line_mark(abs(p.x) + abs(p.y) - 0.32, 0.012), box_mark(p, vec2(0.10, 0.020)));
			ink = vec3(0.64, 0.68, 0.89);
		}
		float badge = 0.0;
		if (state > 1.5) {
			vec2 b = main_screen ? p : (uv - vec2(0.12, 0.16)) * vec2(2.8, 1.7);
			if (state < 2.5) { // Lost link: crossed diagonals.
				badge = line_mark(abs(b.x) - abs(b.y), 0.020) * (1.0 - smoothstep(0.18, 0.21, max(abs(b.x), abs(b.y))));
				ink = vec3(0.98, 0.34, 0.15);
			} else if (state < 4.5) { // Rise / combat online: double upward chevron.
				float apex = abs(b.x) * 0.72;
				badge = max(line_mark(b.y - apex + 0.09, 0.016), line_mark(b.y - apex - 0.04, 0.016));
				badge *= 1.0 - smoothstep(0.18, 0.21, abs(b.x));
				ink = vec3(0.16, 0.81, 0.96);
			} else if (state < 6.5) { // Collapse: triangle and exclamation; no hard white.
				float triangle = max(b.y - 0.17, abs(b.x) * 1.64 - b.y - 0.19);
				badge = max(line_mark(triangle, 0.016), max(box_mark(b + vec2(0.0, 0.02), vec2(0.018, 0.073)), box_mark(b - vec2(0.0, 0.112), vec2(0.019))));
				ink = state > 5.5 ? vec3(0.97, 0.27, 0.12) : vec3(0.96, 0.59, 0.15);
			} else {
				badge = max(line_mark(b.y + b.x - 0.04, 0.014) * box_mark(b - vec2(0.062, -0.016), vec2(0.125, 0.19)), line_mark(b.y - b.x - 0.12, 0.014) * box_mark(b + vec2(0.12, -0.07), vec2(0.069, 0.14)));
				ink = vec3(0.33, 0.79, 0.63);
			}
			glyph *= main_screen ? 0.42 : 0.80;
		}
		float sweep_y = fract(timer * 0.34);
		float track = line_mark(uv.y - sweep_y, 0.012) * 0.11;
		float edge = max(line_mark(uv.y - 0.07, 0.007), line_mark(uv.y - 0.88, 0.008));
		float header = box_mark(uv - vec2(0.19, 0.105), vec2(0.106, 0.012));
		float meters = box_mark(uv - vec2(0.78, 0.925), vec2(0.14, 0.014)) * step(0.24, fract(uv.x * 47.0));
		vec3 original = texture(screen_texture, uv).rgb;
		vec3 picture = original * art * vec3(0.55, 0.62, 0.72) + ink * (0.028 + 0.62 * glyph + 0.75 * badge + 0.21 * edge + 0.30 * header + 0.26 * meters + track);
		float scan = 0.96 + 0.04 * sin(uv.y * 440.0);
		float lock_loss = strength * (0.20 + tear * 0.43);
		picture = picture * scan * mix(0.70, 1.0, wipe) * (1.0 - lock_loss);
		picture += ink.bgr * tear * strength * 0.08;
		ALBEDO = picture * 0.42;
		EMISSION = min(picture * 0.94, vec3(0.83));
	}
}
