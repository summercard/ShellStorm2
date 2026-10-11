# -*- coding: utf-8 -*-
"""驱动 blender_unrig.py 的入口（配合 blender_bridge.py 使用）。

用法：
    # 干跑：只盘点，不改任何东西
    python blender_bridge.py --code-file blender_unrig_run.py --dry-run 是无效的（bridge 无参数机制）
    ⇒ 直接改下面 REPORT_ONLY 再跑。

    # 实际执行
    python blender_bridge.py --code-file blender_unrig_run.py

REPORT_ONLY=True 时等价于干跑，会打印盘点 + 校验两块 JSON。
"""

import bpy

REPORT_ONLY = False   # <-- 改成 True 就是干跑

SCRIPT = r"I:\工作项目\shellstrom2\tools\blender_unrig.py"

with open(SCRIPT, "r", encoding="utf-8") as f:
    src = f.read()

overrides = {"REPORT_ONLY": REPORT_ONLY} if REPORT_ONLY else {}
exec(compile(src, SCRIPT, "exec"), {"bpy": bpy, "_UNRIG_OVERRIDES": overrides})
