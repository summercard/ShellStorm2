extends Node
var root:Window
const WORK := "../ShellStorm2-work/outputs/boss_room02_import/"
var failures:Array[String]=[]
var checks:=0
func _ready() -> void:
	root=get_tree().root
	call_deferred("probe")
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:failures.append(text);push_error(text)
func probe() -> void:
	var normalized:=LevelPlanLoader.normalize_floor("99",0)
	var bad_height:Dictionary=normalized.duplicate(true)
	bad_height.rooms[2].connection_ports[0].height_m=11.0
	var errors:=LevelPlanValidator.validate_normalized("99",0,bad_height,LevelPlanLoader.load_level_plan("99").generation_policy,LevelPlanLoader.load_room_templates("99"))
	check(errors.any(func(e):return str(e).begins_with("connection_port_height_gap")),"Misaligned high entrance rejected")
	var bad_grid:Dictionary=normalized.duplicate(true);bad_grid.rooms[0].center.x=0.0
	errors=LevelPlanValidator.validate_normalized("99",0,bad_grid,LevelPlanLoader.load_level_plan("99").generation_policy,LevelPlanLoader.load_room_templates("99"))
	check(errors.any(func(e):return str(e).begins_with("room_center_not_snapped:entry")),"Ordinary grid room remains constrained")
	check(FloorPlanGenerator._data_driven_layout_id("99",0,normalized,"authored",20260919)!=FloorPlanGenerator._data_driven_layout_id("99",0,bad_height,"authored",20260919),"High port elevation participates in geometry fingerprint")
	var tower:TowerDescent3D=(load("res://scenes/ExpeditionLevel99_3D.tscn") as PackedScene).instantiate();tower.test_mode=true;tower.run_seed_override=20260919;root.add_child(tower)
	await get_tree().process_frame;await get_tree().physics_frame
	for id in ["start","room_01","boss","extraction"]:
		var ob:DungeonRoom3D=tower._room_by_id[id];ob.ensure_shell_built();ob.ensure_detail_built();print("ROOM99 ",id," position=",ob.global_position," dimensions=",ob.get_dimensions()," ports=",ob.connection_ports," doors=",ob._door_nodes.keys()," owners=",ob.door_endpoint_owners)
	var room:DungeonRoom3D=tower._room_by_id["boss"]
	check(room.get_meta("static_layout_scene_loaded",false),"99 loads shared room02 static scene")
	check(room.get_dimensions()==Vector2(80,100),"99 room footprint")
	check(str(room.get_meta("boss_content_id",""))=="boss_monitor002","Boss identity retained")
	await get_tree().physics_frame;await get_tree().physics_frame
	var space:=root.get_world_3d().direct_space_state
	for local in [Vector3(0,0,-22.5),Vector3(-20,0,-22.5),Vector3(20,0,-22.5),Vector3(-38,0,-22.5),Vector3(38,0,-22.5)]:
		var p:=room.to_global(local);var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*2,1));check(not hit.is_empty(),"99 platform and bridge support at "+str(local));if not hit.is_empty():check(not str(hit.collider.name).begins_with("FloorSupport"),"Components uniquely support walk plane")
	var void_point:=room.to_global(Vector3(20,0,-40));var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(void_point+Vector3.UP,void_point-Vector3.UP*2,1));check(hit.is_empty(),"Stage slab removed from deep shaft")
	for x in [-39.0,39.0]:
		var upper_void:=room.to_global(Vector3(x,12,-40))
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(upper_void+Vector3.UP,upper_void-Vector3.UP,1)).is_empty(),"No rounded slab strip inside shaft "+str(x))
	var center:=room.get_node("BossSpawnCenter") as Marker3D;check(center.position==Vector3(0,0,-22.5),"Boss spawn on central platform")
	for marker in room.boss_reinforcement_spawn_markers():
		var p:Vector3=marker.global_position;check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(p,p-Vector3.UP*5,1)).is_empty(),"Reinforcement has platform underneath")
	var nav:=room.find_child("RuntimeNavigationRegion3D",true,false) as NavigationRegion3D;check(nav!=null and nav.navigation_mesh.get_polygon_count()==9,"Navigation includes high stairs")
	var preceding:DungeonRoom3D=tower._room_by_id["room_01"]
	check(room.global_position.is_equal_approx(Vector3(2.5,-12,-95)),"Boss preserves preceding north route")
	check(tower._room_door_world_position(preceding,"north").is_equal_approx(tower._room_door_world_position(room,"south")),"High entrance joins previous rear in all axes")
	check(room.get_door_node("south")==preceding.get_door_node("north"),"One shared high entrance door")
	var start:DungeonRoom3D=tower._room_by_id["start"]
	check(start.global_position.is_equal_approx(Vector3(2.5,0,2.5)),"Entry original position retained")
	var entrydoor:=start.get_door_node("north")
	var closedpoint:=entrydoor.global_position+Vector3.UP
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(closedpoint+Vector3(0,0,1),closedpoint-Vector3(0,0,1),1)).is_empty(),"Closed entry gate blocks passage before interaction")
	tower.player.global_position=entrydoor.global_position+Vector3(0,0.1,1.4)
	tower._on_room_entered(start)
	var interaction:=tower.get_interaction_candidate(tower.player)
	check(str(interaction.get("target_room_id",""))=="room_01","Entry E candidate resolves north door")
	check(tower.perform_interaction(tower.player,interaction),"Entry opens through normal E interaction route")
	await get_tree().create_timer(1.0).timeout
	await get_tree().physics_frame
	var doorway:=entrydoor.global_position+Vector3.UP
	var gatehit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(doorway+Vector3(0,0,1),doorway-Vector3(0,0,1),1))
	check(gatehit.is_empty(),"Entry doorway collision clears")
	for i in range(101):
		var z:=lerpf(-9.5,49.5,float(i)/100.0)
		var y:=clampf((z+10.0)/50.0,0.0,1.0)*12.0
		var p:=room.to_global(Vector3(0,y,z))
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP,p-Vector3.UP,1)).is_empty(),"Stair support "+str(i))
		check(room.contains_world_position(p+Vector3.UP*0.2),"Actual stair belongs to Boss room "+str(i))
	var env:=tower.world_environment.environment
	tower._atmosphere.call("set_room_fog_profile",{},true)
	var ordinary_fog:=env.fog_density
	tower.player.global_position=room.to_global(Vector3(0,12.2,45))
	tower._refresh_physical_location_authority(true)
	check(tower._current_room_id=="boss","High landing automatically enters Boss without forced room event")
	check(tower._physical_floor_index()==0,"Internal descent remains in logical expedition floor")
	check(tower._is_runtime_restore_position_valid(room,tower.player.global_position),"High landing is valid saved player position")
	check(not tower._is_runtime_restore_position_valid(room,room.to_global(Vector3(20,0,-40))),"Empty shaft remains invalid saved player position")
	check(room.contains_world_position(tower._runtime_restore_fallback_position(room)),"Outdated saved position falls back onto real platform")
	tower._update_base_fog_transition(0.0,false)
	await get_tree().create_timer(2.3).timeout
	check(env.fog_density<ordinary_fog and is_equal_approx(env.fog_density,0.003),"Independent boss fog transition")
	check(is_equal_approx(float(env.get_meta("presentation_volumetric_fog_density",-1)),0.0002),"Boss volumetric profile retained on headless renderer")
	var boss_fog:=env.fog_density
	tower.player.global_position=start.global_position+Vector3.UP*0.1
	tower._on_room_entered(start)
	tower._update_base_fog_transition(0.0,false)
	await get_tree().create_timer(2.3).timeout
	check(is_equal_approx(env.fog_density,ordinary_fog),"Ordinary fog restored on exit")
	print("FOG99 ordinary=",ordinary_fog," boss=",boss_fog," restored=",env.fog_density)
	for side in ["south","east"]:
		var door:=room.get_door_node(side);check(door!=null,"Connected endpoint door "+side)
		if door:
			check(door.get_node("DoorPanel/ImportedDoorVisual").find_children("*","MeshInstance3D",true,false).size()>0,"Door imported leaves visible");door.set_open(true,true)
	await get_tree().physics_frame
	var extraction:DungeonRoom3D=tower._room_by_id["extraction"]
	check(extraction.global_position.is_equal_approx(Vector3(55,-12,-117.5)),"Lower east exit aligns")
	var p:=extraction.global_position
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP,p-Vector3.UP,1)).is_empty(),"Lower exit floor support")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*13,p+Vector3.UP*11,1)).is_empty(),"No old slab above lower exit")
	var stage:Node=tower._floor_stages[0];check((stage.get("authored_support_holes") as Array).size()==2,"Stage clears shaft and lower exit")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"room_id":"boss","level_id":"99","floor_holes":stage.get("authored_support_holes").size()};var f:=FileAccess.open(WORK+"level99_acceptance.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	if "--render" in OS.get_cmdline_user_args():
		tower.player.global_position=room.to_global(Vector3(0,12.2,45));tower._on_room_entered(room);tower._update_base_fog_transition(0.0,true)
		var cam:=Camera3D.new();root.add_child(cam);cam.current=true;cam.fov=58;cam.far=250;cam.position=room.to_global(Vector3(0,22,42.5));cam.look_at(room.to_global(Vector3(0,-1,-22.5)));root.size=Vector2i(1600,1000);root.msaa_3d=Viewport.MSAA_4X;tower.player.visible=false;await get_tree().process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(WORK+"level99_game.png");cam.free()
	tower.queue_free();await get_tree().process_frame;await get_tree().process_frame;print("BOSS_ROOM02_LEVEL99_", "OK" if failures.is_empty() else "FAILED"," checks=",checks);get_tree().quit(0 if failures.is_empty() else 1)
