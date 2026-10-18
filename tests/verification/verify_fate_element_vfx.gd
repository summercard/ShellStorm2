extends Node3D
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const Style := preload("res://src/vfx/DamageNumberStyle.gd")
var failures: Array[String] = []
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)
func _ready() -> void:
	call_deferred("run")
func enemy(pos: Vector3) -> Enemy3D:
	var e := ENEMY.instantiate() as Enemy3D
	add_child(e)
	e.position = pos
	e.max_hp = 10000
	e.current_hp = 10000
	e.set_physics_process(false)
	return e
func run() -> void:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	pool.clear_all()
	var e := enemy(Vector3(5, -36, 8))
	var elements := ["fire", "ice", "poison"]
	var assets := [VfxPool3D.FX01_FATE_FIRE, VfxPool3D.FX01_FATE_FROST, VfxPool3D.FX01_FATE_POISON]
	for i in range(3):
		e.apply_fate_element(elements[i], {"dot_duration": 3.0, "freeze_duration": 0.5}, 20, null, null)
		var effect := e._fate_visuals[assets[i]] as VfxEffectBase3D
		check(effect.get_node("Particles").get_child_count() == 4, "four large particles")
		check(effect.has_follow_target(), "formal status binds follow")
		e.position.x += 2
		effect._process(0.05)
		check(effect.global_position.distance_to(e.global_position) < 0.001 and effect.global_position.y < -35.0, "moving nonzero floor follows")
		var id := effect.get_instance_id()
		e.apply_fate_element(elements[i], {"dot_duration": 3.0, "freeze_duration": 0.5}, 20, null, null)
		check(e._fate_visuals[assets[i]].get_instance_id() == id, "refresh reuses same visual")
		check(effect.find_children("*", "CollisionObject3D", true, false).is_empty(), "pure visual")
	e._fate_freeze_remaining = 0.0
	e._tick_fate_statuses(3.1)
	e._sync_fate_visuals()
	check(e._fate_visuals.is_empty(), "expiry clears visuals")
	e.apply_fate_element("ice", {"freeze_duration": 0.0, "slow_duration": 3.0}, 20, null, null)
	check(e._fate_visuals.has(VfxPool3D.FX01_FATE_FROST), "reverse ice slow shows frost")
	e._slow_timer = 0.0
	e._sync_fate_visuals()
	check(e._fate_visuals.is_empty(), "slow end clears frost")
	e.apply_fate_element("fire", {}, 20, null, null)
	var dying_visual := e._fate_visuals[VfxPool3D.FX01_FATE_FIRE] as VfxEffectBase3D
	e.take_damage(20000)
	check(not dying_visual.visible and e._fate_visuals.is_empty(), "death clears fire immediately")
	e.free()
	var removed := enemy(Vector3(0, -36, 0))
	removed.apply_fate_element("poison", {}, 20, null, null)
	var removed_visual := removed._fate_visuals[VfxPool3D.FX01_FATE_POISON] as VfxEffectBase3D
	removed.free()
	check(not removed_visual.visible, "owner removal retires persistent effect")
	var first := enemy(Vector3(3, -36, 0))
	var second := enemy(Vector3(5, -36, 0))
	var shot := Projectile3D.new()
	add_child(shot)
	shot.set_physics_process(false)
	shot.damage = 20
	shot.fate_behavior = {"chain_count": 1, "chain_range": 150.0, "chain_damage_scale": 0.7}
	shot._apply_chain_lightning(first)
	check(second.current_hp < 10000, "chain damages actual target")
	var numbers: Array = pool._active.get(VfxPool3D.FX02_DAMAGE_NUMBER, [])
	check(not numbers.is_empty() and numbers.back().effect_color == Style.damage_color(false, "lightning"), "actual chain caller uses lightning number color")
	var bucket: Array = pool._active.get(VfxPool3D.FX01_FATE_LIGHTNING, [])
	check(bucket.size() == 1, "one arc per actual jump")
	if not bucket.is_empty():
		var arc := bucket[0] as VfxEffectBase3D
		check(arc.global_position.distance_to(first.global_position + Vector3.UP * 0.6) < 0.001, "source anchor")
		arc._on_tick(0.06, arc.lifetime)
		check(arc.get_node("EndGlow").visible and arc.get_node("StartGlow").visible, "both endpoint bursts")
		check((arc.global_position + arc.get_node("EndGlow").position).distance_to(second.global_position + Vector3.UP * 0.6) < 0.001, "target anchor")
		check(arc.get_node("Particles").get_child_count() == 4, "arc four sparks total")
		arc.finish()
		check(arc.get_node("ArcLight").light_energy == 0.0, "retirement extinguishes light")
		var reused := pool.acquire(VfxPool3D.FX01_FATE_LIGHTNING, Vector3(0,-12,0), Color.WHITE, 0.8, {"end_position": Vector3(0,-12,-2)})
		reused._on_tick(0.06, reused.lifetime)
		check(reused.get_node("ArcLight").light_energy > 0.0 and is_equal_approx(reused.get_node("ArcLight").omni_range, 1.44), "reuse resets light and size")
		reused.finish()
	check(Style.damage_color(false) == Color("fff1d5"), "warm white ordinary")
	check(Style.damage_color(false,"poison") == Color("8de85b"), "poison green")
	check(Style.damage_color(true,"fire") == Color("ffd34e"), "critical priority")
	var number := pool.acquire(VfxPool3D.FX02_DAMAGE_NUMBER, Vector3(2,-36,2), Style.damage_color(false,"fire"), 1.0, {"text_value":"16", "magnitude":16})
	check(is_equal_approx(number.lifetime, 0.56), "faster damage lifetime")
	number._on_tick(0.14, number.lifetime)
	check(number.position.y > -35.5 and number.position.y < -35.45, "quick rise stays anchored")
	number.finish()
	first.free()
	second.free()
	shot.free()
	pool.clear_all()
	print("FATE_ELEMENT_VFX checks=%d failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
