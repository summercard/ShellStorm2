class_name ItemModelIcon3D
extends Control
## 将世界道具的同一 3D 模型投射为背包图标；配置后只渲染一次。
##
## 取景口径（2026-09-30 主人反馈「物品大于图标尺寸会被切、居中位置不对」后重写）：
## 图标**永不切边、永远居中**。取景不再按模型种类写死米数 + 写死位移，而是
##   ① 量出模型在取景空间里的投影包围盒（按种类可选只取其中一段 = 局部特写）；
##   ② 正交相机尺寸 = 该包围盒投影进框所需的最小尺寸 ÷ FIT_FILL_RATIO × 追加余量；
##   ③ 模型位移 = 把包围盒中心搬到相机视线轴上（正交投影 ⇒ 只需补横向与纵向）。
## 于是模型换尺寸、换造型、换到别的宽高比图标格，都不会再被裁掉或跑偏；
## 视口分辨率也跟着控件实际长宽比走，宽图标格不再把模型挤进一块正方形里。
##
## 投影包围盒的取法分两档（2026-09-30 第二轮修正）：
##   - 整盒取景（武器/道具）：走**真实顶点支撑区间**。局部外接盒的 8 个角点是凸包
##     顶点，但在斜视方向上常常没有几何落在角上，投影包围盒会偏胖且**不对称** ——
##     实测霰弹枪因此偏心 4.5px / 96px，机枪 3.5px、发射器 2.9px、钥匙 2.2px。
##     顶点支撑给出的是真实轮廓，尺寸与居中同时变准（图标也因此更饱满）。
##   - 局部特写（avatar 部位按世界 Y 分段）：夹取没法用支撑区间表达，沿用外接盒角点。

@export_range(64, 160, 8) var icon_resolution := 96
## 取景填充比：模型投影最多占取景框 88%，余下是安全边距（描边与抗锯齿不会蹭到边缘）。
const FIT_FILL_RATIO := 0.88
## 视口短边下限；控件被压到极小时不至于把渲染分辨率拉成几个像素。
const MIN_VIEWPORT_PIXELS := 24
## 支撑区间单网格的顶点采样上限。超大网格按等步长抽样；抽样误差由
## verify_item_model_icon_framing_visual 的渲染层判据（直接量已绘像素）兜住。
const SUPPORT_SAMPLE_LIMIT := 8192

## 局部支撑区间缓存：`网格实例ID | 量化后的局部方向` → (min, max)。
## 键里的局部方向由「相机轴 × 实例线性部分」算出，同一网格在同一旋转下只算一次；
## 图标是同一批模型反复投影，缓存把顶点遍历摊成一次性成本。
static var _support_cache: Dictionary = {}


var _item_data: Dictionary = {}
var _viewport: SubViewport
var _preview_rect: TextureRect
var _camera: Camera3D
var _model: Node3D
var _configured := false
var _camera_size_multiplier := 1.0
var _rebuild_count := 0
var _custom_model_factory := Callable()
var _custom_model_kind := ""
## 最近一次取景实测（世界空间）。供 get_snapshot() 与验收读取，不参与渲染。
var _model_bounds := AABB()
var _projected_half_extents := Vector2.ZERO
var _center_error_pixels := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_studio()
	resized.connect(_on_resized)
	_sync_viewport_resolution()
	if _configured:
		_rebuild_model()


func configure(item: Dictionary) -> void:
	_item_data = item.duplicate(true)
	_custom_model_factory = Callable()
	_custom_model_kind = ""
	_configured = true
	if is_node_ready():
		_rebuild_model()


func configure_custom_model(factory: Callable, model_kind: String) -> void:
	_item_data.clear()
	_custom_model_factory = factory
	_custom_model_kind = model_kind
	_configured = factory.is_valid()
	if is_node_ready():
		_rebuild_model()


## 追加取景余量：1.0 = 默认（模型占取景框 88%），2.0 = 四周多留一倍空白。
## **只接受 ≥1.0** —— 小于 1 会把模型放大到出框，与「图标永不切边」的口径冲突，
## 故在此封口（调用方传小数不会再静默产生裁切）；要整体放大请改 FIT_FILL_RATIO。
func set_camera_size_multiplier(multiplier: float) -> void:
	_camera_size_multiplier = clampf(multiplier, 1.0, 2.0)
	if _camera != null and _model != null and is_instance_valid(_model):
		_fit_frame_to_model()
		_request_render()


func clear_model() -> void:
	_item_data.clear()
	_custom_model_factory = Callable()
	_custom_model_kind = ""
	_configured = false
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_model_bounds = AABB()
	_projected_half_extents = Vector2.ZERO
	_center_error_pixels = Vector2.ZERO
	visible = false


func get_snapshot() -> Dictionary:
	return {
		"item_id": str(_item_data.get("id", "")),
		"model_kind": _resolved_model_kind(),
		"mesh_count": ItemModelFactory3D.count_mesh_instances(_model) if _model != null else 0,
		"viewport_size": _viewport.size if _viewport != null else Vector2i.ZERO,
		"camera_size": _camera.size if _camera != null else 0.0,
		"camera_size_multiplier": _camera_size_multiplier,
		"rebuild_count": _rebuild_count,
		"update_once": _viewport != null and _viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"uses_world_model_factory": true,
		# 取景实测：投影是否出框（fit_ratio ≤ 1 = 完整可见）、中心偏差几像素。
		"model_bounds_min": _model_bounds.position,
		"model_bounds_size": _model_bounds.size,
		"projected_half_extents": _projected_half_extents,
		"frame_half_extents": _frame_half_extents(),
		"fit_ratio": _fit_ratio(),
		"center_error_pixels": _center_error_pixels,
		"fit_fill_ratio": FIT_FILL_RATIO,
	}


func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ItemPreviewViewport"
	_viewport.size = Vector2i(icon_resolution, icon_resolution)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_preview_rect = TextureRect.new()
	_preview_rect.name = "ProjectedTexture"
	_preview_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_rect.texture = _viewport.get_texture()
	add_child(_preview_rect)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.65
	_camera.position = Vector3(3.2, 2.65, 4.1)
	_camera.look_at_from_position(_camera.position, Vector3(0, 0.10, 0), Vector3.UP)
	_camera.current = true
	_viewport.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	key.light_color = Color(0.90, 0.96, 1.0)
	key.light_energy = 2.2
	key.shadow_enabled = false
	_viewport.add_child(key)


func _rebuild_model() -> void:
	if _viewport == null:
		return
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	if _item_data.is_empty() and not _custom_model_factory.is_valid():
		visible = false
		return
	_rebuild_count += 1
	if _custom_model_factory.is_valid():
		_model = _custom_model_factory.call() as Node3D
	else:
		_model = ItemModelFactory3D.create_model(_item_data, _item_tint(_item_data))
	if _model == null:
		visible = false
		return
	_model.name = "ProjectedItemModel"
	var kind := _resolved_model_kind()
	_model.rotation_degrees = Vector3(0, 180, 0) if kind.begins_with("avatar_") else Vector3(-8, 18, 0)
	_viewport.add_child(_model)
	if kind.begins_with("avatar_"):
		_model.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_strip_preview_runtime_nodes(_model)
	_sync_viewport_resolution()
	_fit_frame_to_model()
	visible = true
	_request_render()


func _strip_preview_runtime_nodes(root: Node) -> void:
	# 图标只需要最终网格；武器装配树与手位/挂点 Marker 属于世界交互契约，
	# 放进单帧预览只会增加常驻节点。模型资产本身仍与世界表现共源。
	for child in root.get_children():
		if child is Marker3D or child.name == "PreviewAssemblyTree":
			root.remove_child(child)
			child.queue_free()
			continue
		_strip_preview_runtime_nodes(child)


# --- 视口分辨率：跟随控件长宽比 -------------------------------------------


func _on_resized() -> void:
	if not _sync_viewport_resolution():
		return
	if _model != null and is_instance_valid(_model):
		_fit_frame_to_model()
		_request_render()


## 视口分辨率按控件实际长宽比取：宽图标格拿宽视口，模型才用得上横向空间，
## 不会出现「正方形视口塞进宽格子、左右各空一条」这种看着没居中的假象。
func _sync_viewport_resolution() -> bool:
	if _viewport == null:
		return false
	var aspect := _control_aspect()
	var target := Vector2i(icon_resolution, icon_resolution)
	if aspect >= 1.0:
		target.y = maxi(MIN_VIEWPORT_PIXELS, int(round(float(icon_resolution) / aspect)))
	else:
		target.x = maxi(MIN_VIEWPORT_PIXELS, int(round(float(icon_resolution) * aspect)))
	if _viewport.size == target:
		return false
	_viewport.size = target
	return true


func _control_aspect() -> float:
	var rect := _control_pixel_size()
	return rect.x / rect.y if rect.y > 0.0 else 1.0


func _viewport_aspect() -> float:
	if _viewport == null or _viewport.size.y <= 0:
		return 1.0
	return float(_viewport.size.x) / float(_viewport.size.y)


## 布局未跑过时 size 还是 0，退到 custom_minimum_size；再不行才用正方形基准。
func _control_pixel_size() -> Vector2:
	var rect := size
	if rect.x < 1.0 or rect.y < 1.0:
		rect = custom_minimum_size
	if rect.x < 1.0 or rect.y < 1.0:
		rect = Vector2(icon_resolution, icon_resolution)
	return rect


# --- 取景：投影几何 → 定相机 → 居中 ---------------------------------------


## 按模型实际投影定相机尺寸，并把投影中心搬到取景框正中央。
##
## **不能先把所有网格并成一个世界 AABB 再投影** —— 斜放的细长件（巨剑、斧、球棒）
## 其 AABB 是个大盒子，再投影会膨胀到实际轮廓的 5 倍以上（2026-09-30 实测：
## 巨剑只填满图标短边的 13%）。这里逐个网格实例单独投影后取并集：
## 细长件自然收敛成它自己的斜条。整盒取景走真实顶点支撑（见文件头两档说明）。
func _fit_frame_to_model() -> void:
	if _camera == null or _model == null or not is_instance_valid(_model):
		return
	var region := _framing_region(_resolved_model_kind())
	var measured := _measure_projection(region)
	if measured.is_empty():
		return
	var right := _camera.global_transform.basis.x.normalized()
	var up := _camera.global_transform.basis.y.normalized()
	var low: Vector2 = measured["low"]
	var high: Vector2 = measured["high"]
	var span := high - low
	var needed := maxf(span.y, span.x / _viewport_aspect())
	_camera.size = needed / FIT_FILL_RATIO * _camera_size_multiplier
	# 居中：把投影中心移到视线轴上（正交投影 ⇒ 只补横向与纵向，深度不影响取景）。
	var center := (low + high) * 0.5
	_model.position -= right * center.x + up * center.y
	# 位移后再量一次：残留偏差是「居中真的生效了」的可失败证据，不是自我复述。
	_model_bounds = _clip_region(_measure_world_bounds(), region)
	var after := _measure_projection(region)
	if after.is_empty():
		return
	_projected_half_extents = ((after["high"] as Vector2) - (after["low"] as Vector2)) * 0.5
	var pixels_per_unit := float(_viewport.size.y) / maxf(_camera.size, 0.0001)
	_center_error_pixels = ((after["low"] as Vector2) + (after["high"] as Vector2)) * 0.5 * pixels_per_unit


## 取景区域：以模型世界外接盒的归一化坐标给出（x/y 从盒的最小角起算，1 = 整盒）。
## 默认整盒（武器与道具都按完整轮廓取景）；avatar_* 沿用「哪个部位看哪一段」的既有
## 取景意图，但不再写死米数与绝对偏移 —— 模型尺寸变了也不会切边或跑偏。
func _framing_region(kind: String) -> Rect2:
	match kind:
		"avatar_head", "avatar_hat", "avatar_glasses":
			return Rect2(0.0, 0.62, 1.0, 0.38)
		"avatar_body":
			return Rect2(0.0, 0.12, 1.0, 0.72)
		"avatar_hand":
			return Rect2(0.0, 0.30, 1.0, 0.42)
		"avatar_feet":
			return Rect2(0.0, 0.0, 1.0, 0.24)
		_:
			return Rect2(0.0, 0.0, 1.0, 1.0)


## 取景区域在取景框局部坐标下的投影包围盒（世界单位，原点 = 相机位置）。
## 顺带把取景段的世界 Y 范围也回传，供快照与探针核对。
func _measure_projection(region: Rect2) -> Dictionary:
	var world := _measure_world_bounds()
	if world.size == Vector3.ZERO:
		return {}
	var band_min := world.position.y + world.size.y * region.position.y
	var band_max := band_min + world.size.y * region.size.y
	var right := _camera.global_transform.basis.x.normalized()
	var up := _camera.global_transform.basis.y.normalized()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	# 整盒取景用真实顶点支撑（准）；局部特写用外接盒角点 + 世界 Y 夹取（挡不住夹取的是支撑区间）。
	var full_box := is_equal_approx(region.position.y, 0.0) and is_equal_approx(region.size.y, 1.0)
	var found := false
	var low := Vector2.ZERO
	var high := Vector2.ZERO
	for instance in meshes:
		if instance.mesh == null:
			continue
		var projected := (
			_project_by_support(instance, right, up)
			if full_box
			else _project_by_corners(instance, right, up, band_min, band_max)
		)
		if projected.is_empty():
			continue
		var instance_low: Vector2 = projected["low"]
		var instance_high: Vector2 = projected["high"]
		if not found:
			low = instance_low
			high = instance_high
			found = true
			continue
		low = low.min(instance_low)
		high = high.max(instance_high)
	if not found:
		return {}
	return {"low": low, "high": high, "world_y": Vector2(band_min, band_max)}


## 单网格实例的投影包围盒：逐网格取**自身局部紧盒**的 8 个角点，变换到取景空间后
## 直接投影取并集。细长件（巨剑/斧/球棒）不能先把所有网格并成一个世界 AABB 再投影 ——
## 那个大盒子投影会膨胀到实际轮廓的 5 倍以上（2026-09-30 实测：巨剑只填满图标短边 13%）。
## 取景段（局部特写）之外的点夹回段内：跨段的实例按夹后位置计入。
func _project_by_corners(
	instance: MeshInstance3D, right: Vector3, up: Vector3, band_min: float, band_max: float
) -> Dictionary:
	var local := instance.mesh.get_aabb()
	var xform := instance.global_transform
	var camera_origin := _camera.global_position
	var low := Vector2.ZERO
	var high := Vector2.ZERO
	for corner in 8:
		var point := xform * _box_corner(local, corner)
		point.y = clampf(point.y, band_min, band_max)
		var delta := point - camera_origin
		var projected := Vector2(right.dot(delta), up.dot(delta))
		if corner == 0:
			low = projected
			high = projected
			continue
		low = low.min(projected)
		high = high.max(projected)
	return {"low": low, "high": high}


## 单网格实例的投影包围盒：用**真实顶点**沿两条相机轴的支撑区间（min/max）。
## 这是精确轮廓，不受外接盒空角影响 —— 外接盒角点法在斜视方向会同时把尺寸放大、
## 把中心推偏（霰弹枪实测偏心 4.5px / 96px）。凸包以外的几何不影响极值，故等价于凸包投影。
func _project_by_support(instance: MeshInstance3D, right: Vector3, up: Vector3) -> Dictionary:
	var xform := instance.global_transform
	var camera_origin := _camera.global_position
	var low := Vector2.ZERO
	var high := Vector2.ZERO
	for axis_index in 2:
		var world_axis: Vector3 = right if axis_index == 0 else up
		# w·(M·p + t) = (Mᵀw)·p + w·t —— 把相机轴搬到网格局部空间，即可直接用顶点支撑。
		var dir_local := Vector3(
			xform.basis.x.dot(world_axis),
			xform.basis.y.dot(world_axis),
			xform.basis.z.dot(world_axis)
		)
		var support := _support_range(instance.mesh, dir_local)
		if support.x > support.y:
			return {}
		# 投影原点必须是相机的（与 _project_by_corners 的 `point - camera_origin` 同口径）。
		# 这个常量在 span 里会抵消，但**在 center 里不抵消**：漏掉它就是整幅图标偏心。
		var base := world_axis.dot(xform.origin - camera_origin)
		if axis_index == 0:
			low.x = base + support.x
			high.x = base + support.y
		else:
			low.y = base + support.x
			high.y = base + support.y
	return {"low": low, "high": high}


## 网格真实顶点沿给定局部方向的支撑区间 `(min, max)`；无顶点时返回 `(INF, -INF)`。
## 结果按「网格实例 ID + 量化局部方向」缓存：相机朝向与模型朝向在图标里都是固定常量，
## 同一网格同一朝向只会遍历一次顶点。
func _support_range(mesh: Mesh, dir_local: Vector3) -> Vector2:
	var key := "%d|%.4f|%.4f|%.4f" % [
		mesh.get_instance_id(), dir_local.x, dir_local.y, dir_local.z
	]
	var cached: Variant = _support_cache.get(key)
	if cached != null:
		return cached
	var low := INF
	var high := -INF
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var raw: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (raw is PackedVector3Array):
			continue
		var vertices: PackedVector3Array = raw
		var count := vertices.size()
		if count == 0:
			continue
		var stride := maxi(1, int(ceil(float(count) / float(SUPPORT_SAMPLE_LIMIT))))
		var index := 0
		while index < count:
			var value := dir_local.dot(vertices[index])
			low = minf(low, value)
			high = maxf(high, value)
			index += stride
	var result := Vector2(low, high)
	if low > high:
		result = Vector2(INF, -INF)
	_support_cache[key] = result
	return result



## 整个模型的世界 AABB（未按取景段裁剪）—— 取景段的世界 Y 范围由它定。
func _measure_world_bounds() -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	var found := false
	var box := AABB()
	for instance in meshes:
		if instance.mesh == null:
			continue
		var node_box: AABB = instance.global_transform * instance.mesh.get_aabb()
		box = node_box if not found else box.merge(node_box)
		found = true
	return box if found else AABB()


## 按取景段裁出世界 AABB（快照读数用；不参与投影计算）。
func _clip_region(box: AABB, region: Rect2) -> AABB:
	if box.size == Vector3.ZERO:
		return box
	return AABB(
		box.position + Vector3(box.size.x * region.position.x, box.size.y * region.position.y, 0.0),
		Vector3(box.size.x * region.size.x, box.size.y * region.size.y, box.size.z)
	)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


## 局部盒的第 index 个角点（index 的三位二进制分别表示 x/y/z 取 max）。
func _box_corner(box: AABB, index: int) -> Vector3:
	return box.position + Vector3(
		box.size.x if (index & 1) != 0 else 0.0,
		box.size.y if (index & 2) != 0 else 0.0,
		box.size.z if (index & 4) != 0 else 0.0
	)


func _frame_half_extents() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return Vector2(_camera.size * _viewport_aspect() * 0.5, _camera.size * 0.5)


## 投影占取景框的比例（取两轴较大者）：≤1.0 表示完整可见。
func _fit_ratio() -> float:
	var frame := _frame_half_extents()
	if frame.x <= 0.0 or frame.y <= 0.0:
		return 0.0
	return maxf(_projected_half_extents.x / frame.x, _projected_half_extents.y / frame.y)


func _request_render() -> void:
	if _viewport != null and _model != null and is_instance_valid(_model):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _resolved_model_kind() -> String:
	if not _custom_model_kind.is_empty():
		return _custom_model_kind
	return ItemModelFactory3D.get_model_kind(_item_data) if not _item_data.is_empty() else ""


func _item_tint(item: Dictionary) -> Color:
	match str(item.get("rarity", "common")):
		"legendary":
			return Color(1.0, 0.54, 0.12)
		"epic":
			return Color(0.72, 0.38, 1.0)
		"rare":
			return Color(0.28, 0.68, 1.0)
		"uncommon":
			return Color(0.34, 0.92, 0.56)
		_:
			return Color(0.72, 0.80, 0.84)
