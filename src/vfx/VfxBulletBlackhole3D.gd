class_name VfxBulletBlackhole3D
extends VfxBulletBody3D
## VFX-BULLET-BLACKHOLE-3D 黑洞核心与吸入流线特效（弹体 + 尾迹段）。
##
## 设计原文（内容库《武器》S12 · mod_bullet_blackhole）：
##   「黑洞核心、吸入流线和范围边界清晰；命中/结束有收束反馈」
## ⇒ 弹体做成**暗核 + 紫光环**、尾迹是**外扩喇叭**（spin 旋转），读得出「在吸」。
##    （范围边界与收束结算属玩法与命中表现，不在本纯视觉 Prefab 内实现。）
## 配色 = WeaponModel3D.BULLET_COLORS["mod_bullet_blackhole"] = Color(0.68, 0.25, 0.95)。

const BASE_COLOR := Color(0.68, 0.25, 0.95)


func _bullet_profile() -> Dictionary:
	return {
		"key": "blackhole",
		"shell_color": BASE_COLOR,
		# 暗核：球形、低亮度，强调「吸进去」的黑心。
		"core_shape": "sphere",
		"core_radius": 0.058,
		"core_color": Color(0.30, 0.10, 0.48),
		"core_emission": 1.0,
		"shell_shape": "sphere",
		"shell_radius": 0.098,
		"shell_emission": 1.9,
		"trail_style": "funnel",
		"trail_alpha": 0.34,
		"trail_emission": 1.7,
		"trail_anim": "spin",
		# 喇叭口：半径沿 +Z 递增（越靠后越张开），模拟吸入流线。
		"trail_segments": [
			{"z": 0.16, "radius": 0.040, "height": 0.20, "alpha": 0.9},
			{"z": 0.34, "radius": 0.068, "height": 0.22, "alpha": 0.75},
			{"z": 0.54, "radius": 0.096, "height": 0.24, "alpha": 0.55},
		],
		"light_energy": 1.45,
		"light_range": 2.2,
		"pulse_rate": 5.5,
		"pulse_amplitude": 0.06,
	}
