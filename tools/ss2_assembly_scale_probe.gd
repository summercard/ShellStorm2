extends Node3D
## 主角装配**尺度实测** · 只读工程。
##
## 动机：换角色后的真渲染出图里，枪的视觉尺寸明显偏大（横跨两个身位）。
## 肉眼读数（"看着挺大"）不能当判据 ⇒ 本探针出数字。
##
## 直接测**真实 `Player3D.tscn`**（当前装配 = 女仆 clip），不替换 `Avatar3D` 节点 ——
## `Player3D.avatar` 是 `@onready` 单次引用，替换节点会让它指向已释放对象，
## 武器根本不会建出来（前一版探针踩过：一直报"未装武器"）。
##
## 对照口径（关键）：
##   `PlayerAvatar3D.BUNNY_LINEAR_SCALE = 1.5 / 2.475 ≈ 0.6061`
##   原角色把**武器**乘这个系数挂上身（见 `_apply_bunny_attachment_scale`），
##   因为武器资产是在「2.475 m 高角色」的空间里建模的。
##   所以「武器世界长度 ÷ 角色高」在两个装配之间必须可比；差一档就是缺陷。
##
## 用法：godot --headless --path . --scene res://tools/ss2_assembly_scale_probe.tscn

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const BUNNY_LINEAR_SCALE := 1.5 / 2.475
const WEAPON_TSN := "res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn"
const GUNS := ["bp_pistol", "bp_rifle", "bp_machinegun"]

var _player: Node3D


func _say(line: String) -> void:
	print("SSAS| " + line)


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


## 武器模型是程序拼装的：`_visual_root` 下的部件。整棵子树的世界 AABB 就是「枪多大」。
func _weapon_report(weapon: Node3D) -> void:
	var box := _subtree_aabb(weapon)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var scale := weapon.global_transform.basis.get_scale()
	_say("  武器节点世界尺度=%s" % str(scale))
	_say("  武器 世界 AABB=%.4f x %.4f x %.4f  最长边=%.4f m" % [
		box.size.x, box.size.y, box.size.z, longest])


func _ready() -> void:
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	await get_tree().process_frame
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_player.set("combat_enabled", false)
	_player.get_node_or_null("Camera3D").set("current", false)

	var avatar := _player.get_node_or_null("Avatar3D") as Node3D
	if avatar == null:
		_say("FAIL 找不到 Avatar3D")
		get_tree().quit(1)
		return
	_say("装配：assembly_version=%s motion_driver=%s" % [
		str(avatar.get_meta("assembly_version", "")), str(avatar.get_meta("motion_driver", ""))])
	_say("avatar.scale=%s" % str(avatar.scale))
	var model := avatar.get_node_or_null("VisualRoot/BunnyRig/Model") as Node3D
	var char_height := 0.0
	if model != null:
		var model_box := _subtree_aabb(model)
		char_height = model_box.size.y
		_say("角色世界 AABB=%.4f x %.4f x %.4f  高=%.4f m （Model 子树世界尺度=%s）" % [
			model_box.size.x, model_box.size.y, model_box.size.z, char_height,
			str(model.global_transform.basis.get_scale())])
	else:
		_say("FAIL 找不到 Model")

	var socket := avatar.get_node_or_null("VisualRoot/BunnyRig/WeaponSocket") as Node3D
	if socket == null:
		_say("FAIL 找不到 WeaponSocket")
		get_tree().quit(1)
		return
	_say("WeaponSocket 世界位置=%s 世界尺度=%s" % [
		str(socket.global_position), str(socket.global_transform.basis.get_scale())])

	for gun in GUNS:
		var equipped: Variant = _player.call("equip_weapon", str(gun), "mod_bullet_standard")
		await get_tree().process_frame
		await get_tree().process_frame
		# 让运动库把 socket 摆到握持位（一帧就够，但多跑几帧稳）。
		avatar.call("_process", 0.016)
		await get_tree().process_frame
		_say("---- %s equip=%s ----" % [gun, str(equipped)])
		var weapon := socket.get_node_or_null("WeaponModel3D") as Node3D
		if weapon == null:
			_say("  没有 WeaponModel3D")
			continue
		_weapon_report(weapon)
		var box := _subtree_aabb(weapon)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if char_height > 0.0:
			_say("  >>> 枪长/角色高 = %.3f" % (longest / char_height))
		_say("  武器中心世界位置=%s （socket=%s）" % [
			str(box.get_center()), str(socket.global_position)])

	_say("==== 测量结束 ====")
	get_tree().quit(0)
