class_name VfxBulletPiercing3D
extends VfxBulletBody3D
## VFX-BULLET-PIERCING-3D 穿甲弹贯穿线与层数特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S16 · mod_bullet_piercing）：
##   「穿透命中显示连续贯穿线与剩余层数，不在首个目标处假性消失」
## ⇒ 弹体做成**细长锐利针形**、尾迹细而长（一条笔直的贯穿感）。
##    （贯穿线与剩余层数属命中表现与玩法，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_piercing"] = Color(1.0, 0.78, 0.22)。

const BASE_COLOR := Color(1.0, 0.78, 0.22)


func _bullet_profile() -> Dictionary:
	return {
		"key": "piercing",
		"shell_color": BASE_COLOR,
		"core_shape": "capsule",
		"core_radius": 0.028,
		"core_height": 0.30,
		"core_color": Color(1.0, 0.96, 0.82),
		"core_emission": 2.4,
		"shell_shape": "capsule",
		"shell_radius": 0.044,
		"shell_height": 0.28,
		"shell_emission": 1.8,
		"trail_style": "needle",
		"trail_alpha": 0.30,
		"trail_emission": 1.6,
		"trail_anim": "none",
		"trail_segments": [
			{"z": 0.30, "radius": 0.036, "height": 0.60, "alpha": 0.95},
			{"z": 0.72, "radius": 0.022, "height": 0.54, "alpha": 0.6},
		],
		"light_energy": 1.35,
		"light_range": 1.95,
		"pulse_rate": 10.0,
		"pulse_amplitude": 0.035,
	}
