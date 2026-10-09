extends Node3D
## 98F设施独立加载、真实房间装配、通道碰撞与渲染验收。
const OUT := "res://outputs/block00_story_rooms_20261009/"
const MANIFEST := "res://assets/art/environments/master_office_3d/source/env_block00_story_rooms/export/v001/import_manifest.json"
var errors: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)

func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for c in node.get_children():
		result.append_array(meshes(c))
	return result

func _ready() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for d in manifest["components"]:
		var packed := load("res://" + str(d["prefab_path"])) as PackedScene
		check(packed != null, "prefab_load:" + str(d["slug"]))
		if packed == null: continue
		var node := packed.instantiate() as Node3D
		add_child(node)
		check(node.scale.is_equal_approx(Vector3.ONE), "unit_scale:" + str(d["slug"]))
		var count := 0
		var bounds := AABB()
		var first := true
		for mi in meshes(node):
			var box := node.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				check(mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path == "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png", "palette:" + str(d["slug"]))
				if mat != null: check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and not mat.texture_repeat, "sampling:" + str(d["slug"]))
				var arrays := mi.mesh.surface_get_arrays(s)
				count += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		check(count == int(d["triangles_after"]), "triangles:" + str(d["slug"]))
		var sz: Array = d["bounds_size_m"]
		check(bounds.size.distance_to(Vector3(sz[0], sz[2], sz[1])) < 0.01, "bounds:" + str(d["slug"]))
		node.free()
	var shell := Block00MasterOfficeLayout3D.load_manifest()
	var center := {"master_office": Vector2(-32.5,0),"meeting_room": Vector2(-5,2.5),"corridor": Vector2(17.5,0),"lobby":Vector2(27.5,2.5)}
	var dims := {"master_office":Vector2(15,20),"meeting_room":Vector2(40,15),"corridor":Vector2(5,20),"lobby":Vector2(15,15)}
	var rooms: Dictionary = {}
	for d in manifest["rooms"]:
		var id := str(d["room_id"])
		var room := DungeonRoom3D.new()
		var rid := ""
		for binding in Block00MasterOfficeLayout3D.ROOM_BINDINGS:
			if str(binding["authored_room_id"]) == id: rid = str(binding["id"])
		room.configure({"room_id":rid,"room_type":"COMBAT","custom_dimensions":dims[id],"tower_module_shell":true,"authored_layout_shell":true,"authored_layout_asset_id":Block00MasterOfficeLayout3D.LAYOUT_ASSET_ID,"authored_layout_room_id":id,"authored_layout_peaceful":true,"search_facilities_enabled":false,"authored_layout_instances":Block00MasterOfficeLayout3D.room_shell_instances(shell,id,center[id])})
		room.position=Vector3(center[id].x,0,-center[id].y+5)
		add_child(room)
		room.ensure_shell_built()
		var art := room.get_node_or_null("AuthoredFacilities")
		check(art != null and art.get_child_count() == int(d["instances"]), "room_count:"+id)
		check(int(room.get_meta("authored_layout_floor_tile_count",0)) == {"master_office":12,"meeting_room":24,"corridor":4,"lobby":9}[id],"existing_floor_count:"+id)
		rooms[id]=room
	var corridor: DungeonRoom3D = rooms["corridor"]
	var office: DungeonRoom3D = rooms["master_office"]
	var sofa := office.get_node("AuthoredFacilities/sofa_001") as Node3D
	check(sofa.scale.distance_to(Vector3(.7,.7,.7)) < .00001,"sofa_user_scale70")
	var rug := office.get_node("AuthoredFacilities/rug_002") as Node3D
	var rug_top := -INF
	for mi in meshes(rug):
		var box := office.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		rug_top=maxf(rug_top,box.end.y)
	check(absf(rug_top-.091)<.001,"rug_surface_8mm_above_visual_floor")
	corridor.ensure_detail_built()
	check(corridor.find_children("*","RoomLightSwitch3D",true,false).is_empty(),"third_room_switch_removed")
	var lobby: DungeonRoom3D=rooms["lobby"]
	var mural:=lobby.get_node("AuthoredFacilities/constructivist_mural_014") as Node3D
	var mural_min:=INF
	for mi in meshes(mural):
		var local_transform:=lobby.global_transform.affine_inverse()*mi.global_transform
		for surface in mi.mesh.get_surface_count():
			var vertices: PackedVector3Array=mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices: mural_min=minf(mural_min,(local_transform*vertex).y)
	print("MURAL_LOWEST=",mural_min)
	check(absf(mural_min-.091)<.001,"fallen_mural_ground_contact")
	check(absf(mural.basis.y.z)>.3,"fallen_mural_leans")
	check(corridor.get_node_or_null("AuthoredLayoutArtRoot/DOORWALL_east_xp20_p2.5") == null,"removed_door_wall")
	corridor.call("_build_door","east","floor_01_entry",dims["corridor"])
	check(corridor.get_door_node("east") == null,"removed_door_leaf")
	await get_tree().physics_frame
	# Doorway free across full 5m slot; meeting central strip tested by physical rays.
	var space := get_world_3d().direct_space_state
	for z in [0.5,1.5,2.5,3.5,4.5]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(19,1,z),Vector3(21,1,z),1)
		check(space.intersect_ray(q).is_empty(),"passage_ray:"+str(z))
	for z in [0.0,2.5,5.0]:
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-24,1,z),Vector3(14,1,z),1)).is_empty(),"meeting_clear:"+str(z))
	var env := WorldEnvironment.new()
	env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.13,.15,.19)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.7,.78,.9);env.environment.ambient_light_energy=.8
	add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-30,0);sun.light_energy=.85;sun.shadow_enabled=true;add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=48;camera.far=300;add_child(camera);camera.current=true
	# Cutaway only for screenshots; assertions above use complete live geometry/collision.
	for room in rooms.values():
		for piece in room.get_node("AuthoredLayoutArtRoot").get_children():
			if piece is Node3D and str(piece.get_meta("tower_wall_direction","")) in ["south","east"]:
				piece.visible=false
			if piece is Node3D and piece.has_meta("tower_wall_corner") and (piece.position.z > 0 or piece.position.x > 0):
				piece.visible=false
	if DisplayServer.get_name() != "headless":
		for shot in [["overview",Vector3(20,58,70),Vector3(-2,0,3),48.0],["office",Vector3(-13,28,35),Vector3(-32,3,4),24.0],["meeting",Vector3(3,33,42),Vector3(-5,1,2),27.0],["passage",Vector3(43,28,36),Vector3(23,2,3),23.0]]:
			camera.position=shot[1];camera.look_at(shot[2]);camera.size=shot[3]
			for frame in 5: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT+"godot_"+str(shot[0])+".png")
	if DisplayServer.get_name() == "headless":
		for room in rooms.values(): room.free()
		var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
		tower.test_mode=true
		tower.run_seed_override=990098
		add_child(tower)
		for frame in 6: await get_tree().process_frame
		check(tower.generate_through_floor_for_test(98),"full_tower_generate98")
		for frame in 6: await get_tree().physics_frame
		var actual: Dictionary=tower.get("_room_by_id")
		for binding in Block00MasterOfficeLayout3D.ROOM_BINDINGS:
			var room: DungeonRoom3D=actual.get(str(binding["id"]))
			check(room != null,"tower_room:"+str(binding["id"]))
			if room == null: continue
			room.ensure_shell_built()
			check(room.get_node_or_null("AuthoredFacilities") != null,"tower_facilities:"+str(binding["id"]))
			check(is_equal_approx(room.global_position.y,-24),"tower_floor98:"+str(binding["id"]))
		var third: DungeonRoom3D=actual.get("floor_01_hub")
		var fourth: DungeonRoom3D=actual.get("floor_01_entry")
		third.ensure_detail_built()
		check(third.find_children("*","RoomLightSwitch3D",true,false).is_empty(),"tower_third_room_no_switch")
		check(third.get_door_node("east")==null and fourth.get_door_node("west")==null,"tower_removed_door_both_sides")
		var edges: Dictionary=tower.get("_open_edges")
		check(bool(edges.get("floor_01_entry|floor_01_hub",false)),"tower_open_edge")
		edges["floor_01_entry|floor_01_hub"]=false
		tower.call("_refresh_edge_visuals","floor_01_entry","floor_01_hub",false)
		check(bool(edges.get("floor_01_entry|floor_01_hub",false)),"old_save_cannot_close_passage")
		var live_space:=third.get_world_3d().direct_space_state
		check(live_space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(19,-23,2.5),Vector3(21,-23,2.5),1)).is_empty(),"tower_passage_physics")
	var f:=FileAccess.open(OUT+("facility_verification.json" if DisplayServer.get_name()=="headless" else "facility_render_verification.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"errors":errors,"passed":errors.is_empty(),"renderer":RenderingServer.get_current_rendering_method()},"  "));f.close()
	print("BLOCK00_FACILITIES_OK" if errors.is_empty() else "BLOCK00_FACILITIES_FAILED", " checks=",checks," errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
