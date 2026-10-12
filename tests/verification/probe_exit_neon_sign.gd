extends Node3D
## 只读探针：EXIT 霓虹灯标牌（ENV-BATTLE-EXIT-NEON-SIGN / v001）
## 验：PackedScene 独立加载、metadata 契约、四角色材质、公共色盘后处理真的生效。
##   godot --headless --path . --scene res://tests/verification/probe_exit_neon_sign.tscn

const SIGN_SCENE := "res://assets/art/environments/tower_zones/battle/runtime/exit_neon_sign/exit_neon_sign_root_top3d.tscn"
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const EXPECTED_ASSET_ID := "ENV-BATTLE-EXIT-NEON-SIGN"
const EXPECTED_ROLES: Array[String] = [
	"01_精工金属_紫色骨架",
	"02_细腻哑光_青绿大面",
	"04_柔和自发光_UI灯光",
]
const EXPECTED_SIZE_M := Vector3(1.84, 0.76, 0.09)
const SIZE_TOLERANCE_M := 0.02

var _failures: Array[String] = []


func _ready() -> void:
	var palette := load(PALETTE_PATH) as Texture2D
	if palette == null:
		_failures.append("palette_missing:%s" % PALETTE_PATH)

	var packed := load(SIGN_SCENE) as PackedScene
	if packed == null:
		_failures.append("packed_scene_load_failed")
		_finish(palette)
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		_failures.append("root_not_node3d")
		_finish(palette)
		return
	add_child(root)

	if String(root.get_meta("asset_id", "")) != EXPECTED_ASSET_ID:
		_failures.append("asset_id_mismatch:%s" % root.get_meta("asset_id", ""))
	if String(root.get_meta("asset_version", "")) != "v001":
		_failures.append("asset_version_mismatch")
	if bool(root.get_meta("visual_only", false)) != true:
		_failures.append("visual_only_not_declared")
	if int(root.get_meta("collision_shape_count", -1)) != 0:
		_failures.append("collision_shape_count_not_zero")

	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	if meshes.is_empty():
		_failures.append("no_mesh_instances")

	var aabb := AABB()
	var first := true
	var roles: Array[String] = []
	for mi in meshes:
		var mesh := mi.mesh
		if mesh == null:
			_failures.append("null_mesh:%s" % mi.name)
			continue
		var local := mi.get_aabb()
		aabb = local if first else aabb.merge(local)
		first = false
		for surface in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null:
				_failures.append("null_material:%s[%d]" % [mi.name, surface])
				continue
			var role := String(mat.resource_name)
			if not roles.has(role):
				roles.append(role)
			if not EXPECTED_ROLES.has(role):
				_failures.append("unexpected_role:%s" % role)
			if mat.albedo_texture != palette:
				_failures.append("albedo_not_palette:%s" % role)
			if mat.emission_texture != palette:
				_failures.append("emission_not_palette:%s" % role)
			if mat.emission_operator != BaseMaterial3D.EMISSION_OP_MULTIPLY:
				_failures.append("emission_operator_not_multiply:%s" % role)
			if mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
				_failures.append("texture_filter_not_nearest:%s" % role)
			print("SURFACE %s[%d] role=%s emission=%s strength=%.2f" % [
				mi.name, surface, role, str(mat.emission_enabled),
				mat.emission_energy_multiplier,
			])

	var size := aabb.size
	print("AABB size=%s roles=%s meshes=%d" % [str(size), str(roles), meshes.size()])
	if absf(size.x - EXPECTED_SIZE_M.x) > SIZE_TOLERANCE_M \
			or absf(size.y - EXPECTED_SIZE_M.y) > SIZE_TOLERANCE_M \
			or absf(size.z - EXPECTED_SIZE_M.z) > SIZE_TOLERANCE_M:
		_failures.append("bounds_mismatch:%s" % str(size))
	if roles.size() != 3:
		_failures.append("role_count:%d" % roles.size())

	root.queue_free()
	_finish(palette)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)


func _finish(_palette: Texture2D) -> void:
	if _failures.is_empty():
		print("PROBE_EXIT_NEON_SIGN_OK")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("PROBE_FAIL %s" % failure)
		print("PROBE_EXIT_NEON_SIGN_FAIL count=%d" % _failures.size())
		get_tree().quit(1)
