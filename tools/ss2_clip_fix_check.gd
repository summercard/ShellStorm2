extends Node3D
## 换角色（clip 装配）**修复验收** · 只读工程。
##
## 覆盖本轮三个真缺陷的修复：
##   A. 武器尺度 —— clip 装配原先不做 `BUNNY_LINEAR_SCALE` 适配，
##      枪比设计值大 1.65 倍（实测 0.853 / 1.072 / 1.241，应为 0.517 / 0.650 / 0.752）。
##   B. 叙事钉帧 —— 开场剧本用 `{clip:"dead", phase:1.0, frozen:true}` 让角色趴地，
##      clip 通道原先没读 `pose_lock_*`，角色会站着播死亡动画。
##   C. 换弹上报 —— `active_overlay` 原先被清空，验收读不出「换弹剪辑在播」。
##
## 用法：godot --headless --path . --scene res://tools/ss2_clip_fix_check.tscn

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
## 与原角色口径同源：武器资产按 2.475 m 角色空间建模，缩到 1.5 m 档。
const EXPECTED_ATTACHMENT_SCALE := 1.5 / 2.475
## 三个枪族的「枪长 / 角色高」目标值，公差 ±0.06（含拼装件网格的 AABB 余量）。
const WEAPON_RATIO_TARGETS := {
	"bp_pistol": 0.517,
	"bp_rifle": 0.650,
	"bp_machinegun": 0.752,
}
const RATIO_TOLERANCE := 0.06

var _player: Node3D
var _failures: Array[String] = []
var _checks := 0


func _say(line: String) -> void:
	print("SSCF| " + line)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		_say("OK   " + label)
	else:
		_say("FAIL " + label)
		_failures.append(label)


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


func _ready() -> void:
	## 实体地板：没它角色永远「不在着地」⇒ 状态机一直停在 falling，
	## 「解除钉帧后 state 回到常规」那条断言就会误判（首版实测）。
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
	if avatar == null:
		_say("FAIL 找不到 Avatar3D")
		get_tree().quit(1)
		return
	_say("装配：assembly_version=%s motion_driver=%s" % [
		str(avatar.get_meta("assembly_version", "")), str(avatar.get_meta("motion_driver", ""))])

	await _check_weapon_scale(avatar)
	await _check_narrative_pose(avatar)
	await _check_reload_overlay(avatar)
	await _check_snapshot_flags(avatar)

	_say("==== 结论：%s（检查 %d 项，失败 %d）====" % [
		"通过" if _failures.is_empty() else "未通过", _checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


## A. 武器尺度
func _check_weapon_scale(avatar: Node3D) -> void:
	_say("---- A. 武器尺度 ----")
	var model := avatar.get_node_or_null("VisualRoot/BunnyRig/Model") as Node3D
	var socket := avatar.get_node_or_null("VisualRoot/BunnyRig/WeaponSocket") as Node3D
	if model == null or socket == null:
		_check(false, "找不到 Model 或 WeaponSocket")
		return
	var char_height := _subtree_aabb(model).size.y
	_check(char_height > 0.1, "角色高有效=%.4f m" % char_height)
	for gun: String in WEAPON_RATIO_TARGETS:
		_player.call("equip_weapon", gun, "mod_bullet_standard")
		await get_tree().process_frame
		await get_tree().process_frame
		avatar.call("_process", 0.016)
		await get_tree().process_frame
		var weapon := socket.get_node_or_null("WeaponModel3D") as Node3D
		if weapon == null:
			_check(false, "%s 没有 WeaponModel3D" % gun)
			continue
		var scale_now := weapon.global_transform.basis.get_scale().x
		# 世界尺度 = 角色体型倍率（0.8） × 挂载缩放。用比值消掉体型倍率。
		var socket_scale := socket.global_transform.basis.get_scale().x
		var ratio := scale_now / maxf(0.0001, socket_scale)
		_check(
			absf(ratio - EXPECTED_ATTACHMENT_SCALE) < 0.01,
			"%s 挂载缩放=%.4f（期望 %.4f）" % [gun, ratio, EXPECTED_ATTACHMENT_SCALE]
		)
		var box := _subtree_aabb(weapon)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		var length_ratio := longest / char_height
		var target: float = WEAPON_RATIO_TARGETS[gun]
		_check(
			absf(length_ratio - target) < RATIO_TOLERANCE,
			"%s 枪长/角色高=%.3f（目标 %.3f ±%.2f）" % [gun, length_ratio, target, RATIO_TOLERANCE]
		)


## B. 叙事钉帧
##
## ⚠️ 判据不能用「某个绝对高度」——GLB 的骨骼局部空间与角色世界空间不同源，
## 而且钉帧读的是 `get_bone_pose_position()`（**骨骼局部**，不是世界坐标）。
## 唯一稳的判据是**同一根骨在不同相位之间的相对变化**：
##   ① 钉 phase=1.0 与钉 phase=0.5，同一根骨必须落在不同位置（证明"钉帧真的生效"）
##   ② 解除钉帧后跑一段 idle，位置必须再变（证明"动画系统被交还了"）
## 至于"哪个相位更低"取决于剪辑本身怎么编，不作断言 —— 剧本两头都要用
## （phase 1.0 = 趴地、推到 0.0 = 起身），两个方向都合法。
func _check_narrative_pose(avatar: Node3D) -> void:
	_say("---- B. 叙事钉帧（开场趴地）----")
	var motion: Variant = avatar.get("_authored_motion")
	if motion == null:
		_check(false, "_authored_motion 为空")
		return
	var skeleton := _find_first(_player, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		_check(false, "找不到 Skeleton3D")
		return
	## 基线：先正常跑一段 idle。
	for _frame in range(12):
		avatar.call("_process", 0.016)
	await get_tree().process_frame
	var idle_hips := _bone_origin(skeleton, "mixamorig_Hips")
	var idle_head := _bone_origin(skeleton, "mixamorig_Head")

	## ① 剧本 `nar_tower_opening_01_wake.json` 的原样参数：钉在 dead 剪辑终点（趴地）。
	avatar.call("set_narrative_pose", "dead", 1.0, true)
	for _frame in range(8):
		avatar.call("_process", 0.016)
	await get_tree().process_frame
	var clip_after: String = str(motion.get("active_clip"))
	_check(clip_after == "dead", "钉帧后 active_clip=%s（应为 dead）" % clip_after)
	var low_hips := _bone_origin(skeleton, "mixamorig_Hips")
	var low_head := _bone_origin(skeleton, "mixamorig_Head")
	_check(
		low_hips.distance_to(idle_hips) > 0.005 or low_head.distance_to(idle_head) > 0.005,
		"钉帧确实改变姿势：Hips 位移=%.4f Head 位移=%.4f" % [
			low_hips.distance_to(idle_hips), low_head.distance_to(idle_head)]
	)

	## ② 换一个相位必须落在别处 —— 这条才真正证明"钉帧读的是 phase，不是随便播一段"。
	avatar.call("set_narrative_pose", "dead", 0.5, true)
	for _frame in range(6):
		avatar.call("_process", 0.016)
	await get_tree().process_frame
	var mid_hips := _bone_origin(skeleton, "mixamorig_Hips")
	_check(
		mid_hips.distance_to(low_hips) > 0.003,
		"钉帧相位可变：dead@1.0 → dead@0.5 的 Hips 位移=%.4f" % mid_hips.distance_to(low_hips)
	)

	## ③ 交还动画系统：位置必须再次变化（否则角色被永久钉死）。
	avatar.call("clear_narrative_pose")
	for _frame in range(20):
		avatar.call("_process", 0.016)
	await get_tree().process_frame
	var restored_hips := _bone_origin(skeleton, "mixamorig_Hips")
	var snapshot: Dictionary = avatar.call("get_component_snapshot")
	_check(
		restored_hips.distance_to(mid_hips) > 0.003,
		"解除钉帧后动画恢复：Hips 位移=%.4f" % restored_hips.distance_to(mid_hips)
	)
	_check(
		str(snapshot.get("state", "")) in ["idle", "moving", "locked"],
		"解除后 state=%s（应回到常规状态）" % str(snapshot.get("state", ""))
	)


func _bone_origin(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	for index in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(index) == bone_name:
			return skeleton.get_bone_pose_position(index)
	return Vector3.ZERO


## C. 换弹上报
func _check_reload_overlay(avatar: Node3D) -> void:
	_say("---- C. 换弹上报 ----")
	_player.set("_presentation_state", "idle")
	_player.call("equip_weapon", "bp_rifle", "mod_bullet_standard")
	await get_tree().process_frame
	var weapon: Variant = _player.get("weapon")
	if weapon == null:
		_check(false, "换弹检查：没有武器")
		return
	## 与 `verify_player3d_reload_motion` 同法：直接驱动 weapon 与 avatar，
	## 不调 `Player3D._process` —— `Player3D` 只有 `_physics_process`，
	## 调 `_process` 会抛 "Nonexistent function" 并跳过后续断言（首版踩过，报了个假通过）。
	var magazine: int = int(weapon.get("magazine_size"))
	weapon.call("cancel_reload")
	weapon.set("current_ammo", 0)
	weapon.set("reload_time", 2.0)
	_check(bool(_player.call("request_reload")), "request_reload 接受")
	weapon.call("_process", 0.0)
	avatar.call("_process", 0.0)
	await get_tree().process_frame
	## 走半个换弹时长，让进度落在中段（0 和 1 两端都可能被边界分支吃掉）。
	weapon.call("_process", 1.0)
	avatar.call("_process", 0.0)
	await get_tree().process_frame
	var snapshot: Dictionary = avatar.call("get_component_snapshot")
	var overlay := str(snapshot.get("authored_overlay_clip", ""))
	_check(overlay == "longgun_reload", "authored_overlay_clip=%s（应为 longgun_reload）" % overlay)
	var overlay_progress := float(snapshot.get("authored_overlay_progress", -1.0))
	_check(
		overlay_progress > 0.2 and overlay_progress < 0.8,
		"authored_overlay_progress=%.3f（应落在中段）" % overlay_progress
	)
	var missing := str(snapshot.get("missing_authored_action", ""))
	_check(missing.is_empty(), "missing_authored_action 为空（实际 '%s'）" % missing)
	var clip := str(snapshot.get("authored_motion_clip", ""))
	_check(clip == "longgun_reload", "authored_motion_clip=%s（应为 longgun_reload）" % clip)


## D. 快照标志位
func _check_snapshot_flags(avatar: Node3D) -> void:
	_say("---- D. 快照标志位 ----")
	var snapshot: Dictionary = avatar.call("get_component_snapshot")
	var driver := str(snapshot.get("animation_driver", ""))
	_check(driver == "glb_clip", "animation_driver=%s（应为 glb_clip）" % driver)
	_check(
		not bool(snapshot.get("legacy_procedural_motion_enabled", true)),
		"legacy_procedural_motion_enabled=false（实际 %s）" % str(snapshot.get("legacy_procedural_motion_enabled"))
	)


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
