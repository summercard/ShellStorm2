extends Node
## 系统鼠标指针的可见性策略。核心决定：**玩家在直接操控 3D 角色时隐藏系统箭头**，
## 菜单 / 暂停 / 非玩法场景恢复显示。
##
## 为什么必须是独立 autoload 且 `PROCESS_MODE_ALWAYS`：暂停菜单走 `Global.acquire_pause`
## 把 `tree.paused` 置 true，挂在玩法场景上的 `_process` 会停摆 ⇒ 刷新逻辑若放在那里，
## 菜单一开箭头就再也回不来（表现为「看得见菜单、点不到按钮」）。autoload 不受 paused 影响。
##
## 世界里的瞄准指示器由 `Player3D` 的 `AimCursor` 承担（唯一指示器，见该节点注释）。
##
## 三个入口由玩法场景申报：
##   hold(self)             —— 玩家已能直接操控（进玩法场景 / 开场页交回输入）
##   release(self)          —— 离开玩法场景
##   set_modal(self, open)  —— 本场景内是否有需要真实指针的菜单打开

## 玩法期间的指针模式：隐藏箭头，同时把指针限制在窗口内 ——
## 只用 `MOUSE_MODE_HIDDEN` 时指针会被推出窗口，瞄准随即失去输入。
const GAMEPLAY_MOUSE_MODE := Input.MOUSE_MODE_CONFINED_HIDDEN
## 菜单 / 非玩法场景：箭头自由移动。
const NON_GAMEPLAY_MOUSE_MODE := Input.MOUSE_MODE_VISIBLE

var _gameplay_owner: Object = null
var _scene_modals: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply()


func _process(_delta: float) -> void:
	_prune_stale_owners()
	_apply()


## 申报「玩家正在 3D 世界里直接操控」。owner 用场景根节点，释放时靠同一引用比对。
func hold(owner: Object) -> void:
	_gameplay_owner = owner
	_apply()


## 撤回申报。只在 owner 仍是当前申报者时生效 —— 场景切换时新旧场景的
## `_ready` / `_exit_tree` 顺序不保证，不比对就会让旧场景把新场景的申报顶掉。
func release(owner: Object) -> void:
	if _gameplay_owner == owner:
		_gameplay_owner = null
	_scene_modals.erase(owner)
	_apply()


## 玩法场景每帧上报「我这边有菜单 / 弹窗需要真实指针」。
func set_modal(owner: Object, open: bool) -> void:
	if _scene_modals.has(owner) and bool(_scene_modals[owner]) == open:
		return
	_scene_modals[owner] = open
	_apply()


func is_gameplay_active() -> bool:
	return _gameplay_owner != null and is_instance_valid(_gameplay_owner)


## 当前是否应当显示系统箭头。抽成纯函数是为了让探针能在无头环境下断言 ——
## 无头没有鼠标设备，`_apply` 会整体早退，探不到真实结果。
func wants_visible() -> bool:
	return not is_gameplay_active() or _paused_or_modal()


func _paused_or_modal() -> bool:
	if Global != null and Global.is_paused:
		return true
	for key in _scene_modals:
		if bool(_scene_modals[key]):
			return true
	return false


func _prune_stale_owners() -> void:
	if _scene_modals.is_empty():
		return
	var stale: Array = []
	for key in _scene_modals:
		if not is_instance_valid(key):
			stale.append(key)
	for key in stale:
		_scene_modals.erase(key)


func _apply() -> void:
	# headless（验收套件）没有鼠标设备：设置会刷无关警告并污染验收日志。
	if not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		return
	var desired := NON_GAMEPLAY_MOUSE_MODE if wants_visible() else GAMEPLAY_MOUSE_MODE
	if Input.mouse_mode == desired:
		return
	Input.mouse_mode = desired
