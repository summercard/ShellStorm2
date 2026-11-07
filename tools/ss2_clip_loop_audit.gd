extends Node3D
## 剪辑循环模式**审计** · 只读工程。
##
## 动机：主人报「跑步动作留在最后一帧，不是重复的」。
## GLB 导入时若无 post-import 脚本，所有 Animation 的 `loop_mode` 默认为
## `LOOP_NONE` ⇒ `AnimationPlayer.play()` 播完**定格在末帧**。
##
## ⚠️ 必须走**真实装配路径**（`chr_maid01_root_v001.tscn` 而不是裸 GLB）：
## 循环标记是在 `ClipMotionLibrary3D.bind()` 里从 JSON 库补齐的，
## 直接 instantiate 裸 GLB 拿到的是**未被修补的引擎默认值** ——
## 首版这么测就报了「128 段全 LOOP_NONE」的假红（修复明明已生效）。
##
## 判据真源是**老通道 JSON 库的 `loop` 字段**（同一批 128 段剪辑，
## Blender 导出时写死；GLB 不带这个信息）。所以本探针直接以 JSON 为准比对，
## 不再自己发明一套名字规则。
##
## 用法：godot --headless --path . --scene res://tools/ss2_clip_loop_audit.tscn

const MAID_SCENE := "res://assets/art/characters/player/external/maid01/chr_maid01_root_v001.tscn"
const CHUCK_SCENE := "res://assets/art/characters/player/external/chuck201/chr_chuck201_root_v001.tscn"
const LOOP_LIBRARY := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_bunny01_motion/anim_bunny01_library.json"


func _say(line: String) -> void:
	print("SSLP| " + line)


func _mode_label(mode: int) -> String:
	match mode:
		Animation.LOOP_NONE:
			return "LOOP_NONE"
		Animation.LOOP_LINEAR:
			return "LOOP_LINEAR"
		Animation.LOOP_PINGPONG:
			return "LOOP_PINGPONG"
	return "UNKNOWN(%d)" % mode


func _load_loop_expectations() -> Dictionary:
	var file := FileAccess.open(LOOP_LIBRARY, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var result := {}
	var clips: Dictionary = (parsed as Dictionary).get("clips", {})
	for key in clips:
		result[str(key)] = bool((clips[key] as Dictionary).get("loop", false))
	return result


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


func _audit(label: String, scene_path: String, expectations: Dictionary) -> bool:
	_say("==== %s : %s ====" % [label, scene_path])
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_say("FAIL 场景加载失败")
		return false
	## 走真实装配：`_ready()` 会建运动库并 `bind()`（其中补 loop 标记）。
	var avatar := packed.instantiate() as Node3D
	add_child(avatar)
	await get_tree().process_frame
	var motion: Variant = avatar.get("_authored_motion")
	if motion == null:
		_say("FAIL 运动库为空")
		return false
	_say("loop_source=%s  applied=%s / total=%s" % [
		str(motion.get("loop_source")), str(motion.get("loop_flags_applied")),
		str(motion.get("loop_flags_total"))])
	var player := _find_first(avatar, "AnimationPlayer") as AnimationPlayer
	if player == null:
		_say("FAIL 找不到 AnimationPlayer")
		return false
	var names := player.get_animation_list()
	_say("剪辑数=%d" % names.size())
	var mode_counts := {}
	var mismatched: Array[String] = []
	var matched := 0
	var missing_in_glb: Array[String] = []
	for clip_name in names:
		var animation := player.get_animation(clip_name)
		if animation == null:
			continue
		var label_mode := _mode_label(animation.loop_mode)
		mode_counts[label_mode] = int(mode_counts.get(label_mode, 0)) + 1
		var key := str(clip_name)
		if not expectations.has(key):
			missing_in_glb.append(key)
			continue
		matched += 1
		var want := bool(expectations[key])
		var got := animation.loop_mode == Animation.LOOP_LINEAR
		if want != got:
			mismatched.append("%s(want=%s got=%s)" % [key, str(want), str(animation.loop_mode)])
	_say("loop_mode 分布：%s" % str(mode_counts))
	_say("与 JSON 库比对：匹配 %d 段，不一致 %d 段" % [matched, mismatched.size()])
	if not mismatched.is_empty():
		_say("   不一致明细（前 12）：%s" % str(mismatched.slice(0, 12)))
	if not missing_in_glb.is_empty():
		_say("   JSON 里没有的剪辑（前 6）：%s" % str(missing_in_glb.slice(0, 6)))
	var loop_count := int(mode_counts.get("LOOP_LINEAR", 0))
	_say("结果：%s（应有 %d 段循环，实测 %d 段）" % [
		"通过" if mismatched.is_empty() else "未通过",
		expectations.values().count(true), loop_count])
	avatar.queue_free()
	return mismatched.is_empty()


func _ready() -> void:
	var expectations := _load_loop_expectations()
	if expectations.is_empty():
		_say("FAIL 读不到循环真源 JSON")
		get_tree().quit(1)
		return
	_say("循环真源：%d 段剪辑（其中应循环 %d 段）" % [
		expectations.size(), expectations.values().count(true)])
	var ok_a := await _audit("女仆 maid01", MAID_SCENE, expectations)
	var ok_b := await _audit("查克2 chuck201", CHUCK_SCENE, expectations)
	_say("==== 结论：%s ====" % ("通过" if ok_a and ok_b else "未通过"))
	get_tree().quit(0 if ok_a and ok_b else 1)
