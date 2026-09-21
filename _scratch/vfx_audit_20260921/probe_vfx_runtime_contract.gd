extends Node
## 只读运行时探针：实测 VfxPool3D 在真实加载环境下的三条契约
##  1) FX02 飘字在缺 context.text_value 时渲染什么文本
##  2) FX01-04 挥砍弧是否消费 context.forward（朝向）
##  3) acquire 出来的特效挂在哪一层

func _ready() -> void:
	var pool := VfxPool3D.new()
	pool.name = "ProbeVfxPool"
	add_child(pool)
	await get_tree().process_frame

	var dmg := pool.acquire(VfxPool3D.FX02_DAMAGE_NUMBER, Vector3.ZERO, Color.RED, 1.0, {})
	print("PROBE_TEXT_NO_CONTEXT=[", _first_label(dmg), "]")

	var dmg2 := pool.acquire(
		VfxPool3D.FX02_DAMAGE_NUMBER, Vector3.ONE, Color.GOLD, 1.0,
		{"text_value": "137", "critical": true}
	)
	print("PROBE_TEXT_WITH_CONTEXT=[", _first_label(dmg2), "]")

	var slash_a := pool.acquire(
		VfxPool3D.FX01_MELEE_SLASH, Vector3.ZERO, Color.WHITE, 1.0, {"forward": Vector3(0, 0, -1)}
	)
	var slash_b := pool.acquire(
		VfxPool3D.FX01_MELEE_SLASH, Vector3.ZERO, Color.WHITE, 1.0, {"forward": Vector3(1, 0, 0)}
	)
	print("PROBE_SLASH_ROT_forwardNegZ=", slash_a.rotation.y, " forwardPosX=", slash_b.rotation.y)
	print("PROBE_SLASH_ROT_CONSUMED_FORWARD=", not is_equal_approx(slash_a.rotation.y, slash_b.rotation.y))
	print("PROBE_SLASH_ARC_FIRST_VERTEX_Z=", _arc_vertex_z(slash_a))

	var mi := pool.acquire(
		VfxPool3D.FX01_MELEE_IMPACT, Vector3.ZERO, Color.WHITE, 1.0,
		{"combo_step": 2, "critical": true, "forward": Vector3(0, 0, -1)}
	)
	print("PROBE_MELEE_IMPACT_ROT=", mi.rotation.y)

	print("PROBE_SPAWN_PARENT=", str(dmg.get_parent().name))
	print("PROBE_SPAWN_PARENT_IS_POOL=", dmg.get_parent() == pool)
	print("PROBE_DONE")
	get_tree().quit(0)


func _first_label(node: Node) -> String:
	if node == null:
		return "<null>"
	var found := node.find_children("*", "Label3D", true, false)
	if found.is_empty():
		return "<no-label>"
	return (found[0] as Label3D).text


func _arc_vertex_z(node: Node) -> float:
	if node == null:
		return -999.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null or str(mi.name) != "SlashArc":
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			return -998.0
		return verts[0].z
	return -999.0
