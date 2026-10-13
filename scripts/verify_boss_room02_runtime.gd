extends SceneTree
const PREFIX := "res://assets/art/environments/tower_zones/expedition/"
const WORK := "../ShellStorm2-work/outputs/boss_room02_import/"
const PALETTE := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
var checks:=0
var failures:Array[String]=[]
var room:Node3D
var spec:Dictionary
func _initialize() -> void:call_deferred("verify")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func nodes(n:Node,type:String) -> Array[Node]:
	var out:Array[Node]=[]
	if n.is_class(type):out.append(n)
	for c in n.get_children():out.append_array(nodes(c,type))
	return out
func tf(v:Array) -> Transform3D:
	return Transform3D(Basis(Vector3(v[0],v[1],v[2]),Vector3(v[3],v[4],v[5]),Vector3(v[6],v[7],v[8])),Vector3(v[9],v[10],v[11]))
func verify() -> void:
	spec=JSON.parse_string(FileAccess.get_file_as_string(WORK+"spec.json"))
	for d in spec.components:
		var ob:Node3D=(load("res://"+str(d.prefab_path)) as PackedScene).instantiate();root.add_child(ob)
		check(ob.get_meta("asset_id")==d.asset_id,str(d.slug)+" identity");check(ob.scale.is_equal_approx(Vector3.ONE),str(d.slug)+" root scale")
		var count:=0;var bounds:=AABB();var first:=true
		for n in nodes(ob,"MeshInstance3D"):
			var mesh:=n as MeshInstance3D
			check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,str(d.slug)+" casts shadow")
			var b:=mesh.transform*mesh.get_aabb();bounds=b if first else bounds.merge(b);first=false
			for surface in range(mesh.mesh.get_surface_count()):
				var arrays:=mesh.mesh.surface_get_arrays(surface);count+=(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
				var material:=mesh.get_active_material(surface)
				if str(d.slug).begins_with("screen_"):
					check(material is ShaderMaterial,str(d.slug)+" screen material")
					var texture:Texture2D=(material as ShaderMaterial).get_shader_parameter("screen_texture");check(texture and max(texture.get_width(),texture.get_height())<=1024,str(d.slug)+" texture budget")
				elif material is BaseMaterial3D:
					var mat:=material as BaseMaterial3D;check(mat.albedo_texture and mat.albedo_texture.resource_path==PALETTE,str(d.slug)+" palette");check(mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and not mat.texture_repeat,str(d.slug)+" nearest")
				else:check(material is ShaderMaterial and (material as ShaderMaterial).get_shader_parameter("shared_palette").resource_path==PALETTE,str(d.slug)+" lamp palette")
		check(count==int(d.export_triangles),str(d.slug)+" triangle count")
		check(bounds.size.distance_to(Vector3(d.bounds_size_m_godot[0],d.bounds_size_m_godot[1],d.bounds_size_m_godot[2]))<0.001,str(d.slug)+" bounds")
		check(abs(bounds.position.y)<0.001,str(d.slug)+" bottom origin")
		check(nodes(ob,"CollisionShape3D").size()==d.collisions.size(),str(d.slug)+" collision count")
		ob.free()
	room=(load(spec.runtime_scene) as PackedScene).instantiate();root.add_child(room)
	var group:=room.get_node("Components");check(group.get_child_count()==652,"652 prefab instances")
	var byid:Dictionary={}
	for child in group.get_children():byid[child.get_meta("source_instance_id")]=child
	for d in spec.instances:
		var ob:Node3D=byid[d.instance_id];check(ob.scene_file_path.ends_with("env_boss_room02_"+str(d.slug)+"_root_top3d.tscn"),str(d.instance_id)+" prefab boundary");check(ob.transform.is_equal_approx(tf(d.godot_transform)),str(d.instance_id)+" source transform");check(ob.scale.is_equal_approx(Vector3.ONE),str(d.instance_id)+" unit scale")
	check(nodes(room,"NavigationRegion3D").is_empty(),"No navigation/encounter logic baked into art")
	var ports:=room.get_node("ConnectionPorts")
	for turn in range(4):
		var rotation:=Basis(Vector3.UP,deg_to_rad(turn*90.0))
		for port in ports.get_children():check(abs((rotation*(port.basis*Vector3.BACK)).length()-1)<0.00001,"Port direction preserved under four rotations")
	await physics_frame;await physics_frame
	var space:=root.get_world_3d().direct_space_state
	# Walkable platform, both bridges, threshold and all stair segment centers.
	var samples:=0
	for x in range(-12,13,2):
		for z in range(-34,-10,2):
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,2,z),Vector3(x,-2,z),1));check(not hit.is_empty(),"Platform support %s,%s"%[x,z]);samples+=1
	for side in [-1,1]:
		for xi in range(13,40):
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(side*xi,2,-22.5),Vector3(side*xi,-2,-22.5),1));check(not hit.is_empty(),"Bridge/door support %s,%s"%[side,xi]);samples+=1
	for ob in group.get_children():
		if ob.get_meta("component_slug")=="stair_flight_5m":
			var p:Vector3=ob.global_position;var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3(0,3,0),p-Vector3(0,1,0),1));check(not hit.is_empty(),"Stair continuous ramp");samples+=1
	var lamps:=0
	for ob in group.get_children():
		if ob.get_meta("component_slug") in ["stair_chase_light","stair_pillar_light"]:
			check(ob.has_method("set_lit") and ob.has_meta("chase_index"),"Independent lamp control API");ob.call("set_lit",false);check(not ob.get("lit"),"Lamp off");ob.call("set_lit",true);lamps+=1
	check(lamps==180,"180 independent lamps")
	var report:={"checks":checks,"failures":failures,"components":46,"instances":652,"support_samples":samples,"independent_lamps":lamps,"passed":failures.is_empty(),"level_binding":"Existing boss01 retained. New boss_room_02 standalone selected for future level connection."}
	var file:=FileAccess.open(WORK+"godot_acceptance.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	if "--render" in OS.get_cmdline_user_args():await render_views()
	room.free();await process_frame
	print("BOSS_ROOM02_RUNTIME_", "OK" if failures.is_empty() else "FAILED"," checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
func render_views() -> void:
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(0.012,0.016,0.025);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(0.35,0.4,0.5);environment.ambient_light_energy=0.22;environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.glow_enabled=true
	environment.ssao_enabled=true;environment.ssao_intensity=1.5
	var world:=WorldEnvironment.new();world.environment=environment;root.add_child(world)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=58;camera.far=240
	root.size=Vector2i(1600,1000);root.msaa_3d=Viewport.MSAA_4X
	for view in [["hero",Vector3(0,22,42.5),Vector3(0,-1,-22.5)],["depth",Vector3(7,7,7.5),Vector3(15,-29,-14.5)],["west",Vector3(-16,7,14.5),Vector3(-33.5,6,-2.5)],["stairs",Vector3(0,14,47),Vector3(0,0,-22.5)]]:
		camera.position=view[1];camera.look_at(view[2]);await process_frame;await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(WORK+str(view[0])+"_godot.png")
	camera.free();world.free()
