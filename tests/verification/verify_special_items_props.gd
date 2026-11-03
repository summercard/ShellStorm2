extends Node3D
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("SPECIAL_PROP_FAIL " + message)
func vase(at: Vector3) -> BreakableClutter3D:
	var result := preload("res://assets/art/environments/tower_zones/battle/runtime/common_components/breakable_vase/breakable_vase_root_top3d.tscn").instantiate() as BreakableClutter3D
	add_child(result)
	result.position = at
	return result
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	position.y = -72.0
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.008,0.008,0.01)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_energy = 0.0
		add_child(environment)
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(12,12)
		ground.mesh = plane
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.5,0.5,0.5)
		ground.material_override = material
		add_child(ground)
		var camera := Camera3D.new()
		add_child(camera)
		camera.position = Vector3(3,4,5)
		camera.look_at(global_position)
		camera.current = true
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 6.0
	var world := SpecialItemWorld3D.new()
	add_child(world)
	world.set_physics_process(false)
	var victim := vase(Vector3(1,0,0))
	var table := preload("res://assets/art/environments/tower_zones/expedition/runtime/common_components/manor_nightstand/env_manor_nightstand_root_top3d.tscn").instantiate() as ReactiveProp3D
	add_child(table)
	table.position = Vector3(-1.5,0,0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	world._detonate({"definition":SpecialItemCatalog.get_item(SpecialItemCatalog.GRENADE),"attacker":null},global_position)
	check(victim._broken, "grenade shatters real vase through its public damage entry")
	check(table.hit_count == 1, "grenade gives real furnishing exactly one hit feedback")
	world.clear()
	victim.queue_free()
	table.queue_free()
	await get_tree().process_frame
	var burned := vase(Vector3(0.5,0,0))
	world.add_fire(global_position,1.25,5.0,12,null)
	world._damage_fire_tick()
	check(burned._broken, "fire damages real fragile object")
	world.clear()
	burned.queue_free()
	await get_tree().process_frame
	var protected := vase(Vector3(1.2,0,0))
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.15,3,5)
	collider.shape = box
	wall.add_child(collider)
	add_child(wall)
	wall.position = Vector3(0.6,1.5,0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	world._detonate({"definition":SpecialItemCatalog.get_item(SpecialItemCatalog.GRENADE),"attacker":null},global_position)
	check(not protected._broken, "solid wall shields fragile prop from blast")
	world.clear()
	var effects := LampFirePatch3D.create_ground_flames(world._acquire_ground_flame,global_position,0.58)
	var flame := effects[0]
	flame.set_process(false)
	var light := flame.get_node("FireLight") as OmniLight3D
	check(light.visible and light.light_energy > 0.0 and not light.shadow_enabled, "oil flame illuminates floor without shadow maps")
	await capture("oil_fire_lit.png")
	flame._on_tick(4.0,5.0)
	var energy := light.light_energy
	flame._on_tick(4.7,5.0)
	check(light.light_energy > 0.0 and light.light_energy < energy, "fire light dims before expiry")
	check((flame.get_node("Particles/P0") as MeshInstance3D).transparency > 0.0, "flames smoothly fade before expiry")
	await capture("oil_fire_fading.png")
	flame._on_tick(4.99,5.0)
	check(light.light_energy < 0.01, "fire reaches near zero before retirement")
	flame.finish()
	check(light.light_energy == 0.0, "retirement leaves no persistent light")
	var oil := world._effect(VfxPool3D.FX01_SPECIAL_OIL,global_position,0.58,45.0)
	oil.call("set_fade_ratio",0.5)
	check(is_equal_approx((oil.get_node("OilSurface") as MeshInstance3D).transparency,0.5), "burned oil surface fades with flames")
	world.clear()
	await get_tree().process_frame
	if failures.is_empty():
		print("SPECIAL_ITEMS_PROPS_OK: %d checks" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	get_viewport().get_texture().get_image().save_png(output.path_join(filename))
