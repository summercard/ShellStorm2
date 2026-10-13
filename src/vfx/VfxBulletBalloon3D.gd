class_name VfxBulletBalloon3D
extends VfxBulletBody3D
## VFX-BULLET-BALLOON-3D 气球弹膨胀弹体与厚重尾迹特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S11 · mod_bullet_balloon）：
##   「膨胀弹体、较重尾迹与命中体积一致，不能只改伤害数值」
## ⇒ 弹体做成**大球体**、尾迹**粗而短**（厚重感），并支持 apply_growth 继续膨胀。
##    （命中体积属玩法碰撞，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_balloon"] = Color(0.98, 0.35, 0.72)。

const BASE_COLOR := Color(0.98, 0.35, 0.72)


func _bullet_profile() -> Dictionary:
	return {
		"key": "balloon",
		"shell_color": BASE_COLOR,
		"core_shape": "sphere",
		"core_radius": 0.070,
		"core_color": Color(1.0, 0.86, 0.94),
		"core_emission": 2.0,
		"shell_shape": "sphere",
		"shell_radius": 0.118,
		"shell_emission": 1.75,
		"trail_style": "thick",
		"trail_alpha": 0.44,
		"trail_emission": 1.5,
		"trail_anim": "none",
		"trail_segments": [{"z": 0.22, "radius": 0.104, "height": 0.36, "alpha": 1.0}],
		"light_energy": 1.3,
		"light_range": 2.05,
		"pulse_rate": 5.0,
		"pulse_amplitude": 0.075,
	}
