extends SceneTree
## 独立验收：频道管理者替换 room_09 异常信号终端后的完整事件链。

const ENCOUNTER = preload("res://assets/art/characters/npc/channel_manager/runtime/channel_manager_encounter.gd")
const ROOM_LAYOUT = preload("res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_09_static_layout.tscn")
var errors: Array[String] = []
var checks := 0
var encounter: Node
var room: Node3D
var player: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		printerr(message)

func wait_seconds(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await process_frame
		left -= 1.0 / 60.0

func _run() -> void:
	room = ROOM_LAYOUT.instantiate() as Node3D
	room.name = "f00_room_09"
	root.add_child(room)
	player = Node3D.new()
	player.name = "MockPlayer"
	room.add_child(player)
	player.position = Vector3(0.0, 0.0, -2.2)
	encounter = ENCOUNTER.new()
	encounter.configure(null, room, player)
	await process_frame
	check(encounter.get_snapshot().npc_state == "sleep", "NPC starts in sleep")
	check(encounter.get_snapshot().started == false, "first conversation has not started")
	await encounter.interact()
	await wait_seconds(0.2)
	check(encounter.get_snapshot().started, "first interaction starts encounter")
	# Dialogue auto-advances its first exchange; wait for the first choice row.
	await wait_seconds(7.5)
	check(encounter.get_snapshot().npc_state == "active_idle", "first conversation activates NPC and returns to active idle")
	check(encounter.get_snapshot().started and not encounter.get_snapshot().paid, "first conversation exposes unpaid branch")
	check(root.get_node_or_null("DialogueUI") != null, "DialogueUI autoload exists")
	var game_manager := root.get_node_or_null("GameManager")
	check(game_manager != null, "GameManager autoload exists")
	game_manager.set("currency", 2000)
	game_manager.emit_signal("currency_changed", 2000)
	await encounter._on_pay_pressed()
	check(int(game_manager.get("currency")) == 1000, "payment uses 1000 run currency")
	check(encounter.get_snapshot().paid, "paid state persists")
	check(encounter.get_snapshot().portal_result in ["识别", "监听", "中继"], "skill result is one of three cards")
	await wait_seconds(1.8)
	check(encounter.get_snapshot().portal_open, "wall portal finishes opening")
	check(encounter.get_snapshot().portal_result in ["识别", "监听", "中继"], "portal preserves the skill result")
	await encounter.interact()
	await wait_seconds(2.5)
	check(encounter.get_snapshot().searched == false, "information branch is initially not used")
	await encounter._on_information_pressed()
	check(encounter.get_snapshot().searched, "information branch reveals additional search dialogue")
	print("CHANNEL_MANAGER_EXPEDITION_EVENT_TESTS ", checks, " checks; ", errors.size(), " failures")
	quit(0 if errors.is_empty() else 1)
