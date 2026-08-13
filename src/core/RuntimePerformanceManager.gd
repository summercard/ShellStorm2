extends Node
## 正式运行时帧率、失焦节能与渲染质量策略。默认 HIGH 不改变现有画面。

signal quality_changed(profile: String)
signal focus_budget_changed(focused: bool, max_fps: int)

const PROFILE_HIGH := "high"
const PROFILE_BALANCED := "balanced"
const PROFILE_LOW := "low"
const VALID_PROFILES := [PROFILE_HIGH, PROFILE_BALANCED, PROFILE_LOW]
const FOREGROUND_MAX_FPS := 60
const BACKGROUND_MAX_FPS := 15

var quality_profile := PROFILE_HIGH
var focused := true
var application_paused := false
var scene_tree_paused := false
var _registered_atmospheres: Array[WeakRef] = []
var _registered_lights: Array[WeakRef] = []
var _verification_frame_budget_override := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quality_profile = str(ProjectSettings.get_setting("performance/quality_profile", PROFILE_HIGH))
	if quality_profile not in VALID_PROFILES:
		quality_profile = PROFILE_HIGH
	set_process(true)
	_apply_frame_budget(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_apply_frame_budget(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_apply_frame_budget(false)
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		application_paused = true
		_apply_current_frame_budget()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		application_paused = false
		_apply_current_frame_budget()


func _process(_delta: float) -> void:
	var next_scene_tree_paused := get_tree().paused
	if scene_tree_paused == next_scene_tree_paused:
		return
	scene_tree_paused = next_scene_tree_paused
	_apply_current_frame_budget()


func set_quality_profile(profile: String) -> bool:
	if profile not in VALID_PROFILES:
		return false
	if quality_profile == profile:
		return true
	quality_profile = profile
	_apply_quality_to_registered()
	quality_changed.emit(profile)
	return true


func register_atmosphere(atmosphere: Node) -> void:
	_register_weak(_registered_atmospheres, atmosphere)
	if atmosphere != null and atmosphere.has_method("apply_performance_quality"):
		atmosphere.call("apply_performance_quality", quality_profile)


func register_light(light: Node) -> void:
	_register_weak(_registered_lights, light)
	if light != null and light.has_method("apply_performance_quality"):
		light.call("apply_performance_quality", quality_profile)


func get_shadow_light_limit() -> int:
	return 3 if quality_profile == PROFILE_HIGH else 2 if quality_profile == PROFILE_BALANCED else 1


func get_snapshot() -> Dictionary:
	_prune_weak(_registered_atmospheres)
	_prune_weak(_registered_lights)
	return {
		"quality_profile": quality_profile,
		"focused": focused,
		"application_paused": application_paused,
		"scene_tree_paused": scene_tree_paused,
		"max_fps": Engine.max_fps,
		"foreground_max_fps": FOREGROUND_MAX_FPS,
		"background_max_fps": BACKGROUND_MAX_FPS,
		"verification_frame_budget_override": _verification_frame_budget_override,
		"shadow_light_limit": get_shadow_light_limit(),
		"registered_atmospheres": _registered_atmospheres.size(),
		"registered_lights": _registered_lights.size(),
	}


func simulate_focus_for_test(next_focused: bool) -> void:
	_apply_frame_budget(next_focused)


func simulate_pause_for_test(next_paused: bool) -> void:
	application_paused = next_paused
	_apply_current_frame_budget()


func set_verification_frame_budget_override(max_fps: int) -> void:
	# 真实渲染自动化通常在非焦点窗口运行。只有验收场景显式调用此入口，
	# 才锁定被测前台预算；0 会恢复正式的焦点/暂停策略。
	_verification_frame_budget_override = maxi(0, max_fps)
	_apply_current_frame_budget()


func _apply_frame_budget(next_focused: bool) -> void:
	focused = next_focused
	_apply_current_frame_budget()


func _apply_current_frame_budget() -> void:
	var foreground_active := focused and not application_paused and not scene_tree_paused
	Engine.max_fps = (
		_verification_frame_budget_override
		if _verification_frame_budget_override > 0
		else FOREGROUND_MAX_FPS if foreground_active else BACKGROUND_MAX_FPS
	)
	focus_budget_changed.emit(focused, Engine.max_fps)


func _apply_quality_to_registered() -> void:
	for collection in [_registered_atmospheres, _registered_lights]:
		_prune_weak(collection)
		for reference in collection:
			var node := (reference as WeakRef).get_ref() as Node
			if node != null and node.has_method("apply_performance_quality"):
				node.call("apply_performance_quality", quality_profile)


func _register_weak(collection: Array[WeakRef], node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	for reference in collection:
		if reference.get_ref() == node:
			return
	collection.append(weakref(node))


func _prune_weak(collection: Array[WeakRef]) -> void:
	for index in range(collection.size() - 1, -1, -1):
		var node := collection[index].get_ref() as Node
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			collection.remove_at(index)
