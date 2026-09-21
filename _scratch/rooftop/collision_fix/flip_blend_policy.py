"""反向对照（reverse-control）辅助脚本 —— 默认禁用。

用途：把 100F 天台布局 .blend 里 ROOFTOP_LAYOUT_INSTANCES 集合中
collision_policy == "blocking" 的实例（20 件绿化）翻回 "visual_only"，
用来验证 QA 校验器确实会因该契约缺失而变红。

⚠️ 本脚本会**直接改写真实 .blend**（git 未跟踪，无法用 git 回滚）。
   → 必须先做字节快照，跑完立刻从快照还原：
     _scratch/rooftop/collision_fix/layout.green.before_validator_reverse.blend
   → 只有在显式设了环境变量 ALLOW_REVERSE_CONTROL=1 时才会执行翻转，
     防止误跑把正式布局改坏。
"""

import os
import sys

import bpy

ALLOW_ENV = "ALLOW_REVERSE_CONTROL"

BLEND = (
    "I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/"
    "rooftop/source/layouts/100f_decorated_v001/rooftop_100f_decorated_layout_v001.blend"
)


def main() -> int:
    if os.environ.get(ALLOW_ENV) != "1":
        sys.stderr.write(
            "REFUSED: 本脚本会直接改写真实 .blend（破坏性）。\n"
            "如确需做反向对照，请先做字节快照，然后显式设 %s=1 再跑，\n"
            "跑完立即从快照还原。\n" % ALLOW_ENV
        )
        return 2

    bpy.ops.wm.open_mainfile(filepath=BLEND)
    col = bpy.data.collections.get("ROOFTOP_LAYOUT_INSTANCES")
    flipped = 0
    for ob in col.objects:
        if ob.get("collision_policy", "") == "blocking":
            ob["collision_policy"] = "visual_only"
            flipped += 1
    print("REVERSE_FLIP_COUNT=%d" % flipped)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
