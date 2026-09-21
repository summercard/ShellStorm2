extends Node
## 诊断探针：真实塔楼开场下，剧情 01 与 MainEntryScreen3D 的**输入/相机争用**。
##
## 为什么需要它：headless 下 TowerDescent3D._install_main_entry_screen() 会直接 return
## （test_mode / headless 早退），所以常规探针看不到开场页。这里**手工挂载**同一个
## 开场页场景，并严格复刻真机时序：
##   1. add_child(tower) —— tower._ready 里已 room_entered 触发剧情（play() 入队）
##   2. 同帧 add_child(entry) —— entry._ready 里 call_deferred("_auto_present")
##   3. 帧末 _auto_present → present() → set_input_locked(true)，_previous_input_locked=false
##   4. 下一帧剧情首帧派发 t=0 的 player.lock_input → before 读到 **true**
## 这正是真机顺序，也是 before=true 被登记成"归还值"的根因。
##
## 只读，不改任何游戏数据；跑完打印 DIAG 行，最后 quit。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const ENTRY_SCENE := "res://scenes/ui/MainEntryScreen3D.tscn"
const SEED := 990098
const CLICK_START_AT := 1.5
const RUN_SECONDS := 22.0

var _tower: TowerDescent3D = null
var _entry: CanvasLayer = null
var _player: Player3D = null
var _elapsed := 0.0

var _last_locked: Variant = null
var _last_active := false
var _last_presenting: Variant = null
var _clicked := false


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var packed := load(TOWER_SCENE) as PackedScene
	if packed == null:
		print("DIAG FATAL 塔楼场景加载失败")
		return
	_tower = packed.instantiate() as TowerDescent3D
	_tower.test_mode = true
	_tower.run_seed_override = SEED
	_tower.force_new_game_opening_for_test = true
	add_child(_tower)

	# 同帧挂开场页：复刻真机"剧情已入队、开场页尚未 present"的状态。
	var entry_packed := load(ENTRY_SCENE) as PackedScene
	if entry_packed != null:
		_entry = entry_packed.instantiate() as CanvasLayer
		add_child(_entry)

	await get_tree().physics_frame
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player_3d") as Player3D

	print("=== 帧 0：剧情已入队、开场页 auto_present 即将执行 ===")
	_dump("t0")

	var physics_step := 1.0 / 60.0
	var sample_accum := 0.0
	while _elapsed < RUN_SECONDS:
		await get_tree().physics_frame
		_elapsed += physics_step
		sample_accum += physics_step
		if not _clicked and _elapsed >= CLICK_START_AT:
			_clicked = true
			_click_start()
		if sample_accum >= 0.5:
			sample_accum = 0.0
			_dump("t=%.1f" % _elapsed)

	print("=== 结束态 ===")
	_dump("end")
	print("DIAG diagnostics=%s" % str(NarrativeDirector.diagnostics()))
	print("DIAG dispatch_log=%s" % str(NarrativeDirector.dispatch_log()))


func _click_start() -> void:
	if _entry == null or not is_instance_valid(_entry):
		print("DIAG 未挂开场页，跳过点击开始")
		return
	print(">>> 模拟点击「开始」（t=%.2f）" % _elapsed)
	_entry.call("start_game")


func _dump(tag: String) -> void:
	if _player == null or not is_instance_valid(_player):
		print("DIAG %s player 无效" % tag)
		return
	var locked := bool(_player.input_locked)
	var active := NarrativeDirector.is_playing()
	var presenting: Variant = false
	if _entry != null and is_instance_valid(_entry):
		presenting = _entry.get("_presenting")
	var cam: Camera3D = _player.camera
	var cam_txt := "cam=n/a"
	if cam != null and is_instance_valid(cam):
		var offset := cam.global_position - _player.global_position
		cam_txt = "camY=%.2f planar=%.2f horizAngle=%.1f" % [
			cam.global_position.y,
			Vector2(offset.x, offset.z).length(),
			rad_to_deg(atan2(offset.y, Vector2(offset.x, offset.z).length())),
		]
	var marks: Array[String] = []
	if _last_locked != locked:
		_last_locked = locked
		marks.append("<<<input_locked=%s" % str(locked))
	if _last_active != active:
		_last_active = active
		marks.append("<<<nar_playing=%s" % str(active))
	if _last_presenting != presenting:
		_last_presenting = presenting
		marks.append("<<<entry_presenting=%s" % str(presenting))
	print(
		"DIAG %-8s locked=%-5s nar=%-5s t=%5.2f entry_presenting=%-5s %s %s"
		% [
			tag, str(locked), str(active), NarrativeDirector.active_time(),
			str(presenting), cam_txt, " ".join(marks),
		]
	)
