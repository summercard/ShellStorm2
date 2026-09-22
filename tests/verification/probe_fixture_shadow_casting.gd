extends Node

## 查「一个组件包是否投射阴影」—— 只读采集，不下结论。
##
## 背景（为什么要问这个）
## 61_仓库防爆吊灯组_资产包 的 GLB 里**没有光源**（JSON chunk 无 KHR_lights_punctual、
## 无顶层 lights 键）；运行时给它补光的 BaseFixtureGlow3D 也已经写了
## `light.shadow_enabled = false`。所以这个组件唯一的「投影」来源只可能是
## **自身网格在场景主光下投出的阴影**，对应 GeometryInstance3D.cast_shadow。
##
## 本探针量出运行时真实值；同时用三个同类包做对照。
## 不 add_child 进树（普通包无脚本，但保持与既有摆位探针同口径）。

const RUNTIME_DIR := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities"
const SLUGS := [
	"warehouse_pendant_light_group",
	"east_round_pendant_light",
	"corridor_emergency_light_group",
	"industrial_water_tank",
]

var _geometry_total := 0
var _shadow_casters := 0


func _ready() -> void:
	var pressed := 0
	for slug in SLUGS:
		var path := "%s/%s/%s_root_top3d.tscn" % [RUNTIME_DIR, slug, slug]
		var packed := load(path) as PackedScene
		if packed == null:
			print("PROBE_FAIL\tmissing\t%s" % path)
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			print("PROBE_FAIL\tinstantiate\t%s" % path)
			continue
		pressed += 1
		print("PREFAB\t%s\troot_class=%s\tchildren=%d" % [slug, root.get_class(), root.get_child_count()])
		_dump(root, 1)
		root.free()
	print("SENTINEL\tpressed=%d\tgeometry_total=%d\tcasters=%d" % [pressed, _geometry_total, _shadow_casters])
	get_tree().quit(0)


func _dump(node: Node, depth: int) -> void:
	var pad := ""
	for _i in range(depth):
		pad += "  "
	var info := ""
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		_geometry_total += 1
		if int(geometry.cast_shadow) != int(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF):
			_shadow_casters += 1
		info = "\tcast_shadow=%d(%s)" % [int(geometry.cast_shadow), _shadow_label(int(geometry.cast_shadow))]
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			var surfaces := 0
			var mesh_name := "<null>"
			if mesh_instance.mesh != null:
				surfaces = mesh_instance.mesh.get_surface_count()
				mesh_name = str(mesh_instance.mesh.resource_name)
			info += "\tsurfaces=%d\tmesh=%s" % [surfaces, mesh_name]
	if node is Light3D:
		var light := node as Light3D
		info += "\tLIGHT shadow_enabled=%s energy=%.2f" % [light.shadow_enabled, light.light_energy]
	print("TREE\t%s%s\t%s%s" % [pad, node.name, node.get_class(), info])
	for child in node.get_children():
		_dump(child, depth + 1)


func _shadow_label(setting: int) -> String:
	match setting:
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return "OFF"
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			return "ON"
		GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
			return "DOUBLE_SIDED"
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			return "SHADOWS_ONLY"
	return "UNKNOWN"
