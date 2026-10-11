extends CanvasLayer
## 全局光圈过场遮罩：黑圈收拢（盖住当前画面 → 全黑）/ 黑圈展开（中心露出新画面）。
##
## 设计边界（与读取界面同一条纪律）：
##   - 只做视觉遮罩。不读、不写任何玩法状态、存档、输入模式与相机。
##   - 层级固定高于读取界面（128）与战局 HUD，保证任何界面之上都是它。
##   - 无头环境瞬时完成，绝不给验收脚本增加等待帧数。
##
## 几何：以 `hole_center`（归一化屏幕坐标）为圆心、`hole_radius`（以屏幕高为单位的
## 归一化半径）为界的"洞"。
##   收拢 = 洞从 HOLE_MAX 收到 CLOSED_RADIUS（黑从四边向中心合拢，最后全黑）
##   展开 = 洞从 CLOSED_RADIUS 放到 HOLE_MAX（黑从中心向四边退去，露出新画面）
## CLOSED_RADIUS 取负值，保证"合拢到底"时羽化带整体落在屏幕外 —— 中心不留灰点。

const LAYER := 240
## 归一化洞半径上限：16:9 下四角距离 = sqrt(1.7778² + 1) / 2 ≈ 1.019，
## 留约 13% 余量确保四角完全露出，避免边缘残留一圈黑。
const HOLE_MAX := 1.15
## 合拢终点（负值：羽化带被推到屏幕外，画面纯黑）。
const CLOSED_RADIUS := -0.06
const DEFAULT_CENTER := Vector2(0.5, 0.5)
## 收拢略快于展开：读感像"合上 — 打开"。
const CLOSE_SECONDS := 0.5
const OPEN_SECONDS := 0.55
const FEATHER := 0.03

const IRIS_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform vec2 hole_center = vec2(0.5, 0.5);
uniform float hole_radius = 1.15;
uniform float aspect = 1.7777778;
uniform float feather = 0.03;

void fragment() {
	vec2 p = UV - hole_center;
	p.x *= aspect;
	float d = length(p);
	// 洞内 alpha=0（透明），洞外 alpha=1（纯黑），边缘一条羽化带。
	float a = clamp((d - (hole_radius - feather)) / (2.0 * feather), 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

## 读取页与目标场景共用的公开契约；不参与玩法状态或场景切换。
## 新一轮读取由读取页直接赋值并重置状态，进度上报本身只允许单调推进。
var loading_destination_scene: String = ""
var loading_destination_name: String = ""
var loading_target_scene: String = ""
var loading_progress: float = 0.0
var loading_status: String = ""
var loading_scene_ready: bool = false
var loading_scene_failed: bool = false

var _mask: ColorRect
var _material: ShaderMaterial
var _radius := HOLE_MAX
var _tween: Tween


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply_radius(HOLE_MAX)


## 立即全黑（不播动画）：用于"先盖住、再切场景"的时刻。
func cover_now(center: Vector2 = DEFAULT_CENTER) -> void:
	_kill_tween()
	if _material != null:
		_material.set_shader_parameter("hole_center", center)
	_apply_radius(CLOSED_RADIUS)


## 立即完全透明（不播动画）：用于新场景已经自己铺好黑底、不需要遮罩的时刻。
func clear_now() -> void:
	_kill_tween()
	_apply_radius(HOLE_MAX)


func is_covered() -> bool:
	return _mask != null and _mask.visible and _radius <= CLOSED_RADIUS + 0.001


func is_loading_active() -> bool:
	return not loading_target_scene.is_empty()


## 优先按场景资源路径识别，也兼容以节点名或节点路径登记的目标。
func is_loading_scene(node: Node) -> bool:
	if not is_instance_valid(node) or not is_loading_active():
		return false
	if node.scene_file_path == loading_target_scene:
		return true
	if node.is_inside_tree() and str(node.get_path()) == loading_target_scene:
		return true
	return (
		str(node.name) == loading_target_scene
		or str(node.name) == loading_target_scene.get_file().get_basename()
	)


## 读取页可直接 set 重置进度；普通上报不能让进度倒退，失败也不自动补满。
func report_loading(progress: float, status: String) -> void:
	loading_progress = maxf(loading_progress, clampf(progress, 0.0, 1.0))
	loading_status = status


## 场景就绪并不等于读取页已交接完成，成功仅保证到达 0.96。
func complete_loading(failed: bool = false) -> void:
	loading_scene_ready = not failed
	loading_scene_failed = failed
	if not failed:
		loading_progress = maxf(loading_progress, 0.96)


## 只使用 Node 公开接口恢复处理；先交接，再清理，通知期间仍可读取目标信息。
func release_loading_scene(node: Node) -> void:
	if not is_instance_valid(node):
		return
	# 显式交接先恢复子树、最后启用根，避开 ENABLED 通知传播中的 process owner 竞态。
	if node.has_method("release_loading_scene"):
		node.call("release_loading_scene")
	elif node.process_mode != Node.PROCESS_MODE_INHERIT:
		node.process_mode = Node.PROCESS_MODE_INHERIT
	loading_target_scene = ""
	loading_progress = 0.0
	loading_status = ""
	loading_scene_ready = false
	loading_scene_failed = false
	loading_destination_scene = ""
	loading_destination_name = ""


## 黑圈收拢：从当前状态合到全黑。await 完成。
func iris_close(duration: float = CLOSE_SECONDS, center: Vector2 = DEFAULT_CENTER) -> void:
	await _animate_to(CLOSED_RADIUS, duration, center)


## 黑圈展开：从全黑开到完全透明。await 完成。
func iris_open(duration: float = OPEN_SECONDS, center: Vector2 = DEFAULT_CENTER) -> void:
	await _animate_to(HOLE_MAX, duration, center)


## 切场景之后的展开：等新场景渲染若干帧再开圈，避免"开到一半还是旧画面"。
## 本方法挂在 autoload 上，所以旧场景被 change_scene 销毁不会打断它。
## 开圈后保留读取契约，供读取页核对目标；仅在 release_loading_scene 交接后清理。
func open_after_scene(
	duration: float = OPEN_SECONDS,
	center: Vector2 = DEFAULT_CENTER,
	frames: int = 2
) -> void:
	# 无头环境不等待渲染帧，仍沿用原有半径更新路径。
	for _i in (0 if _skip_motion() else maxi(0, frames)):
		if get_tree() == null:
			return
		await get_tree().process_frame
	await _animate_to(HOLE_MAX, duration, center)


func _build() -> void:
	_mask = ColorRect.new()
	_mask.name = "IrisMask"
	_mask.color = Color(0.0, 0.0, 0.0, 1.0)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = IRIS_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("feather", FEATHER)
	_mask.material = _material
	add_child(_mask)
	_update_aspect()
	get_viewport().size_changed.connect(_update_aspect)


func _animate_to(target: float, duration: float, center: Vector2) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("hole_center", center)
	_mask.visible = true
	_kill_tween()
	if duration <= 0.0 or _skip_motion():
		_apply_radius(target)
		# 正常环境保留瞬时切换后的一帧等待；无头环境立即返回。
		if not _skip_motion() and get_tree() != null:
			await get_tree().process_frame
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_apply_radius, _radius, target, duration)
	await _tween.finished


func _apply_radius(value: float) -> void:
	_radius = clampf(value, CLOSED_RADIUS, HOLE_MAX)
	if _material != null:
		_material.set_shader_parameter("hole_radius", _radius)
	# 完全打开时连遮罩一起隐藏：省一次全屏混合，也杜绝边缘残留。
	if _mask != null:
		_mask.visible = _radius < HOLE_MAX - 0.01


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _update_aspect() -> void:
	if _material == null or get_viewport() == null:
		return
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	_material.set_shader_parameter("aspect", size.x / size.y)


func _skip_motion() -> bool:
	return DisplayServer.get_name() == "headless"
