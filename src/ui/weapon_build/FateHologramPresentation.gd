extends Control

## 宿主只负责候选和事务；这里仅管理上下分区及投影开闭。
const TRANSITION := preload("res://src/ui/weapon_build/WeaponHologramTransition.gd")
const BOARD_PATH := "res://assets/art/ui/weapon_build/weapon_build_board.tscn"
var row: HBoxContainer
var board: Control
var _owner: Node
var _intro: Tween
var _epoch := 0
var _settled := false
var _closing := false
var _moving := false
var _dialogue_reserved := false

func set_dialogue_reserved(reserved: bool) -> void:
	_dialogue_reserved = reserved
	_layout()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("ui_prism_exempt", true)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row = HBoxContainer.new()
	row.name = "FateCandidates"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	row.hide()
	add_child(row)
	board = (load(BOARD_PATH) as PackedScene).instantiate() as Control
	board.name = "WeaponBuildBoard"
	add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	board.call("set_compact", true)
	resized.connect(_layout)
	_layout()

func set_player(player: Node) -> void:
	_owner = player
	board.call("set_weapon_owner", player)

func _board_destination() -> Vector2:
	if _dialogue_reserved:
		return Vector2((size.x - board.size.x * 0.68) * 0.5, size.y * 0.50)
	return Vector2(32, size.y * 0.51)

func _layout() -> void:
	if board == null:
		return
	row.position = Vector2(24, maxf(12, size.y * 0.025))
	row.size = Vector2(maxf(1, size.x - 48), 320)
	if _moving:
		return
	board.size = Vector2(maxf(1, size.x - 64), maxf(1, size.y * 0.45 - 40))
	if _settled:
		# 教程期间为两侧人物和底框让出安全区，结束精确回到原布局。
		board.scale = Vector2.ONE * (0.68 if _dialogue_reserved else 1.0)
	if _settled:
		board.position = _board_destination()
	elif not _closing:
		board.position = Vector2(32, (size.y - board.size.y) * 0.5)

func play_intro(reveal: Callable) -> void:
	_epoch += 1
	var epoch := _epoch
	_layout()
	_moving = true
	_intro = TRANSITION.open(board, _owner)
	_intro.finished.connect(func() -> void:
		if epoch != _epoch or _closing:
			return
		_settled = true
		_intro = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var duration := 0.01 if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)) else 0.26
		_intro.tween_property(board, "position", _board_destination(), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_intro.tween_callback(func() -> void:
			if epoch == _epoch and not _closing:
				_moving = false
				_layout()
				row.show()
				reveal.call()))

func play_close() -> void:
	_epoch += 1
	_closing = true
	if _intro != null and _intro.is_valid():
		_intro.kill()
	row.hide()
	await TRANSITION.close(board, _owner).finished
