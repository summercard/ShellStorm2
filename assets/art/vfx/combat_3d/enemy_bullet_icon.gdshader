shader_type spatial;
// 敌方子弹图标（2026-11-09 主人：「敌方子弹也一样」—— 即同样做成一直面对摄像机的公告板）。
//
// 为什么敌方子弹要 billboard：俯视 52° 下，3D 棱柱弹体在屏幕上是「一根短棍的顶面」，
// 飞行方向一变就只剩一个点，暗场景里几乎读不出来。改成面向相机的图标后，
// 任何角度都是一颗「发光能量弹」，形状恒定、颜色恒定，玩家一眼能判读。
//
// 为什么不用 `render_mode billboard`：同准星 shader —— Godot 的 billboard 只绕 Y 轴，
// 俯视会被压扁。朝向由 `VfxBulletBody3D._pose_icon()` 手写基向量驱动。
//
// 图标构图（由内到外）：
//   ① 白热核心：判定球的实际大小，所见即所中
//   ② 弹色光层：核心外的实心环，给颜色
//   ③ 外晕：径向衰减，让子弹在暗处有存在感
//   ④ 细外框：一圈深色描边，压在亮地面/亮特效上也不糊
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 弹色由脚本按 `bullet_color` 逐发写入（池化复借会换色）。
uniform vec4 bullet_color : source_color = vec4(1.0, 0.36, 0.32, 1.0);
// 白热核心
uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.94, 1.0);
// 描边（深色，靠 alpha 控制强度）
uniform vec4 rim_color : source_color = vec4(0.05, 0.02, 0.03, 0.75);

// 核心半径（UV），必须与 `BulletBillboardIcon3D.CORE_UV_RADIUS` 一致 ——
// 那里用它反算面片世界尺寸，使核心直径正好等于判定球直径。
// 0.30 是实拍定的上限：再大，白热核心就会盖住整颗弹、颜色只剩最外一圈细细的边，
// 三发不同弹色的敌弹在屏幕上全都读成「白色圆点」（2026-11-09 首版实拍）。
uniform float core_radius = 0.30;
// 弹色层的实心半径。0.42 让弹色环有 0.12 UV 宽 —— 白核 0.30 + 色环 0.12。
uniform float body_radius = 0.42;
// 外晕衰减到零的半径
uniform float halo_radius = 0.50;
uniform float rim_radius = 0.435;
uniform float rim_half_width = 0.012;
uniform float edge_softness = 1.0;
// 亮度增益。⚠ 这个值**加上核心增益**必须留在 1.0 附近：ALBEDO 一旦超过 1 就被
// 硬钳到白，三发不同弹色的敌弹会全部读成「白色圆点」（2026-11-09 首版实拍踩过：
// glow 1.25 + 核心 0.9 = 2.15 倍，紫色弹的核心实测 RGB ≈ (1.9, 1.46, 2.15) ⇒ 全白）。
uniform float glow = 0.95;
// 核心的额外提亮量，只给一点点「白热」读法，不破坏弹色。
uniform float core_boost = 0.18;
// 核心的「白化」程度：1 = 纯白（丢颜色），0 = 完全用弹色。
// 0.35 是实拍折中：核心仍读成发热的亮点，但红弹 / 紫弹 / 橙弹一眼分得出。
uniform float core_whiteness = 0.35;

float coverage(float distance, float half_width) {
	float edge = max(fwidth(distance), 0.00035) * edge_softness;
	return 1.0 - smoothstep(half_width - edge, half_width + edge, distance);
}

void fragment() {
	float radius = length(UV - vec2(0.5));

	// ① 白热核心
	float a_core = coverage(radius - core_radius, 0.0);
	// ② 弹色实心层（核心之外到 body_radius）
	float a_body = coverage(radius - body_radius, 0.0);
	// ③ 外晕：从 body_radius 线性衰减到 halo_radius
	float a_halo = 1.0 - smoothstep(body_radius, halo_radius, radius);
	// ④ 细描边
	float a_rim = coverage(abs(radius - rim_radius), rim_half_width);

	// 合成顺序：晕在最底，弹色层覆盖它，核心覆盖弹色层，描边最后压上。
	vec3 rgb = bullet_color.rgb * 0.75;
	float alpha = a_halo * 0.42;
	rgb = mix(rgb, bullet_color.rgb, a_body);
	alpha = max(alpha, a_body * bullet_color.a);
	// 核心不是纯白，而是「弹色提亮」：纯白会让三发不同弹色的敌弹在屏幕上一模一样。
	vec3 hot_core = mix(bullet_color.rgb, core_color.rgb, core_whiteness);
	rgb = mix(rgb, hot_core, a_core);
	alpha = max(alpha, a_core);
	rgb = mix(rgb, rim_color.rgb, a_rim * rim_color.a);
	alpha = max(alpha, a_rim * rim_color.a);

	ALBEDO = rgb * (glow + a_core * core_boost);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
