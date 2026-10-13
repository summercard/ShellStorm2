class_name VfxBulletExplosive3D
extends VfxBulletBody3D
## VFX-BULLET-EXPLOSIVE-3D 爆炸弹体与尾迹特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S14 · mod_bullet_explosive）：
##   「弹体、尾迹、爆炸半径与伤害时点同步，低特效下保留轮廓圈」
## ⇒ 弹体**粗壮**、尾迹**带飞散火星**（flicker 动画），体积感与弹体重匹配。
##    （爆炸半径与伤害时点属 FX01-EXPLOSION 与玩法，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_explosive"] = Color(1.0, 0.28, 0.08)。

const BASE_COLOR := Color(1.0, 0.28, 0.08)


func _bullet_profile() -> Dictionary:
	return {
		"key": "explosive",
		"shell_color": BASE_COLOR,
		"core_shape": "capsule",
		"core_radius": 0.055,
		"core_height": 0.22,
		"core_color": Color(1.0, 0.86, 0.55),
		"core_emission": 2.6,
		"shell_shape": "capsule",
		"shell_radius": 0.094,
		"shell_height": 0.20,
		"shell_emission": 1.9,
		"trail_style": "sparks",
		"trail_alpha": 0.40,
		"trail_emission": 1.8,
		"trail_anim": "flicker",
		"trail_segments": [{"z": 0.21, "radius": 0.078, "height": 0.40, "alpha": 1.0}],
		"trail_sparks": [
			{"offset": Vector3(0.05, 0.02, 0.34), "length": 0.24, "alpha": 0.85},
			{"offset": Vector3(-0.05, 0.03, 0.42), "length": 0.20, "alpha": 0.75},
			{"offset": Vector3(0.0, -0.05, 0.50), "length": 0.18, "alpha": 0.65},
		],
		"light_energy": 1.65,
		"light_range": 2.4,
		"pulse_rate": 12.0,
		"pulse_amplitude": 0.06,
	}
