extends Node
## 天台参考组件库 v002「地砖 + 外墙（实墙 / 窗墙）」接入验收（2026-09-20 新增）。
##
## 三类断言，缺一不可：
##   1. 包络与原点：每件 GLB 的实测包络 == 参考组件库 catalog 的 bounds_size，且原点在
##      底面中心（AABB 底面 Y=0）。摆放公式（顶面贴 Y=0 / 底面贴 Y=-12）直接依赖这一点，
##      写错就是整圈错台。
##   2. Prefab 契约：asset_id / origin_contract / bounds_size_m / visual_node_name 齐备，
##      且 TowerGeometry3D.resolve_visual_bounds(prefab) 与声明的 bounds_size_m 逐值相同
##      —— 防「声明的包络」与「实际摆出来的包络」各写一份而漂移。
##   3. 色盘：每个表面都绑上共享色盘 albedo_texture —— 防「新 GLB 的 .import 没绑
##      scene_facility_shared_palette_post_import.gd」→ 进游戏是白板且不触发门禁。
##
## 防假绿哨兵：三件任一件加载失败都会让样本数落到 0，而「全部表面都有色盘」在 0 样本下
## 恒真。因此先打印 SAMPLES=n，n < 期望件数直接判红。

const COMPONENTS: Array = [
	{
		"label": "floor_full",
		"asset_id": "ENV-ROOFTOP-REF-FLOOR-FULL",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_floor_5m.tscn",
		"expected_size": Vector3(5.0, 0.3, 5.0),
		"expected_min_surfaces": 1,
	},
	{
		"label": "facade_solid",
		"asset_id": "ENV-ROOFTOP-REF-FACADE-SOLID",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_facade_solid_5m.tscn",
		"expected_size": Vector3(5.0, 11.9, 0.3),
		"expected_min_surfaces": 1,
	},
	{
		"label": "facade_window",
		"asset_id": "ENV-ROOFTOP-REF-FACADE-WINDOW",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_facade_window_5m.tscn",
		"expected_size": Vector3(5.0, 11.9, 0.3),
		"expected_min_surfaces": 3,
	},
]
const SIZE_TOLERANCE := 0.001
const ORIGIN_TOLERANCE := 0.001


func _ready() -> void:
	var failures: Array[String] = []
	var samples := 0
	var surfaces_checked := 0
	var surfaces_palette_bound := 0

	for entry in COMPONENTS:
		var label := str(entry["label"])
		var prefab_path := str(entry["prefab"])
		var expected_size := entry["expected_size"] as Vector3
		var expected_surfaces := int(entry["expected_min_surfaces"])

		var packed := ResourceLoader.load(
			prefab_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
		) as PackedScene
		if packed == null:
			_expect(false, "%s 的 prefab 加载失败：%s" % [label, prefab_path], failures)
			continue
		var instance := packed.instantiate()
		samples += 1
		add_child(instance)

		# —— 1. 声明元数据 ——
		_expect(
			str(instance.get_meta("asset_id", "")) == str(entry["asset_id"]),
			"%s 的 asset_id 声明不符：%s" % [label, str(instance.get_meta("asset_id", ""))],
			failures
		)
		_expect(
			str(instance.get_meta("origin_contract", "")) == "bottom_center",
			"%s 的 origin_contract 不是 bottom_center" % label,
			failures
		)
		_expect(
			bool(instance.get_meta("visual_only", false)),
			"%s 不是 visual_only（碰撞必须留给 TowerFloorStage3D 的边界代理体）" % label,
			failures
		)
		_expect(
			str(instance.get_meta("collision_owner", "")) == "TowerFloorStage3D",
			"%s 的 collision_owner 不是 TowerFloorStage3D" % label,
			failures
		)
		_expect(
			str(instance.get_meta("visual_node_name", "")) != "",
			"%s 没有声明 visual_node_name（批渲染取网格唯一入口靠它）" % label,
			failures
		)

		# —— 2. 实测包络 == 声明包络 == 期望包络 ——
		var declared: Variant = instance.get_meta("bounds_size_m", null)
		_expect(
			declared is Vector3 and (declared as Vector3).is_equal_approx(expected_size),
			"%s 的 bounds_size_m 声明 %s != 期望 %s" % [label, str(declared), str(expected_size)],
			failures
		)
		var bounds := TowerGeometry3D.resolve_visual_bounds(instance)
		_expect(
			bounds.size.is_equal_approx(expected_size),
			"%s 实测包络 %s != 期望 %s（catalog bounds_size 口径）"
				% [label, str(bounds.size), str(expected_size)],
			failures
		)
		_expect(
			absf(bounds.position.y) <= ORIGIN_TOLERANCE,
			"%s 原点不在底面中心：AABB 底面 Y=%.5f（应为 0）" % [label, bounds.position.y],
			failures
		)
		_expect(
			absf(bounds.position.x + bounds.size.x * 0.5) <= ORIGIN_TOLERANCE
				and absf(bounds.position.z + bounds.size.z * 0.5) <= ORIGIN_TOLERANCE,
			"%s 没有在 XY 上居中（AABB 中心 %s）" % [label, str(bounds.get_center())],
			failures
		)

		# —— 3. 色盘：每个表面都要绑共享色盘 ——
		var mesh := TowerGeometry3D.resolve_visual_mesh(instance)
		if mesh == null:
			_expect(false, "%s 取不到批渲染网格（visual_node_name 指错？）" % label, failures)
			remove_child(instance)
			instance.free()
			continue
		var surface_count := mesh.get_surface_count()
		_expect(
			surface_count >= expected_surfaces,
			"%s 表面数 %d < 期望 %d" % [label, surface_count, expected_surfaces],
			failures
		)
		for surface_index in range(surface_count):
			surfaces_checked += 1
			var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
			if material == null:
				_expect(false, "%s 表面 %d 没有材质" % [label, surface_index], failures)
				continue
			if material.albedo_texture == null:
				_expect(
					false,
					"%s 表面 %d 的 albedo_texture 为空（.import 没绑共享色盘脚本？会白板）"
						% [label, surface_index],
					failures
				)
				continue
			surfaces_palette_bound += 1
			print(
				"  [%s] surface=%d material=%s palette=%s"
				% [
					label,
					surface_index,
					str(material.resource_name),
					str(material.albedo_texture.resource_path),
				]
			)
		print(
			"  [%s] bounds=%s surfaces=%d" % [label, str(bounds.size), surface_count]
		)

		remove_child(instance)
		instance.free()

	# 哨兵：样本数不足时下面「全部表面都有色盘」会退化成恒真。
	print("  SAMPLES=%d surfaces_checked=%d palette_bound=%d" % [
		samples, surfaces_checked, surfaces_palette_bound
	])
	_expect(samples == COMPONENTS.size(), "样本数 %d != 期望 %d" % [samples, COMPONENTS.size()], failures)
	_expect(
		surfaces_checked >= COMPONENTS.size(),
		"表面样本数 %d 过少（0 样本下色盘断言恒真）" % surfaces_checked,
		failures
	)
	_expect(
		surfaces_palette_bound == surfaces_checked,
		"色盘未绑满：%d/%d 个表面绑上共享色盘" % [surfaces_palette_bound, surfaces_checked],
		failures
	)

	await get_tree().process_frame
	if failures.is_empty():
		print(
			"ROOFTOP_FLOOR_FACADE_COMPONENTS_PASS: %d 件 / %d 个表面，包络·原点·色盘全对"
				% [samples, surfaces_checked]
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
