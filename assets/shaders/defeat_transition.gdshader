shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float effect_time = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	float grade = smoothstep(0.05, 1.0, progress);
	// Blue/white rolling interference, strongest early and absent at the final grade.
	float interference = smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.28, 0.95, progress));
	float tick = floor(effect_time * 24.0);
	float row = floor(SCREEN_UV.y * 90.0);
	float tear = step(0.88, hash(row + tick * 13.0));
	vec2 uv = SCREEN_UV;
	uv.x += (hash(row + tick * 7.0) - 0.5) * tear * 0.014 * interference;
	vec3 source = texture(screen_texture, uv).rgb;
	float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luma), source, 1.0 - grade * 0.5);
	graded = (graded - vec3(0.5)) * (1.0 + grade * 0.2) + vec3(0.5);
	float scan = pow(0.5 + 0.5 * sin(SCREEN_UV.y * 850.0 - effect_time * 31.0), 12.0);
	float noise = hash(floor(SCREEN_UV.x * 640.0) + row * 37.0 + tick * 71.0);
	vec3 blue_white = mix(vec3(0.15, 0.48, 1.0), vec3(0.85, 0.95, 1.0), noise);
	float band = exp(-pow((SCREEN_UV.y - fract(effect_time * 0.7)) * 22.0, 2.0));
	float strength = interference * (0.045 * noise + 0.16 * scan + 0.23 * band + 0.12 * tear);
	COLOR = vec4(mix(clamp(graded, vec3(0.0), vec3(1.0)), blue_white, strength), 1.0);
}
