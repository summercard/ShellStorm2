extends Node3D

## 核对「房间 TSCN 里的暗门节点」与「运行时位点」是否同一处。
##
## 三件事必须同时成立，否则业主在编辑器里拖的门在游戏里就不在同一个地方：
##   ① TSCN 里门的 transform 是**房间局部**（不是世界坐标）；
##   ② `房间节点.global_transform × 门局部` = 运行时 `sites[].position`；
##   ③ 门的朝向（+Z）与 `sites[].normal` 同向。
##
## 跑法：
##   godot --headless --path . res://tests/verification/probe_secret_door_authored.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const LAYOUT_ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01"
const SEED := 77001199

var _tower: Node3D = null
var _branch: Node = null


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	_tower = scene.instantiate() as Node3D
	(_tower as Node).set("test_mode", true)
	(_tower as Node).set("run_seed_override", SEED)
	add_child(_tower)
	for _index in range(10):
		await get_tree().process_frame
		await get_tree().physics_frame
	_branch = _tower.get_node_or_null("SecretBranches")
	if _branch == null:
		print("AUTHORED_DOOR_PROBE_FAILED 没有 SecretBranches")
		get_tree().quit(1)
		return
	_branch.call("settle_sites")
	var snapshot := _branch.call("debug_snapshot") as Dictionary
	var sites: Array = snapshot.get("sites", []) as Array
	print("=== 运行时位点 ===")
	for value in sites:
		var site := value as Dictionary
		var pos := site.get("position", Vector3.ZERO) as Vector3
		var normal := site.get("normal", Vector3.FORWARD) as Vector3
		print("  %-4s %-9s pos=(%.2f, %.2f, %.2f) normal=(%.2f, %.2f, %.2f) manual=%s" % [
			str(site.get("site_id", "")), str(site.get("room_id", "")),
			pos.x, pos.y, pos.z, normal.x, normal.y, normal.z,
			str(site.get("manual_site", false)),
		])
	print("=== TSCN 门节点 vs 运行时 ===")
	_inspect_state("room_03")
	var failures := 0
	for value in sites:
		var site := value as Dictionary
		var site_id := str(site.get("site_id", ""))
		var room_id := str(site.get("room_id", ""))
		var door_local: Variant = _tscn_door_transform(room_id, site_id)
		if door_local == null:
			print("  %-4s %-9s TSCN 里没有这扇门（走运行时自动位点）" % [site_id, room_id])
			continue
		var room := _find_room(room_id)
		if room == null:
			print("  %-4s %-9s 运行时找不到房间节点" % [site_id, room_id])
			failures += 1
			continue
		var world: Vector3 = (room.global_transform * (door_local as Transform3D)).origin
		var want := site.get("position", Vector3.ZERO) as Vector3
		var gap := world.distance_to(want)
		var facing: Vector3 = (room.global_transform.basis * (door_local as Transform3D).basis.z)
		facing.y = 0.0
		var want_normal := site.get("normal", Vector3.FORWARD) as Vector3
		var dot := 0.0
		if facing.length() > 0.001 and want_normal.length() > 0.001:
			dot = facing.normalized().dot(want_normal.normalized())
		var ok := gap <= 0.05 and dot >= 0.99
		print("  %s %-4s %-9s TSCN局部=(%.2f, %.2f, %.2f) → 世界=(%.2f, %.2f, %.2f) 运行时=(%.2f, %.2f, %.2f) 差=%.3fm 朝向点积=%.3f" % [
			"✔" if ok else "✘", site_id, room_id,
			(door_local as Transform3D).origin.x, (door_local as Transform3D).origin.y,
			(door_local as Transform3D).origin.z,
			world.x, world.y, world.z, want.x, want.y, want.z, gap, dot,
		])
		if not ok:
			failures += 1
	if failures == 0:
		print("AUTHORED_DOOR_PROBE_OK 位点=%d" % sites.size())
	else:
		print("AUTHORED_DOOR_PROBE_FAILED count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _find_room(room_id: String) -> Node3D:
	return _tower.find_child(room_id, true, false) as Node3D


## 诊断用：把房间 TSCN 的节点名 / 父路径 / 类型打出来，确认
## `SecretDoor_*` 是不是根层直接子节点（`get_node_path()` 的返回值形态）。
func _inspect_state(room_id: String) -> void:
	var path := "%s/f00_%s_static_layout.tscn" % [LAYOUT_ROOT, room_id]
	var packed := load(path) as PackedScene
	if packed == null:
		print("  [诊断] 读不到 %s" % path)
		return
	var state := packed.get_state()
	print("  [诊断] %s 节点数=%d" % [room_id, state.get_node_count()])
	var shown := 0
	for index in range(state.get_node_count()):
		var node_name := str(state.get_node_name(index))
		var parent_path := str(state.get_node_path(index))
		var prop_count := state.get_node_property_count(index)
		var has_transform := false
		for property_index in range(prop_count):
			if str(state.get_node_property_name(index, property_index)) == "transform":
				has_transform = true
		if node_name.begins_with("SecretDoor") or parent_path == ".":
			if shown < 12:
				print("    [%d] name=%s parent='%s' type=%s props=%d transform=%s" % [
					index, node_name, parent_path, state.get_node_type(index),
					prop_count, str(has_transform),
				])
				shown += 1


## 读房间 TSCN 里 `SecretDoor_<site_id>` 的局部 transform；没有返回 null。
func _tscn_door_transform(room_id: String, site_id: String) -> Variant:
	var path := "%s/f00_%s_static_layout.tscn" % [LAYOUT_ROOT, room_id]
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	if state == null:
		return null
	var wanted := "SecretDoor_%s" % site_id
	for index in range(state.get_node_count()):
		if str(state.get_node_name(index)) != wanted:
			continue
		for property_index in range(state.get_node_property_count(index)):
			if str(state.get_node_property_name(index, property_index)) == "transform":
				return state.get_node_property_value(index, property_index) as Transform3D
		return Transform3D.IDENTITY
	return null
