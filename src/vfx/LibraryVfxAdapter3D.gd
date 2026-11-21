class_name LibraryVfxAdapter3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## ShellStorm2 生命周期壳。
## 不修改 UnityVFXLibrary 的源场景、粒子参数或运行脚本；只负责把库特效接入 VfxPool3D。

## Wrapper scale = existing call-site size × source_to_game_scale.
@export var source_to_game_scale: float = 1.0
@export var source_lifetime: float = 2.0
@export var align_forward: bool = false
@export var track_mount_rotation: bool = false
@export var mirror_second_swing: bool = false
@export var yaw_offset_degrees: float = 0.0
@export var forward_offset_per_size: float = 0.0

@onready var library_effect: Node3D = $LibraryEffect
var _forward := Vector3.FORWARD

func _enter_tree() -> void:
	# Parent enters before the library child. Configure only this instance,
	# not the source PackedScene or its shared resources.
	prepare_visual(get_node("LibraryEffect") as Node3D)


## Also used by compound effects that own their timing instead of retiring with the library clip.
static func prepare_visual(child: Node3D, keep_lights: bool = true) -> void:
	child.set("auto_play", false)
	child.hide()
	var components: Array[Dictionary] = child.get("components").duplicate(true)
	for component: Dictionary in components:
		var qualified_type := str(component.get("type", ""))
		var type_name := qualified_type.get_slice(".", qualified_type.get_slice_count(".") - 1)
		if type_name == "AudioSource" or (not keep_lights and type_name == "Light"):
			component["enabled"] = false
	child.set("components", components)


static func play_visual(child: Node3D, size: float, seed_value: int) -> void:
	child.scale = Vector3.ONE * maxf(0.00001, size)
	child.show()
	child.call("play_exact", seed_value)


static func stop_visual(child: Node3D) -> void:
	child.call("stop_exact", true)
	child.hide()

func _ready() -> void:
	lifetime = source_lifetime
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func _on_activate(_world_pos: Vector3, _color: Color, size: float, context: Dictionary) -> void:
	lifetime = source_lifetime
	_forward = context.get("forward", Vector3.FORWARD)
	var fit := maxf(0.00001, size * source_to_game_scale)
	var swing_sign := -1.0 if mirror_second_swing and int(context.get("combo_step", 1)) == 2 else 1.0
	library_effect.scale = Vector3(fit * swing_sign, fit, fit)
	_update_pose()
	library_effect.visible = true
	library_effect.call("stop_exact", true)
	library_effect.call("play_exact", -1)

func _update_pose() -> void:
	var forward := follow_forward() if track_mount_rotation and has_follow_target() else _forward
	if align_forward:
		if absf(forward.normalized().dot(Vector3.UP)) > 0.999:
			forward = Vector3.FORWARD
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		global_basis = Basis.looking_at(forward) * Basis(Vector3.UP, deg_to_rad(yaw_offset_degrees))
	library_effect.position = Vector3.FORWARD * forward_offset_per_size * effect_size

func _on_tick(_elapsed_time: float, _total: float) -> void:
	if track_mount_rotation and has_follow_target():
		_update_pose()

func _process(delta: float) -> void:
	super._process(delta)
	# Both runtimes stop their own processing once authored playback ends.
	# Check after the base timeout to avoid retiring twice on the same frame.
	if _active and not library_effect.is_physics_processing():
		finish()

func _on_lifetime_expired() -> void:
	library_effect.call("stop_exact", true)
	library_effect.visible = false
