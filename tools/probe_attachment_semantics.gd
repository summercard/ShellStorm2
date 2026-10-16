extends Node3D
## 一次性工具：**实测 `BoneAttachment3D` 到底按什么变换摆放子节点**。
##
## 走到这一步的原因：我按 `world = skeleton.global · bone_pose · local` 反解偏移，
## 实测眼位偏到脚底/下巴，且左右不对称 —— 说明真实语义与我假设的不同。
## 本探针不猜：建一个偏移为 0 的 BoneAttachment3D，直接读它的 global_transform，
## 与「skeleton.global · bone_pose」「skeleton.global · bone_rest」逐个比对，
## 谁对上就是谁。
## 用法：godot --headless --path . res://tools/probe_attachment_semantics.tscn

const TARGETS := {
	"melee_chaser": "res://assets/art/enemies/normal_enemy_3d/melee_chaser/runtime/enm_melee_fungboar01_root_top3d.tscn",
	"ranged_caster": "res://assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn",
	"fat_zombie03": "res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn",
}


func _ready() -> void:
	for kind in TARGETS:
		_probe(kind, str(TARGETS[kind]))
	print("PROBE_ATTACHMENT_SEMANTICS_DONE")
	get_tree().quit(0)


func _probe(kind: String, path: String) -> void:
	print("================================================================")
	print("=== %s" % kind)
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	add_child(inst)
	var skeleton: Skeleton3D = null
	for node in inst.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null:
		print("  无骨架")
		return
	var idx := skeleton.find_bone("Head")

	var attach := BoneAttachment3D.new()
	attach.name = "ProbeAttach"
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	attach.force_update_transform()

	var actual := attach.global_transform
	print("  BoneAttachment3D(偏移0).global   = pos %s" % _v(actual.origin))
	print("  skeleton.global                  = pos %s scale %s" % [
		_v(skeleton.global_transform.origin), _v(skeleton.global_transform.basis.get_scale())
	])
	var pose_g := skeleton.get_bone_global_pose(idx)
	var rest_g := skeleton.get_bone_global_rest(idx)
	print("  bone_global_pose(Head)           = pos %s" % _v(pose_g.origin))
	print("  bone_global_rest(Head)           = pos %s" % _v(rest_g.origin))
	var a := skeleton.global_transform * pose_g
	var b := skeleton.global_transform * rest_g
	print("  skeleton.global · pose           = pos %s  %s" % [
		_v(a.origin), "← 与实测一致" if a.origin.distance_to(actual.origin) < 0.0005 else ""
	])
	print("  skeleton.global · rest           = pos %s  %s" % [
		_v(b.origin), "← 与实测一致" if b.origin.distance_to(actual.origin) < 0.0005 else ""
	])
	# 也试「只用骨架本地位姿、不带 skeleton.global」。
	print("  仅 pose（不带 skeleton.global）   = pos %s  %s" % [
		_v(pose_g.origin), "← 与实测一致" if pose_g.origin.distance_to(actual.origin) < 0.0005 else ""
	])

	# 子节点在 attach 下的世界位置 = actual * child_local。
	# 我们想让子节点落在「模型根空间」的 p 处，问 child_local 该取什么。
	var p := Vector3(0.16, 0.99, -0.56)  # 小僵尸眼点的量级
	print("  子节点 local=%s → 世界 %s" % [_v(p), _v(actual * p)])
	inst.free()


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
