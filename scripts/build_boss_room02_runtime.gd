extends SceneTree
## Native component wrapping, then a new room scene. Existing room01 is never packed.
const PREFIX := "res://assets/art/environments/tower_zones/expedition/"
const WORK := "../ShellStorm2-work/outputs/boss_room02_import/"
var spec: Dictionary

func _initialize() -> void:
	call_deferred("build")

func tf(v: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(v[0],v[1],v[2]),Vector3(v[3],v[4],v[5]),Vector3(v[6],v[7],v[8])),Vector3(v[9],v[10],v[11]))

func meshes(n: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if n is MeshInstance3D:result.append(n)
	for child in n.get_children():result.append_array(meshes(child))
	return result

func save_scene(node: Node, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	assert(packed.pack(node)==OK)
	assert(ResourceSaver.save(packed,path)==OK)

func build() -> void:
	spec=JSON.parse_string(FileAccess.get_file_as_string(WORK+"spec.json"))
	var components: Dictionary={}
	for d in spec.components:
		var wrapper:=Node3D.new();wrapper.name="BossRoom02_"+str(d.slug)
		var visual: Node3D=(load("res://"+str(d.glb_path)) as PackedScene).instantiate();visual.name="ImportedModel";wrapper.add_child(visual);visual.owner=wrapper
		for key in ["asset_id","slug","version","source_path","optimized_path","glb_sha256","collision_policy","collision_owner"]:wrapper.set_meta(key,d[key])
		wrapper.set_meta("asset_version",d.version);wrapper.set_meta("component_slug",d.slug);wrapper.set_meta("source_blend","res://"+str(d.source_path));wrapper.set_meta("origin_contract","bottom_center");wrapper.set_meta("front_axis_godot","+Z");wrapper.set_meta("bounds_size_m",Vector3(d.bounds_size_m_godot[0],d.bounds_size_m_godot[1],d.bounds_size_m_godot[2]));wrapper.set_meta("display_name_zh",d.name_zh)
		if str(d.slug).begins_with("screen_"):
			var material:=ShaderMaterial.new();material.shader=load(PREFIX+"runtime/room_type_components/boss_room_02/screen_scan.gdshader");material.set_shader_parameter("screen_texture",load(d.screen_texture));material.set_shader_parameter("scan_phase",0.0)
			var path:=PREFIX+"runtime/room_type_components/boss_room_02/"+str(d.slug)+"/screen_material.tres";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()));assert(ResourceSaver.save(material,path)==OK)
			wrapper.set_script(load("res://src/world3d/BossRoomDisplay3D.gd"));wrapper.set("screen_material",load(path));wrapper.set_meta("texture_exception","User-authorized Image-2 screen; external 1024px runtime texture")
		elif d.slug in ["stair_chase_light","stair_pillar_light"]:
			var material:=ShaderMaterial.new();material.shader=load(PREFIX+"runtime/room_type_components/boss_room_02/lamp.gdshader");material.set_shader_parameter("shared_palette",load("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"))
			wrapper.set_script(load("res://src/world3d/BossRoomDisplay3D.gd"));wrapper.set("lamp_material",material);wrapper.set_meta("control_api","set_lit(bool); room instance metadata/chase_index; no character trigger embedded")
		var body: StaticBody3D
		if not d.collisions.is_empty():
			body=StaticBody3D.new();body.name="CollisionBody";body.collision_layer=1;body.collision_mask=0;wrapper.add_child(body);body.owner=wrapper
		var index:=0
		for c in d.collisions:
			var shape: Shape3D
			var position:=Vector3.ZERO
			if c.kind=="box":
				var box:=BoxShape3D.new();box.size=Vector3(c.size[0],c.size[1],c.size[2]);shape=box;position=Vector3(c.position[0],c.position[1],c.position[2])
			elif c.kind=="convex":
				var convex:=ConvexPolygonShape3D.new();var points:=PackedVector3Array()
				for p in c.points:points.append(Vector3(p[0],p[1],p[2]))
				convex.points=points;shape=convex
			else:
				var faces:=PackedVector3Array()
				for mesh in meshes(visual):
					for v in mesh.mesh.get_faces():faces.append(mesh.transform*v)
				var concave:=ConcavePolygonShape3D.new();concave.set_faces(faces);shape=concave
			var cs:=CollisionShape3D.new();cs.name="Shape_%02d"%index;cs.shape=shape;cs.position=position
			# 走面承重交给房间的一体地面碰撞（见 prepare_boss_room02_import.py 的 WALK_SURFACE_MARK）。
			# 只停用形状、保留节点：collision_shape_count 与实测节点数都不变，验收口径照旧。
			cs.disabled=bool(c.get("room_owned_walk_surface",false))
			body.add_child(cs);cs.owner=wrapper;index+=1
		wrapper.set_meta("collision_shape_count",index)
		if d.has("walk_surface_owner"):wrapper.set_meta("walk_surface_owner",d["walk_surface_owner"])
		save_scene(wrapper,"res://"+str(d.prefab_path));components[d.slug]=load("res://"+str(d.prefab_path));wrapper.free()
	print("BOSS_ROOM02_02B_WRAPPERS_SAVED ",components.size())
	# New file only. Existing author-owned room01 stays protected by baseline hashes.
	assert(not FileAccess.file_exists(spec.runtime_scene),"Refuse to overwrite an existing room. Review its authored differences first.")
	var room:=Node3D.new();room.name="Expedition01BossRoom02"
	room.set_meta("asset_id",spec.asset_id);room.set_meta("asset_version",spec.version);room.set_meta("block_id","expedition");room.set_meta("level_id","expedition_01");room.set_meta("room_id","boss_room_02");room.set_meta("room_type","BOSS_ROOM");room.set_meta("room_variant","deep_shaft_02");room.set_meta("layout_instance_total",spec.instances.size());room.set_meta("component_definition_count",components.size());room.set_meta("layout_owner","formal Godot TSCN; Blender JSON initialization only");room.set_meta("floor_plane_y",0.0);room.set_meta("future_level_binding","Use this new room when connecting the level. Existing room01 retained.")
	var lamps:=Node3D.new();lamps.name="RoomLighting";room.add_child(lamps);lamps.owner=room
	for d in spec.lights:
		var light:=OmniLight3D.new();light.name=str(d.name);light.position=tf(d.godot_transform).origin;light.light_color=Color(d.color[0],d.color[1],d.color[2]);light.light_energy=clampf(float(d.energy)/6500.0,0.25,2.4);light.omni_range=34;light.omni_attenuation=0.8;light.shadow_enabled=false;light.set_meta("source_area_energy_w",d.energy);light.set_meta("converted_area_fill","Calibrated room fill; bottom sources preserve upward contour lighting");lamps.add_child(light);light.owner=room
	var group:=Node3D.new();group.name="Components";room.add_child(group);group.owner=room
	var chase:=0
	for d in spec.instances:
		var ob:Node3D=(components[d.slug] as PackedScene).instantiate();ob.name=str(d.instance_id);ob.transform=tf(d.godot_transform);ob.set_meta("source_instance_id",d.instance_id);ob.set_meta("asset_id",d.component_id);ob.set_meta("component_slug",d.slug);group.add_child(ob);ob.owner=room
		if d.slug in ["stair_chase_light","stair_pillar_light"]:
			# Source y identifies descent order; paired modules remain independently controlled.
			var source_y:float=d.matrix_room_local[1][3];ob.set_meta("chase_index",clampi(int(floor((source_y+62.5)/0.5)),0,99));ob.set_meta("chase_direction","entrance_to_platform")
			chase+=1
	var ports:=Node3D.new();ports.name="ConnectionPorts";room.add_child(ports);ports.owner=room
	for value in [["West",Vector3(-40,0,-22.5),Vector3.LEFT],["East",Vector3(40,0,-22.5),Vector3.RIGHT],["Entrance",Vector3(0,12,50),Vector3.BACK]]:
		var marker:=Marker3D.new();marker.name="Port_"+str(value[0]);marker.position=value[1];marker.basis=Basis.looking_at(-value[2],Vector3.UP);marker.set_meta("port_id",str(value[0]).to_lower());marker.set_meta("connection_state","unconnected_closed");ports.add_child(marker);marker.owner=room
	# 一体地面碰撞：平台 + 东西走道 + 楼梯 + 高位平台合成一个网格，房间自持。
	# 几何与实测依据全在 `scripts/build_boss_room02_walk_surface.py`；这里只负责挂上它。
	# 房间根上写入声明，供 `probe_boss_room02_walk_surface` 与文档追溯。
	var walk_surface_path:="res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/boss_room_02_walk_surface.tscn"
	if not FileAccess.file_exists(walk_surface_path):
		push_error("缺一体地面碰撞场景，请先跑 scripts/build_boss_room02_walk_surface.py --write：%s"%walk_surface_path)
	else:
		var walk_surface:Node3D=(load(walk_surface_path) as PackedScene).instantiate()
		walk_surface.name="WalkSurfaceCollision";room.add_child(walk_surface);walk_surface.owner=room
		room.set_meta("walk_surface_owner","room")
		room.set_meta("walk_surface_scene",walk_surface_path)
	save_scene(room,spec.runtime_scene);room.free()
	print("BOSS_ROOM02_SCENE_SAVED components=46 instances=652 independent_lamps=",chase)
	quit(0)
