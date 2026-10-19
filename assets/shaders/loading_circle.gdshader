// 读取页兔子身后的两枚圆形色块（平面纯色，探照灯交错移动）。
//
// 形态：两个**纯色实心圆**，没有任何内部衰减、没有光晕、没有柔边 ——
// 圆内是恒定颜色，圆外完全透明，边界只有 edge 宽度的一像素级抗锯齿带。
// 这不是"光"，是两块贴上去的色片；光的读法完全靠 `blend_add` 叠加：
// 单灯区 = 1×，两灯交叠 = 2×，交叠区自己就成了一块更亮的实色形状。
//
// 为什么去掉衰减：柔边/内衰减会读成"光晕"。纯色 + 硬边才是平面图形语言，
// 与读取页的棱镜线框（纯白剪影、纯白进度条）同一套语汇。
//
// 颜色：正黄。实测单灯区 = rgb(118, 103, 30)（内部多点采样零方差），
// 交叠区 = rgb(229, 191, 38)，正是前者减去底色后翻倍 —— add 的数学结果，不是另调的颜色。
// add 模式下 light_color 是**加色量**：交叠处加两次，所以只给单灯峰值。
//   单灯增量 = (118,103,30) - 底色(8,14,22) = (110, 89, 8)
//   light_color = (110, 89, 8)/255 ≈ (0.435, 0.349, 0.031)
// 判定"够不够黄"要分开看两个量，混用会调错方向：
//   增量比值 G/R = 0.81、B/R = 0.07 —— 这是光源本身的色相，决定"黄不黄"；
//   成品比值 G/R = 0.87、B/R = 0.25 —— 含了底色，B 会被底色抬起来。
// 上一版增量 B/R = 0.33，蓝太多，所以成品读成橄榄 / 卡其。
//
// 动态：两灯的偏移由脚本每帧写入 offset_a / offset_b，二者相位差 π ——
// 沿同一椭圆反向运动，从两侧扫过、在中间交错而过。
// 着色器自己不读 TIME，相位由脚本掌握，暂停/淡出时不会出现「色块还在动、进度条停住」。

shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 light_color : source_color = vec4(0.435, 0.349, 0.031, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
/// 灯 A 的圆心相对控件中心的偏移（uv），脚本写入。
uniform vec2 offset_a = vec2(0.0, 0.0);
/// 灯 B 的圆心相对控件中心的偏移（uv），脚本写入。与 A 相位差 π，形成交错。
uniform vec2 offset_b = vec2(0.0, 0.0);
/// 圆半径（uv 单位，相对控件边长）。
uniform float radius : hint_range(0.05, 0.6) = 0.25;
/// 边界抗锯齿带宽度（uv）。只够压掉锯齿，不参与塑形 —— 再大就不是纯色硬边了。
/// 0.014 × 360px ≈ 5px，实测从底色到纯色约 2px 过渡。
uniform float edge : hint_range(0.004, 0.12) = 0.014;

/// 单枚纯色圆：圆内恒为 1，圆外恒为 0，只留一像素抗锯齿带。
float disc(vec2 uv, vec2 center) {
	float d = length(uv - center) / max(radius, 0.001);
	return 1.0 - smoothstep(1.0 - edge, 1.0, d);
}

void fragment() {
	vec2 base = vec2(0.5);
	// 两块纯色相加：交叠区 = 2×，单灯区 = 1× —— 这就是 add 的观感来源。
	float v = disc(UV, base + offset_a) + disc(UV, base + offset_b);
	COLOR = vec4(light_color.rgb * clamp(v, 0.0, 2.0) * intensity, 1.0);
}
