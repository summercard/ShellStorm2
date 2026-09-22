# -*- coding: utf-8 -*-
"""写 2026-09-22/1524 事务 + 索引行 + playbooks 追加段。幂等、CRLF 纯净。"""

import os
import sys

ROOT = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(ROOT, "2026-09-22")
TXN = os.path.join(DAY, "1524_开场剧情四改_锁输入第二段提示与地上那把枪.md")
IDX = os.path.join(DAY, "_INDEX.md")
PB = os.path.join(ROOT, "MEMORY-playbooks.md")

BODY = """# 开场剧情四改：锁输入口径 / 第二段台词与系统提示 / 开场无枪 / 地上那把枪

- 时间：2026-09-22 15:24
- 触发：主人按条列出开场演出的改动清单（第一条是「锁死移动和鼠标等内容，但是鼠标还是能旋转」）
- 涉及：`src/world3d/TowerDescent3D.gd`、`src/world3d/Dungeon3D.gd`、`src/narrative/NarrativeAdapter3D.gd`、
  `data/narrative/nar_tower_opening_01_wake.json`、`data/narrative/nar_tower_opening_02_zombies.json`、
  两个验收探针、`docs/v0.1/08_技术施工_剧情触发.md`

## 主人的七条 → 落地

| # | 要求 | 落地 |
|---|---|---|
| 1 | 锁死移动与鼠标**动作**，但**鼠标还能转视角** | **已有口径，没改代码**：`Player3D.set_input_locked(true)` 只拦移动/射击/换弹/冲刺/交互，**不拦鼠标瞄准**（源码注释原话「input_locked 不拦瞄准」）。唯一例外是 `actor.face` 占用朝向期间（`_narrative_holds_aim()`）——那是 §13.5 缺陷③的修复 |
| 2 | 第一个房间灯默认开 | §13.6 已落地，本次未动 |
| 3 | 第二段镜头平移到怪物再平移回来 | 已有（`camera.pan` 的 `pivot: last_spawn` → `pivot: player`） |
| 4 | 台词「黑暗中是什么东西！」＋ 系统提示「打开你身上的手电，那里有危险！按F开启手电」 | 剧本 02：改词 + 新增 `ui.hint`（`auto: 4.0`）；`duration` 7.0 → **10.6**，让提示播完才解锁（否则玩家按不到 F） |
| 5 | 开场身上没有枪、保留备弹 | `TowerDescent3D._reset_new_game_opening_loadout()`：`clear_all_equipped_weapons()` 收回。**只动「新游戏开场」分支**，天台/死亡返城照旧白送枪 |
| 6 | 那把枪放在办公室靠右近门的地上 | 收回函数的**返回值**就是他那一把的原样实例（含命运改造），直接落地。落点常量 `NEW_GAME_OPENING_DROP_OFFSET`（房间局部）；实测东门在局部 `(7.5, 0, -2.5)` ⇒ 房间局部 `(5.3, 0.05, -0.7)` = 离门 2.2m、出门方向（+x）右手侧 1.8m |
| 7 | 起身后对着枪说「那是主人留下的礼物。。」再解锁 | 剧本 01 尾段：`actor.face`（新能力，房间相对目标点）→ `actor.say` → `flow.end` @18.0s |

## 新增的引擎能力

**`actor.face` 支持「朝向一个目标点」**（`to_point_room` + `to_point_offset` / `point_m`）。
理由：「对着某件东西说」**不能写相对角度** —— 玩家出生朝向由鼠标决定、不确定。
方位由目标点反解（与 `Player3D` 同口径 `aim_yaw = atan2(-dir.x, -dir.z)`，只取水平）。
给了点就压过 `yaw_deg` / `relative`；找不到房间一律告警并退回，不静默。
朝向归还在**剧本收口时**统一做（占用法），所以「转向 → 说话 → `flow.end`」里朝向不会提前弹回。

## ⛔ 三个只在真机上才露头的坑

1. **掉落物有确定性散布。** `_spawn_loot_items()` 按「第几件」把落点推出去
   （实测 index 0 = `(cos0.45, 0, sin0.45) * 0.7` ≈ **偏 0.70m**）。
   单件、且落点要被剧本精确引用时，会让「指的那个点」与「枪实际在哪」差 0.7m。
   已加 `spread := true` 形参（默认不变，其余 3 个调用方一字未动），开场那把枪传 `false`。
2. **备弹发放被 `test_mode` 挡住。** 真机路径是 `if not test_mode: _grant_guaranteed_loadout_ammo()`，
   而真机探针本身就跑在 `test_mode` 下 ⇒ 探针里备弹恒为 0。
   改法：探针**显式调一次发放**，验真正关心的关系「把枪收回后备弹照样能进包」（实测 0 → 300），
   外加源码守卫：发放条件只能是「非 test_mode」，不能被「有没有枪」挟持。
3. **`.gd` 是 CRLF，探针里跨行 `contains` 永远为假。** 源码守卫用 `\\n` 搜
   `"if not test_mode:\\n\\t\\t_grant..."` 这种两行片段必然搜不到 ⇒ 守卫变成「永远红」。
   读源码后必须 `.replace("\\r\\n", "\\n")` 再用。（红了先怀疑守卫自己。）

## 验收

- `verify_opening_script_runtime` **87 → 105 项**全绿（新增 I 段）。
  真机实测：`地上那把枪 = (-27.2, -24.0, 4.3)，离东门 2.84m`；`保底备弹 0 → 300`。
- `verify_narrative_timeline` **105 项**全绿（C1 台词改两句、C2 台词改词、假世界补「办公室」房）。
- **反向对照**：塔楼常量 5.3→2.0 + 剧本 `flow.end` 18.0→15.0（挪到台词前）⇒ 精确变红；
  还原后逐字节干净。
- 途中自伤一处：GDScript **不支持链式比较** `a > b >= 0.0`（会解析成 `(a>b) >= 0`）⇒
  整脚本解析失败、探针挂住。已写成 `a > b and b >= 0.0`。

## 值得记住的

- 「区域/流程级的口径」要写在**分支入口**上（这里 = 新游戏开场落位那一步），
  不要改全局 export 的默认值 —— 后者会波及天台出生 / 死亡返城。
- 「收回武器」用 `clear_all_equipped_weapons()` 的**返回值**当掉落物，比重新造一把更贴主人原话
  （「玩家身上那把枪」），也顺带保住了命运改造。
"""

PB_ANCHOR = "### 开局 · 98F 门策略 / 房间灯 / 剧情刷怪锚点（2026-09-22）\n"
PB_BEFORE = """### 开场演出 · 交互与武装口径（2026-09-22）

- ⛔ **「锁死操作」不等于「锁死鼠标」**：`Player3D.set_input_locked(true)` 只拦移动/射击/换弹/冲刺/交互，
  **不拦鼠标瞄准**（源码原话「input_locked 不拦瞄准」）。所以「演出期间玩家不能动但能转视角」是**已有**行为，
  不用改代码。唯一例外是 `actor.face` 占用朝向期间（`_narrative_holds_aim()`）——那是为防玩家晃鼠标
  把剧本摆好的「左右张望」顶掉，故意加的。
- **`actor.face` 的目标点**（新增）：要「对着某件东西说/看」时**不能写相对角度**——玩家出生朝向由鼠标决定、
  不确定。用 `to_point_room` + `to_point_offset`（房间相对，世界坐标 = `room.to_global(offset)`）或
  `point_m`；给了点就压过 `yaw_deg` / `relative`，解出来的方位与 `Player3D` 同口径
  （`aim_yaw = atan2(-dir.x, -dir.z)`）。朝向归还在**剧本收口**时统一做，所以「转向→说话→flow.end」不会提前弹回。
- ⛔ **`_spawn_loot_items()` 会把落点推出去**（确定性散布：index 0 = `(cos0.45, 0, sin0.45) * 0.7`，**偏 0.70m**）。
  单件、且落点要被剧本的 `actor.face` 精确引用时必须传新增的 `spread := false`，否则「指的点」与「东西在哪」对不上。
- ⛔ **保底备弹被 `test_mode` 挡住**：真机是 `if not test_mode: _grant_guaranteed_loadout_ammo()`，
  而真机探针跑在 `test_mode` 下 ⇒ 探针里恒为 0。要在探针里验「无枪也能拿到备弹」，只能**显式调一次发放函数**，
  再配一条源码守卫（发放条件不能被「有没有枪」挟持）。
- ⛔ **探针里读源码做跨行 `contains` 必须先归一 CRLF**：本仓 `.gd` 是 CRLF，用 `\\n` 搜两行片段**永远为假**
  ⇒ 守卫自己变成「永远红」。读源码后 `.replace("\\r\\n", "\\n")` 再搜。
- **GDScript 没有链式比较**：`a > b >= 0.0` 会被解析成 `(a > b) >= 0` ⇒ `Invalid operands "bool" and "float"`，
  整脚本解析失败且**探针挂住不退**。写成 `a > b and b >= 0.0`。
- **「流程级口径」写在分支入口**（新游戏开场落位那一步），不要改全局 export 默认值——后者会波及
  天台出生 / 死亡返城。收回武器用 `clear_all_equipped_weapons()` 的**返回值**当掉落物，
  比重新造一把更贴原话，也保住命运改造。

"""

ROW = (
    "| 15:24 | [开场剧情四改：锁输入口径 / 第二段台词与系统提示 / 开场无枪 / 地上那把枪]"
    "(1524_开场剧情四改_锁输入第二段提示与地上那把枪.md) | **实际改动（引擎 + 剧本 + 验收）** | "
    "主人列表交代 → ①「锁操作但鼠标可转」是**已有**行为（`input_locked` 不拦瞄准）；"
    "②第二段台词改「黑暗中是什么东西！」+ 新 `ui.hint`「…按F开启手电」（`duration` 7→10.6 让提示播完才解锁）；"
    "③开场**收回玩家的枪**（用 `clear_all_equipped_weapons()` 的返回值）；④那把枪落到办公室东门内侧右手边"
    "（新常量 `NEW_GAME_OPENING_DROP_OFFSET`，实测离门 2.84m）；⑤新增 `actor.face` 房间相对目标点，"
    "起身后**对着枪**说「那是主人留下的礼物。。」再解锁。真机 **87→105 项**全绿，反向对照精确变红 |\n"
)


def main() -> int:
    os.makedirs(DAY, exist_ok=True)
    if os.path.exists(TXN):
        print("txn exists, skip")
    else:
        data = BODY.replace("\n", "\r\n").encode("utf-8")
        assert data.count(b"\r") == data.count(b"\n")
        open(TXN, "wb").write(data)
        print("txn written")

    # 索引
    raw = open(IDX, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n")
    t = raw.decode("utf-8").replace("\r\n", "\n")
    if "1524_开场剧情四改" in t:
        print("index row exists, skip")
    else:
        t = t.rstrip("\n") + "\n" + ROW
        data = t.replace("\n", "\r\n").encode("utf-8")
        assert data.count(b"\r") == data.count(b"\n") and b"\r\r" not in data
        open(IDX, "wb").write(data)
        print("index row appended")

    # playbooks
    raw = open(PB, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n")
    t = raw.decode("utf-8").replace("\r\n", "\n")
    if "开场演出 · 交互与武装口径（2026-09-22）" in t:
        print("playbooks exists, skip")
    else:
        n = t.count(PB_ANCHOR)
        assert n == 1, "playbooks 锚点命中 %d" % n
        t = t.replace(PB_ANCHOR, PB_BEFORE + PB_ANCHOR)
        data = t.replace("\n", "\r\n").encode("utf-8")
        assert data.count(b"\r") == data.count(b"\n") and b"\r\r" not in data
        open(PB, "wb").write(data)
        print("playbooks section added")

    for path in (TXN, IDX, PB):
        raw = open(path, "rb").read()
        print("%s CR=%d LF=%d" % (os.path.basename(path), raw.count(b"\r"), raw.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
