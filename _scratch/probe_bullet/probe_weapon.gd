extends Node3D
## 诊断（只读）：玩家实际持枪的**可见几何高度**（武器网格 AABB）与枪口 Marker、
## 以及玩家自身可见模型 AABB。用于判定子弹真实起飞高度，与怪碰撞体高度对比。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(12)
	tower.force_enter_room_for_test("room_01")
	await _settle(6)
	var player := tower.player
	if player == null:
		print("WEAPON_PROBE no_player")
		get_tree().quit(0)
		return
	var origin := player.global_position
	print("WEAPON_PROBE player_origin=%.3f" % origin.y)
	print("WEAPON_PROBE player_visual=%s" % _span(player))
	if player.avatar != null:
		print("WEAPON_PROBE avatar_visual=%s avatar_scale=%s" % [
			_span(player.avatar), str(player.avatar.scale),
		])
		if player.avatar.weapon_socket != null:
			var wt := player.avatar.weapon_socket.global_transform
			var socket_off := wt.origin.y - origin.y
			print("WEAPON_PROBE socket_off=%.3f socket_basis_z=%s" % [
				socket_off, str(wt.basis.z),
			])
	var weapon := player.weapon as WeaponModel3D
	if weapon != null:
		print("WEAPON_PROBE weapon_node_off=%.3f weapon_scale=%s gun_id=%s" % [
			weapon.global_position.y - origin.y, str(weapon.scale), weapon.gun_id,
		])
		print("WEAPON_PROBE weapon_visual=%s" % _span(weapon))
		var muzzle := weapon.get("_muzzle") as Marker3D
		if muzzle != null and muzzle.is_inside_tree():
			print("WEAPON_PROBE muzzle_off=%.3f muzzle_local=%s" % [
				muzzle.global_position.y - origin.y, str(muzzle.position),
			])
	print("WEAPON_PROBE_DONE")
	get_tree().quit(0)


func _span(root: Node) -> String:
	var min_y := INF
	var max_y := -INF
	var meshes := 0
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null or not mesh.visible:
			continue
		var world_aabb: AABB = mesh.global_transform * mesh.get_aabb()
		min_y = minf(min_y, world_aabb.position.y)
		max_y = maxf(max_y, world_aabb.end.y)
		meshes += 1
	if min_y == INF:
		return "no_mesh"
	var base := tower.player.global_position.y
	return "y=%.3f..%.3f (off %.3f..%.3f) meshes=%d" % [
		min_y, max_y, min_y - base, max_y - base, meshes,
	]


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
