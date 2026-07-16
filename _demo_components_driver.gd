extends Node
func _ready() -> void:
	await get_tree().process_frame
	_build_player()
	await get_tree().process_frame
	_dump_all()

func _build_player() -> void:
	var player: Node2D = Node2D.new()
	player.name = "Player"
	add_child(player)
	var old_body: Node2D = Node2D.new()
	old_body.name = "OldBody"
	player.add_child(old_body)
	var comps: CharacterComponents = CharacterComponents.new()
	comps.name = "Components"
	player.add_child(comps)
	comps.create_default_layout(NodePath(""), NodePath(""), NodePath(""))
	old_body.visible = false

func _dump_all() -> void:
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null:
		print("[DEMO] no player")
		get_tree().quit()
		return
	print("[DEMO] ===== Player 子节点 =====")
	for child in player.get_children():
		print("[DEMO]   direct child: %s (%s)" % [child.name, child.get_class()])
		for grand in child.get_children():
			print("[DEMO]     grandchild: %s (%s)" % [grand.name, grand.get_class()])
			for ggrand in grand.get_children():
				print("[DEMO]       ggrand: %s (%s)" % [ggrand.name, ggrand.get_class()])
				for gggrand in ggrand.get_children():
					print("[DEMO]         gggrand: %s (%s)" % [gggrand.name, gggrand.get_class()])
					for ggg in gggrand.get_children():
						print("[DEMO]           ggg: %s (%s)" % [ggg.name, ggg.get_class()])
	get_tree().quit()
