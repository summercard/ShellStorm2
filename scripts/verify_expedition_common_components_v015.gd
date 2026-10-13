extends SceneTree
## 远征关卡02 通用组件库 v015 · 独立加载与契约验证（纯只读）。
##
## 跑法：
##   godot --headless --path "<项目根>" --script res://scripts/verify_expedition_common_components_v015.gd
##
## 逐件验证：PackedScene 可加载 / 可实例化、ImportedModel 在位、layer=1 碰撞体数量与尺寸、
## 材质 albedo_texture 指向唯一公共色盘、包络尺寸与 slot 相符。
##
## 🔴 封顶件（`ceiling_deck_5m`）单独加两条：碰撞层必须是 1、碰撞盒必须盖满整个 5×5 槽。
## 这两条一旦不成立，房间「不受太阳照射」就是假的 —— 而且**画面上看不出来**。

const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const PREFAB_ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

## slug -> {collision_shapes: [Vector3 尺寸], top_cover: bool}
const EXPECTED := {
	"wall_standard_5m_h3": {
		"shapes": [Vector3(5, 3, 0.3)],
		"top_cover": false,
	},
	"wall_door_5m_h3": {
		"shapes": [Vector3(1.4, 3, 0.3), Vector3(1.4, 3, 0.3), Vector3(2.2, 0.2, 0.3)],
		"top_cover": false,
	},
	"wall_collapse_5m_h12": {
		"shapes": [Vector3(5, 9.1, 0.3)],
		"top_cover": false,
	},
	"wall_standard_5m_h12": {
		"shapes": [Vector3(5, 11.9, 0.3)],
		"top_cover": false,
	},
	"wall_door_5m_h12": {
		"shapes": [Vector3(1.4, 11.9, 0.3), Vector3(1.4, 11.9, 0.3), Vector3(2.2, 9.1, 0.3)],
		"top_cover": false,
	},
	"floor_tile_5m": {
		"shapes": [],
		"top_cover": false,
		"no_collision": true,
	},
	"ceiling_deck_5m": {
		"shapes": [Vector3(5, 0.26, 5)],
		"top_cover": true,
	},
	"floor_base_5m": {
		"shapes": [Vector3(5, 0.26, 5)],
		"top_cover": false,
	},
}

var failures: Array[String] = []


func _initialize() -> void:
	var checked := 0
	for slug in EXPECTED.keys():
		checked += _verify(slug, EXPECTED[slug])
	if failures.is_empty():
		print("EXPEDITION_COMMON_V015_VERIFY_OK components=%d" % checked)
		quit(0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	quit(1)


func _verify(slug: String, expect: Dictionary) -> int:
	var scene_path := "%s/%s/%s_root_top3d.tscn" % [PREFAB_ROOT, slug, slug]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("%s: PackedScene 加载失败 %s" % [slug, scene_path])
		return 0
	var instance := packed.instantiate()
	if instance == null:
		_fail("%s: 实例化失败" % slug)
		return 0
	_root_inspect(slug, instance, expect)
	instance.free()
	return 1


func _root_inspect(slug: String, root: Node, expect: Dictionary) -> void:
	if root is not Node3D:
		_fail("%s: 根节点不是 Node3D" % slug)
		return
	var model := root.get_node_or_null("ImportedModel")
	if model == null:
		_fail("%s: 缺 ImportedModel" % slug)

	# ---- 碰撞体 ----
	var body := root.get_node_or_null("CollisionBody") as StaticBody3D
	if expect.get("no_collision", false):
		# 纯视觉面砖：**必须没有**碰撞体。多了会让地面出现 0.04m 的空阻挡台阶。
		if body != null:
			_fail("%s: 声明为纯视觉（无碰撞），却存在 CollisionBody" % slug)
	else:
		if body == null:
			_fail("%s: 缺 CollisionBody" % slug)
		else:
			if body.collision_layer != 1:
				_fail("%s: CollisionBody.collision_layer=%d，必须是 1" % [slug, body.collision_layer])
			var shapes: Array[Vector3] = []
			for child in body.get_children():
				var shape_node := child as CollisionShape3D
				if shape_node == null:
					continue
				var box := shape_node.shape as BoxShape3D
				if box == null:
					_fail("%s: 碰撞体不是 BoxShape3D（%s）" % [slug, child.name])
					continue
				shapes.append(box.size)
			var wanted: Array = expect["shapes"]
			if shapes.size() != wanted.size():
				_fail("%s: 碰撞盒数 %d，期望 %d" % [slug, shapes.size(), wanted.size()])
			else:
				for index in wanted.size():
					if not shapes[index].is_equal_approx(wanted[index]):
						_fail("%s: 碰撞盒 %d 尺寸 %s，期望 %s"
							% [slug, index, str(shapes[index]), str(wanted[index])])

			# 🔴 封顶件专条：层与全槽覆盖
			if expect["top_cover"]:
				if body.collision_layer != 1:
					_fail("%s: 封顶件碰撞层不是 1 —— 太阳射线会穿过去，房间不受日照是假的" % slug)
				if shapes.is_empty() or not shapes[0].is_equal_approx(Vector3(5, 0.26, 5)):
					_fail("%s: 封顶件碰撞盒未盖满 5×5 槽（实得 %s）" % [slug, str(shapes)])

			# 🔴 摄像机遮挡标记专条。
			# 射线命中返回的是 CollisionObject3D，所以标记必须落在 CollisionBody 上；
			# 写在根节点上读不到，等于没写，而**不会报任何错**。
			var marker := ""
			if slug.begins_with("wall_"):
				marker = "camera_lower_wall"
			elif slug == "ceiling_deck_5m":
				marker = "camera_ceiling_occluder"
			if not marker.is_empty():
				if not bool(body.get_meta(marker, false)):
					_fail("%s: CollisionBody 缺 %s —— 组件级镜头遮挡不生效" % [slug, marker])
			else:
				for forbidden in ["camera_lower_wall", "camera_ceiling_occluder"]:
					if bool(body.get_meta(forbidden, false)):
						_fail("%s: 非墙非顶盖件带了 %s" % [slug, forbidden])

	# ---- 材质：必须绑到唯一公共色盘 ----
	var palette := load(PALETTE_PATH)
	if palette == null:
		_fail("%s: 公共色盘加载失败 %s" % [slug, PALETTE_PATH])
	var mesh_nodes := _collect_meshes(root)
	if mesh_nodes.is_empty():
		_fail("%s: 没有任何 MeshInstance3D" % slug)
	for mesh_node in mesh_nodes:
		var mesh := mesh_node.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				continue
			if material.albedo_texture == null:
				_fail("%s: %s 表面 %d 的 albedo_texture 为空（色盘后处理未生效）"
					% [slug, mesh_node.name, surface])
			elif material.albedo_texture.resource_path != PALETTE_PATH:
				_fail("%s: %s 表面 %d 的 albedo_texture=%s，应为公共色盘"
					% [slug, mesh_node.name, surface, material.albedo_texture.resource_path])


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_meshes(child))
	return out


func _fail(message: String) -> void:
	failures.append(message)
