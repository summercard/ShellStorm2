extends Node

const LAYOUT_PATH: String = "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"
const NAMES: Array[String] = [
	"32_参考床头柜与生活物件_资产包",
	"41_床前辅助小桌_资产包",
	"37_红棕茶几与生活物件_资产包",
	"42_双屏电脑完整工位_资产包",
	"48_窄型应急柜_资产包",
	"80_低矮储物收纳区_资产包",
]

func _ready() -> void:
	var packed: PackedScene = load(LAYOUT_PATH) as PackedScene
	if packed == null:
		push_error("TABLE_CANDIDATE_PROBE_FAIL")
		get_tree().quit(1)
		return
	var root: Node3D = packed.instantiate() as Node3D
	add_child(root)
	await get_tree().process_frame
	for wanted in NAMES:
		var node: Node3D = root.find_child(wanted, true, false) as Node3D
		if node == null:
			print("CANDIDATE_MISSING name=%s" % wanted)
			continue
		print("CANDIDATE name=%s parent=%s origin=%s yaw=%.4f node_bounds=%s" % [wanted, node.get_parent().name, _v(node.global_position), node.global_rotation.y, _v(_node_bounds(node).size)])
		for value in node.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = value as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var b: AABB = _bounds(mesh)
			print("  MESH name=%s center=%s pos=%s size=%s" % [mesh.name, _v(b.get_center()), _v(b.position), _v(b.size)])
	print("TABLE_CANDIDATE_PROBE_OK")
	get_tree().quit(0)

func _node_bounds(node: Node3D) -> AABB:
	var acc: AABB = AABB()
	var found: bool = false
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _bounds(value as MeshInstance3D)
		if b.size == Vector3.ZERO:
			continue
		acc = b if not found else acc.merge(b)
		found = true
	return acc if found else AABB()

func _bounds(mesh: MeshInstance3D) -> AABB:
	var local: AABB = mesh.get_aabb()
	var acc: AABB = AABB()
	var found: bool = false
	for i in 8:
		var p: Vector3 = mesh.global_transform * local.get_endpoint(i)
		acc = AABB(p, Vector3.ZERO) if not found else acc.expand(p)
		found = true
	return acc

func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
