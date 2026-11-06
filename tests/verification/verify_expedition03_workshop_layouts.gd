extends Node3D
## Isolate APPDATA before starting Godot. No native application automation.
const DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"
const CONTRACT := preload("res://src/world3d/RoomArtLayoutContract.gd")
const FILES := ["storage_40x30_ef3f827636f7_3e5f15", "merchant_30x40_f2a374f5465f_d77c54", "combat_45x40_6351962d84c2_007418", "scavenge_40x30_a0eceb3887c9_23641e", "extraction_25x25_6f808c2e0839_ea81ed", "trap_40x30_29d67dbb9bda_d2426a", "merchant_20x15_327ac0ee6b3c_d77c54"]
var _checks := 0
var _fails := 0
var _out := ""
var _report := {}

func _ready() -> void:
	_out = OS.get_environment("SS_WORKSHOP_QA_DIR").replace("\\", "/")
	var user_dir := OS.get_user_data_dir().replace("\\", "/")
	var runner_name := OS.get_environment("SHELLSTORM_VERIFICATION_USER_DIR_NAME")
	var runner_isolated := runner_name.begins_with("ShellStorm2Verification_") and bool(ProjectSettings.get_setting("application/config/use_custom_user_dir",false)) and str(ProjectSettings.get_setting("application/config/custom_user_dir_name","")) == runner_name
	if _out.is_empty() and runner_isolated:
		_out = user_dir.path_join("workshop_qa")
		DirAccess.make_dir_recursive_absolute(_out)
	if not runner_isolated and (_out.is_empty() or not user_dir.begins_with(_out + "/userdata/")):
		push_error("Workshop QA requires APPDATA isolation before Autoload")
		get_tree().quit(1)
		return
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	var render := OS.get_environment("SS_WORKSHOP_RENDER") == "1"
	for file in FILES:
		var source := (load(DIR + file + ".tscn") as PackedScene).instantiate() as Node3D
		var dim := CONTRACT.dimensions(source)
		var type := str((source.get_meta("runtime_room_geometry") as Dictionary).type)
		var ports := CONTRACT.candidate_ports(dim)
		_check(not FileAccess.get_file_as_string(DIR + file + ".tscn").contains("script = null"), file + " inherited scripts never removed")
		var interior := 0
		for node in source.find_children("*", "Node3D", true, false):
			if bool(node.get_meta("authored_interior_structure", false)) and not bool(node.get_meta("port_clearance_candidate",false)): interior += 1
		if render:
			source.position = Vector3(-1000, 0, 0)
			add_child(source)
			await _capture(source, dim, file + "_source")
			source.queue_free()
		else:
			source.free()
		var room := DungeonRoom3D.new()
		room.configure({"room_id":"workshop_qa", "room_type":type, "custom_dimensions":dim,
			"static_layout_scene_path":DIR + file + ".tscn", "procedural_shell":true,
			"art_layer_keep_structure":true, "connection_ports":ports})
		add_child(room)
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		await _settle(5)
		var art := room.get_node("AuthoredLayoutArtRoot") as Node3D
		var live_interior := 0
		var interactive := 0
		for node in art.find_children("*", "Node3D", true, false):
			if bool(node.get_meta("authored_interior_structure", false)) and not bool(node.get_meta("port_clearance_candidate",false)): live_interior += 1
			if node is ReactiveProp3D:
				interactive += 1
				_check(node._receiver != null and node._receiver.collision_layer & 4 != 0, file + " reactive hit receiver " + str(node.name))
				var active := 0
				for body in node.find_children("*", "StaticBody3D", true, false):
					if body.collision_layer & 5 != 0: active += 1
				_check(active == 1, file + " one collider owner " + str(node.name))
		_check(live_interior == interior, file + " saved interior walls survive shell rebuild")
		_check(bool(room.get_meta("art_layer_floor_complete", false)), file + " full floor coverage")
		room._collect_spawn_blockers()
		var boxes := room.get("_spawn_blockers") as Array
		var grid := _walk_grid(dim, boxes)
		var starts := []
		for port in ports:
			var at := _door_point(port, dim)
			var cell := Vector2i(roundi(at.x * 4), roundi(at.y * 4))
			_check(grid.has(cell), file + " door approach clear " + str(port))
			if grid.has(cell): starts.append(cell)
		var reached := _flood(grid, [starts[0]] if not starts.is_empty() else [])
		for cell in starts:
			_check(reached.has(cell), file + " real door approaches connected " + str(cell))
		if file.begins_with("storage"):
			_check(not reached.has(Vector2i.ZERO), file + " ring has no central shortcut")
		if file.begins_with("combat_45"):
			for end in [Vector2(18,0), Vector2(-18,0), Vector2(0,18)]:
				_check(_segment_blocked(Vector2.ZERO,end,boxes), "gallery central cache has one entrance, no through shortcut")
		if file.begins_with("merchant_30"):
			for at in [Vector2(0,0), Vector2(0,10), Vector2(-12,-3), Vector2(12,-3),Vector2(0,-3)]:
				_check(reached.has(Vector2i(roundi(at.x*4),roundi(at.y*4))), "D central cross and outer routes " + str(at))
			_check_cabinet_faces(art)
			for at in [Vector2(-8,-8),Vector2(8,-8),Vector2(-7,4),Vector2(7,4)]:
				_check(not reached.has(Vector2i(roundi(at.x*4),roundi(at.y*4))),"D four furnishing blocks closed " + str(at))
		if file.begins_with("scavenge"):
			for at in [Vector2(0,-8),Vector2(0,0),Vector2(0,8),Vector2(-10,0),Vector2(10,0)]:
				_check(reached.has(Vector2i(roundi(at.x*4),roundi(at.y*4))), "B centre and side dead-end reachable " + str(at))
			for x in [-12.0,12.0]:
				_check(_segment_blocked(Vector2(x,0),Vector2(x,-6),boxes), "B side branch has no onward route")
		if file.begins_with("extraction"):
			_check(reached.has(Vector2i.ZERO), "extraction centre remains reachable")
		if file.begins_with("combat_45"):
			_check(room.get_treasure_chests().size() == 1, "gallery has exactly one authored chest")
			var chest := room.find_chest_by_id("gallery_cache")
			_check(chest != null and chest.open_requested.is_connected(room._on_chest_open_requested), "gallery chest uses real room opening protocol")
			var gate := _prop_with_meta(art, "cache_entrance")
			_check(gate != null, "gallery cache entrance has interactive shelf")
			if render: await _capture(room,dim,file + "_runtime")
			if gate != null:
				gate._receiver.call("take_damage", 9999, false, Vector3.BACK)
				await _settle(65)
				_check(gate.state == "fallen" and gate.books_dropped == 8, "gallery entrance shelf topples and releases books")
				room._collect_spawn_blockers()
				var opened := _walk_grid(dim, room.get("_spawn_blockers"))
				var after := _flood(opened, [starts[0]])
				_check(after.has(Vector2i(0,-8)), "gallery chest reachable after shelf topples")
				room.capture_reactive_prop_states()
				_check(room.get_persistent_detail_state("reactive_props").has(str(gate.get_meta("reactive_prop_id"))), "gallery fallen shelf persists")
				if chest != null:
					chest.commit_opened()
					_check(bool(room.get_persistent_detail_state("treasure_chests").get("gallery_cache",{}).get("opened",false)), "gallery chest open state persists")
		else:
			var shelf := _first_shelf(art)
			if shelf != null:
				shelf._receiver.call("take_damage",1,false,Vector3.RIGHT)
				await _settle(3)
				_check(shelf.hit_count == 1 and shelf.current_hp == shelf.max_hp-1, file + " shelf hit responds")
			if render: await _capture(room,dim,file + "_runtime")
		_report[file] = {"interior_walls":live_interior,"interactive":interactive,"door_cases":ports.size(),"reachable_cells":reached.size(),"blockers":_boxes_json(boxes)}
		print("WORKSHOP_ROOM ",file," interactive=",interactive," walls=",live_interior," doors=",ports.size())
		room.queue_free()
		await _settle(3)
		if OS.get_environment("SS_WORKSHOP_PORT_MATRIX") == "1" and (file.begins_with("merchant_30") or file.begins_with("scavenge") or file.begins_with("extraction")):
			await _check_port_matrix(file,dim,type,ports)
	var output := FileAccess.open(_out.path_join("runtime_report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(_report,"\t"));output.close()
	print("EXP03_WORKSHOP_LAYOUTS %s checks=%d failures=%d" % ["OK" if _fails==0 else "FAIL",_checks,_fails])
	get_tree().quit(0 if _fails==0 else 1)

func _check_port_matrix(file:String,dim:Vector2,type:String,ports:Array) -> void:
	var anchor:Dictionary=ports[0]
	var variants:=[]
	for port in ports:
		var actual: Array = [anchor] if port==anchor else [anchor,port]
		var room:=DungeonRoom3D.new()
		room.configure({"room_id":"workshop_port_qa","room_type":type,"custom_dimensions":dim,
			"static_layout_scene_path":DIR+file+".tscn","procedural_shell":true,"art_layer_keep_structure":true,"connection_ports":actual})
		add_child(room)
		room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
		await _settle(3)
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		await _settle(5)
		room._collect_spawn_blockers()
		var grid:=_walk_grid(dim,room.get("_spawn_blockers"))
		variants.append({"ports":actual,"blockers":_boxes_json(room.get("_spawn_blockers"))})
		var a:=_door_point(anchor,dim);var b:=_door_point(port,dim)
		var start:=Vector2i(roundi(a.x*4),roundi(a.y*4));var end:=Vector2i(roundi(b.x*4),roundi(b.y*4))
		_check(grid.has(start) and grid.has(end) and _flood(grid,[start]).has(end),file+" individual door variant connects "+str(port))
		_check(int(room.get_meta("furnishing_navigation_refresh_count",0))>0,file+" delayed detail activation refreshes actual navigation")
		room.queue_free();await _settle(2)
	print("WORKSHOP_PORT_MATRIX ",file," cases=",ports.size())
	_report[file+"_variants"]=variants

func _walk_grid(dim: Vector2, boxes: Array) -> Dictionary:
	var grid := {}
	for x in range(roundi(-dim.x*2)+2,roundi(dim.x*2)-1):
		for z in range(roundi(-dim.y*2)+2,roundi(dim.y*2)-1):
			var point := Vector2(x*.25,z*.25)
			var free := true
			for box in boxes:
				if Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(.42).has_point(point):
					free=false;break
			if free:grid[Vector2i(x,z)]=true
	return grid

func _flood(grid:Dictionary, starts:Array) -> Dictionary:
	var seen := {};var queue := starts.duplicate();var cursor:=0
	for at in starts:seen[at]=true
	while cursor<queue.size():
		var at:Vector2i=queue[cursor];cursor+=1
		for delta in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var next:Vector2i=at+delta
			if grid.has(next) and not seen.has(next):seen[next]=true;queue.append(next)
	return seen

func _door_point(port:Dictionary,dim:Vector2) -> Vector2:
	var lane:=float(port.lane_m)
	match str(port.side):
		"north":return Vector2(lane,-dim.y*.5+1.25)
		"south":return Vector2(lane,dim.y*.5-1.25)
		"west":return Vector2(-dim.x*.5+1.25,lane)
	return Vector2(dim.x*.5-1.25,lane)

func _segment_blocked(a:Vector2,b:Vector2,boxes:Array) -> bool:
	for step in 60:
		var at:=a.lerp(b,float(step)/59)
		for box in boxes:
			if Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(.42).has_point(at):return true
	return false

func _check_cabinet_faces(art:Node3D) -> void:
	var layout:=art.get_node("ArtComponents/WorkshopLayout")
	var rectangles:=art.get_meta("workshop_block_regions") as Array
	for node in layout.get_children():
		if not str(node.scene_file_path).contains("/manor_wardrobe/") or bool(node.get_meta("port_clearance_candidate",false)):continue
		var at:Vector3=node.position
		var rect: Array = rectangles[int(node.get_meta("workshop_region_index"))]
		var center:=Vector2((float(rect[0])+float(rect[2]))*.5,(float(rect[1])+float(rect[3]))*.5)
		var front:Vector3=node.basis.z.normalized()
		_check(Vector2(front.x,front.z).dot(Vector2(at.x,at.z)-center)>0, "shop cupboard doors face out " + str(node.name))

func _prop_with_meta(root:Node3D,key:String) -> ReactiveProp3D:
	for node in root.find_children("*","",true,false):
		if node is ReactiveProp3D and bool(node.get_meta(key,false)):return node
	return null

func _first_shelf(root:Node3D) -> ReactiveProp3D:
	for node in root.find_children("*","",true,false):
		if node is ReactiveProp3D and node.prop_kind=="bookcase":return node
	return null

func _boxes_json(boxes:Array) -> Array:
	var result:=[]
	for box in boxes:result.append([box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z])
	return result

func _capture(target:Node3D,dim:Vector2,file:String) -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1600,1100);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var saved_parent:=target.get_parent();var saved_transform:=target.transform
	target.reparent(viewport,false);target.transform=Transform3D.IDENTITY
	var camera:=Camera3D.new();viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=maxf(dim.x,dim.y)*1.25
	camera.position=Vector3(7,45,28);camera.look_at(Vector3.ZERO);camera.make_current()
	var env:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(.055,.07,.085)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color(.78,.83,.92);settings.ambient_light_energy=.85
	env.environment=settings;viewport.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-65,-25,0);light.light_energy=1.7;light.shadow_enabled=true;viewport.add_child(light)
	await _settle(4);await RenderingServer.frame_post_draw
	var img:=viewport.get_texture().get_image()
	_check(img!=null and img.save_png(_out.path_join(file+".png"))==OK,"real-renderer capture "+file)
	target.reparent(saved_parent,false);target.transform=saved_transform;viewport.queue_free()

func _settle(frames:int) -> void:
	for i in frames:await get_tree().physics_frame;await get_tree().process_frame

func _check(ok:bool,message:String) -> void:
	_checks+=1
	if not ok:_fails+=1;printerr("WORKSHOP_FAIL "+message)
