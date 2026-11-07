extends SceneTree
## SS2 主角换角色自检（只读工程）。
## 输出全部走 stdout，由批处理重定向到 _check_console.txt。
## 树相关检查必须等真帧（_process）；_initialize 阶段 root 还没活。

const MAID := "res://assets/art/characters/player/external/maid01/chr_maid01_root_v001.tscn"
const CHUCK := "res://assets/art/characters/player/external/chuck201/chr_chuck201_root_v001.tscn"
const EXPECTED_HEIGHT := 1.5
const REQUIRED_NODES := [
	"VisualRoot/BunnyRig/BodyJoint",
	"VisualRoot/BunnyRig/BodyJoint/LowerBodySocket",
	"VisualRoot/BunnyRig/HeadJoint",
	"VisualRoot/BunnyRig/HeadJoint/Ears/EarSocketL",
	"VisualRoot/BunnyRig/HeadJoint/Ears/EarSocketR",
	"VisualRoot/BunnyRig/HandRoot/HandJointL",
	"VisualRoot/BunnyRig/HandRoot/HandJointR",
	"VisualRoot/BunnyRig/FeetRoot/FootJointL",
	"VisualRoot/BunnyRig/FeetRoot/FootJointR",
	"VisualRoot/BunnyRig/WeaponSocket",
	"VisualRoot/BunnyRig/StowedWeaponSocketPrimary",
	"VisualRoot/BunnyRig/StowedWeaponSocketSecondary",
	"VisualRoot/BunnyRig/BackpackSocket",
	"VisualRoot",
	"VisualRoot/Body",
	"VisualRoot/Head",
	"VisualRoot/Scarf",
	"VisualRoot/Hand",
	"VisualRoot/Feet",
	"VisualRoot/StateVFX/DashDustBurst",
	"VisualRoot/StateVFX/LockRing",
	"VisualRoot/StateVFX/LowHealthRing",
	"ReloadProgress3D",
	"ReloadProgress3D/Track",
	"ReloadProgress3D/Fill",
]

var _failures := 0
var _runtime: Array = []
var _runtime_done := false


func _say(line: String) -> void:
	print("SSCK| " + line)


func _fail(line: String) -> void:
	_failures += 1
	_say("FAIL " + line)


func _ok(line: String) -> void:
	_say("OK " + line)


func _compose(node: Node, stop_at: Node) -> Transform3D:
	var chain: Array = []
	var cursor: Node = node
	while cursor != null and cursor != stop_at:
		chain.append(cursor)
		cursor = cursor.get_parent()
	var result := Transform3D.IDENTITY
	for index in range(chain.size() - 1, -1, -1):
		result = result * (chain[index] as Node3D).transform
	return result


func _collect_meshes(root_node: Node, out: Array) -> void:
	if root_node is MeshInstance3D:
		out.append(root_node)
	for child in root_node.get_children():
		_collect_meshes(child, out)


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


func _box_of(avatar: Node, scope: Node) -> AABB:
	var meshes: Array = []
	_collect_meshes(scope, meshes)
	var box := AABB()
	var first := true
	for mesh in meshes:
		var instance := mesh as MeshInstance3D
		if instance.mesh == null:
			continue
		var world := _compose(instance, avatar) * instance.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box


func _static_check(label: String, path: String) -> void:
	_say("==== %s : %s ====" % [label, path])
	var packed := load(path)
	if packed == null:
		_fail("场景加载失败")
		return
	var avatar := (packed as PackedScene).instantiate()
	_say("assembly_version=%s motion_driver=%s" % [
		str(avatar.get_meta("assembly_version", "")), str(avatar.get_meta("motion_driver", ""))])
	if str(avatar.get_meta("motion_driver", "")) != "clip":
		_fail("motion_driver 不是 clip")
	for node_path in REQUIRED_NODES:
		var node := avatar.get_node_or_null(NodePath(node_path))
		if node == null:
			_fail("缺节点 " + node_path)
		elif node is MeshInstance3D and node.visible and not node_path.contains("StateVFX") and not node_path.contains("ReloadProgress3D"):
			var nbox := _compose(node, avatar) * (node as MeshInstance3D).get_aabb()
			_say("  旧回退网格仍可见 %s size=%s" % [node_path, str(nbox.size)])
	var model := avatar.get_node_or_null("VisualRoot/BunnyRig/Model")
	if model == null:
		_fail("缺 Model")
	else:
		var box := _box_of(avatar, model)
		_say("Model 盒 min=%s max=%s SIZE=%s" % [str(box.position), str(box.position + box.size), str(box.size)])
		var tolerance := EXPECTED_HEIGHT * 0.02
		if absf(box.size.y - EXPECTED_HEIGHT) > tolerance:
			_fail("总高 %.4f 超差（目标 %.2f ±%.3f）" % [box.size.y, EXPECTED_HEIGHT, tolerance])
		else:
			_ok("总高 %.4f （目标 %.2f ±%.3f）" % [box.size.y, EXPECTED_HEIGHT, tolerance])
		if absf(box.position.y) > 0.005:
			_fail("脚底 y=%.4f 未贴地（±0.005）" % box.position.y)
		else:
			_ok("脚底 y=%.4f" % box.position.y)
	_say("INFO 整机 AABB SIZE=%s" % str(_box_of(avatar, avatar).size))
	var player := _find_first(avatar, "AnimationPlayer") as AnimationPlayer
	if player == null:
		_fail("找不到 AnimationPlayer")
	else:
		var list := player.get_animation_list()
		_say("动画数=%d" % list.size())
		if list.size() != 128:
			_fail("动画数不是 128")
		var missing: Array = []
		for clip in ["idle", "moving", "walking", "armed_idle", "sidearm_idle", "sidearm_moving_forward", "longgun_reload", "melee_bat_1_active"]:
			if not player.has_animation(clip):
				missing.append(clip)
		if missing.is_empty():
			_ok("关键剪辑齐全")
		else:
			_fail("缺剪辑 " + str(missing))
		_say("INFO 剪辑前 12=%s" % str(list.slice(0, 12)))
	_runtime.append({"label": label, "avatar": avatar})


func _runtime_check() -> void:
	for entry in _runtime:
		var label: String = entry["label"]
		var avatar: Node3D = entry["avatar"]
		var host := Node3D.new()
		host.name = "CheckHost"
		root.add_child(host)
		host.add_child(avatar)
		_say("---- %s 运行时 ----" % label)
		if not avatar.is_inside_tree():
			_fail("加进树后 is_inside_tree 仍为 false")
			continue
		_ok("is_inside_tree=true")
		for _frame in range(10):
			avatar.call("_process", 0.016)
		var motion: Variant = avatar.get("_authored_motion")
		if motion == null or not (motion is ClipMotionLibrary3D):
			_fail("_authored_motion 不是 ClipMotionLibrary3D（实际 %s）" % str(motion))
		else:
			_ok("剪辑库 active_clip=%s fallback=%s speed_role=%s" % [
				str(motion.get("active_clip")), str(motion.get("fallback_reason")), str(motion.get("speed_role"))])
		var rig := avatar.get_node_or_null("VisualRoot/BunnyRig") as Node3D
		var socket := avatar.get_node_or_null("VisualRoot/BunnyRig/WeaponSocket") as Node3D
		var hand_r := avatar.get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointR") as Node3D
		var hand_l := avatar.get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointL") as Node3D
		var head := avatar.get_node_or_null("VisualRoot/BunnyRig/HeadJoint") as Node3D
		if rig != null and socket != null and hand_r != null:
			var inv := rig.global_transform.affine_inverse()
			var socket_local := inv * socket.global_transform
			var hand_r_local := inv * hand_r.global_transform
			var hand_l_local := (inv * hand_l.global_transform) if hand_l != null else Transform3D()
			var head_local := (inv * head.global_transform) if head != null else Transform3D()
			_say("posture WeaponSocket(rig)=%s" % str(socket_local.origin))
			_say("posture 右手(rig)=%s 左手(rig)=%s 头(rig)=%s" % [str(hand_r_local.origin), str(hand_l_local.origin), str(head_local.origin)])
			_say("posture 枪口-右手间距=%.4f m" % socket_local.origin.distance_to(hand_r_local.origin))
		var skel := _find_first(avatar, "Skeleton3D") as Skeleton3D
		if skel == null:
			_fail("找不到 Skeleton3D")
		else:
			_say("Skeleton 骨数=%d" % skel.get_bone_count())
		host.queue_free()


func _initialize() -> void:
	_static_check("女仆 maid01", MAID)
	_static_check("查克2 chuck201", CHUCK)


func _process(_delta: float) -> bool:
	if _runtime_done:
		return true
	_runtime_done = true
	_runtime_check()
	_say("==== 结论：%s（失败项 %d）====" % ["通过" if _failures == 0 else "未通过", _failures])
	return true
