"""瞄准手感改版（响应曲线 + 瞄准辅助）的反向对照注入器。

三组缺陷，各自只破坏一个性质，用来证明新断言有判别力：
  curve  把 resolve_aim_speed_scale 退化成恒 1.0（拿掉幅度权威）
  dark   把 is_eligible 的「黑暗不可吸」判断拿掉（等于给玩家透视）
  cap    把 solve 的偏转上限拿掉（准星会被一次吸满 = 抢控制）

用法：
  python negctl_assist.py <curve|dark|cap> off   # 注入缺陷（自动备份）
  python negctl_assist.py <curve|dark|cap> on    # 还原
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = next(
    p
    for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents]
    if (p / "project.godot").exists()
)

GAMEPAD = ROOT / "src/core/GamepadInput.gd"
ASSIST = ROOT / "src/player3d/AimAssist3D.gd"
PLAYER = ROOT / "src/player3d/Player3D.gd"

# (文件, 修复后文本, 破损文本)
PATCHES = {
    "curve": (
        GAMEPAD,
        """	var t := clampf(magnitude_after_deadzone, 0.0, 1.0)
	var shaped := pow(t, AIM_RESPONSE_EXPONENT)
	return (
		AIM_PRECISION_SPEED_SCALE
		+ (AIM_FLICK_SPEED_SCALE - AIM_PRECISION_SPEED_SCALE) * shaped
	)""",
        """	return 1.0""",
    ),
    "dark": (
        ASSIST,
        """	if illumination_state == EnemyIllumination3D.STATE_DARKNESS:
		return false""",
        """	pass""",
    ),
    "cap": (
        ASSIST,
        """	var limit := (
		deg_to_rad(float(options.get("max_angle_deg", DEFAULT_MAX_ANGLE_DEG)))
		* strength
		* best_weight
	)
	var delta := clampf(flat_aim.angle_to(best_direction), -limit, limit)""",
        """	var delta := flat_aim.angle_to(best_direction)""",
    ),
    # 胶水层：把敌人的真实照明状态换成常量「阳光」，模拟「接线取错字段」。
    # 纯函数测试看不出来，只有端到端用例能抓。
    "glue": (
        PLAYER,
        """			enemy.get_illumination_state(),
			distance,""",
        """			EnemyIllumination3D.STATE_SUNLIGHT,
			distance,""",
    ),
}


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in PATCHES or argv[2] not in ("on", "off"):
        print("用法: python negctl_assist.py <curve|dark|cap> <on|off>")
        return 2
    key, action = argv[1], argv[2]
    path, healed, broken = PATCHES[key]
    text = path.read_text(encoding="utf-8")
    if action == "off":
        if healed not in text:
            print(f"FAIL {key}: 找不到待破坏的原文（可能已注入）")
            return 1
        path.write_text(text.replace(healed, broken), encoding="utf-8")
        print(f"OK {key}: 已注入缺陷（{path.name}）")
    else:
        if broken not in text:
            print(f"FAIL {key}: 找不到破损文本（可能已还原）")
            return 1
        path.write_text(text.replace(broken, healed), encoding="utf-8")
        print(f"OK {key}: 已还原（{path.name}）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
