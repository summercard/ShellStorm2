extends SceneTree

const SCENES := [
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v003.tscn",
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_contents_v021/env_base99_wall_contents_root_top3d_v003.tscn",
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v005.tscn",
]

func _init() -> void:
	for path in SCENES:
		var packed := load(path) as PackedScene
		assert(packed != null, "Failed to load %s" % path)
		var node := packed.instantiate()
		assert(node != null, "Failed to instantiate %s" % path)
		node.free()
	var vfx := load("res://assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn") as PackedScene
	var vfx_node := vfx.instantiate()
	assert(vfx_node.get_node("DustParticles") is GPUParticles3D)
	assert(vfx_node.get_node("DustParticles").amount == 96)
	assert(vfx_node.get_node("DustParticles").emitting == true)
	vfx_node.free()
	var holo := load("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/hologram_terminal_platform/hologram_terminal_platform_root_top3d_v002.tscn") as PackedScene
	var holo_node := holo.instantiate()
	var players := holo_node.find_children("*", "AnimationPlayer", true, false)
	assert(players.size() > 0, "Hologram GLB has no imported AnimationPlayer")
	assert((players[0] as AnimationPlayer).get_animation_list().size() > 1, "Hologram GLB has no authored rotation animation")
	holo_node.free()
	print("BASE99_V022_VERIFY_OK scenes=3 particles=96 hologram_animation=true")
	quit()
