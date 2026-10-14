class_name VfxBulletStandard3D
extends VfxBulletBody3D
## VFX-BULLET-STANDARD-3D 标准子弹弹体与尾迹特效（FX01-06 系列弹种专属）。
##
## 设计原文（内容库《武器》S17 · mod_bullet_standard）：
##   「使用清晰中性弹体、尾迹和命中；不附加误导性的元素效果」
## ⇒ 本弹种是**基准形态**：中性细胶囊 + 柔和单锥尾迹，无任何元素附加物。
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_standard"] = Color(0.76, 0.86, 0.92)。

const BASE_COLOR := Color(0.76, 0.86, 0.92)


func _bullet_profile() -> Dictionary:
	return {
		"key": "standard",
		"shell_color": BASE_COLOR,
		"core_shape": "prism",
		"core_radius": 0.045,
		"core_height": 0.20,
		"core_color": Color(0.92, 0.96, 1.0),
		"core_emission": 2.2,
		"shell_shape": "prism",
		"shell_radius": 0.075,
		"shell_height": 0.18,
		"shell_emission": 1.5,
		"trail_style": "cone",
		"trail_alpha": 0.34,
		"trail_emission": 1.35,
		"trail_anim": "none",
		"trail_segments": [{"z": 0.23, "radius": 0.055, "height": 0.46, "alpha": 1.0}],
		"light_energy": 1.15,
		"light_range": 1.75,
		"pulse_rate": 8.5,
		"pulse_amplitude": 0.04,
	}
