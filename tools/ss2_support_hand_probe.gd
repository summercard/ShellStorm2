extends Node3D
## 双手持枪**支撑手**实测 · 只读工程。
##
## 验收里的 `weapon_support_error_m` 断言 `< 0.02 m`（左掌到枪上 SupportHandSocket 的距离）。
## 长枪/机枪是双手武器，左手必须扶在枪上；只靠右手单持会明显穿帮。
## 本探针把这个距离**打出来**，而不是只报一个红/绿 ——
## 修复前先知道差多少，才能判断是"差几厘米的调参"还是"整条通道没接"。
##
## 用法：godot --headless --path . --scene res://tools/ss2_support_hand_probe.tscn

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const GUNS := {
	"bp_pistol": "sidearm",
	"bp_rifle": "longgun",
	"bp_machinegun": "machinegun",
}
const MOVE_STATES := ["idle", "moving"]

var _player: Node3D


func _say(line: String) -> void:
	print("SSSH| " + line)


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 0.4, 40.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	await get_tree().process_frame
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_player.set("combat_enabled", false)
	_player.get_node_or_null("Camera3D").set("current", false)
	var avatar := _player.get_node_or_null("Avatar3D") as Node3D
	_say("装配 motion_driver=%s" % str(avatar.get_meta("motion_driver", "")))

	for gun: String in GUNS:
		_player.call("equip_weapon", gun, "mod_bullet_standard")
		await get_tree().process_frame
		await get_tree().process_frame
		for state in MOVE_STATES:
			_player.set("_presentation_state", state)
			if state == "moving":
				_player.set("velocity", Vector3(0.0, 0.0, -4.0))
			else:
				_player.set("velocity", Vector3.ZERO)
			for _frame in range(10):
				avatar.call("_process", 0.016)
			await get_tree().process_frame
			var snapshot: Dictionary = avatar.call("get_component_snapshot")
			var support := float(snapshot.get("weapon_support_error_m", -999.0))
			var clip := str(snapshot.get("authored_motion_clip", ""))
			var socket := avatar.get_node_or_null("VisualRoot/BunnyRig/WeaponSocket") as Node3D
			var left_hand := avatar.get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointL") as Node3D
			var right_hand := avatar.get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointR") as Node3D
			var support_socket: Node3D = null
			if socket != null:
				var weapon := socket.get_node_or_null("WeaponModel3D") as Node3D
				if weapon != null:
					support_socket = weapon.find_child("SupportHandSocket", true, false) as Node3D
			var dist_socket := -1.0
			var dist_hand := -1.0
			if support_socket != null and left_hand != null:
				dist_socket = left_hand.global_position.distance_to(support_socket.global_position)
			if right_hand != null and left_hand != null:
				dist_hand = left_hand.global_position.distance_to(right_hand.global_position)
			## 骨骼原始姿态下的左右手间距 —— 用来区分「GLB 剪辑里左手本来就没扶枪」
			## 与「剪辑扶了但我们的 socket 重定位把它甩开」。
			var raw_hand_gap := -1.0
			var skeleton := _find_first(avatar, "Skeleton3D") as Skeleton3D
			if skeleton != null:
				var l := _bone_world(skeleton, "mixamorig_LeftHand")
				var r := _bone_world(skeleton, "mixamorig_RightHand")
				if l != null and r != null:
					raw_hand_gap = l.origin.distance_to(r.origin)
			## 关键补充：左手到**枪身几何**的距离。
			## `SupportHandSocket` 只是武器上的一个名义挂点（在护木处）；
			## 视觉上「左手有没有扶着枪」取决于手离枪的**网格**有多远，
			## 而不是离那个挂点多远 —— 两者可以差很远（枪短、挂点靠前时）。
			var dist_body := -1.0
			var weapon_node := socket.get_node_or_null("WeaponModel3D") as Node3D if socket != null else null
			if weapon_node != null and left_hand != null:
				var weapon_box := _subtree_aabb(weapon_node)
				dist_body = _distance_to_aabb(left_hand.global_position, weapon_box)
			_say("%s/%s clip=%-24s support_error=%s" % [
				gun, state, clip,
				("(不适用)" if support < -900.0 else "%.4f m" % support)])
			_say("   左掌↔挂点=%.4f  左掌↔右掌=%.4f  骨骼原始左右手距=%.4f  左掌↔枪身=%.4f" % [
				dist_socket, dist_hand, raw_hand_gap, dist_body])
	_say("==== 测量结束 ====")
	get_tree().quit(0)


func _find_first(root_node: Node, cls: String) -> Node:
	if root_node == null:
		return null
	if root_node.is_class(cls):
		return root_node
	for child in root_node.get_children():
		var found := _find_first(child, cls)
		if found != null:
			return found
	return null


func _bone_world(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	for index in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(index) == bone_name:
			return skeleton.global_transform * skeleton.get_bone_global_pose(index)
	return Transform3D()


func _collect_meshes(root_node: Node, out: Array) -> void:
	if root_node is MeshInstance3D:
		out.append(root_node)
	for child in root_node.get_children():
		_collect_meshes(child, out)


func _subtree_aabb(root_node: Node) -> AABB:
	var meshes: Array = []
	_collect_meshes(root_node, meshes)
	var box := AABB()
	var first := true
	for value in meshes:
		var instance := value as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		if not instance.is_visible_in_tree():
			continue
		var world := instance.global_transform * instance.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box


## Godot 4 的 `AABB` 没有 `get_closest_point()`（旧版 API），手动求盒内最近点：
## 每轴把坐标夹到 [position, position+size]，再取欧氏距离。
func _distance_to_aabb(point: Vector3, box: AABB) -> float:
	if box.size == Vector3.ZERO:
		return -1.0
	var closest := Vector3(
		clampf(point.x, box.position.x, box.position.x + box.size.x),
		clampf(point.y, box.position.y, box.position.y + box.size.y),
		clampf(point.z, box.position.z, box.position.z + box.size.z)
	)
	return point.distance_to(closest)
