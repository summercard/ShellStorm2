class_name VfxBulletBounce3D
extends VfxBulletBody3D
## VFX-BULLET-BOUNCE-3D 回旋镖弹反弹折线与计数特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S13 · mod_bullet_bounce）：
##   「反弹点有折线闪光与计数递减，飞行方向变化清楚可读」
## ⇒ 尾迹做成**分段错位的折线锥**（方向感强），弹体圆润。
##    （反弹点的闪光与剩余次数属命中表现与玩法，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_bounce"] = Color(0.30, 0.70, 1.0)。

const BASE_COLOR := Color(0.30, 0.70, 1.0)


func _bullet_profile() -> Dictionary:
	return {
		"key": "bounce",
		"shell_color": BASE_COLOR,
		"core_shape": "prism",
		"core_radius": 0.048,
		"core_height": 0.14,
		"core_color": Color(0.85, 0.94, 1.0),
		"core_emission": 2.1,
		"shell_shape": "prism",
		"shell_radius": 0.072,
		"shell_height": 0.13,
		"shell_emission": 1.6,
		"trail_style": "dashed",
		"trail_alpha": 0.38,
		"trail_emission": 1.5,
		"trail_anim": "none",
		# 三段短锥沿 +Z 依次错位（x 交替左右），读起来是一条折线而不是直线拖尾。
		"trail_segments": [
			{"z": 0.17, "radius": 0.052, "height": 0.20, "alpha": 1.0},
			{"z": 0.37, "radius": 0.040, "height": 0.18, "alpha": 0.8},
			{"z": 0.54, "radius": 0.030, "height": 0.16, "alpha": 0.6},
		],
		"light_energy": 1.2,
		"light_range": 1.8,
		"pulse_rate": 9.0,
		"pulse_amplitude": 0.045,
	}
