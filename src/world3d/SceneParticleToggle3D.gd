# src/world3d/SceneParticleToggle3D.gd
# 场景氛围粒子开关执行者。
# 设计原则：
#   - 监听 GraphicsSettingsManager.settings_changed，仅对 scene_particles 变化生效
#   - 遍历场景树中所有 GPUParticles3D / CPUParticles3D 节点
#   - 过滤规则：节点或其任意祖先的 metadata/asset_category == "scene_vfx" 才视为场景粒子
#   - 关掉时：emitting=false + visible=false + freeze=true（GPU 模拟停 + 渲染停 + 进程停）
#   - 开启时：恢复原状态（emitting=true + visible=true + freeze=false）
#   - 不动其他脚本，不动任何 .tscn
extends Node

const PARTICLE_GROUP_TAG := "scene_vfx"  # 与现有场景粒子 metadata/asset_category 对齐

var _last_enabled: bool = true
var _cached_state: Dictionary = {}  # node_instance_id -> { emitting, visible, freeze, was_alive }


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 首帧同步一次（应用启动时玩家设置已加载完）
	if GraphicsSettingsManager != null:
		_apply(GraphicsSettingsManager.is_enabled("scene_particles"))
		if not GraphicsSettingsManager.settings_changed.is_connected(_on_settings_changed):
			GraphicsSettingsManager.settings_changed.connect(_on_settings_changed)


func _on_settings_changed(settings: Dictionary) -> void:
	var enabled := bool(settings.get("scene_particles", true))
	if enabled == _last_enabled:
		return
	_apply(enabled)


func _apply(enabled: bool) -> void:
	_last_enabled = enabled
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	_gather_particles(root)
	for node in _cached_state.keys():
		var state: Dictionary = _cached_state[node]
		var n: Node = weakref(node).get_ref()
		if n == null or not is_instance_valid(n):
			continue
		if enabled:
			# 恢复（用快照，避免改到原始默认）
			if state.has("emitting"): n.set("emitting", state["emitting"])
			if state.has("visible"): n.visible = state["visible"]
			if state.has("freeze"): n.set("freeze", state["freeze"])
		else:
			# 关掉（粒子仍占节点，但不再模拟不再渲染）
			n.set("emitting", false)
			n.visible = false
			n.set("freeze", true)


func _gather_particles(root: Node) -> void:
	_cached_state.clear()
	if root == null:
		return
	_walk(root)


func _walk(n: Node) -> void:
	if (n is GPUParticles3D or n is CPUParticles3D) and _is_scene_particle(n):
		var inst_id: int = n.get_instance_id()
		_cached_state[n] = {
			"emitting": n.get("emitting"),
			"visible": n.visible,
			"freeze": n.get("freeze"),
		}
	for child in n.get_children():
		_walk(child)


func _is_scene_particle(n: Node) -> bool:
	# 检查自身或祖先是否有 metadata/asset_category == "scene_vfx"
	var cur: Node = n
	while cur != null:
		var cat = cur.get_meta("asset_category", "")
		if str(cat) == PARTICLE_GROUP_TAG:
			return true
		cur = cur.get_parent()
	return false