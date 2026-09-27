extends Node
## 实测跑步剪辑的播放倍率：统计固定秒数内 foot_l 的抬脚次数，换算实际循环周期。
## 反向对照：把 CharacterMotionLibrary3D.RUN_CLIP_RATE_SCALE 改回 1.0 后，
## 循环周期应回到 0.800s（6s 内抬脚次数按倍率同比回落）。

const PKG := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/runtime/chr_bunny01_root_v021.tscn"
const SAMPLE_SECONDS := 6.0
const STEP := 1.0 / 60.0
const LIFT_THRESHOLD := 0.09


class FakePlayer extends Node:
	var velocity := Vector3(5.0, 0.0, 0.0)


func _ready() -> void:
	var failures: Array[String] = []
	var scale := float(CharacterMotionLibrary3D.RUN_CLIP_RATE_SCALE)
	var expected_period := 0.8 / scale
	var expected_lifts := SAMPLE_SECONDS / expected_period
	var plain := _measure(false)
	var armed := _measure(true)
	print("RUN_CLIP_RATE scale=%.2f plain lifts=%d period=%.4f cycles/s=%.3f" % [scale, plain.lifts, plain.period, plain.cps])
	print("RUN_CLIP_RATE scale=%.2f armed lifts=%d period=%.4f cycles/s=%.3f" % [scale, armed.lifts, armed.period, armed.cps])
	for tag in ["plain", "armed"]:
		var m: Dictionary = plain if tag == "plain" else armed
		if absf(float(m.period) - expected_period) > 0.02:
			failures.append("%s period=%.4f 期望 %.4f（倍率 %.2f 未生效）" % [tag, m.period, expected_period, scale])
		if absf(float(m.lifts) - expected_lifts) > 1.0:
			failures.append("%s lifts=%d 期望约 %d" % [tag, m.lifts, int(expected_lifts)])
		if absf(float(m.lifts) - SAMPLE_SECONDS / 0.8) < 1.0:
			failures.append("%s 抬脚次数与 1.0 倍率无差别，倍率没接上" % tag)
	if failures.is_empty():
		print("RUN_CLIP_RATE_OK: moving/armed_moving 循环周期 %.4fs（%.2f 倍）" % [expected_period, scale])
		get_tree().quit()
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _measure(armed: bool) -> Dictionary:
	var avatar: Node3D = load(PKG).instantiate()
	avatar.set_process(false)
	var player := FakePlayer.new()
	avatar.set("_player", player)
	avatar.set("_state", "moving")
	if armed:
		avatar.set("_weapon_grip_pose_active", true)
		avatar.set("_weapon_class", "sidearm")
	add_child(avatar)
	var driver := CharacterMotionLibrary3D.new()
	driver.bind(avatar)
	var lifts := 0
	var above := false
	var first_lift := -1.0
	var last_lift := -1.0
	var elapsed := 0.0
	while elapsed < SAMPLE_SECONDS:
		driver.apply(avatar, STEP)
		elapsed += STEP
		var lifted := avatar.foot_l.position.y > LIFT_THRESHOLD
		if lifted and not above:
			lifts += 1
			if first_lift < 0.0:
				first_lift = elapsed
			last_lift = elapsed
		above = lifted
	var period := 0.0
	if lifts >= 2:
		period = (last_lift - first_lift) / float(lifts - 1)
	avatar.queue_free()
	player.queue_free()
	return {"lifts": lifts, "period": period, "cps": (1.0 / period) if period > 0.0 else 0.0}
