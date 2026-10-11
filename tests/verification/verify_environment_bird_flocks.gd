extends Node
## Environment bird-flock acceptance (two sets: cross-tower flyby / 100F rooftop ground).
##
## Why this gate exists: the first integration on 2026-10-09 hit three defects that ALL
## present as "I can't see the birds", and none of them report an error:
##   1. Both GLBs store "one Action per bird" (7 birds = 7 animations on ONE
##      AnimationPlayer). The loader played only the first animation and broke out,
##      so bird 01 moved and the other 6 stayed frozen in their glTF rest pose.
##   2. Every animation also carries static tracks for ALL 7 birds (147 tracks = 7 x 21),
##      so giving each animation its own parallel player makes them stomp each other:
##      last writer wins, and again only one bird moves.
##   3. A one-shot performance that `queue_free()`s itself on finish is gone after
##      12s / 24s, so the player almost never sees it.
## This probe therefore asserts PER-BIRD motion over time, not just node/mesh counts.
##
## Run (headless is fine; structure and numbers only, no input dispatch):
##   "<godot_console>" --headless --path "<project>" --scene \
##     res://tests/verification/verify_environment_bird_flocks.tscn
## Success marker: ENVIRONMENT_BIRD_FLOCKS_OK
##
## NOTE: every print/push_error below is deliberately ASCII-only. Headless stdout on this
## host drops non-ASCII lines, which would silently hide the probe's own findings.

const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"

## Expected anchors (same source as README / asset_manifest.json).
const EXPECTED_FLYBY_WORLD := Vector3(20.0, 1.6, -64.5)
const EXPECTED_GROUND_LOCAL := Vector3(25.0, 0.0, -31.0)
const EXPECTED_BIRDS := 7
## Minimum single-bird travel (metres) across the sampling window. Below this = frozen.
const MIN_BIRD_TRAVEL_M := 1.0
## 100F rooftop load-bearing shell world rect, for "stays on the roof while grounded".
const ROOFTOP_RECT := Rect2(-50.0, -35.0, 100.0, 80.0)
## Above this height a bird is considered to have cleared the 0.80m parapet.
const TAKEOFF_CLEARANCE_Y := 1.2
const SKELETON_ROOT := "鸟群_整体移动缩放控制"


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_flyby(failures)
	await _verify_ground(failures)
	if failures.is_empty():
		print("ENVIRONMENT_BIRD_FLOCKS_OK flocks=3 birds=%d" % EXPECTED_BIRDS)
		get_tree().quit(0)
		return
	print("ENVIRONMENT_BIRD_FLOCKS_FAILED count=%d" % failures.size())
	for failure in failures:
		print("  FAIL %s" % failure)
		push_error(failure)
	get_tree().quit(1)


func _verify_flyby(failures: Array[String]) -> void:
	var route := (load(ROUTE) as PackedScene).instantiate() as Node3D
	add_child(route)
	await get_tree().process_frame
	var host := route.get_node_or_null("FlybyBirdFlock") as Node3D
	if host == null:
		failures.append("flyby: FlybyBirdFlock not found under CrossTowerRoute")
		route.queue_free()
		return
	if not host.global_position.is_equal_approx(EXPECTED_FLYBY_WORLD):
		failures.append("flyby: anchor=%s expected=%s" % [str(host.global_position), str(EXPECTED_FLYBY_WORLD)])
	var placement := str(host.get_meta("placement", ""))
	if placement != "above_tower_02_at_bridge_mid_span":
		failures.append("flyby: placement meta=%s" % placement)
	await _check_flock(failures, "flyby", host, EXPECTED_FLYBY_WORLD)
	_check_presentation(failures, host, true)
	var lower := route.get_node_or_null("LowerFlybyBirdFlock") as Node3D
	if lower == null:
		failures.append("lower flyby missing")
	else:
		if not lower.global_position.is_equal_approx(Vector3(20.0, -9.0, -70.0)):
			failures.append("lower flyby anchor changed")
		if lower.visible:
			failures.append("lower flyby did not delay its first pass")
		await get_tree().create_timer(3.0).timeout
		await _check_flock(failures, "lower_flyby", lower, lower.global_position)
		_check_presentation(failures, lower, true)
		var root := lower.find_child(SKELETON_ROOT, true, false)
		for bird in root.get_children():
			if bird is Node3D and (bird.global_position.y >= 0.0 or bird.global_position.y <= -12.3):
				failures.append("lower bird outside airspace between roof and bridge")
	await get_tree().create_timer(2.5).timeout
	if not host.visible:
		failures.append("flyby disappeared before ten seconds")
	route.queue_free()


func _verify_ground(failures: Array[String]) -> void:
	var stage := TowerFloorStage3D.new()
	stage.configure(0, "rooftop", ["west"], [], false, Rect2())
	add_child(stage)
	await get_tree().process_frame
	var host := stage.get_node_or_null("RooftopGroundBirdFlock") as Node3D
	if host == null:
		failures.append("ground: RooftopGroundBirdFlock not found under the 100F stage")
		stage.queue_free()
		return
	if not host.position.is_equal_approx(EXPECTED_GROUND_LOCAL):
		failures.append("ground: local anchor=%s expected=%s" % [str(host.position), str(EXPECTED_GROUND_LOCAL)])
	await _check_flock(failures, "ground", host, host.global_position)
	_check_presentation(failures, host, false)
	await _check_ground_containment(failures, host)
	stage.queue_free()


func _check_presentation(failures: Array[String], host: Node3D, flyby: bool) -> void:
	var players := host.find_children("*", "AnimationPlayer", true, false)
	var primary := players[0] as AnimationPlayer
	var checked_scale := 0
	var visual_path := "res://assets/art/vfx/environment_3d/bird_flocks/components/%s/vfx_env_birds_%s_visual.glb" % ["flyby" if flyby else "ground", "flyby" if flyby else "ground"]
	var original_visual := (load(visual_path) as PackedScene).instantiate()
	var original_root := original_visual.find_child(SKELETON_ROOT, true, false)
	var resized_root := host.find_child(SKELETON_ROOT, true, false)
	var expected_variations := [0.90, 1.06, 0.97, 1.10, 0.94, 1.02, 1.01]
	for original_bird in original_root.get_children():
		var resized_bird := resized_root.get_node(NodePath(str(original_bird.name))) as Node3D
		var expected_size: float = 0.75 * expected_variations[original_bird.get_index()]
		if not resized_bird.scale.is_equal_approx((original_bird as Node3D).scale * expected_size):
			failures.append("bird scale must be 150 percent of previous size with +/-10 percent variation")
		checked_scale += 1
	original_visual.free()
	var checked_travel := 0
	var wing_tracks := 0
	for node in players:
		var player := node as AnimationPlayer
		var animation := player.get_animation(player.current_animation)
		if animation == null:
			failures.append("presentation player is not playing")
			continue
		var source_name := player.current_animation.trim_prefix("birds/").trim_suffix("__pruned")
		var source := primary.get_animation(source_name)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var kind := animation.track_get_type(track)
			if ":" not in str(path) and kind == Animation.TYPE_SCALE_3D:
				var original_track := source.find_track(path, kind)
				var original := source.track_get_key_value(original_track, 0) as Vector3
				var resized := animation.track_get_key_value(track, 0) as Vector3
				if resized.x / original.x < 0.675 or resized.x / original.x > 0.825:
					failures.append("animated scale exceeds +/-10 percent size range")
			if flyby and ":" not in str(path) and kind == Animation.TYPE_POSITION_3D:
				var first := animation.track_get_key_value(track, 0) as Vector3
				var last := animation.track_get_key_value(track, animation.track_get_key_count(track) - 1) as Vector3
				if absf(last.x - first.x - 200.0) > 0.1 or not is_equal_approx(animation.length, 24.0):
					failures.append("flyby path must cover 200m in 24s at half previous speed")
				var p0 := animation.position_track_interpolate(track, 10.0)
				var p1 := animation.position_track_interpolate(track, 12.0)
				if absf((p1.x - p0.x) / 2.0 - 200.0 / 24.0) > 0.02:
					failures.append("sampled flyby speed is not 8.33m/s")
				checked_travel += 1
			if flyby and (":wing_" in str(path) or ":tip_" in str(path)) and kind == Animation.TYPE_ROTATION_3D:
				var original_track := source.find_track(path, kind)
				var sample := animation.rotation_track_interpolate(track, 1.0)
				var accelerated := source.rotation_track_interpolate(original_track, 1.35)
				if sample.angle_to(accelerated) > 0.015:
					failures.append("wing rotation does not sample at 135 percent speed")
				wing_tracks += 1
	if checked_scale != EXPECTED_BIRDS or (flyby and (checked_travel != EXPECTED_BIRDS or wing_tracks != 28)):
		failures.append("presentation track coverage scale=%d travel=%d wings=%d" % [checked_scale, checked_travel, wing_tracks])
	print("BIRD_PRESENTATION_CHECK scales=%d travel=%d wings=%d" % [checked_scale, checked_travel, wing_tracks])


## Assert "every bird actually moves" -- this is the check that was missing.
##
## MUST be awaited by the caller: `_check_flock` contains a 2.5s sampling await, so it is a
## coroutine. Without `await` the caller frees the host and returns before sampling finishes,
## the failures are never collected, and the gate prints OK even with 6 frozen birds.
## (That exact bug was in the first version of this probe; only the "play first animation
## only" negative control exposed it.)
func _check_flock(failures: Array[String], label: String, host: Node3D, origin: Vector3) -> void:
	var skeleton := host.find_child(SKELETON_ROOT, true, false) as Node3D
	if skeleton == null:
		failures.append("%s: skeleton root '%s' not found" % [label, SKELETON_ROOT])
		return
	if skeleton.get_child_count() != EXPECTED_BIRDS:
		failures.append("%s: bird count=%d expected=%d" % [label, skeleton.get_child_count(), EXPECTED_BIRDS])
	var collisions := host.find_children("*", "CollisionObject3D", true, false).size() \
		+ host.find_children("*", "CollisionShape3D", true, false).size()
	if collisions != 0:
		failures.append("%s: %d collision node(s) present (environment birds must be visual-only)" % [label, collisions])
	var first := _sample_birds(skeleton)
	await get_tree().create_timer(2.5).timeout
	var second := _sample_birds(skeleton)
	var frozen: Array[String] = []
	for bird_name in first:
		var a: Vector3 = first[bird_name]
		var b: Vector3 = second.get(bird_name, a)
		if a.distance_to(b) < MIN_BIRD_TRAVEL_M:
			frozen.append("%s(%.2fm)" % [bird_name, a.distance_to(b)])
	if not frozen.is_empty():
		failures.append("%s: %d/%d birds barely moved in 2.5s => animations not all playing: %s" % [
			label, frozen.size(), first.size(), ", ".join(frozen)])
	else:
		print("BIRD_FLOCK_ANIMATED set=%s birds=%d anchor=%s" % [label, first.size(), str(origin)])
	# Lifecycle: must not self-destruct on finish, or the player never sees the birds.
	var lifecycle := str(host.get_meta("lifecycle", ""))
	if not lifecycle.ends_with("ambient_repeat"):
		failures.append("%s: lifecycle=%s expected something ending in ambient_repeat" % [label, lifecycle])
	if not host.visible:
		failures.append("%s: node not visible" % label)


## Ground set: while grounded the birds must stay on the roof; any sample outside the roof
## rect must already be above the parapet.
func _check_ground_containment(failures: Array[String], host: Node3D) -> void:
	var skeleton := host.find_child(SKELETON_ROOT, true, false) as Node3D
	if skeleton == null:
		return
	var low_outside := 0
	var high_outside := 0
	# Covers a full 24s performance, so the takeoff leg is definitely sampled.
	for step in 26:
		if step > 0:
			await get_tree().create_timer(1.0).timeout
		for child in skeleton.get_children():
			var bird := child as Node3D
			if bird == null:
				continue
			var world := bird.global_position
			if ROOFTOP_RECT.has_point(Vector2(world.x, world.z)):
				continue
			if world.y < TAKEOFF_CLEARANCE_Y:
				low_outside += 1
			else:
				high_outside += 1
	print("BIRD_GROUND_CONTAINMENT clearance_y=%.1f low_outside=%d high_outside=%d" % [
		TAKEOFF_CLEARANCE_Y, low_outside, high_outside])
	if low_outside > 0:
		failures.append("ground: %d sample(s) outside the roof while still low => birds would clip the parapet" % low_outside)


func _sample_birds(skeleton: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for child in skeleton.get_children():
		var bird := child as Node3D
		if bird != null:
			out[String(bird.name)] = bird.global_position
	return out
