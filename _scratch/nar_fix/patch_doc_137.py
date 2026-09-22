# -*- coding: utf-8 -*-
"""08 文档：actor 表补 `actor.face` + 目标点说明；真机项数 87→105；追加 §13.7 开场口径。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"

FACE_ROW_ANCHOR = "| `actor.turn_to` |"
FACE_ROW = (
    "| `actor.face` | `yaw_deg` / `relative` / `duration` / "
    "**`to_point_room` + `to_point_offset`** / **`point_m`** | "
    "直写 `Player3D.aim_yaw`（绝对方位）并同步 `avatar.visual_root`。"
    "`yaw_deg` 缺省是**绝对**方位；`relative: true` 才是相对**序列基准**（「左右张望」用这个）。"
    "给了目标点就压过两者（见下） | ✅ |\n"
)

FACE_NOTE_ANCHOR = "**`fx`**\n"
FACE_NOTE = '''
**`actor.face` 的目标点（2026-09-22 新增）**：要「**对着某件东西**说 / 看」时**不能写相对角度** ——
玩家出生朝向由鼠标决定、**不确定**。给一个点，方位由目标点反解（与 `Player3D` 同口径
`aim_yaw = atan2(-dir.x, -dir.z)`，只取水平分量）：

- `to_point_room` + `to_point_offset: [x, y, z]` —— **房间相对**（推荐）；世界坐标 = `room.to_global(offset)`。
  房间是运行时生成的，写死世界坐标会在换布局后**静默指偏**。
- `point_m: [x, y, z]` —— 显式世界坐标（优先级最高）。

给了目标点就压过 `yaw_deg` / `relative`；找不到房间或偏移写错一律**告警并退回 `yaw_deg`**，不静默。
⚠️ 朝向的归还是在**剧本收口时**统一做的（占用法 `_occupy`），所以「转向 → 说话 → 再 `flow.end`」
这一串里角色会**一直保持**转过去的方向，不会在开口前弹回来。

'''

COUNT_OLD = "**87 项**检查"
COUNT_NEW = "**105 项**检查"
CLAUSE_OLD = "/ H（98F 和平区不产出房间钥匙 + HUD 目标文案不提钥匙） |"
CLAUSE_NEW = "/ H（98F 和平区不产出房间钥匙 + HUD 目标文案不提钥匙）/ I（开场武装口径：身上无枪 + 保底备弹仍能入包 + 地上那把出厂枪的落位与「剧本目标点 == 落位常量」） |"

SECT_ANCHOR_TAIL = "和 \u00a713.5 \u7684\u56db\u4e2a\u7f3a\u9677\u540c\u7c7b\uff1a**\u5168\u90e8\u96f6\u62a5\u9519\uff0c\u53ea\u6709\u4eba\u62a5\u624d\u4f1a\u53d1\u73b0\u3002**</span>\n"

SECT = '''
### 13.7 开场的交互与武装口径（2026-09-22）

| # | 主人要求 | 落地 |
|---|---|---|
| 1 | 锁死移动与鼠标**动作**，但**鼠标还能转视角** | **已有口径，不动代码**：`Player3D.set_input_locked(true)` 只拦移动 / 射击 / 换弹 / 冲刺 / 交互，**不拦鼠标瞄准**（源码注释原话「input_locked 不拦瞄准」）。⚠️ 唯一例外是 `actor.face` 占用朝向期间（`_narrative_holds_aim()`）——那是 §13.5 缺陷③的修复，防止玩家晃鼠标把剧本摆好的「左右张望」顶掉 |
| 2 | 第一个房间的灯默认开 | §13.6 已落地（`authored_room_light_on`），本次不动 |
| 3 | 第二段：镜头**平移到**怪物 → 看到 → **平移回来** | 已有（`camera.pan` 的 `pivot: "last_spawn"` → `pivot: "player"`），本次只改台词与提示 |
| 4 | 玩家说「黑暗中是什么东西！」＋ 系统提示「打开你身上的手电，那里有危险！按F开启手电」 | 剧本 02：`actor.say` 改词；台词后接 `ui.hint`（`auto: 4.0`，走 `DialogueUI.announce`）。**`duration` 加到 10.6 覆盖到提示播完** —— 玩家得按到 F，就不能在提示还在时解锁 |
| 5 | 开场**身上没有枪、但保留备弹** | `TowerDescent3D._reset_new_game_opening_loadout()` 用 `Player3D.clear_all_equipped_weapons()` 收回。**只动「新游戏开场」这一条分支** —— 天台出生 / 死亡返城 / 撤离返航照旧白送枪（那些路径靠 `start_with_weapon` 的默认值）。保底备弹 `GUARANTEED_LOADOUT_AMMO_ROUNDS = 300` 本来就与「有没有枪」解耦 |
| 6 | 他原本那把枪放在办公室**靠右近门**的地上 | 收回函数的**返回值**就是他那一把的原样实例（含已装命运改造），直接落地 —— 不重新造一把。落点 `NEW_GAME_OPENING_DROP_OFFSET`（房间局部）；真机实测办公室东门在局部 `(7.5, 0, -2.5)` ⇒ 本值 = **离门 2.2m、出门方向（+x）右手侧 1.8m** |
| 7 | 起身后对着枪说「那是主人留下的礼物。。」**再**解锁 | 剧本 01 尾段：`actor.face`（`to_point_room` + `to_point_offset` 指那把枪）→ `actor.say` → `flow.end` @18.0s。占用法保证说完之前朝向不弹回 |

<span style="color:#791F1F">**三个只在真机上才露头的点：**</span>

1. **掉落物有确定性散布。** `_spawn_loot_items()` 会按「第几件」把落点推出去
   （实测 index 0 = `(cos0.45, 0, sin0.45) * 0.7` ≈ **偏 0.70m**）。单件、且落点要被剧本的
   `actor.face` 精确引用时，散布会让「指的那个点」与「枪实际在哪」**差 0.7m**（转身指偏）。
   已给该函数加 `spread := true` 形参（默认不变，其余三个调用方一字未动），开场那把枪传 `false`。
2. **备弹发放被 `test_mode` 挡住。** 真机路径是 `if not test_mode: _grant_guaranteed_loadout_ammo()`，
   而真机探针本身跑在 `test_mode` 下 ⇒ 探针里备弹恒为 0。所以探针改为**显式调一次发放**，
   验真正关心的那条关系：**把枪收回之后，备弹照样能进包**（实测 0 → 300），
   外加源码守卫：发放条件只能是「非 test_mode」，**不能被「有没有枪」挟持**。
3. **`.gd` 源码是 CRLF，探针里跨行 `contains` 会永远为假。** 源码守卫用 `\\n` 去搜
   `"if not test_mode:\\n\\t\\t_grant..."` 这种两行片段**必然搜不到** ⇒ 守卫变成「永远红」。
   守卫读源码后必须 `.replace("\\r\\n", "\\n")` 再用。
   （同一条也适用于写这类守卫本身：它红了先怀疑它自己。）

**验收**：`verify_opening_script_runtime` 从 87 → **105 项**（新增 I 段 17 项 + F 段门节点 1 项）。
`verify_narrative_timeline` 仍是 **105 项**（C1 台词改两句、C2 台词改词、假世界补一个「办公室」房
供新 `actor.face` 的房间相对目标点解析）。
'''

DOC_EXTRA_OLD = "### 13.7 开场的交互与武装口径（2026-09-22）\n"


def patch_one(old: str, new: str, label: str) -> bool:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE: 行尾不纯")
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if new in text:
        print("%s: already" % label)
        return False
    n = text.count(old)
    if n != 1:
        print("SKIP %s: 锚点命中 %d" % (label, n))
        return False
    text = text.replace(old, new)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write")
    open(P, "wb").write(data)
    print("%s OK CR=%d LF=%d" % (label, data.count(b"\r"), data.count(b"\n")))
    return True


def main() -> int:
    patch_one(FACE_ROW_ANCHOR, FACE_ROW + FACE_ROW_ANCHOR, "face-row")
    patch_one(FACE_NOTE_ANCHOR, FACE_NOTE.lstrip("\n") + FACE_NOTE_ANCHOR, "face-note")
    patch_one(COUNT_OLD, COUNT_NEW, "count")
    patch_one(CLAUSE_OLD, CLAUSE_NEW, "clause")
    patch_one(SECT_ANCHOR_TAIL, SECT_ANCHOR_TAIL + SECT, "sect-13.7")
    return 0


if __name__ == "__main__":
    sys.exit(main())
