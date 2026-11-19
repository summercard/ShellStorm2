extends Node3D
## 旧 fat_zombie03 玩法与新 fat_zombie21 视觉之间的单向适配器。
## 只采样导入动作和材质反馈；状态、根位移、碰撞、伤害与死亡计时归 Enemy3D。

const VfxPool3D = preload("res://src/vfx/VfxPool3D.gd")
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
const CLIP_BY_STATE := {
	"dormant": "idle", "idle": "idle", "patrol": "walking", "alert": "idle",
	"chase": "running", "search": "running", "return": "running",
	"telegraph": "attack", "attack": "attack", "recovery": "attack",
	"stagger": "idle", "dead": "idle"
}
const SOURCE_FPS := 60.0
const ATTACK_CONTACT_FRAME := 78.0
const FLASH_DURATION := 0.12
const WARNING_PEAK_ENERGY := 0.35
const WARNING_EMISSION_COLOR := Color(0.32, 0.55, 0.10)

var _player: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _flash_baseline: Array = []
var _flash_time := 0.0
var _warning_progress := 0.0
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _attack_visual_frame := 0.0
var _slam_fx_fired := false
var _slam_fx_count := 0
var _event := ""
var _event_anchor := 0.0

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "胖子僵尸2.1缺少 AnimationPlayer")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, material)
				_materials.append(material)
	_flash_baseline = HitFlash.prepare(_materials)
	sync_state("idle", 0.0, 0.0, 1.2, 1.3, 0.0)

func _process(delta: float) -> void:
	if _state in ["dormant", "death_warning"]:
		return
	_flash_time = maxf(0.0, _flash_time - delta)
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

func sync_state(
	state: String, state_time: float, speed: float,
	telegraph_duration: float, recovery_duration: float, base_speed := 0.0
) -> void:
	if _player == null:
		return
	if _state == "death_warning" and state != "death_warning":
		position = Vector3.ZERO
		rotation.z = 0.0
		HitFlash.restore(_flash_baseline)
	if state != _state:
		_event = ""
		_event_anchor = state_time
		if state == "patrol":
			_event = "move_start"
		elif _state == "patrol" and state == "idle":
			_event = "move_stop"
	_state = state
	_clip = str(CLIP_BY_STATE.get(state, "idle"))
	var length := _player.get_animation(_clip).length
	var contact := ATTACK_CONTACT_FRAME / SOURCE_FPS
	match state:
		"telegraph":
			# 将源 F0..F78 映射到原玩法前摇，不改变 1.2 秒伤害边界。
			_sample = contact * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		"attack":
			_sample = contact
		"recovery":
			_sample = lerpf(contact, length, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
		"patrol", "chase", "search", "return":
			var reference_speed := base_speed * (0.5 if state == "patrol" else 1.0)
			var rate := maxf(0.0, speed) / reference_speed if reference_speed > 0.001 else 1.0
			_sample = fmod(maxf(0.0, state_time) * rate, length)
		"dormant", "stagger", "dead", "death_warning":
			_sample = 0.0
		_:
			_sample = fmod(maxf(0.0, state_time), length)
	if not _event.is_empty():
		var progress := maxf(0.0, state_time - _event_anchor)
		if progress < _player.get_animation(_event).length:
			_clip = _event
			_sample = progress
		else:
			_event = ""
	_player.play(_clip)
	_player.seek(_sample, true)
	_player.advance(0.0)
	_attack_visual_frame = _sample * SOURCE_FPS if state in ["telegraph", "attack", "recovery"] else 0.0
	if state not in ["telegraph", "attack", "recovery"]:
		_slam_fx_fired = false
	elif state == "telegraph" and state_time <= 0.001:
		_slam_fx_fired = false
	elif state in ["attack", "recovery"] and not _slam_fx_fired and _sample >= contact - 0.00001:
		_fire_slam_fx()

func flash_hit(_play_hit_pose := true) -> void:
	# 当前源无 hurt/hit_light，保留闪白，不伪造全身或局部受击动作。
	if _state not in ["dead", "death_warning"]:
		_flash_time = FLASH_DURATION
		HitFlash.apply(_materials, _flash_baseline, 1.0)

func sync_death_warning(elapsed: float, duration: float) -> void:
	if _player == null:
		return
	_state = "death_warning"
	_clip = "idle"
	_sample = 0.0
	_flash_time = 0.0
	_warning_progress = clampf(elapsed / maxf(0.001, duration), 0.0, 1.0)
	_player.play("idle")
	_player.seek(0.0, true)
	_player.advance(0.0)
	position = Vector3(sin(elapsed * 93.0) * 0.035, 0.0, sin(elapsed * 117.0) * 0.025)
	rotation.z = sin(elapsed * 105.0) * 0.018
	for entry in _flash_baseline:
		var record := entry as Dictionary
		var material := record["material"] as StandardMaterial3D
		material.emission = WARNING_EMISSION_COLOR
		var energy := float(record["energy"]) + WARNING_PEAK_ENERGY * _warning_progress * _warning_progress
		material.emission_energy_multiplier = energy
		record["written"] = energy

func _fire_slam_fx() -> void:
	_slam_fx_fired = true
	_slam_fx_count += 1
	var pools := get_tree().get_nodes_in_group("vfx_pool_3d")
	if pools.is_empty() or not pools[0] is VfxPool3D:
		return
	var pool := pools[0] as VfxPool3D
	pool.acquire(VfxPool3D.FX01_FAT_ZOMBIE_SLAM, global_position, Color.WHITE, 1.0, {"floor_y": global_position.y})

func get_attack_visual_frame() -> float:
	return _attack_visual_frame

func get_presentation_snapshot() -> Dictionary:
	return {
		"state": _state, "clip": _clip, "sample_time": _sample,
		"source_fps": SOURCE_FPS, "source_attack_frame": _attack_visual_frame,
		"asset_id": "ENM-NORMAL-FAT-ZOMBIE21", "asset_version": "v006",
		"bones": 41, "vertices": 597, "vertex_groups": 29,
		"procedural_pose": false, "collision_owned": false, "damage_owner": "Enemy3D",
		"slam_fx_asset_id": "VFX-FAT-ZOMBIE-SLAM-3D",
		"slam_fx_trigger_frame": ATTACK_CONTACT_FRAME, "slam_fx_count": _slam_fx_count,
		"hit_light_active": false, "flash_time": _flash_time,
		"warning_progress": _warning_progress, "supplemental_event": _event,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"unavailable_clips": ["hurt", "dead", "awaken", "alert", "turn_l", "turn_r", "hit_light"]
	}
