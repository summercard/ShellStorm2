extends SceneTree

const DUST_SCENE := "res://assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn"

func _init() -> void:
	var scene := load(DUST_SCENE) as PackedScene
	assert(scene != null, "base facility dust VFX scene must load")
	var root := scene.instantiate()
	var particles := root.get_node_or_null("DustParticles") as GPUParticles3D
	assert(particles != null and particles.emitting, "dust particles must remain enabled")
	assert(particles.amount == 250, "dust particle density mismatch")
	assert(particles.position.is_equal_approx(Vector3(0, 5.6, 0)), "dust emitter vertical range must begin at 3m above the ground")
	assert(particles.visibility_aabb == AABB(Vector3(-15, -2.6, -15), Vector3(30, 5.2, 30)), "dust visibility range mismatch")
	var process := particles.process_material as ParticleProcessMaterial
	assert(process != null and process.emission_box_extents == Vector3(14.5, 2.6, 15.0), "dust emission range mismatch")
	assert(process != null and is_equal_approx(process.color.a, 0.58), "dust particle opacity mismatch")
	assert(process != null and is_equal_approx(process.initial_velocity_min, 0.01) and is_equal_approx(process.initial_velocity_max, 0.05), "dust drift speed must be one fifth of the previous range")
	var quad := particles.draw_pass_1 as QuadMesh
	var material := quad.material as StandardMaterial3D
	assert(quad != null and quad.size == Vector2(0.02, 0.02), "dust particle size mismatch")
	assert(material != null and material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "dust must use additive HDR blending for Bloom")
	assert(material != null and material.emission_enabled and is_equal_approx(material.emission_energy_multiplier, 15.0), "dust HDR emission must support Bloom")
	print("BASE99_DUST_VFX_OK amount=", particles.amount, " energy=", material.emission_energy_multiplier, " extents=", process.emission_box_extents)
	root.free()
	quit()
