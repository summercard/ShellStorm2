class_name PlantSway3D
extends Node3D
## 叶面风摆：给植物 prefab 里所有色盘 surface 套上共享风摆材质。
##
## 只做三件事：
##   1. 遍历子树，把「色盘角色」surface 换成风摆 ShaderMaterial；
##   2. 按 (材质角色, 固定端高度, 摆动区间, 向上/向下) 分档缓存材质，同档全部实例共用；
##   3. 只有一个实例推进时钟，每帧给各档材质各写一次 wind_time —— 整片天台 ≈ 10 次 uniform 写入。
##
## 为什么金属骨架也要摆：植物是「金属枝干 + 哑光叶片」两张面，
## 只摆叶片会让叶子脱离枝干。两张面各自保留自己的 albedo/metallic/roughness，表现不变。
##
## 不碰：节点 transform（基地植物顶点是世界坐标烘焙的，旋转会绕世界原点甩飞）、
## 碰撞、玩法光、`WastelandLight3D`、存档。纯表现层。
##
## 时钟走 _process 累加而不是 shader 的 TIME：暂停时 TIME 仍推进，会让场景在
## 暂停菜单背后继续摆，与 VfxCloudSea3D 的既有口径不一致。

const WIND_SHADER := preload("res://src/world3d/foliage_wind.gdshader")
## 色盘四个角色前缀（见 tools/asset_pipeline/scene_facility_shared_palette_post_import.gd）。
const PALETTE_ROLE_PREFIXES := ["01_精工金属", "02_细腻哑光", "03_清漆反光", "04_柔和自发光"]

## 冠部最大位移（米）。业主两轮反馈：
##   2026-10-17「轻微晃动」→ 0.035（1.62m 冠高上 2.2°，要盯着看才读得出）
##   2026-10-18「幅度再大一些，不够明显」→ 0.120（约 4.2°，冠顶峰-峰 24cm）
## 仍是风里晃的姿态，不是被吹折：盆口处权重为 0，只有冠部走满这个量。
const SWAY_AMPLITUDE := 0.120
## 贴墙藤蔓：横向主导。它离墙只有 0.2~0.4m 且只有薄薄一层，
## 但横向不受墙厚限制，按冠高比例给到 0.090（2.0m 冠高约 2.6°）。
const SWAY_AMPLITUDE_CLIMBING := 0.090

## 固定端高度（本地 y，米）。**必须按 prefab 指定**，不能默认 0：
## 花盆与叶片共用同一个「青绿大面」surface，从 0 起算会让整只花盆跟着摆。
##   实测（原始 GLB 顶点 5cm 分箱）：
##     plant_large  盆体 0~1.10，盆顶金属环 1.15，枝叶 1.15~2.77
##     plant_small  盆体 0~0.65，枝叶 0.85~1.50
##     flowerbox    箱体 0~1.10，花叶 1.15~2.13（金属绑带 0.08~1.10 也在箱体段）
##     ivy          顶部固定向下垂，固定端在 3.80
##     parapet_ivy  顶部固定向下垂，固定端在 2.01
@export var foliage_base_y := 0.0

## true = 顶部固定向下垂（藤蔓）；false = 根部固定向上长（盆栽/花箱）。
@export var sway_from_top := false

## true = 贴墙件（藤蔓）：横向沿墙面水平摆为主 + 离墙扑动为辅。
## 2026-10-18 修正：初版只做本地 z 的离墙扑动，正面视角几乎看不出移动。
@export var wall_mounted := false

## 分档材质缓存。key = "角色|固定端|区间|方向"，同档全部实例共用一份。
static var _material_by_key: Dictionary = {}
static var _materials: Array[ShaderMaterial] = []
## 全部存活实例（弱引用）。用来在时钟源离场时把时钟移交给下一个 —— 否则
## 「加载分帧里第一个实例被替换」会让整片天台的植物停在最后一帧。
static var _instances: Array[WeakRef] = []
static var _ticker: WeakRef
static var _clock := 0.0


func _ready() -> void:
	_apply_sway()
	_instances.append(weakref(self))
	_become_ticker_if_needed()


## 把色盘 surface 换成共享材质。幂等：已换过的 surface 直接跳过。
func _apply_sway() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var current := mesh_instance.get_active_material(surface)
			if current is ShaderMaterial:
				continue
			var original := current as BaseMaterial3D
			if original == null:
				continue
			if not _is_palette_role(original.resource_name):
				continue
			var material := _material_for(original, mesh_instance.mesh, surface)
			if material != null:
				mesh_instance.set_surface_override_material(surface, material)


static func _is_palette_role(text: StringName) -> bool:
	var name := String(text)
	for prefix in PALETTE_ROLE_PREFIXES:
		if name.begins_with(prefix):
			return true
	return false


## 摆动区间：从固定端到该 surface 的最远端。
## 用 surface 自身的顶点极值而不是全局 AABB，藤蔓的枝条面与叶片面各有各的区间。
static func _surface_extent(mesh: Mesh, surface: int, from_top: bool) -> float:
	var extreme := INF if from_top else -INF
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		extreme = minf(extreme, vertex.y) if from_top else maxf(extreme, vertex.y)
	return extreme


## 同档共用一份材质：色盘纹理、albedo、metallic/roughness 全部从原材质读，
## 保证换 shader 之后颜色与光照响应逐像素一致。
func _material_for(original: BaseMaterial3D, mesh: Mesh, surface: int) -> ShaderMaterial:
	var far_y := _surface_extent(mesh, surface, sway_from_top)
	if far_y == INF or far_y == -INF:
		return null
	# 向上长：区间 = [固定端, 最高点]；向下垂：区间 = [最低点, 固定端]。
	var low := foliage_base_y if not sway_from_top else far_y
	var high := far_y if not sway_from_top else foliage_base_y
	var span := maxf(high - low, 0.1)
	var amplitude := SWAY_AMPLITUDE_CLIMBING if sway_from_top else SWAY_AMPLITUDE
	var key := "%s|%.2f|%.2f|%s|%s" % [
		original.resource_name, low, span, str(sway_from_top), str(wall_mounted)
	]
	var cached: ShaderMaterial = _material_by_key.get(key)
	if cached != null:
		return cached
	var material := ShaderMaterial.new()
	material.resource_name = "风摆_%s" % key
	material.shader = WIND_SHADER
	# 色盘采样器带 source_color 做 sRGB 解码，这里必须传 albedo_color 原值 ——
	# 再手动转 linear 会多转一次，整株偏暗约 12%（实测 108 vs 123）。
	material.set_shader_parameter("palette", original.albedo_texture)
	material.set_shader_parameter("albedo_tint", original.albedo_color)
	material.set_shader_parameter("metallic_value", original.metallic)
	material.set_shader_parameter("roughness_value", original.roughness)
	material.set_shader_parameter("specular_value", original.metallic_specular)
	material.set_shader_parameter("sway_amplitude", amplitude)
	material.set_shader_parameter("foliage_base_y", low)
	material.set_shader_parameter("foliage_span", span)
	material.set_shader_parameter("sway_from_top", sway_from_top)
	material.set_shader_parameter("wall_mounted", wall_mounted)
	material.set_shader_parameter("wind_time", _clock)
	_material_by_key[key] = material
	_materials.append(material)
	return material


## 只有一个实例当时钟源。已有存活时钟源时本实例立即停止 _process。
func _become_ticker_if_needed() -> void:
	var current: Object = null
	if _ticker != null:
		current = _ticker.get_ref()
	if current != null and is_instance_valid(current) and current != self:
		set_process(false)
		return
	_ticker = weakref(self)
	set_process(true)


func _process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	for material in _materials:
		if material != null:
			material.set_shader_parameter("wind_time", _clock)


## 时钟源离场时把时钟交给下一个存活实例。
## 不这么做的话：本次是首个实例当时钟源，若它被单独替换（加载分帧/换 prefab），
## 其余实例早就在 _ready 里 set_process(false) 了，整片天台会停在最后一帧。
func _exit_tree() -> void:
	for index in range(_instances.size() - 1, -1, -1):
		var reference := _instances[index]
		if reference == null or reference.get_ref() == null or reference.get_ref() == self:
			_instances.remove_at(index)
	var is_ticker: bool = _ticker != null and _ticker.get_ref() == self
	if not is_ticker:
		return
	_ticker = null
	for reference in _instances:
		var candidate := reference.get_ref() as PlantSway3D
		if candidate == null or not is_instance_valid(candidate) or not candidate.is_inside_tree():
			continue
		_ticker = reference
		candidate.set_process(true)
		return
