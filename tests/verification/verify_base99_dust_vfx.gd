extends SceneTree

const DUST_SCENE := "res://assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn"

func _init() -> void:
	var scene := load(DUST_SCENE) as PackedScene
	assert(scene != null, "base facility dust VFX scene must load")
	var root := scene.instantiate()
	var particles := root.get_node_or_null("DustParticles") as GPUParticles3D
	assert(particles != null and particles.emitting, "dust particles must remain enabled")
	assert(particles.amount == 192, "dust amount must be doubled")
	assert(particles.visibility_aabb == AABB(Vector3(-15, -3.8, -8.5), Vector3(30, 7.6, 17)), "dust visibility range mismatch")
	var process := particles.process_material as ParticleProcessMaterial
	assert(process != null and process.emission_box_extents == Vector3(14.5, 3.6, 7.25), "dust emission range mismatch")
	var quad := particles.draw_pass_1 as QuadMesh
	var material := quad.material as StandardMaterial3D
	assert(material != null and is_equal_approx(material.emission_energy_multiplier, 2.2), "dust glow must match the scene emissive baseline")
	print("BASE99_DUST_VFX_OK amount=", particles.amount, " energy=", material.emission_energy_multiplier, " extents=", process.emission_box_extents)
	root.free()
	quit()
