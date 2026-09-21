extends Node3D
## 保安僵尸表现层：复用 ranged_caster 玩法状态，枪械仅为视觉附件。
const DEATH_DURATION := 2.4
const VISUAL_HEIGHT := 1.857143
const CLIP_BY_STATE := {
	"dormant": "armed_idle", "idle": "armed_idle", "patrol": "walking_armed", "alert": "armed_idle",
	"chase": "running_armed", "search": "running_armed", "return": "running_armed",
	"telegraph": "shoot", "attack": "shoot", "recovery": "shoot",
	"stagger": "hurt", "dead": "dead",
}
var _player: AnimationPlayer
var _state := "idle"
var _clip := "armed_idle"
var _sample := 0.0
var _clock := 0.0
var _hurt_time := 1.0
var _flash_time := 0.0
var _materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "Security zombie AnimationPlayer missing")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
	_attach_shotgun()
	sync_state("idle", 0.0, 0.0, 0.38, 0.34)

func _attach_shotgun() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("Security zombie Skeleton3D missing")
		return
	var gun_scene := load("res://assets/art/weapons/weapon_3d/runtime/double_barrel_cannon/wpn_double_barrel_cannon_root_top3d_v001.tscn") as PackedScene
	if gun_scene == null:
		push_error("Security zombie shotgun visual missing")
		return
	var socket := BoneAttachment3D.new()
	socket.name = "SecurityShotgunAttachment"
	socket.bone_name = "L_Hand"
	skeleton.add_child(socket)
	var gun := gun_scene.instantiate() as Node3D
	gun.name = "ShotgunVisual"
	gun.position = Vector3(0.0, 0.0, 0.0)
	socket.add_child(gun)

func _process(delta: float) -> void:
	_clock += delta
	_hurt_time += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	for material in _materials:
		material.emission_enabled = _flash_time > 0.0
		material.emission = Color(1.0, 0.65, 0.45)
		material.emission_energy_multiplier = 0.6 * _flash_time / 0.12

func sync_state(state: String, state_time: float, _speed: float, telegraph_duration: float, recovery_duration: float) -> void:
	_state = state
	_clip = str(CLIP_BY_STATE.get(state, "armed_idle"))
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
		"source": "blender_v002", "collision_owned": false, "procedural_pose": false,
		"shotgun_visual": true, "shotgun_bone": "L_Hand"}
