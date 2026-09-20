extends Node3D
## 仅采样美术骨动画。攻击事件与位移仍由 Enemy3D 拥有。
const DEATH_DURATION := 2.4
const VISUAL_HEIGHT := 1.857143
## 走路动画只服务巡逻；只要朝玩家方向移动（追击、搜寻、归位）一律用跑步，不按速度切档。
const CLIP_BY_STATE := {
	"dormant": "idle", "idle": "idle", "patrol": "walking", "alert": "idle",
	"chase": "running", "search": "running", "return": "running",
	"telegraph": "attack", "attack": "attack", "recovery": "attack",
	"stagger": "hurt", "dead": "dead",
}
var _player: AnimationPlayer
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _clock := 0.0
var _hurt_time := 1.0
var _flash_time := 0.0
var _materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "Zombie animation player missing")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
	sync_state("idle", 0.0, 0.0, 0.38, 0.34)

func _process(delta: float) -> void:
	_clock += delta
	_hurt_time += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	for material in _materials:
		material.emission_enabled = _flash_time > 0.0
		material.emission = Color(1.0, 0.65, 0.45)
		material.emission_energy_multiplier = 0.6 * _flash_time / 0.12

## speed 仍按契约保留在参数位（调用方按顺序传入），但不再参与选段。
func sync_state(state: String, state_time: float, _speed: float, telegraph_duration: float, recovery_duration: float) -> void:
	_state = state
	# 速度不再参与选段：巡逻走、接近玩家跑，由状态唯一决定，避免同一状态在快慢档之间抖动。
	_clip = str(CLIP_BY_STATE.get(state, "idle"))
	if _player == null or not _player.has_animation(_clip):
		return
	var length := _player.get_animation(_clip).length
	_sample = fmod(_clock, maxf(length, 0.001))
	match state:
		"dormant": _sample = 0.0
		"telegraph": _sample = length * 0.48 * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		"attack": _sample = length * 0.48
		"recovery": _sample = length * lerpf(0.48, 1.0, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
		"stagger": _sample = length * clampf(state_time / 0.16, 0.0, 1.0)
		"dead": _sample = minf(state_time, length)
	# 非硬直受击只覆盖表现，不延迟攻击与伤害事件。
	if _hurt_time < 0.8 and state not in ["dead", "telegraph", "attack", "recovery", "stagger", "dormant"]:
		_clip = "hurt"
		_sample = _hurt_time
	_player.play(_clip)
	_player.seek(_sample, true)

func flash_hit() -> void:
	if _state != "dead":
		_hurt_time = 0.0
		_flash_time = 0.12

func get_presentation_snapshot() -> Dictionary:
	return {"state": _state, "clip": _clip, "sample_time": _sample,
		"visual_height": VISUAL_HEIGHT, "death_duration": DEATH_DURATION,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"source": "blender_v003", "collision_owned": false, "procedural_pose": false}
