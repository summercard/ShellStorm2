class_name VfxBulletSticky3D
extends VfxBulletBody3D
## VFX-BULLET-STICKY-3D 黏黏弹附着与倒计时特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S18 · mod_bullet_sticky）：
##   「命中后弹体留在表面并显示倒计时/状态，结束时反馈与结算同步」
## ⇒ 弹体做成**短粗黏稠**形态、尾迹带**滴落小珠**（drip 动画），强调「附着」质感。
##    （附着后的倒计时/结算属玩法与命中表现，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_sticky"] = Color(0.32, 0.92, 0.62)。

const BASE_COLOR := Color(0.32, 0.92, 0.62)


func _bullet_profile() -> Dictionary:
	return {
		"key": "sticky",
		"shell_color": BASE_COLOR,
		"core_shape": "capsule",
		"core_radius": 0.050,
		"core_height": 0.16,
		"core_color": Color(0.78, 1.0, 0.88),
		"core_emission": 2.0,
		"shell_shape": "capsule",
		"shell_radius": 0.086,
		"shell_height": 0.16,
		"shell_emission": 1.7,
		"trail_style": "beads",
		"trail_alpha": 0.42,
		"trail_emission": 1.5,
		"trail_anim": "drip",
		"trail_segments": [{"z": 0.20, "radius": 0.062, "height": 0.34, "alpha": 1.0}],
		"trail_beads": [
			{"z": 0.42, "radius": 0.018, "alpha": 0.95},
			{"z": 0.56, "radius": 0.014, "alpha": 0.8},
			{"z": 0.68, "radius": 0.011, "alpha": 0.62},
		],
		"light_energy": 1.2,
		"light_range": 1.8,
		"pulse_rate": 6.5,
		"pulse_amplitude": 0.055,
	}
