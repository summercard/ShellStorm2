shader_type spatial;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform int role = 1;
uniform float red_black = 0.0;
uniform float camera_cutaway = 0.0;
instance uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
instance uniform float slam_charge : hint_range(0.0, 0.25) = 0.0;
instance uniform vec3 slam_visual_offset = vec3(0.0);

void vertex() {
	// Render-only world-space tremor; sockets and damage shapes stay on the authored pose.
	VERTEX += (inverse(MODEL_MATRIX) * vec4(slam_visual_offset, 0.0)).xyz;
}

void fragment() {
	if (camera_cutaway > 0.0) {
		vec2 pixel = mod(floor(FRAGCOORD.xy), 4.0);
		vec2 low = mod(pixel, 2.0);
		vec2 high = floor(pixel * 0.5);
		float bayer = 4.0 * mod(dot(low, vec2(2.0, 3.0)), 4.0) + mod(dot(high, vec2(2.0, 3.0)), 4.0);
		if (bayer < camera_cutaway * 16.0) {
			discard;
		}
	}
	vec3 original = texture(palette, UV).rgb;
	float grade = dot(original, vec3(0.2126, 0.7152, 0.0722));
	float warning = smoothstep(0.04, 0.35, original.r - original.b);
	vec3 graphite = mix(vec3(0.025, 0.018, 0.024), vec3(0.24, 0.21, 0.22), smoothstep(0.0, 0.65, grade));
	vec3 lacquer = vec3(0.45, 0.035, 0.052) * (0.32 + grade * 1.05);
	float pigment = max(warning, smoothstep(0.22, 0.65, grade) * 0.90);
	vec3 red = mix(graphite, lacquer, pigment);
	ALBEDO = mix(original, red, red_black);
	ALBEDO = mix(ALBEDO, vec3(1.0, 0.035, 0.025), hit_flash * 0.92);
	if (role == 1) {
		METALLIC = 0.58;
		ROUGHNESS = 0.32;
	} else if (role == 2) {
		METALLIC = 0.12;
		ROUGHNESS = 0.61;
	} else if (role == 3) {
		METALLIC = 0.30;
		ROUGHNESS = 0.26;
		CLEARCOAT = 0.55;
		CLEARCOAT_ROUGHNESS = 0.29;
	} else {
		METALLIC = 0.10;
		ROUGHNESS = 0.41;
		vec3 lamp = mix(vec3(0.65, 0.055, 0.08), vec3(1.0, 0.36, 0.065), warning) * (0.25 + 2.2 * grade);
		EMISSION = mix(original * 1.9, lamp, red_black);
	}
	EMISSION += vec3(1.0, 0.02, 0.01) * hit_flash * 1.8;
	EMISSION += vec3(1.0, 0.40, 0.08) * slam_charge;
}
