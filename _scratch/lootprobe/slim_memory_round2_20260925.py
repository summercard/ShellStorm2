# -*- coding: utf-8 -*-
"""MEMORY.md 瘦身 · 第二轮（2026-09-25）：
把「输入与手柄细则」「远景城市 / 99F 主灯」再下沉到 playbooks，MEMORY.md 只留口径与指针。
同样 CRLF 域写回 + 字节校验；未命中即退出。
"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
MAIN = os.path.join(MEM, "MEMORY.md")
PLAY = os.path.join(MEM, "MEMORY-playbooks.md")

NEW = """### 远景城市 / 99F 主灯 / 输入细则（2026-09-25 自 MEMORY.md 二次下沉）
**远景城市**
- `TowerAtmosphere3D.build_city_layout()` 是**纯函数**（headless 读不到 MultiMesh，只能读它）；布局贴 `TOWER_SHELL_WORLD_RECT` 环带，外墙外 15 m 起、环距 / 槽距 20 m、奇数环错半格、顶面高度 `-20 - ring*18 - (奇偶防 24)`。**改壳体必须同步它**。
**99F 玩法主灯**
- 真源 `assets/art/props/dungeon_3d/prp_base99_facility_main_light_top3d.tscn`；位置**不写进 prefab**，世界高 **11.62 m**、energy **×3.0**、`light_range` **≥28 m**。前置美术灯已接墙面开关（`visible` 定参与、开关定亮灭、延迟 2 s、`_set_spill_progress` 索引 0 不许跳基准）。全口径见上面「99F 玩法主灯 / 手摆美术灯接墙面开关」节。
**输入与手柄**
- `gamepad_left_stick_aim` 默认 false；死区滞回 ×0.7；绝不发零回鼠标。`AimAssist3D` 只吸「存活 + 已照亮 + 锥内 + 射程内」的目标、上限 8°。

"""

EDITS = [
    # 输入节 → 压
    (
        "- 玩法走 InputMap action（`InputSettings`/`InputDevice`/`GamepadInput`/`MobileInput`）。面向即弹道及准星；屏幕右投影 `Vector2(-f.y, f.x)`。手柄朝向三档 = 右摇杆>左摇杆>保持上次、绝不发零回鼠标、死区滞回 ×0.7；右摇杆瞄准「2+1」= `resolve_aim_speed_scale`（`clamp(t)^1.60`）+ `AimAssist3D`（上限 8°）。**细则见 playbooks「输入与手柄细则」**。",
        "- 玩法走 InputMap action（`InputSettings`/`InputDevice`/`GamepadInput`/`MobileInput`）。面向即弹道及准星；屏幕右投影 `Vector2(-f.y, f.x)`。手柄朝向三档 = 右摇杆>左摇杆>保持上次；右摇杆瞄准「2+1」= `resolve_aim_speed_scale`（`clamp(t)^1.60`）+ `AimAssist3D`（上限 8°）。**细则见 playbooks**。",
    ),
    # 远景城市 → 下沉
    (
        "- 远景城市 `TowerAtmosphere3D.build_city_layout()`（纯函数；headless 不能读 MultiMesh）：贴 `TOWER_SHELL_WORLD_RECT` 环带，外墙外 15m、环距/槽距 20m、奇数环错半格、顶面 `-20-ring*18-(奇偶防24)`。改壳体要同步。",
        "- 远景城市 `TowerAtmosphere3D.build_city_layout()` 是**纯函数**（headless 读不到 MultiMesh，只能读它）；**改壳体必须同步它**。参数见 playbooks「远景城市 / 99F 主灯 / 输入细则」。",
    ),
    # 99F 主灯 → 下沉（细节已在 playbooks 同名节）
    (
        "- 99F 玩法主灯真源 `assets/art/props/dungeon_3d/prp_base99_facility_main_light_top3d.tscn`（位置不写进 prefab、世界高 11.62m、energy ×3.0、`light_range` ≥28m）；前置美术灯已接墙面开关（`visible` 定参与、开关定亮灭、延迟 2s、`_set_spill_progress` 索引 0 不许跳基准）。**全口径见 playbooks「99F 玩法主灯」**。",
        "- 99F 玩法主灯真源 = `prp_base99_facility_main_light_top3d.tscn`（位置不写进 prefab、世界高 11.62 m、energy ×3.0、`light_range` ≥28 m）；前置美术灯已接墙面开关。**全口径见 playbooks「99F 玩法主灯」**。",
    ),
    # 记忆目录两套 → 压
    (
        "- 🔴 **记忆目录两套并存、互不可见（2026-09-25 实测）**：① 父目录 `I:/工作项目/shellstrom2/.workbuddy/memory/`（本机专用，**不在任何 git 内**，`MEMORY.md` 与 `MEMORY-playbooks.md` 只在这里）；② 仓库内 `ShellStorm2/.workbuddy/memory/`（**被 git 跟踪并推 GitHub**，另一会话在写）。同一日期可能两边都有内容（如 09-24 白天在①、深夜在②）。查历史**两边都要看**；待主子裁决统一口径前，勿擅自合并。",
        "- 🔴 **记忆目录两套并存、互不可见（2026-09-25 实测）**：① 父目录 `I:/工作项目/shellstrom2/.workbuddy/memory/`（本机专用、**不在 git 内**；`MEMORY.md` 与 `MEMORY-playbooks.md` 只在这里）；② 仓库内 `ShellStorm2/.workbuddy/memory/`（**被 git 跟踪并推 GitHub**，另一会话在写）。同一日期两边都可能有内容 ⇒ 查历史**两边都要看**；待主子裁决前勿擅自合并。",
    ),
    # 资产：骨架 + Blender 桥 → 压
    (
        "- 普通怪骨架 = 36 骨 Mixamo 式人形、全场共享；四足怪也套这套（`normal-enemy-model-pipeline`）。Blender 桥（9876；60600 是 Tripo 桥）见 `blender-mcp-bridge`。",
        "- 普通怪骨架 = 36 骨 Mixamo 式人形、全场共享（四足怪也套这套，见 `normal-enemy-model-pipeline`）；Blender 桥 9876 / Tripo 桥 60600，见 `blender-mcp-bridge`。",
    ),
    # 远征01 示例版图数字 → 压
    (
        "**示例版图实测**：面积 16675 m²、轮廓 13750 m²、内墙 ≈549、占用 ≈17224、包络 **235×215**、中心 (2.5,2.5)；300 种子 **回退 0**（旧「296/回退 4」已作废）。",
        "**示例版图实测**：面积 16675 m²、轮廓 13750 m²、占用 ≈17224、包络 **235×215**、中心 (2.5,2.5)；300 种子 **回退 0**（旧「296/回退 4」已作废）。",
    ),
]

main = open(MAIN, "rb").read().decode("utf-8").replace("\r\n", "\n")
play = open(PLAY, "rb").read().decode("utf-8").replace("\r\n", "\n")
before = len(main.encode("utf-8")) + len(play.encode("utf-8"))

missing = []
for old, new in EDITS:
    if old not in main:
        missing.append(old[:60])
        continue
    main = main.replace(old, new, 1)
if missing:
    print("!! 未命中，未写盘：")
    for m in missing:
        print("   -", m)
    raise SystemExit(1)

anchor = "### 远征01 怪物与掉落口径（2026-09-25 实测）"
if anchor not in play:
    print("!! playbooks 锚点未命中，未写盘")
    raise SystemExit(1)
if "远景城市 / 99F 主灯 / 输入细则（2026-09-25" in play:
    print("!! playbooks 已含本轮新节，未写盘")
    raise SystemExit(1)
play = play.replace(anchor, NEW + anchor, 1)

def write_crlf(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    open(path, "wb").write(data)
    return data

d_main = write_crlf(MAIN, main)
d_play = write_crlf(PLAY, play)
for name, data in (("MEMORY.md", d_main), ("MEMORY-playbooks.md", d_play)):
    crlf = data.count(b"\r\n")
    lone = data.count(b"\n") - crlf
    print("%-22s size=%d crlf=%d loneLF=%d crcr=%d" % (name, len(data), crlf, lone, data.count(b"\r\r")))
print("两文件合计 %d -> %d (%+d)" % (before, len(d_main) + len(d_play), len(d_main) + len(d_play) - before))
