class_name VfxBulletHoming3D
extends VfxBulletBody3D
## VFX-BULLET-HOMING-3D 蜂卵弹锁定与弯曲尾迹特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S15 · mod_bullet_homing）：
##   「锁定框、弯曲尾迹和转向动作一致；目标丢失有解除提示」
## ⇒ 弹体做成**椭圆蜂卵**感、尾迹**向两侧摆动**（wave 动画），读得出「在追」。
##    （锁定框与目标丢失提示属锁定表现与玩法，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_homing"] = Color(0.50, 1.0, 0.42)。

const BASE_COLOR := Color(0.50, 1.0, 0.42)


func _bullet_profile() -> Dictionary:
	return {
		"key": "homing",
		"shell_color": BASE_COLOR,
		"core_shape": "capsule",
		"core_radius": 0.050,
		"core_height": 0.18,
		"core_color": Color(0.88, 1.0, 0.80),
		"core_emission": 2.2,
		"shell_shape": "capsule",
		"shell_radius": 0.082,
		"shell_height": 0.16,
		"shell_emission": 1.7,
		"trail_style": "wavy",
		"trail_alpha": 0.38,
		"trail_emission": 1.6,
		"trail_anim": "wave",
		"trail_segments": [
			{"z": 0.18, "radius": 0.058, "height": 0.22, "alpha": 0.95},
			{"z": 0.34, "radius": 0.046, "height": 0.20, "alpha": 0.8},
			{"z": 0.48, "radius": 0.034, "height": 0.18, "alpha": 0.6},
		],
		"light_energy": 1.25,
		"light_range": 1.9,
		"pulse_rate": 7.0,
		"pulse_amplitude": 0.05,
	}
