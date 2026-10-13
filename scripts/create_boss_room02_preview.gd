extends SceneTree
## Standalone F6 preview references the formal assembly; no component internals unpacked.
func _initialize() -> void:
	var room_path:="res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_boss_room_02_static_layout.tscn"
	var root_node:=Node3D.new();root_node.name="BossRoom02Standalone"
	var room:Node3D=(load(room_path) as PackedScene).instantiate();room.name="BossRoom02";root_node.add_child(room);room.owner=root_node
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(0.012,0.016,0.025);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(0.35,0.4,0.5);env.ambient_light_energy=0.22;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.glow_enabled=true;env.ssao_enabled=true;env.ssao_intensity=1.5
	var world:=WorldEnvironment.new();world.name="WorldEnvironment";world.environment=env;root_node.add_child(world);world.owner=root_node
	var camera:=Camera3D.new();camera.name="InspectionCamera";camera.current=true;camera.fov=58;camera.far=240;root_node.add_child(camera);camera.owner=root_node;camera.position=Vector3(0,22,42.5);camera.basis=Basis.looking_at(Vector3(0,-1,-22.5)-camera.position)
	var packed:=PackedScene.new();assert(packed.pack(root_node)==OK);assert(ResourceSaver.save(packed,"res://scenes/Expedition01BossRoom02_3D.tscn")==OK);root_node.free();print("BOSS_ROOM02_STANDALONE_SAVED");quit()
