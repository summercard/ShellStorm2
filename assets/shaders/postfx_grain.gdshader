// 全屏后处理 overlay：屏幕空间颗粒（噪点）+ 可选色相偏移。
// 通过 hint_screen_texture 抓 viewport 颜色，按 SCREEN_UV 输出。
// FlashlightColorTweaker P 键面板 -> PostfxOverlay autoload -> 改 uniform。
//
// 设计取舍：
// - 颗粒使用简单 hash 噪声而非 Perlin，避免移动端片段压力；
// - 颗粒尺寸 strength 线性映射（0..1），用户视角下与 Godot 原 grain_* 同语义。
// - 色相用 RGB -> HSV -> rotate hue -> RGB，避免依赖 Color 资源。
// - 整体 alpha 1.0，overlay 默认 visible=false 由代码控制。

shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grain_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float grain_size : hint_range(0.05, 3.0, 0.05) = 1.0;
uniform float hue_shift : hint_range(0.0, 1.0, 0.005) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	if (hue_shift > 0.0001) {
		vec3 hsv = rgb2hsv(col);
		hsv.x = fract(hsv.x + hue_shift);
		col = hsv2rgb(hsv);
	}

	if (grain_strength > 0.0001) {
		float scale = max(grain_size, 0.05);
		vec2 pixel = floor(SCREEN_UV / max(SCREEN_PIXEL_SIZE, vec2(0.001)) * scale);
		float n = hash21(pixel + floor(TIME * 60.0));
		float delta = (n - 0.5) * grain_strength;
		col = clamp(col + delta, 0.0, 1.0);
	}

	COLOR = vec4(col, 1.0);
}