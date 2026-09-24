extends Node3D
## Turns the Blender-authored palette emission into readable HDR glow.
## Strong fixtures also receive small environment-only light pools. This remains
## presentation-only and never participates in PlayerVision3D visibility.

const PALETTE := preload("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
const SOFT_EMISSION_TARGET := 2.35
const STARTUP_BATCH_COUNT := 18
const STARTUP_FLICKER_BATCHES := [2, 8, 14]
const STARTUP_DOUBLE_FLICKER_BATCH := 8
## 手摆美术灯（Art 下的原生 OmniLight3D）在开关启动序列里的亮相延迟（秒）。
## 业主 2026-09-24 指定 ≈2 秒：开关点开后先由设施自发光按批铺开，
## 主光级的手摆灯在这一刻一并补上 —— 不让它抢在第一批「啪」地先亮。
const AUTHORED_ART_LIGHT_DELAY_SECONDS := 2.0
const FIXTURE_PROFILES := [
	{"name": "BASE_CAMP霓虹标识", "offset": Vector3(0, 0, 0.32), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "二楼GOOD_VIBES霓虹", "offset": Vector3(0, 0, 0.32), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "楼梯墙STAY_CURIOUS标识", "offset": Vector3(0.32, 0, 0), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "33_暖橙床头灯_资产包", "offset": Vector3.ZERO, "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "梯下壁灯生活点缀", "offset": Vector3(0, 0, 0.20), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "84_东面圆形工业吊灯_资产包", "offset": Vector3(0, -0.35, 0), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "61_仓库防爆吊灯组_资产包", "offset": Vector3(0, -0.35, 0), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "62_主通道应急灯组_资产包", "offset": Vector3.ZERO, "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "50_二楼分层照明支持_资产包", "offset": Vector3.ZERO, "cool": false, "spill": false, "target": 2.35},
]

var _enhanced_surfaces := 0
var _strong_fixtures := 0
var _spill_lights := 0
var _processed_surfaces := {}
var _controlled_emission_materials: Array[BaseMaterial3D] = []
var _emission_energy_by_material := {}
var _controlled_spill_lights: Array[OmniLight3D] = []
## 手摆美术灯子集（保持收集顺序）。它们不跟补光一起分批，而是统一延后
## AUTHORED_ART_LIGHT_DELAY_SECONDS 一次点亮。
var _authored_art_lights: Array[OmniLight3D] = []
## 启动延迟的世代号。玩家在延迟途中关灯/重开时自增，作废在途的延迟协程，
## 避免「已经关灯了，延迟到点又把灯补亮」。
var _startup_generation := 0
## 美术师在本场景里手工摆放的原生 OmniLight3D 的编辑期 visible。它表示「这盏灯是否
## 参与墙面开关」，不表示「此刻亮不亮」—— 后者运行时一律由开关状态决定。
var _authored_art_light_visible := {}
var _presentation_lighting_enabled := true
var _presentation_starting := false


func _ready() -> void:
	# 必须先于 _enhance_fixture 收集：后者会往灯具下挂代码生成的 PaletteLightSpill，
	# 那些补光由 _add_light_spill 自行登记，不能被当成手摆美术灯收两次。
	_collect_authored_art_lights()
	var palette_image := PALETTE.get_image()
	if palette_image.is_compressed():
		palette_image.decompress()
	for profile in FIXTURE_PROFILES:
		var fixture := find_child(str(profile.name), true, false) as Node3D
		if fixture == null:
			push_error("BASE_GLOW_FIXTURE_MISSING: %s" % profile.name)
			continue
		_strong_fixtures += 1
		_enhance_fixture(fixture, palette_image, profile)
	# Screens, status strips and utility emitters share the same HDR target. Their
	# authored palette cells stay unchanged and they do not create extra lights.
	for node in find_children("*", "MeshInstance3D", true, false):
		_enhance_mesh(node as MeshInstance3D, palette_image, SOFT_EMISSION_TARGET, false)


## 把美术师在本场景（Art 节点）里手工摆放的原生 OmniLight3D 纳入墙面开关控制。
##
## 规则只有一条、不需要额外声明：**Art 下非代码生成的原生 OmniLight3D 全部跟随开关**。
## 每盏灯自己的 `visible` 决定「这盏灯是否参与」（编辑期作者意图，运行时被本函数记住），
## 开关（RoomLightSwitch3D → set_presentation_lighting_enabled）决定「此刻亮不亮」。
## 于是「把 visible 打开但不接开关」这种半生效状态不再存在 —— 业主 2026-09-24 就是因为
## 手摆的「中央冷色主灯」没进这套链路，改了色、开了灯，关开关时它却一直亮着。
##
## 用原生灯而不是换成 WastelandLight3D，是为了不把它注册进玩法光照判定
## （EnemyIllumination3D 只认 WastelandLight3D），保持「表现层不参与玩法」这条口径。
func _collect_authored_art_lights() -> void:
	for node in find_children("*", "OmniLight3D", true, false):
		var art_light := node as OmniLight3D
		if art_light == null:
			continue
		_authored_art_light_visible[art_light.get_instance_id()] = art_light.visible
		_authored_art_lights.append(art_light)
		_controlled_spill_lights.append(art_light)
		art_light.visible = art_light.visible and _presentation_lighting_enabled


## 手摆美术灯用记下的编辑期 visible 做与运算；代码生成的补光没有登记，默认参与。
func _apply_spill_visibility(spill_light: OmniLight3D, wanted: bool) -> void:
	if spill_light == null or not is_instance_valid(spill_light):
		return
	spill_light.visible = wanted and bool(
		_authored_art_light_visible.get(spill_light.get_instance_id(), true)
	)


func get_presentation_snapshot() -> Dictionary:
	return {
		"strong_fixtures": _strong_fixtures,
		"enhanced_surfaces": _enhanced_surfaces,
		"spill_lights": _spill_lights,
		"authored_art_lights": _authored_art_lights.size(),
		"authored_art_light_delay_seconds": AUTHORED_ART_LIGHT_DELAY_SECONDS,
		"controlled_emission_materials": _controlled_emission_materials.size(),
		"presentation_lighting_enabled": _presentation_lighting_enabled,
		"presentation_starting": _presentation_starting,
	}


## 基地墙边开关调用此方法。开关是唯一状态源；这里仅同步美术表现，
## 保留每个材质原有的色彩和HDR能量，恢复时不重新计算也不改写资产。
func set_presentation_lighting_enabled(enabled: bool) -> void:
	if not enabled:
		# 作废在途的手摆灯延迟：已经关灯了，延迟到点不能再把灯补亮。
		_startup_generation += 1
	_presentation_starting = false
	_presentation_lighting_enabled = enabled
	for material in _controlled_emission_materials:
		if material == null or not is_instance_valid(material):
			continue
		var restored_energy := float(
			_emission_energy_by_material.get(
				material.get_instance_id(), material.emission_energy_multiplier
			)
		)
		material.emission_energy_multiplier = restored_energy if enabled else 0.0
	for spill_light in _controlled_spill_lights:
		_apply_spill_visibility(spill_light, enabled)


## 约五秒的基地美术灯启动：按稳定批次依次恢复灯具，三个批次会短暂
## 闪烁。RoomLightSwitch3D 会在第4.5秒并行点亮中央玩法顶灯。
## 手摆美术灯不参与分批，统一延后 AUTHORED_ART_LIGHT_DELAY_SECONDS 亮相。
func play_turn_on_sequence(duration_seconds := 4.2) -> void:
	set_presentation_lighting_enabled(false)
	if _controlled_emission_materials.is_empty():
		_presentation_lighting_enabled = true
		return
	_presentation_starting = true
	# 与下面的分批序列并行推进；世代号在关灯/重开时会自增，从而中止这条延迟。
	_start_authored_art_light_delay(_startup_generation, duration_seconds)
	var batch_count := mini(STARTUP_BATCH_COUNT, _controlled_emission_materials.size())
	var batch_duration := maxf(duration_seconds / float(batch_count), 0.04)
	for batch_index in range(batch_count):
		var start_index := int(
			floor(float(batch_index) * _controlled_emission_materials.size() / batch_count)
		)
		var end_index := int(
			floor(float(batch_index + 1) * _controlled_emission_materials.size() / batch_count)
		)
		var flickers := STARTUP_FLICKER_BATCHES.has(batch_index)
		if flickers:
			var flicker_count := 2 if batch_index == STARTUP_DOUBLE_FLICKER_BATCH else 1
			for flicker_index in range(flicker_count):
				_set_material_energy_range(start_index, end_index, 0.16)
				await get_tree().create_timer(minf(batch_duration * 0.30, 0.075)).timeout
				_set_material_energy_range(start_index, end_index, 0.0)
				await get_tree().create_timer(minf(batch_duration * 0.25, 0.06)).timeout
		_set_material_energy_range(start_index, end_index, 1.0)
		_set_spill_progress(batch_index + 1, batch_count)
		var flicker_time := (
			batch_duration * 0.55
			* (2.0 if batch_index == STARTUP_DOUBLE_FLICKER_BATCH else 1.0)
			if flickers
			else 0.0
		)
		await get_tree().create_timer(maxf(batch_duration - flicker_time, 0.01)).timeout
	_set_material_energy_range(0, _controlled_emission_materials.size(), 1.0)
	_set_spill_progress(batch_count, batch_count)
	_presentation_starting = false
	_presentation_lighting_enabled = true


func _set_material_energy_range(start_index: int, end_index: int, factor: float) -> void:
	for material_index in range(start_index, end_index):
		var material := _controlled_emission_materials[material_index]
		if material == null or not is_instance_valid(material):
			continue
		var restored_energy := float(
			_emission_energy_by_material.get(
				material.get_instance_id(), material.emission_energy_multiplier
			)
		)
		material.emission_energy_multiplier = restored_energy * factor


func _set_spill_progress(completed_batches: int, total_batches: int) -> void:
	var enabled_count := int(
		ceil(float(completed_batches) * _controlled_spill_lights.size() / total_batches)
	)
	for spill_index in range(_controlled_spill_lights.size()):
		var spill_light := _controlled_spill_lights[spill_index]
		# 手摆美术灯不参与分批（由 _start_authored_art_light_delay 统一延后点亮）。
		# 这里只跳过、不改变索引基准 ⇒ 补光的亮起时刻与手摆灯接入前逐位一致。
		if spill_light == null or _authored_art_light_visible.has(spill_light.get_instance_id()):
			continue
		_apply_spill_visibility(spill_light, spill_index < enabled_count)


## 手摆美术灯延后 AUTHORED_ART_LIGHT_DELAY_SECONDS 一次点亮（业主 2026-09-24：≈2s）。
## 与自发光分批序列并行推进：既不阻塞它，也不改变序列总时长。
## generation 与当前世代不符即中止 —— 玩家在延迟途中关灯/重开时不能把灯补亮。
func _start_authored_art_light_delay(generation: int, sequence_seconds: float) -> void:
	if _authored_art_lights.is_empty():
		return
	var delay := clampf(AUTHORED_ART_LIGHT_DELAY_SECONDS, 0.0, maxf(sequence_seconds, 0.0))
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if generation != _startup_generation:
		return
	for art_light in _authored_art_lights:
		_apply_spill_visibility(art_light, true)


func _enhance_fixture(fixture: Node3D, palette_image: Image, profile: Dictionary) -> void:
	var bounds := AABB()
	var has_bounds := false
	var tint := Color.BLACK
	var sample_count := 0
	for node in fixture.find_children("*", "MeshInstance3D", true, false):
		var result := _enhance_mesh(
			node as MeshInstance3D, palette_image, float(profile.target), true
		)
		if int(result.get("sample_count", 0)) == 0:
			continue
		tint += result.tint
		sample_count += int(result.sample_count)
		var visual_bounds: AABB = result.bounds
		if not has_bounds:
			bounds = visual_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(visual_bounds)
	if not bool(profile.spill) or not has_bounds or sample_count == 0:
		return
	tint /= float(sample_count)
	var maximum := maxf(tint.r, maxf(tint.g, tint.b))
	tint = Color(tint.r / maximum, tint.g / maximum, tint.b / maximum)
	if bool(profile.cool):
		# A less saturated blue-white reads as light after filmic tonemapping.
		tint = tint.lerp(Color.WHITE, 0.34)
	_add_light_spill(
		fixture,
		bounds.get_center() + profile.offset,
		tint,
		float(profile.energy),
		float(profile.range)
	)


func _enhance_mesh(
	visual: MeshInstance3D,
	palette_image: Image,
	target: float,
	collect_samples: bool
) -> Dictionary:
	var result := {"tint": Color.BLACK, "sample_count": 0, "bounds": AABB()}
	if visual == null or visual.mesh == null:
		return result
	var has_bounds := false
	for surface in range(visual.mesh.get_surface_count()):
		var uses_instance_override := visual.material_override != null
		if uses_instance_override and surface > 0:
			continue
		var key := (
			"%d:override" % visual.get_instance_id()
			if uses_instance_override
			else "%d:%d" % [visual.get_instance_id(), surface]
		)
		if _processed_surfaces.has(key):
			continue
		var original := visual.get_active_material(surface) as BaseMaterial3D
		if original == null or not original.emission_enabled:
			continue
		var arrays := visual.mesh.surface_get_arrays(surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var peak := 0.0
		for index in range(uvs.size()):
			var uv := uvs[index]
			var color := palette_image.get_pixel(
				clampi(int(uv.x * palette_image.get_width()), 0, palette_image.get_width() - 1),
				clampi(int(uv.y * palette_image.get_height()), 0, palette_image.get_height() - 1)
			)
			var linear := color.srgb_to_linear()
			peak = maxf(peak, maxf(linear.r, maxf(linear.g, linear.b)))
			if collect_samples:
				result.tint += color
				result.sample_count += 1
				var point := to_local(visual.to_global(vertices[index]))
				if not has_bounds:
					result.bounds = AABB(point, Vector3.ZERO)
					has_bounds = true
				else:
					result.bounds = result.bounds.expand(point)
		var material := original.duplicate() as BaseMaterial3D
		material.resource_name = original.resource_name + (
			"_基地灯具HDR" if collect_samples else "_基地微光HDR"
		)
		material.emission = Color.WHITE
		material.emission_texture = PALETTE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = maxf(
			original.emission_energy_multiplier,
			clampf(target / maxf(peak, 0.001), target, 128.0)
		)
		if uses_instance_override:
			visual.material_override = material
		else:
			visual.set_surface_override_material(surface, material)
		_register_controlled_emission_material(material)
		_processed_surfaces[key] = true
		_enhanced_surfaces += 1
	return result


func _register_controlled_emission_material(material: BaseMaterial3D) -> void:
	if material == null or _emission_energy_by_material.has(material.get_instance_id()):
		return
	_controlled_emission_materials.append(material)
	_emission_energy_by_material[material.get_instance_id()] = material.emission_energy_multiplier


func _add_light_spill(
	fixture: Node3D,
	world_position: Vector3,
	tint: Color,
	energy: float,
	range_meters: float
) -> void:
	var light := OmniLight3D.new()
	light.name = "PaletteLightSpill"
	fixture.add_child(light)
	light.global_position = to_global(world_position)
	light.light_color = tint
	light.light_energy = energy
	light.light_specular = 0.15
	light.omni_range = range_meters
	light.omni_attenuation = 1.4
	light.light_cull_mask = 1
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.18
	light.distance_fade_enabled = true
	light.distance_fade_begin = 20.0
	light.distance_fade_length = 6.0
	_controlled_spill_lights.append(light)
	_spill_lights += 1
