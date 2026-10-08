extends SceneTree

const EDIT := "res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn"
const CHUNKS: Array[String] = ["open_world_chunk_square_30x30", "open_world_chunk_square_100x101", "open_world_chunk_square_100x105", "open_world_chunk_square_100x100", "open_world_chunk_square_100x104"]
const UNCHANGED: Array[String] = ["open_world_chunk_square_100x103", "open_world_chunk_square_100x102", "open_world_chunk_square_60x60"]
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func transform_data(t: Transform3D) -> Array:
	return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

func compare_tree(author: Node, actual: Node, label: String) -> void:
	check(actual != null, label+" exists")
	if actual == null:
		return
	check(author.scene_file_path == actual.scene_file_path, label+" resource")
	if author is Node3D and actual is Node3D:
		check((author as Node3D).global_transform.is_equal_approx((actual as Node3D).global_transform), label+" world transform")
		check((author as Node3D).is_visible_in_tree()==(actual as Node3D).is_visible_in_tree(),label+" visibility")
	if author is MeshInstance3D and actual is MeshInstance3D:
		check((author as MeshInstance3D).mesh.get_aabb().is_equal_approx((actual as MeshInstance3D).mesh.get_aabb()), label+" mesh dimensions")
	check(author.get_child_count()==actual.get_child_count(),label+" child count")
	for child: Node in author.get_children():
		compare_tree(child,actual.get_node_or_null(NodePath(str(child.name))),label+"/"+str(child.name))

func run() -> void:
	var author: Node3D = load(EDIT).instantiate()
	root.add_child(author)
	var game: Node3D = load("res://scenes/TowerDescent3D.tscn").instantiate()
	game.set("test_mode",true)
	root.add_child(game)
	for i: int in 30:
		await physics_frame
	var route := game.get_node("Blocks/Rooftop/CrossTowerRoute") as Node3D
	var foundation := route.get_node("LandscapeFoundation") as Node3D
	for name: String in CHUNKS:
		var a := author.get_node(NodePath(name)) as Node3D
		var b := foundation.get_node(NodePath("AuthoredCityChunks/"+name)) as Node3D
		compare_tree(a,b,name)
		records.append({"node":name,"author":transform_data(a.global_transform),"actual":transform_data(b.global_transform),"scene":b.scene_file_path})
		check(b.find_children("*","CollisionObject3D",true,false).is_empty(),name+" remains visual only")
	compare_tree(author.get_node("Tower3FoundationBox"), foundation.get_node("Tower3FoundationBox"), "Tower3FoundationBox")
	compare_tree(author.get_node("Skyline20Placement"),route.get_node("Skyline20Placement"),"Skyline20Placement")
	var skyline := route.get_node("Skyline20Placement/Skyline20") as Node3D
	check(absf(skyline.global_position.y+86.36)<0.001,"Skyline20 height unchanged")
	var n := 0
	for node: Node in game.find_children("*","Node3D",true,false):
		if str(node.get_meta("asset_id",""))=="ENV-OPENWORLD-LANDSCAPE-SKYLINE20":
			n += 1
	check(n==1,"Skyline20 exactly one")
	var legacy: Array[Dictionary] = []
	for name: String in UNCHANGED:
		var a := author.get_node(NodePath(name)) as Node3D
		var b := foundation.get_node(NodePath("AuthoredCityChunks/"+name)) as Node3D
		legacy.append({"node":name,"author":transform_data(a.global_transform),"actual":transform_data(b.global_transform),"author_scene":a.scene_file_path,"actual_scene":b.scene_file_path,"note":"Historical difference, not changed by this request"})
	var result := {"checks":checks,"failures":failures,"changed_chunks":records,"skyline20_world":transform_data(skyline.global_transform),"tower3_foundation_world":transform_data((foundation.get_node("Tower3FoundationBox") as Node3D).global_transform),"skyline20_instance_count":n,"unchanged_historical_differences":legacy}
	var f := FileAccess.open("res://outputs/open_world_manual_sync_20261008/runtime_validation.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"))
	f.close()
	print("OPENWORLD_MANUAL_SYNC ",checks," checks; failures=",failures)
	author.free()
	game.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
