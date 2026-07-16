extends Node
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var player: Node = get_tree().root.find_child("Player", true, false)
	var aim: Node = player.get_node_or_null("Aim")
	if aim: aim.set_process(false)
	print("[AIM] 准备跑 4 方向")
	await _test(player, Vector2(1, 0))
	await _test(player, Vector2(0, 1))
	await _test(player, Vector2(-1, 0))
	await _test(player, Vector2(0, -1))
	get_tree().quit()
func _test(player: Node, d: Vector2) -> void:
	player.set_aim_direction(d)
	await get_tree().create_timer(0.15).timeout
	var comps: Node = player.get_node_or_null("Components")
	var hand: Node = comps.get("hand") if comps else null
	var hand_anchor: Node = hand.find_child("WeaponAnchor", true, false) if hand else null
	var display: Node = player.get_node_or_null("WeaponAnchor/WeaponDisplay")
	var expected: float = d.normalized().angle()
	var hand_rot: float = (hand_anchor as Node2D).rotation if hand_anchor is Node2D else -99.0
	var display_rot: float = (display as Node2D).rotation if display else -99.0
	print("[AIM] d=%s: expected=%.3f, hand=%.3f, display=%.3f" % [d, expected, hand_rot, display_rot])
