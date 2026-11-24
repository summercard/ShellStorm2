class_name ChannelManagerPortal3D
extends Node3D
## 频道管理者技能结果对应的墙面裂口。
## 只做视觉表现：玩家穿越与后续地图逻辑由后续关卡设计接管。

signal opening_finished(result: String)

const OPEN_SECONDS := 1.45
# room_09 的两个作者对象职责不同：蓝色盒保持房间全息底层，虚空盒作为北墙门。
const BACKGROUND_NODE := "CyberSpaceBlueBox"
const DOOR_NODE := "VoidErosionBox"

var result := ""
var _room: Node3D
var _background: Node3D
var _volume: Node3D
var _elapsed := 0.0
var _opening := false


func configure_room(room: Node3D) -> void:
	_room = room
	_disable_all()
	var background := _room.find_child(BACKGROUND_NODE, true, false) as Node3D
	if background != null:
		background.set("enabled", true)
		background.set("progress", 1.0)


func open(card_result: String) -> bool:
	if card_result.is_empty() or not is_instance_valid(_room):
		return false
	var background := _room.find_child(BACKGROUND_NODE, true, false) as Node3D
	var door := _room.find_child(DOOR_NODE, true, false) as Node3D
	if background == null or door == null or not background.has_method("refresh_targets") or not door.has_method("refresh_targets"):
		push_error("ChannelManagerPortal: missing authored objects %s / %s" % [BACKGROUND_NODE, DOOR_NODE])
		return false
	_disable_all()
	result = card_result
	_background = background
	_background.set("enabled", true)
	_background.set("progress", 1.0)
	_volume = door
	_volume.set("enabled", true)
	_volume.set("progress", 0.0)
	_elapsed = 0.0
	_opening = true
	return true


func cancel_opening() -> void:
	_disable_all()
	result = ""


func _process(delta: float) -> void:
	if not _opening or _volume == null or not is_instance_valid(_volume):
		return
	_elapsed += maxf(delta, 0.0)
	var t := clampf(_elapsed / OPEN_SECONDS, 0.0, 1.0)
	_volume.set("progress", _aperture_progress(t))
	if t >= 1.0:
		_opening = false
		opening_finished.emit(result)


func _aperture_progress(t: float) -> float:
	# 三拍开裂：中心闪现、短暂回收、快速拉开，最后轻微回弹。
	if t < 0.16:
		return lerpf(0.0, 0.10, smoothstep(0.0, 1.0, t / 0.16))
	if t < 0.30:
		return lerpf(0.10, 0.045, smoothstep(0.0, 1.0, (t - 0.16) / 0.14))
	if t < 0.80:
		return lerpf(0.045, 0.88, smoothstep(0.0, 1.0, (t - 0.30) / 0.50))
	if t < 0.94:
		return lerpf(0.88, 1.08, ease((t - 0.80) / 0.14, 0.55))
	return lerpf(1.08, 1.0, smoothstep(0.0, 1.0, (t - 0.94) / 0.06))


func is_open() -> bool:
	return _volume != null and is_instance_valid(_volume) and not _opening


func _disable_all() -> void:
	if _room == null or not is_instance_valid(_room):
		return
	for node_name: String in [BACKGROUND_NODE, DOOR_NODE]:
		var volume := _room.find_child(node_name, true, false) as Node3D
		if volume != null:
			volume.set("enabled", false)
			volume.set("progress", 0.0)
	_volume = null
	_opening = false
