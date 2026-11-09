shader_type spatial;
// 准星图标（2026-11-09 主人：「准星重新设计，设计成准星的图标，一直面对摄像机的公告板」）。
//
// 为什么是 shader 而不是贴图：准星的屏幕尺寸随距离变化（恒定像素口径），
// 位图会被重采样糊掉；SDF 画法在任意尺寸下边缘都是干净的。
//
// 为什么朝向由脚本驱动而不是 `render_mode billboard`：
// Godot 的 billboard 只绕 **Y 轴**转（Y-billboard），本作相机俯视约 52°，
// 面片会被压成 sin(52°) ≈ 0.79 的椭圆 —— 正是本文件要消灭的东西。
// 朝向真源在 `Player3D._pose_aim_cursor()`，那里直接把基向量设成相机 basis。
//
// `depth_test_disabled`：准星**必须永远看得见**。
// 它贴在枪口高度的瞄准平面上，而瞄准敌人时那个点就在敌人身体里 ——
// 开着深度测试会正好在最需要准心的时候把它埋进网格（同贪心环
// `RELOAD_RING_DRAW_OVER_CHARACTER` 的取舍）。代价是准星也会画在墙前面，
// 这与 HUD 惯例一致：准星是「我在瞄哪」的指示器，不是世界物体。
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

// 环（细外环）
uniform vec4 ring_color : source_color = vec4(0.24, 0.86, 1.0, 0.86);
// 四向刻度
uniform vec4 tick_color : source_color = vec4(0.62, 0.96, 1.0, 0.96);
// 中心点
uniform vec4 dot_color : source_color = vec4(0.92, 0.99, 1.0, 1.0);

// 以下半径都是 UV 单位（0.5 = 面片边缘）。改大小请改 `Player3D.AIM_CURSOR_SCREEN_PX`，
// 不要动这里 —— 这里的比例关系决定「环 / 刻度 / 点」的读数，放大缩小会破坏构图。
uniform float ring_radius = 0.205;
uniform float ring_half_width = 0.016;
uniform float tick_inner = 0.255;
uniform float tick_outer = 0.355;
uniform float tick_half_width = 0.014;
// 0.040 是实拍定的：0.028 时中心点在 1080p 只有 2px，看上去像脏点而不是准心。
uniform float dot_radius = 0.040;
// 边缘软化倍率：1 = 按屏幕导数自适应（1px 抗锯齿）；调大更糊、调小更硬。
uniform float edge_softness = 1.0;
// 亮度增益（unshaded 下直接乘到输出色）。
uniform float glow = 1.35;

// 有符号距离 → 覆盖率。fwidth 让抗锯齿宽度随实际屏幕像素变化，
// 所以图标放大到 200px 或缩到 20px 边缘都一样干净。
float coverage(float distance, float half_width) {
	float edge = max(fwidth(distance), 0.00035) * edge_softness;
	return 1.0 - smoothstep(half_width - edge, half_width + edge, distance);
}

// 矩形有符号距离：q = 相对矩形中心的偏移，half_size = 半宽半高。内部为负。
float box_distance(vec2 q, vec2 half_size) {
	vec2 d = abs(q) - half_size;
	return max(d.x, d.y);
}

void fragment() {
	vec2 p = UV - vec2(0.5);

	// 外环：|length(p) - r| <= w
	float a_ring = coverage(abs(length(p) - ring_radius), ring_half_width);

	// 四向刻度：沿 ±X / ±Y 各一根短柱，从环外向内指。
	// `abs(p.x)` 做镜像，一条表达式同时覆盖左右（上下同理）。
	float mid = (tick_inner + tick_outer) * 0.5;
	float half_len = (tick_outer - tick_inner) * 0.5;
	vec2 half_size = vec2(half_len, tick_half_width);
	float tick_x = box_distance(vec2(abs(p.x) - mid, p.y), half_size);
	float tick_y = box_distance(vec2(abs(p.y) - mid, p.x), half_size);
	float a_tick = coverage(min(tick_x, tick_y), 0.0);

	// 中心点
	float a_dot = coverage(length(p) - dot_radius, 0.0);

	// 三层按各自 alpha 加权混合：中心点最亮，环最淡，读数「中间是准心、外面是圈」。
	float w_ring = a_ring * ring_color.a;
	float w_tick = a_tick * tick_color.a;
	float w_dot = a_dot * dot_color.a;
	float w_sum = w_ring + w_tick + w_dot;
	vec3 rgb = vec3(0.0);
	if (w_sum > 0.0001) {
		rgb = (ring_color.rgb * w_ring + tick_color.rgb * w_tick + dot_color.rgb * w_dot) / w_sum;
	}
	ALBEDO = rgb * glow;
	ALPHA = clamp(w_sum, 0.0, 1.0);
}
