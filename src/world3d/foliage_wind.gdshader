shader_type spatial;

// 叶面风摆：只位移顶点，不改材质表现。
//
// 为什么是顶点位移而不是旋转节点：
//   植物顶点在本地坐标以 y=0 起算，按高度加权就能让「花盆/箱体不动、枝叶摆」一次到位。
//   基地植物顶点是世界坐标烘焙的，旋转节点会绕世界原点甩飞 —— 顶点位移对两者都安全。
//
// 为什么「金属骨架」也要一起位移（不能只摆叶片）：
//   实测五类植物都是「金属枝干 + 哑光叶片」两张 surface。只摆叶片的话，
//   3.5cm 的叶片位移会让叶子脱离枝干（4m 尺度上肉眼可见）。
//   所以两张面都套本 shader，各用自己的 albedo/metallic/roughness，表现完全不变。
//
// 为什么需要 foliage_base_y：
//   花盆与叶片**共用同一个「青绿大面」surface**（实测 plant_large 的 444 个顶点里，
//   y=0 那一层 72 点是盆底、radius 0.482；叶片从 y=1.15 才开始）。
//   不设底座高度，整只花盆会跟着摆。
//
// 为什么需要 sway_from_top：
//   藤蔓（ivy / parapet_ivy）是**顶部固定在墙上、向下垂挂**，固定端在上；
//   盆栽与花箱从土里往上长，固定端在下。权重方向相反，不能用同一个公式。

render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
// 由脚本从原材质读入。色盘采样器带 source_color 做 sRGB 解码后，
// albedo_color 必须原值传入 —— 再转一次 linear 会让整株偏暗约 12%（实测 108 vs 123）。
uniform vec4 albedo_tint = vec4(0.9063, 0.9063, 0.9063, 1.0);
uniform float metallic_value = 0.025;
uniform float roughness_value = 0.72;
uniform float specular_value = 0.5;

// 共享时钟：全场景每档材质共用一份 ShaderMaterial，每帧只写这一个参数。
uniform float wind_time = 0.0;
uniform float sway_amplitude = 0.035;
// 固定端高度（本地米）与摆动区间长度（本地米）。由脚本按 prefab 实测传入。
uniform float foliage_base_y = 0.0;
uniform float foliage_span = 2.0;
// true = 顶部固定向下垂（藤蔓）；false = 根部固定向上长（盆栽/花箱）。
uniform bool sway_from_top = false;
// true = 贴墙件（藤蔓）：横向沿墙面水平摆为主 + 离墙扑动为辅。
//   ⚠️ 2026-10-18 业主反馈「藤蔓不动」。根因是最初只做本地 z 的离墙扑动 ——
//   墙面在 x-y 平面，z 位移在正面视角下几乎没有透视变化，等于看不出来。
//   故改为横向（本地 x）主导；横向不穿墙（墙厚方向是 z），且正面可见。
//   离墙分量保留 0.5 倍，让叶片有起落，不至于像整块贴图平移。
uniform bool wall_mounted = false;
// 与云海同向（0.85, -0.53）：云往哪飘，叶子就往哪倒。
uniform vec2 wind_direction = vec2(0.85, -0.53);

void vertex() {
	float height_ratio = clamp((VERTEX.y - foliage_base_y) / max(foliage_span, 0.001), 0.0, 1.0);
	if (sway_from_top) {
		height_ratio = 1.0 - height_ratio;
	}
	// 指数 1.5（原 1.8）：业主 2026-10-18 反馈「不够明显」，
	// 指数过高会把位移全挤到尖端，中段叶片几乎不动，读起来像只有最上面几片在抖。
	// 1.5 让整层枝叶一起走，根部仍是 0。
	float weight = pow(height_ratio, 1.5);
	// 相位 = 植株世界位置（相邻植物不同步）+ 本地偏移（同一株内枝条错开）。
	vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = dot(instance_origin.xz, vec2(0.31, 0.47)) + dot(VERTEX.xz, vec2(0.21, 0.33));
	// 主频 1.55 rad/s ≈ 4.1s 一个来回；副频 1.7 倍做非正弦起伏。
	float sway = 0.72 * sin(1.55 * wind_time + phase) + 0.28 * sin(2.65 * wind_time + 1.7 * phase);
	float gust = 0.62 + 0.38 * sin(0.21 * wind_time + 0.13 * phase);
	float amount = sway_amplitude * weight * gust * sway;
	if (wall_mounted) {
		// 横向（沿墙面水平）为主，正面可见；离墙扑动为辅，给叶片起落。
		// 横向用固定符号：墙面是竖直面，水平摆动不会穿过墙体（墙厚在 z 方向）。
		VERTEX.x += sign(wind_direction.x) * amount;
		VERTEX.z += sign(VERTEX.z) * amount * 0.5;
	} else {
		VERTEX.xz += normalize(wind_direction) * amount;
	}
}

void fragment() {
	ALBEDO = texture(palette, UV).rgb * albedo_tint.rgb;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
