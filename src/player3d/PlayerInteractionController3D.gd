class_name PlayerInteractionController3D
extends Node
## 3D世界唯一的“interact”输入入口。
## 可交互对象只实现候选/聚焦/执行协议，不得自行读取E键。

const PROVIDER_GROUP := "interaction_provider_3d"
const INTERACTION_DOT_SCRIPT := preload("res://src/ui/InteractionDot3D.gd")
## provider 没有提供锚点时的兜底高度：悬在对象原点上方，避免圆点埋进地板。
const DOT_ANCHOR_FALLBACK_HEIGHT_M := 1.7
## 不挂圆点的 provider（2026-10-02 主人指定）。
##
## 基地设施保留自己那套「黄色文字提示牌」：牌子的显隐由 BaseFacility3D 自己的
## set_interaction_focus() 负责，这里再挂一个圆点就成了双份提示。
##
## 用脚本路径、而不是 `provider is BaseFacility3D`：控制器在 player3d/ 下，
## 不该为了一条表现策略反向依赖 base3d/。
## 代价是改了文件名会**静默**失效，所以由 verify_interaction_dot_presentation 的
## 「基地设施不挂圆点」断言盯着 —— 谁动了这条路径，测试当场变红。
const DOT_EXCLUDED_PROVIDER_SCRIPTS := [
	"res://src/base3d/BaseFacility3D.gd",
]

var player: Player3D
var _focused_provider: Node
var _focused_candidate: Dictionary = {}
## provider instance_id → InteractionDot3D。常驻圆点由控制器统一创建与驱动。
var _dots: Dictionary = {}


func configure(p_player: Player3D) -> void:
	player = p_player
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_refresh_focused_candidate()
	_sync_interaction_dots(delta)


func _exit_tree() -> void:
	for id in _dots.keys():
		var dot: Variant = _dots.get(id)
		if dot != null and is_instance_valid(dot):
			(dot as Node).queue_free()
	_dots.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if request_interaction():
		get_viewport().set_input_as_handled()


func request_interaction() -> bool:
	if not _can_player_interact():
		_clear_focus()
		return false
	_refresh_focused_candidate()
	if _focused_provider == null or _focused_candidate.is_empty():
		return false
	if not _focused_provider.has_method("perform_interaction"):
		return false
	var performed := bool(_focused_provider.call(
		"perform_interaction", player, _focused_candidate.duplicate()
	))
	if performed:
		# 交互成功的一次性反馈：圆点放大脉冲。读条类交互由进度环触顶自己触发。
		pulse_dot(_focused_provider)
	return performed


func get_focus_snapshot() -> Dictionary:
	if _focused_provider == null or _focused_candidate.is_empty():
		return {}
	return {
		"provider": _focused_provider.name,
		"interaction_id": str(_focused_candidate.get("interaction_id", "")),
		"prompt": str(_focused_candidate.get("prompt", "")),
		"priority": int(_focused_candidate.get("priority", 0)),
		"distance_m": float(_focused_candidate.get("distance_m", INF)),
	}


func _refresh_focused_candidate() -> void:
	if not _can_player_interact() or not is_inside_tree():
		_clear_focus()
		return
	var best_provider: Node = null
	var best_candidate: Dictionary = {}
	for value in get_tree().get_nodes_in_group(PROVIDER_GROUP):
		var provider := value as Node
		if not _provider_is_eligible(provider):
			continue
		var candidate := provider.call("get_interaction_candidate", player) as Dictionary
		if candidate.is_empty() or not bool(candidate.get("available", false)):
			continue
		var position := candidate.get("position", Vector3.INF) as Vector3
		if not position.is_finite():
			continue
		candidate["distance_m"] = player.global_position.distance_to(position)
		if _candidate_is_better(candidate, provider, best_candidate, best_provider):
			best_provider = provider
			best_candidate = candidate
	_set_focus(best_provider, best_candidate)


func _provider_is_eligible(provider: Node) -> bool:
	if (
		provider == null
		or not is_instance_valid(provider)
		or not provider.is_inside_tree()
		or not provider.has_method("get_interaction_candidate")
		or not provider.has_method("perform_interaction")
	):
		return false
	if provider is Node3D:
		return (provider as Node3D).get_world_3d() == player.get_world_3d()
	return true


## 这个 provider 该不该拿圆点。见 DOT_EXCLUDED_PROVIDER_SCRIPTS 的说明。
func _provider_uses_dot(provider: Node) -> bool:
	var script := provider.get_script() as Script
	if script == null:
		return true
	return not DOT_EXCLUDED_PROVIDER_SCRIPTS.has(script.resource_path)


func _candidate_is_better(
	candidate: Dictionary,
	provider: Node,
	current: Dictionary,
	current_provider: Node
) -> bool:
	if current_provider == null or current.is_empty():
		return true
	var priority := int(candidate.get("priority", 0))
	var current_priority := int(current.get("priority", 0))
	if priority != current_priority:
		return priority > current_priority
	var distance := float(candidate.get("distance_m", INF))
	var current_distance := float(current.get("distance_m", INF))
	if not is_equal_approx(distance, current_distance):
		return distance < current_distance
	return provider.get_instance_id() < current_provider.get_instance_id()


func _set_focus(provider: Node, candidate: Dictionary) -> void:
	var previous_id := str(_focused_candidate.get("interaction_id", ""))
	var next_id := str(candidate.get("interaction_id", ""))
	if (
		_focused_provider != null
		and is_instance_valid(_focused_provider)
		and (_focused_provider != provider or previous_id != next_id)
		and _focused_provider.has_method("set_interaction_focus")
	):
		_focused_provider.call("set_interaction_focus", _focused_candidate, false)
	_focused_provider = provider
	_focused_candidate = candidate
	if (
		_focused_provider != null
		and _focused_provider.has_method("set_interaction_focus")
	):
		_focused_provider.call("set_interaction_focus", _focused_candidate, true)


func _clear_focus() -> void:
	if (
		_focused_provider != null
		and is_instance_valid(_focused_provider)
		and _focused_provider.has_method("set_interaction_focus")
	):
		_focused_provider.call("set_interaction_focus", _focused_candidate, false)
	_focused_provider = null
	_focused_candidate.clear()


func _can_player_interact() -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.is_inside_tree()
		and not get_tree().paused
		and not player.input_locked
		and player.current_hp > 0
	)


# ============================================================================
# 常驻交互圆点
# ----------------------------------------------------------------------------
# 控制器是唯一知道「谁可交互、谁被聚焦、距离多远、按 e 能做什么」的地方，所以圆点
# 也在这里统一创建与驱动：provider 只按需暴露三个可选接口，不实现也能得到一个默认圆点。
#   get_interaction_dot_anchor() -> Vector3    圆点世界锚点（缺省：原点上方）
#   is_interaction_dot_visible() -> bool       圆点是否该常驻显示（缺省：true）
#   get_interaction_progress() -> Dictionary   {"active": bool, "progress": float}
# 圆点主色**不在这里分派**：全场是同一个白点，见 InteractionDot3D.DOT_COLOR。
# ============================================================================

func _sync_interaction_dots(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	# 暂停时停住动画时间，但位置与可见性继续跟随，暂停画面里圆点不会「卡在半空」。
	var step := 0.0 if tree.paused else delta
	var live_ids := {}
	for value in tree.get_nodes_in_group(PROVIDER_GROUP):
		var provider := value as Node
		if not _provider_is_eligible(provider) or not _provider_uses_dot(provider):
			continue
		var id := provider.get_instance_id()
		live_ids[id] = true
		var dot := _ensure_dot(provider, id)
		if dot == null:
			continue
		var anchor := _dot_anchor(provider)
		(dot as Node3D).global_position = anchor
		# 距离 →（尺寸档, 清晰度）的映射只有一处实现：圆点脚本里的两个 static。
		# 控制器曾自己抄一份算式，两处口径一旦漂移，「走近才变大」会静默失效 ——
		# 画面看着还行，数字却对不上。故收回成一个真源。
		var distance := player.global_position.distance_to(anchor)
		dot.call("set_approach_from_distance", distance)
		var clarity := INTERACTION_DOT_SCRIPT.clarity_for_distance(distance)
		dot.call("set_visible_state", _dot_should_show(provider))
		if provider.has_method("get_interaction_progress"):
			var progress := provider.call("get_interaction_progress") as Dictionary
			dot.call(
				"set_progress",
				bool(progress.get("active", false)),
				float(progress.get("progress", 0.0))
			)
		# 按键牌的功能词只在被聚焦的那个圆点上显示；其余圆点清空，
		# 免得残留上一句文案（聚焦量平滑衰减期间牌子上会挂着旧词）。
		var prompt_text := ""
		if provider == _focused_provider:
			prompt_text = str(_focused_candidate.get("prompt", ""))
		dot.call("set_prompt", prompt_text)
		dot.call("update_state", clarity, provider == _focused_provider, step)
	_prune_dots(live_ids)


## 让某个 provider 的圆点播一次放大脉冲。已在读条中的对象不必调用 ——
## 进度环触顶时圆点会自己触发。
func pulse_dot(provider: Node) -> void:
	if provider == null or not is_instance_valid(provider):
		return
	var dot: Variant = _dots.get(provider.get_instance_id())
	if dot != null and is_instance_valid(dot):
		(dot as Node).call("play_confirm_pulse")


func get_interaction_dot_snapshot(provider: Node) -> Dictionary:
	if provider == null or not is_instance_valid(provider):
		return {}
	var dot: Variant = _dots.get(provider.get_instance_id())
	if dot == null or not is_instance_valid(dot):
		return {}
	return (dot as Node).call("get_snapshot") as Dictionary


func get_interaction_dot_count() -> int:
	return _dots.size()


func _ensure_dot(provider: Node, id: int) -> Node:
	# provider 被 free 时圆点作为子节点一并释放，字典里可能留下悬垂引用，
	# 所以先取 Variant 判定有效性 —— 直接 `as Node` 转换已释放对象会报 cast 错误。
	var existing: Variant = _dots.get(id)
	if existing != null and is_instance_valid(existing):
		return existing as Node
	# 用 preload + Node/动态调用，而不是全局类名类型标注：新增的 class_name 在
	# .godot/global_script_class_cache.cfg 刷新前用全局名会 parse error（同
	# LevelPlanValidator 的处理）。
	var dot := INTERACTION_DOT_SCRIPT.new() as Node
	dot.name = "InteractionDot3D"
	provider.add_child(dot)
	_dots[id] = dot
	return dot


func _prune_dots(live_ids: Dictionary) -> void:
	var stale: Array = []
	for id in _dots.keys():
		if live_ids.has(id):
			continue
		var dot: Variant = _dots.get(id)
		if dot != null and is_instance_valid(dot):
			(dot as Node).queue_free()
		stale.append(id)
	for id in stale:
		_dots.erase(id)


func _dot_anchor(provider: Node) -> Vector3:
	if provider.has_method("get_interaction_dot_anchor"):
		var raw: Variant = provider.call("get_interaction_dot_anchor")
		if raw is Vector3 and (raw as Vector3).is_finite():
			return raw as Vector3
	if provider is Node3D:
		return (provider as Node3D).global_position + Vector3.UP * DOT_ANCHOR_FALLBACK_HEIGHT_M
	return Vector3.ZERO


func _dot_should_show(provider: Node) -> bool:
	if provider.has_method("is_interaction_dot_visible"):
		return bool(provider.call("is_interaction_dot_visible"))
	return true
