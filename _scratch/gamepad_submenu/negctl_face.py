"""三档朝向的反向对照开关：一次只破坏一个性质，跑验收应精准变红。

用法（在 ShellStorm2/ 下跑）：
    python _scratch/gamepad_submenu/negctl_face.py off <rc>
    python _scratch/gamepad_submenu/negctl_face.py on  <rc>

rc 取值：
    tier    掐掉左摇杆那一档（move_raw 恒为 0）
    hyster  把滞回系数改成 1.0（等于没有滞回）
    smooth  第二档改成瞬跳（不平滑，等价「甩枪」）

`off` = 注入缺陷（期望变红）；`on` = 还原。每个 rc 各自备份一份 .bak_<rc>。
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in [HERE, *HERE.parents] if (p / "project.godot").exists())
TARGET = ROOT / "src" / "core" / "GamepadInput.gd"

PATCHES: dict[str, tuple[str, str]] = {
    # 左摇杆那一档整体失效。
    "tier": (
        "\tvar move_raw := _read_stick_axes(device, STICK_LEFT) if left_stick_aim else Vector2.ZERO",
        "\tvar move_raw := Vector2.ZERO  # REVERSE-CONTROL tier",
    ),
    # 滞回系数 1.0 ⇒ 退出阈值与进入阈值重合 ⇒ 没有保持区。
    "hyster": (
        "const STICK_HYSTERESIS_FACTOR := 0.7",
        "const STICK_HYSTERESIS_FACTOR := 1.0  # REVERSE-CONTROL hyster",
    ),
    # 第二档不平滑：直接跳到目标角。
    "smooth": (
        "\t\tvar rate := AIM_SMOOTHING_BASE_RATE * (1.0 - InputSettings.get_aim_smoothing())\n"
        "\t\tvar weight := 1.0 - exp(-maxf(rate, 0.01) * delta)\n"
        "\t\t_aim_angle = lerp_angle(_aim_angle, target_angle, clampf(weight, 0.0, 1.0))",
        "\t\t_aim_angle = target_angle  # REVERSE-CONTROL smooth",
    ),
}


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 1
    action, rc = argv[1], argv[2]
    if rc not in PATCHES:
        print("未知 rc：%s（可选 %s）" % (rc, ", ".join(PATCHES)))
        return 1
    healed, broken = PATCHES[rc]
    backup = HERE / ("GamepadInput.gd.bak_%s" % rc)

    if action == "off":
        if backup.exists():
            print("SKIP %s 已有备份（先 on 还原）" % rc)
            return 1
        text = TARGET.read_bytes().replace(b"\r\n", b"\n").decode("utf-8")
        if text.count(healed) != 1:
            print("FAIL %s 锚点命中 %d 次" % (rc, text.count(healed)))
            return 1
        shutil.copyfile(TARGET, backup)
        TARGET.write_bytes(text.replace(healed, broken, 1).replace("\n", "\r\n").encode("utf-8"))
        print("OFF %s 已注入缺陷" % rc)
        return 0

    if action == "on":
        if not backup.exists():
            print("SKIP %s 没有备份（本来就是好的）" % rc)
            return 1
        shutil.copyfile(backup, TARGET)
        backup.unlink()
        print("ON  %s 已还原" % rc)
        return 0

    print(__doc__)
    return 1


def _healed_text(rc: str) -> str:
    """当前「好」的写法（PATCHES 的左边）。给调试探针用。"""
    return PATCHES[rc][0]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
