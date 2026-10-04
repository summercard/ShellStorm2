extends SceneTree

var tower: Node
var source: Node
var failures: Array[String] = []
var source_hash: String

func _initialize() -> void:
	_run.call_deferred()

func wt(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

func _run() -> void:
	var path := "res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn"
	source_hash = FileAccess.get_sha256(path)
	source = (load(path) as PackedScene).instantiate()
	tower = (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", 990095)
	root.add_child(tower)
	for i in range(120):
		await process_frame
		if i == 11 or i == 119:
			compare(i + 1)
	if FileAccess.get_sha256(path) != source_hash:
		failures.append("Source changed during probe")
	print("SOURCE_SHA256=", source_hash)
	print("FAILURES=", JSON.stringify(failures))
	source.free()
	tower.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func compare(frame: int) -> void:
	var foundation := tower.get_node_or_null("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
	if foundation == null:
		failures.append("Missing runtime foundation")
		return
	var chunks := foundation.get_node("AuthoredCityChunks")
	var count := 0
	var buildings := 0
	var meshes := 0
	var mismatch := 0
	for child in source.get_children():
		if not child is Node3D or not child.has_meta("chunk_id"):
			continue
		count += 1
		var actual := chunks.get_node_or_null(NodePath(str(child.name))) as Node3D
		if actual == null:
			failures.append("Missing chunk " + str(child.name))
			continue
		var ok := wt(child).is_equal_approx(actual.global_transform) and child.scene_file_path == actual.scene_file_path
		print("CHUNK frame=", frame, " name=", child.name, " match=", ok, " world=", actual.global_transform, " visible=", actual.is_visible_in_tree())
		if not ok:
			mismatch += 1
		for building in child.get_node("buildings").get_children():
			buildings += 1
			var ab := actual.get_node_or_null(child.get_path_to(building)) as Node3D
			if ab == null or not wt(building).is_equal_approx(ab.global_transform):
				mismatch += 1
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			var am := actual.get_node_or_null(child.get_path_to(mesh)) as Node3D
			if am == null or not wt(mesh).is_equal_approx(am.global_transform):
				mismatch += 1
	if mismatch > 0 or count != chunks.get_child_count():
		failures.append("Transform/count mismatch frame=" + str(frame))
	print("SUMMARY frame=", frame, " source_chunks=", count, " runtime_chunks=", chunks.get_child_count(), " buildings=", buildings, " meshes=", meshes, " mismatches=", mismatch)
	print("PROCEDURAL_CITY_500=", foundation.get_node_or_null("ProceduralCity500") != null)
	for old in tower.find_children("RooftopCityBelow", "Node3D", true, false):
		print("LEGACY_CITY path=", old.get_path(), " visible=", old.is_visible_in_tree())
		for mm in old.find_children("*", "MultiMeshInstance3D", true, false):
			print("LEGACY_MULTIMESH name=", mm.name, " count=", mm.multimesh.instance_count, " visible=", mm.is_visible_in_tree())
