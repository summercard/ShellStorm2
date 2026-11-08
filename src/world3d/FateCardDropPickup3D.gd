class_name FateCardDropPickup3D
extends GroundLootPickup3D
## 命运卡专用世界凭据。
## 复用普通地面物的落地、漂浮与回收动画，但只允许统一交互控制器主动执行。

const INTERACTION_PRIORITY := 65
const INTERACTION_ID_PREFIX := "fate_card_drop:"
const FATE_CARD_ROTATION_SPEED := 0.55
const GROUND_LOOT_ROTATION_SPEED := 1.35
## 命运卡是稀有主动交互凭据，不能沿用普通消耗品的视觉体量。
## 该倍率只作用于 FateCardDropPickup3D 的 `_visual`，不改变碰撞球、拾取距离或普通掉落基线。
const FATE_CARD_VISUAL_SCALE_MULTIPLIER := 1.45
const FATE_CARD_LABEL_HEIGHT_M := 1.20
const FATE_CARD_PARTICLE_AMOUNT := 12
const FATE_CARD_PARTICLE_LIFETIME_S := 0.95

## Dungeon3D 注入 `_on_fate_pickup_interacted`；返回 true 才表示凭据已被主事务成功认领。
## 本类不会在成功后自行 accept_pickup()，认领、offer 与回收由 Dungeon3D 同步收口。
var interaction_handler: Callable
var _fate_fx_anchor: Node3D
var _rise_particles: CPUParticles3D
var _fate_light: OmniLight3D


func configure(data: Dictionary, color := Color(0.72, 0.34, 1.0)) -> void:
	if not is_fate_pickup_data(data):
		item_data = data.duplicate(true)
		return
	item_data = data.duplicate(true)
	_build_visual(color)


## 命运卡只放大自己的世界视觉，不改普通掉落基线、碰撞球或交互距离。
func _build_visual(color: Color) -> void:
	super._build_visual(color)
	if _visual == null:
		return
	_visual.scale *= FATE_CARD_VISUAL_SCALE_MULTIPLIER
	if _label != null:
		_label.position.y = FATE_CARD_LABEL_HEIGHT_M
	_fate_fx_anchor = Node3D.new()
	_fate_fx_anchor.name = "FateCardFxAnchor"
	add_child(_fate_fx_anchor)
	_fate_fx_anchor.position = Vector3(0.0, 0.28, 0.0)

	_rise_particles = CPUParticles3D.new()
	_rise_particles.name = "FateRiseParticles"
	_rise_particles.amount = FATE_CARD_PARTICLE_AMOUNT
	_rise_particles.lifetime = FATE_CARD_PARTICLE_LIFETIME_S
	_rise_particles.randomness = 0.35
	_rise_particles.emitting = false
	_rise_particles.local_coords = false
	_rise_particles.direction = Vector3.UP
	_rise_particles.spread = 14.0
	_rise_particles.initial_velocity_min = 0.38
	_rise_particles.initial_velocity_max = 0.72
	_rise_particles.gravity = Vector3(0.0, 0.62, 0.0)
	_rise_particles.scale_amount_min = 0.55
	_rise_particles.scale_amount_max = 1.0
	_rise_particles.color = Color(0.64, 0.34, 1.0, 0.92)
	var particle_mesh := BoxMesh.new()
	particle_mesh.size = Vector3(0.075, 0.075, 0.075)
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = Color(0.48, 0.20, 0.92)
	particle_material.emission_enabled = true
	particle_material.emission = Color(0.42, 0.16, 1.0)
	particle_material.emission_energy_multiplier = 2.2
	particle_material.roughness = 0.28
	particle_mesh.material = particle_material
	# CPUParticles3D 使用单一 `mesh` 属性；`draw_pass_1` 是 GPUParticles3D API。
	_rise_particles.mesh = particle_mesh
	_fate_fx_anchor.add_child(_rise_particles)

	_fate_light = OmniLight3D.new()
	_fate_light.name = "FateCardGlow"
	_fate_light.light_color = Color(0.45, 0.22, 1.0)
	_fate_light.light_energy = 1.25
	_fate_light.omni_range = 2.35
	_fate_light.shadow_enabled = false
	_fate_light.visible = false
	_fate_fx_anchor.add_child(_fate_light)


func requires_manual_interaction() -> bool:
	return true


func _process(delta: float) -> void:
	super._process(delta)
	if _fate_fx_anchor != null and _visual != null and is_instance_valid(_visual):
		# 宝箱弧线移动的是 `_visual`，特效锚点必须跟随视觉而不是留在最终落点。
		_fate_fx_anchor.global_position = _visual.global_position + Vector3.UP * 0.18
	if _accepted or _collecting:
		_stop_fate_visual_fx()
	elif not _spawn_animating:
		_start_fate_visual_fx()
	if not _accepted and _visual != null and not _spawn_animating and not _collecting:
		_visual.rotation.y += delta * (FATE_CARD_ROTATION_SPEED - GROUND_LOOT_ROTATION_SPEED)


func _start_fate_visual_fx() -> void:
	if _rise_particles == null or _rise_particles.emitting or not _rise_particles.is_inside_tree():
		return
	_rise_particles.visible = true
	_rise_particles.restart()
	_rise_particles.emitting = true
	if _fate_light != null:
		_fate_light.visible = true


func _stop_fate_visual_fx() -> void:
	if _rise_particles != null:
		_rise_particles.emitting = false
		_rise_particles.visible = false
	if _fate_light != null:
		_fate_light.visible = false


func get_model_snapshot() -> Dictionary:
	var snapshot := super.get_model_snapshot()
	snapshot["fate_visual_scale_multiplier"] = FATE_CARD_VISUAL_SCALE_MULTIPLIER
	snapshot["fate_particles_present"] = _rise_particles != null
	snapshot["fate_particles_emitting"] = _rise_particles != null and _rise_particles.emitting
	snapshot["fate_glow_light_visible"] = _fate_light != null and _fate_light.visible
	return snapshot


func accept_pickup(target: Node3D = null) -> void:
	_stop_fate_visual_fx()
	super.accept_pickup(target)


static func is_fate_pickup_data(data: Dictionary) -> bool:
	return str(data.get("type", "")) == "fate_pickup" \
		and str(data.get("id", "")) == "item_fate_card_drop"


func get_fate_pickup_id() -> String:
	return str(item_data.get("fate_pickup_id", ""))


func _ready() -> void:
	super._ready()
	add_to_group("interaction_provider_3d")


func get_interaction_candidate(player: Node3D) -> Dictionary:
	if not _can_interact_with(player):
		return {}
	return {
		"available": true,
		"interaction_id": "%s%s" % [INTERACTION_ID_PREFIX, get_fate_pickup_id()],
		"fate_pickup_id": get_fate_pickup_id(),
		"position": global_position,
		"priority": INTERACTION_PRIORITY,
		"prompt": "[E] 获取命运卡",
	}


func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func perform_interaction(player: Node3D, candidate: Dictionary) -> bool:
	if not _can_interact_with(player):
		return false
	if str(candidate.get("fate_pickup_id", "")) != get_fate_pickup_id():
		return false
	if str(candidate.get("interaction_id", "")) != "%s%s" % [INTERACTION_ID_PREFIX, get_fate_pickup_id()]:
		return false
	if not interaction_handler.is_valid():
		return false
	return bool(interaction_handler.call(self))


func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3.UP * (LABEL_HEIGHT_M + 0.45)


func is_interaction_dot_visible() -> bool:
	return not is_pickup_accepted() and not get_fate_pickup_id().is_empty()


func get_interaction_progress() -> Dictionary:
	return {"active": false, "progress": 0.0}


func _can_interact_with(player: Node3D) -> bool:
	if not is_fate_pickup_data(item_data):
		return false
	if get_fate_pickup_id().is_empty() or is_pickup_accepted():
		return false
	if _spawn_animating or not is_pickup_available():
		return false
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var offset := player.global_position - global_position
	offset.y = 0.0
	return offset.length() <= get_pickup_distance_m()
