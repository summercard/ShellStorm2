extends Node
## 窗口指针与世界准星的统一显示入口。场景只提供自己的交互上下文。

enum Presentation { HIDDEN, UI, AIM }

const ARROW_HOTSPOT := Vector2(3, 3)
const ARROW_SVG := '''<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
<path d="M3 3 L22 16 L14 17 L18 25 L13.5 27 L9.5 19 L4 25 Z"
      fill="%s" stroke="#14222a" stroke-width="2.2" stroke-linejoin="round"/>
%s</svg>'''
const DRAG_MARK := '<circle cx="25" cy="24" r="4" fill="#7fe9e9" stroke="#14222a" stroke-width="2"/>'
const DROP_MARK := '<path d="M21 24l3 3 5-6" fill="none" stroke="#14222a" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/><path d="M21 24l3 3 5-6" fill="none" stroke="#8ef3d5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
const FORBIDDEN_MARK := '<circle cx="25" cy="24" r="5" fill="#14222a"/><path d="M22 21l6 6m0-6-6 6" stroke="#ff8b84" stroke-width="2" stroke-linecap="round"/>'

var _reticle: Node3D
var _world_context := Callable()
var _overlays: Dictionary[int, Callable] = {}
var _has_mouse := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_has_mouse = DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)
	if _has_mouse:
		_install_arrow(Input.CURSOR_ARROW, "#f0ffff")
		_install_arrow(Input.CURSOR_POINTING_HAND, "#8ef3ed")
		_install_arrow(Input.CURSOR_DRAG, "#f0ffff", DRAG_MARK)
		_install_arrow(Input.CURSOR_CAN_DROP, "#f0ffff", DROP_MARK)
		_install_arrow(Input.CURSOR_FORBIDDEN, "#f0ffff", FORBIDDEN_MARK)
	get_window().focus_entered.connect(_refresh)
	get_window().focus_exited.connect(_refresh)
	InputDevice.active_device_changed.connect(func(_device: String) -> void: _refresh())
	Global.game_paused.connect(func(_paused: bool) -> void: _refresh())


func bind_world(reticle: Node3D, context: Callable) -> void:
	if is_instance_valid(_reticle) and _reticle != reticle:
		_reticle.hide()
	if _reticle != reticle:
		reticle.tree_exited.connect(_release_world.bind(reticle.get_instance_id()), CONNECT_ONE_SHOT)
	_reticle = reticle
	_world_context = context
	_refresh()


func bind_overlay(owner: Node, context: Callable) -> void:
	var owner_id := owner.get_instance_id()
	if not _overlays.has(owner_id):
		owner.tree_exited.connect(_release_overlay.bind(owner_id), CONNECT_ONE_SHOT)
	_overlays[owner_id] = context
	_refresh()


func get_presentation() -> Presentation:
	if not _overlays.is_empty():
		var top: Callable = _overlays.values().back()
		if top.is_valid():
			return top.call()
	if get_tree().paused:
		return Presentation.UI
	if _world_context.is_valid():
		return _world_context.call()
	return Presentation.UI


func is_aim_blocked(reticle: Node3D) -> bool:
	return _reticle == reticle and (get_presentation() != Presentation.AIM or not _window_has_focus())


func _process(_delta: float) -> void:
	_refresh()


func _release_world(reticle_id: int) -> void:
	if is_instance_valid(_reticle) and _reticle.get_instance_id() == reticle_id:
		_reticle = null
		_world_context = Callable()


func _release_overlay(owner_id: int) -> void:
	_overlays.erase(owner_id)


func _window_has_focus() -> bool:
	return not _has_mouse or get_window().has_focus()


func _refresh() -> void:
	var presentation := get_presentation()
	var focused := _window_has_focus()
	if is_instance_valid(_reticle):
		_reticle.visible = focused and presentation == Presentation.AIM
	if not _has_mouse:
		return
	var desired := Input.MOUSE_MODE_HIDDEN
	if not focused:
		desired = Input.MOUSE_MODE_VISIBLE
	elif InputDevice.get_active_device() == InputDevice.DEVICE_KEYBOARD_MOUSE:
		if presentation == Presentation.AIM:
			desired = Input.MOUSE_MODE_CONFINED_HIDDEN
		elif presentation == Presentation.UI:
			desired = Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != desired:
		Input.mouse_mode = desired


func _install_arrow(shape: Input.CursorShape, fill: String, mark: String = "") -> void:
	var image := Image.new()
	if image.load_svg_from_string(ARROW_SVG % [fill, mark]) == OK:
		Input.set_custom_mouse_cursor(image, shape, ARROW_HOTSPOT)
