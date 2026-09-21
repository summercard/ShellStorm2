extends Node

const ENEMY_SCENE := "res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
const PREFAB := "res://assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn"

func _ready() -> void:
	var scene := load(ENEMY_SCENE) as PackedScene
	assert(scene != null, "generic enemy scene missing")
	var enemy := scene.instantiate()
	get_tree().root.add_child.call_deferred(enemy)
	await get_tree().process_frame
	enemy.configure_from_enemy_data({"enemy_type": "ranged_caster", "is_elite": false})
	await get_tree().process_frame
	var avatar := enemy.get_node("Avatar")
	var snap: Dictionary = avatar.get_component_snapshot()
	assert(snap.get("formal_normal_asset", false), "ranged formal presentation not mounted")
	assert(snap.get("component_count", 0) == 2, "formal component contract changed")
	var visual := avatar.find_child("FormalNormal_ranged_caster", true, false) as Node3D
	assert(visual != null, "security zombie visual root missing; children=%s" % avatar.get_children())
	var presenter := visual as Node3D
	var animations := presenter.get_presentation_snapshot().get("animations", []) as Array
	for clip in ["armed_idle", "walking_armed", "running_armed", "shoot", "hurt", "dead"]:
		assert(clip in animations, "missing animation: %s" % clip)
	assert(presenter.get_presentation_snapshot().get("shotgun_visual", false), "shotgun visual missing")
	assert(presenter.get_presentation_snapshot().get("shotgun_bone", "") == "L_Hand", "wrong gun hand")
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "skeleton missing")
	assert(skeleton.get_node_or_null("SecurityShotgunAttachment") != null, "gun attachment missing")
	assert(skeleton.get_node("SecurityShotgunAttachment").get_node_or_null("ShotgunVisual") != null, "shotgun instance missing")
	avatar.sync_presentation("patrol", 0.0, 9.0, 0.38, 0.34)
	assert(presenter.get_presentation_snapshot().get("clip", "") == "walking_armed", "patrol must use walking armed clip")
	avatar.sync_presentation("attack", 0.18, 0.0, 0.38, 0.34)
	assert(presenter.get_presentation_snapshot().get("clip", "") == "shoot", "attack must use shoot clip")
	print("SECURITY_ZOMBIE_PRESENTATION_OK animations=%d shotgun=true bone=L_Hand ranged_logic_preserved=true" % animations.size())
	get_tree().quit()
