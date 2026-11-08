extends Node
## Real expedition03 generation, room lifecycle, monitor phases and three-wave exit.
const GENERATOR = preload("res://src/map/FloorPlanGenerator.gd")
const LOADER = preload("res://src/map/LevelPlanLoader.gd")
var tower: TowerDescent3D
var room: DungeonRoom3D
var failures: Array[String] = []
var checks := 0
var clear_count := 0

func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures.append(message)
  print("MONITOR03_FAIL ", message)

func enemies() -> Array[Enemy3D]:
 var result: Array[Enemy3D] = []
 for value in tower._enemy_nodes_by_room.get(room.room_id, []):
  if is_instance_valid(value) and not value.is_queued_for_deletion() and value.current_hp > 0:
   result.append(value)
 return result

func _ready() -> void:
 RuntimePerformanceManager.set_verification_frame_budget_override(60)
 call_deferred("run")

func run() -> void:
 var blueprint = LOADER.normalize_floor("expedition_03", 0)
 var expected: Dictionary = {}
 for value in blueprint.rooms:
  if value.key == "boss": expected = value
 var flows := {}
 for seed_value in range(77003201, 77003225):
  var plan = GENERATOR.generate_from_level_plan("expedition_03", 0, seed_value, 0)
  check(bool(plan.get("valid", false)), "valid generated plan seed=%d errors=%s" % [seed_value, str(plan.get("validation_errors", []))])
  var boss_rooms := 0
  for value in plan.get("rooms", []):
   if str(value.get("key", "")) == "boss":
    boss_rooms += 1
    check(str(value.get("boss_content_id", "")) == "boss_monitor002", "generated identity seed=%d" % seed_value)
    check(value.get("boss_reinforcement_plan", {}) == expected.boss_reinforcement_plan, "generated reinforcement seed=%d" % seed_value)
    check(value.get("spawn_placements", []) == expected.spawn_placements and value.get("encounter", {}) == expected.encounter, "generated three waves seed=%d" % seed_value)
  check(boss_rooms == 1, "exactly one boss room seed=%d" % seed_value)
  var chosen = preload("res://src/map/EgtFlowAssembler.gd").pick_flow(LOADER.load_flows("expedition_03"), seed_value ^ absi("expedition_03".hash()))
  flows[str(chosen.get("flow_id", ""))] = true
 check(flows.size() == 6, "all six random flow skeletons covered")
 print("MONITOR03_GENERATION checks=", checks, " flows=", flows)
 tower = load("res://scenes/ExpeditionLevel03_3D.tscn").instantiate()
 tower.test_mode = true
 tower.run_seed_override = 77003244
 add_child(tower)
 await get_tree().process_frame
 await get_tree().physics_frame
 for config in tower._map_fate_triggers._triggers:
  config.enabled = false
 room = tower._room_by_id.get("boss") as DungeonRoom3D
 check(room != null, "formal scene has boss room")
 if room == null:
  await finish()
  return
 room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
 room.ensure_shell_built()
 room.ensure_detail_built()
 await get_tree().physics_frame
 check(str(room.get_meta("boss_content_id", "")) == "boss_monitor002", "formal room identity")
 check(enemies().is_empty(), "no premature boss before room entry")
 check(room.boss_reinforcement_spawn_markers().size() == 10, "ten reinforcement markers")
 tower.room_cleared.connect(func(value: DungeonRoom3D):
  if value == room: clear_count += 1)
 tower.player.global_position = room.global_position + Vector3(0, 0.5, 12)
 tower.player.set_physics_process(false)
 tower._on_room_entered(room)
 var spawn_deadline := Time.get_ticks_msec() + 10000
 while enemies().is_empty() and not room.cleared and Time.get_ticks_msec() < spawn_deadline:
  await get_tree().process_frame
 print("MONITOR03_ROOM ", room.spawn_placements, " encounter=", room.encounter, " waves=", tower._room_wave_totals.get(room.room_id, 0))
 check(int(tower._room_wave_totals.get(room.room_id, 0)) == 3, "three authored waves")
 var bosses: Array[Enemy3D] = []
 for value in enemies():
  if str(value.enemy_data.get("boss_content_id", "")) == "boss_monitor002": bosses.append(value)
 check(bosses.size() == 1, "exactly one monitor in first wave")
 check(tower._room_is_sealed(room.room_id), "entry seals combat room")
 if bosses.is_empty():
  await finish()
  return
 var boss := bosses[0]
 boss.set_physics_process(false)
 check(boss.max_hp == 32000, "03 boss HP still 32000 (01 lowered to 18000 on 2026-11-08, not synced)")
 check(boss.monitor_combat != null and boss.avatar._formal_boss_root is MonitorBossPresentation, "formal model and combat controller")
 check(boss.global_position.distance_to(room.boss_spawn_position_world()) < 0.2, "boss at translated arena center")
 check(boss.boss_phase_changed.is_connected(tower._on_boss_phase_changed), "phase events connected")
 check(boss.boss_activation_completed.is_connected(tower._on_boss_activation_completed), "activation connected to HUD/reinforcements")
 tower.player.global_position = boss.global_position + Vector3(10.1, 0, 0)
 boss._physics_process(0.25)
 check(not boss.monitor_combat.activation_started, "outside ten meters stays dormant")
 tower.player.global_position = boss.global_position + Vector3(9.9, 0, 0)
 boss._physics_process(0.25)
 check(boss.monitor_combat.activation_started and not boss.monitor_combat.activation_completed, "ten meters starts activation")
 check(not tower._boss_panel.visible, "HUD hidden during activation")
 boss._physics_process(6.5)
 check(boss.monitor_combat.activation_completed and tower._boss_panel.visible, "activation completes and shows HUD")
 if OS.get_cmdline_user_args().has("--visual"):
  var camera = tower.player.camera
  camera.global_position = boss.global_position + Vector3(7, 11, 12)
  camera.look_at(boss.global_position + Vector3(0, 1, 0), Vector3.UP)
  await get_tree().process_frame
  await RenderingServer.frame_post_draw
  var output := OS.get_environment("SHELLSTORM_PROBE_OUTPUT")
  check(not output.is_empty(), "visual output path configured")
  if not output.is_empty():
   var image = get_viewport().get_texture().get_image()
   check(image.save_png(output.path_join("monitor03.png")) == OK, "native boss screenshot saved")

 var reinforcement_state: Dictionary = tower._boss_reinforcement_states.get(room.room_id, {})
 var until_first := 10.0 - float(reinforcement_state.get("elapsed", 0.0))
 check(until_first > 0.01, "activation delay remains before first reinforcement")
 tower._tick_boss_reinforcements(maxf(0.0, until_first - 0.01))
 check(tower._boss_reinforcement_alive(room.room_id) == 0, "no reinforcement before ten second delay")
 tower._tick_boss_reinforcements(0.02)
 check(tower._boss_reinforcement_alive(room.room_id) == 3, "first round has three reinforcements")
 tower._tick_boss_reinforcements(5.66)
 check(tower._boss_reinforcement_alive(room.room_id) == 7, "second round adds four after shorter interval")
 boss.take_damage(int(ceil(boss.max_hp * 0.35)))
 check(boss.boss_phase == 2, "66 percent threshold enters phase two")
 boss.take_damage(int(ceil(boss.max_hp * 0.34)))
 check(boss.boss_phase == 3, "33 percent threshold enters phase three")
 boss.take_damage(1000000)
 check(boss.ai_state == "dead" and tower.is_room_boss_defeated(room.room_id), "formal death and boss defeat recorded")
 check(not room.cleared, "boss death does not skip followers/waves")
 var alive_before := tower._boss_reinforcement_alive(room.room_id)
 tower._tick_boss_reinforcements(30)
 check(tower._boss_reinforcement_alive(room.room_id) == alive_before, "boss death stops further reinforcements")
 var deadline := Time.get_ticks_msec() + 25000
 while not room.cleared and Time.get_ticks_msec() < deadline:
  for enemy in enemies(): enemy.take_damage(1000000)
  await get_tree().create_timer(0.1).timeout
 check(room.cleared and clear_count == 1, "all three waves clear exactly once")
 check(int(tower._alive_by_room.get(room.room_id, -1)) == 0, "alive account reaches zero")
 check(not tower._room_is_sealed(room.room_id), "clear unseals room")
 check(tower._boss_descent_key_count == 0 and not tower._conditional_extractions.has("BOSS_KILL"), "no tower descent or extra boss extraction")
 check(tower._conditional_extractions.get("STANDARD") is ExtractionBeacon3D, "standard extraction preserved")
 tower._on_room_entered(room)
 await get_tree().process_frame
 check(enemies().is_empty() and clear_count == 1, "reentry cannot respawn/reward again")
 await finish()

func finish() -> void:
 print("MONITOR03_REPORT ", JSON.stringify({"checks": checks, "failures": failures}))
 if is_instance_valid(tower): tower.queue_free()
 await get_tree().process_frame
 if failures.is_empty(): print("EXPEDITION03_MONITOR_BOSS_FLOW_OK")
 get_tree().quit(0 if failures.is_empty() else 1)
