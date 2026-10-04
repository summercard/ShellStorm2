class_name RingProgressGeometry
extends RefCounted
## 环形进度几何的**唯一真源**。
##
## 谁在用：
## - 交互圆点 `InteractionDot3D` 的读条环（搜索容器 / 过门 / 撤离 / 切灯…）；
## - 角色换弹环 `PlayerAvatar3D`（0.2-PLAYER-001：横条 → 圆环，位置挪到角色下方）。
##
## 两者是同一套视觉语言（见 `docs/v0.2/PLAN.md` 的 0.2-PRESENTATION-001 与
## 0.2-PLAYER-001：诉求末句「所有圈的进度条要统一」），所以绘圆口径只留一份 ——
## 有第二份独立实现就一定会漂移，而漂移的表现是「整块被剔除 / 半透明糊成一坨」
## 这种「日志全绿、画面全错」的形态。
##
## ⚠️ 绕序约定：Godot 的**正面 = 从 +Z 看顺时针**（与引擎自带 QuadMesh 一致）。
## 曾经写成逆时针，整块被 CULL_BACK 剔除，圆点只剩 0.62R 的内核。
## 改这里之前先跑 `verify_interaction_dot_presentation` 的绕序断言（它拿引擎 QuadMesh
## 的首三角法线当参考基准）。
##
## 圆环起点从 **12 点方向**开始、顺时针推进 —— 与屏幕上看到的方向一致。

## 默认分段数。读条环 48 段；换弹环在角色脚下、半径更大，调用方给 64。
const DEFAULT_SEGMENTS := 48
## 起点角度：mesh 空间的 12 点方向（+Y）。
const START_ANGLE := PI * 0.5
## 默认首尾淡出比例（相对整圈）。0 = 均匀不淡出。
const DEFAULT_END_FADE_RATIO := 0.06


## 整圈环带（底轨）。progress 恒为 1，通常当「空槽」使用。
static func build_annulus(
	inner_radius_m: float, outer_radius_m: float, segments := DEFAULT_SEGMENTS
) -> ArrayMesh:
	return build_arc(inner_radius_m, outer_radius_m, 1.0, segments, 0.0)


## 按角度裁切出的圆弧：从 12 点起顺时针扫过 progress 比例（0..1）。
##
## end_fade_ratio > 0 时首尾 alpha 自然淡出（圆点读条环用，让弧头不突兀）；
## 传 0 得到亮度均匀的一圈（换弹环用 —— 它是「填充量」，淡出会读成"没走完"）。
static func build_arc(
	inner_radius_m: float,
	outer_radius_m: float,
	progress: float,
	segments := DEFAULT_SEGMENTS,
	end_fade_ratio := DEFAULT_END_FADE_RATIO
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var swept := clampf(progress, 0.0, 1.0)
	if swept <= 0.0:
		# 空弧仍返回一个合法（零三角面）网格：调用方不必判空，可见性由外层管。
		return build_mesh(vertices, colors, indices)
	var drawn := maxf(1.0, ceil(float(segments) * swept))
	for index in range(int(drawn) + 1):
		var ratio := float(index) / drawn
		var angle := START_ANGLE - TAU * swept * ratio
		var alpha := 1.0
		if end_fade_ratio > 0.0:
			if ratio < end_fade_ratio:
				alpha = ratio / end_fade_ratio
			elif ratio > 1.0 - end_fade_ratio:
				alpha = (1.0 - ratio) / end_fade_ratio
		var outer := Vector3(cos(angle), sin(angle), 0.0) * outer_radius_m
		var inner := Vector3(cos(angle), sin(angle), 0.0) * inner_radius_m
		vertices.append(outer)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
		vertices.append(inner)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	var total := int(drawn)
	for index in range(total):
		var base := index * 2
		# 与圆盘扇面同向（从 +Z 看顺时针）。环带绕反过一次：扇面翻正了、环带没翻，
		# 结果占 2/3 面积的环带整块被剔除，圆点只剩 0.62R 的内核 —— 直径凭空少一半，
		# 而 visible / AABB / surfaces 全都正常。
		indices.append(base)
		indices.append(base + 3)
		indices.append(base + 1)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 3)
	return build_mesh(vertices, colors, indices)


## 顶点色 + 固定 +Z 法线的三角网格。绕序由调用方保证（见文件头）。
##
## 空弧（progress = 0）返回**没有 surface** 的 ArrayMesh：给空数组调
## `add_surface_from_arrays()` 会报 `Condition "array_len == 0" is true` +
## `err != OK` 两组引擎错误，把日志弄脏（验收门禁会因此判红），而空网格本来就
## 什么都不画 —— 少一次无意义的调用。换弹环在每局开始就处于 progress = 0。
static func build_mesh(
	vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if indices.is_empty() or vertices.is_empty():
		return mesh
	var normals := PackedVector3Array()
	for _index in range(vertices.size()):
		normals.append(Vector3(0.0, 0.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
