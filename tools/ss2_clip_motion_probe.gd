extends Node3D
## 换角色（clip 装配）**判活探针** · 只读工程、不改玩法。
##
## 为什么必须单开一个：
## `tools/ss2_char_swap_check.gd` 的 `posture` 读数与 `chr_maid01_root_v001.tscn`
## 里的**静态 rest 值逐位吻合**（差 1e-5 量级），意味着「关节跟着骨骼走」这件事
## 其实**没被证明** —— 它恰好也是「骨架根本没被驱动」的读数。
## （2026-09 踩过同款：0.04° 中位跳变被当成"静止"，实为动画未驱动。）
##
## 判据只有一条：**跨真帧的位移波动幅度**。
##   · 波动 ≈ 1e-6 m  ⇒ 冻结在 rest pose，动画没在驱动（FAIL）
##   · 波动 ≥ 1e-3 m  ⇒ 骨架确实被驱动（PASS，幅度另行打印供人读）
##
## 用法（**不加 --headless 也行，但 headless 更稳**；本探针不出图）：
##   godot --headless --path . --scene res://tools/ss2_clip_motion_probe.tscn
## 用 `--scene` 而非 `--script`：Player3D 依赖 autoload，`--script` 模式不加载它们。

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
## 采样对象：GLB 骨架骨骼 + 表现层挂点（两者都取，才能区分"骨骼动了但没同步"）。
const BONES := [
	"mixamorig_Hips", "mixamorig_Head", "mixamorig_RightHand", "mixamorig_LeftFoot",
]
const JOINTS := [
	"VisualRoot/BunnyRig/HandRoot/HandJointR",
	"VisualRoot/BunnyRig/HeadJoint",
	"VisualRoot/BunnyRig/FeetRoot/FootJointL",
]
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 60
## 硬判据：跨 60 帧的最大单轴摆幅。低于此值 = 冻结在 rest pose。
const ALIVE_MIN_AMPLITUDE := 0.001

var _player: Node3D
var _skeleton: Skeleton3D
var _bone_index: Dictionary = {}
var _joint_nodes: Array[Node3D] = []
var _joint_paths: Array[String] = []

var _frames := 0
var _phase := ""
var _sampling := false
## label -> bone/joint 名 -> Array[Vector3]
var _samples: Dictionary = {}
var _failures: Array[String] = []
var _lines: Array[String] = []


func _say(line: String) -> void:
	_lines.append(line)
	print("SSMP| " + line)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.4, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	body.add_child(shape)
	add_child(body)


func _ready() -> void:
	_build_ground()
	_player = PLAYER_SCENE.instantiate() as Node3D
	add_child(_player)
	var avatar := _player.get_node_or_null("Avatar3D")
	if avatar == null:
		_say("FAIL 找不到 Avatar3D")
		get_tree().quit(1)
		return
	_say("avatar scene=%s" % str(avatar.get_meta("source_model", "(无)")))
	_say("motion_driver=%s assembly_version=%s" % [
		str(avatar.get_meta("motion_driver", "")), str(avatar.get_meta("assembly_version", ""))])
	var motion: Variant = avatar.get("_authored_motion")
	_say("_authored_motion=%s" % ("null" if motion == null else motion.get_class()))
	if motion != null:
		_say("library_version=%s" % str(motion.get("library_version")))
	_skeleton = _find_first(_player, "Skeleton3D") as Skeleton3D
	if _skeleton == null:
		_say("FAIL 找不到 Skeleton3D")
		get_tree().quit(1)
		return
	for index in range(_skeleton.get_bone_count()):
		_bone_index[_skeleton.get_bone_name(index)] = index
	_say("骨架骨数=%d" % _skeleton.get_bone_count())
	for path in JOINTS:
		var node := avatar.get_node_or_null(NodePath(path)) as Node3D
		if node == null:
			_say("FAIL 缺表现挂点 %s" % path)
			_failures.append(path)
			continue
		_joint_nodes.append(node)
		_joint_paths.append(path)


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


func _sample_now(label: String) -> void:
	if label.is_empty():
		return
	var bucket: Dictionary = _samples.get(label, {})
	for bone_name in BONES:
		if not _bone_index.has(bone_name):
			continue
		var pose := _skeleton.get_bone_global_pose(int(_bone_index[bone_name]))
		var trace: Array = bucket.get(bone_name, [])
		trace.append(pose.origin)
		bucket[bone_name] = trace
	for index in range(_joint_nodes.size()):
		var key := "joint:" + _joint_paths[index]
		var trace2: Array = bucket.get(key, [])
		trace2.append(_joint_nodes[index].position)
		bucket[key] = trace2
	_samples[label] = bucket


func _amplitude(label: String, key: String) -> float:
	var bucket: Dictionary = _samples.get(label, {})
	var trace: Array = bucket.get(key, [])
	if trace.size() < 2:
		return -1.0
	var first: Vector3 = trace[0]
	var lo := first
	var hi := first
	for value in trace:
		var point: Vector3 = value
		lo = Vector3(minf(lo.x, point.x), minf(lo.y, point.y), minf(lo.z, point.z))
		hi = Vector3(maxf(hi.x, point.x), maxf(hi.y, point.y), maxf(hi.z, point.z))
	var delta := hi - lo
	return maxf(delta.x, maxf(delta.y, delta.z))


func _report(label: String) -> void:
	var bucket: Dictionary = _samples.get(label, {})
	if bucket.is_empty():
		_say("FAIL [%s] 无采样数据" % label)
		_failures.append(label + "/无数据")
		return
	var worst := INF
	var worst_key := ""
	for key in bucket:
		var amplitude := _amplitude(label, key)
		var tag := "OK  " if amplitude >= ALIVE_MIN_AMPLITUDE else "FAIL"
		_say("%s [%s] %-52s 摆幅=%.6f m" % [tag, label, key, amplitude])
		if amplitude < worst:
			worst = amplitude
			worst_key = key
	if worst < ALIVE_MIN_AMPLITUDE:
		_failures.append("%s/%s 摆幅 %.6f < %.4f" % [label, worst_key, worst, ALIVE_MIN_AMPLITUDE])
	else:
		_say("PASS [%s] 全部通道最小摆幅=%.6f m（%s）" % [label, worst, worst_key])


func _rest_check(label: String) -> void:
	## 与 tscn 静态值对表：只要采样起点 ≈ rest 且全程无波动，就是没驱动。
	var bucket: Dictionary = _samples.get(label, {})
	for index in range(_joint_nodes.size()):
		var key := "joint:" + _joint_paths[index]
		var trace: Array = bucket.get(key, [])
		if trace.is_empty():
			continue
		var point: Vector3 = trace[0]
		_say("   rest表 [%s] %s 首帧=%s" % [label, _joint_paths[index], str(point)])


func _process(_delta: float) -> void:
	_frames += 1
	if _sampling:
		_sample_now(_phase)
	if _frames < WARMUP_FRAMES or _frames > WARMUP_FRAMES + SAMPLE_FRAMES * 2 + 40:
		return
	if _frames == WARMUP_FRAMES:
		_phase = "idle"
		_sampling = true
		_say("---- 采样段 A：idle（玩家静置）----")
	elif _frames == WARMUP_FRAMES + SAMPLE_FRAMES:
		_sampling = false
		_report("idle")
		_rest_check("idle")
		## 切 moving：gallery 同款接口，需 input_locked=false。
		if _player.get("input_locked") != null:
			_player.set("input_locked", false)
		_player.call("set_test_move_direction", Vector3(0.0, 0.0, -1.0))
		_say("---- 采样段 B：moving（set_test_move_direction=-Z）----")
		_phase = "moving"
		_sampling = true
	elif _frames == WARMUP_FRAMES + SAMPLE_FRAMES * 2:
		_sampling = false
		_report("moving")
		_rest_check("moving")
		var motion: Variant = _player.get_node_or_null("Avatar3D").get("_authored_motion")
		if motion != null:
			_say("INFO 最终 active_clip=%s fallback=%s playback_rate=%.3f movement_direction=%s" % [
				str(motion.get("active_clip")), str(motion.get("fallback_reason")),
				float(motion.get("playback_rate")), str(motion.get("movement_direction"))])
		var verdict := "通过" if _failures.is_empty() else "未通过"
		print("SSMP| ==== 结论：%s（失败项 %d）====" % [verdict, _failures.size()])
		for item in _failures:
			print("SSMP|   · " + item)
		get_tree().quit(0 if _failures.is_empty() else 1)
