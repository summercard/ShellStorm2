# -*- coding: utf-8 -*-
"""1152 事务：开局阶段三改（98F 门锁 / 第一间房灯 / 第二段刷怪排列）。"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(MEM, "2026-09-22")
TX = os.path.join(DAY, "1152_开局阶段三改_门锁灯与刷怪排列.md")
IDX = os.path.join(DAY, "_INDEX.md")
PB = os.path.join(MEM, "MEMORY-playbooks.md")


def load(p):
    raw = open(p, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s" % p
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(p, t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(p, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(p), data.count(b"\r"), data.count(b"\n")))


BODY = """# 开局阶段三改：98F 门锁 / 第一间房灯 / 第二段刷怪排列

> 类型：故障修复 + 体验调整（主人一条消息里的三件事）
> 关联：**2024**（第二段触发进深）、**1946**（运镜枢轴）

## ① 98F 每个房间都要钥匙 —— 根因是「和平区」是空承诺
- 区块00（98F）声明 `PEACEFUL_ZONE = true`；`Dungeon3D._door_policies_for_record()` 也确实为它算出
  `requires_clear/requires_key/triggers_fate` 全 false 的策略，并按**门方向**存进 `DungeonRoom3D.door_policies`。
- ⛔ 但**门开启路径** `Dungeon3D._try_open_room_door()` 走的是
  `_door_policy_for_edge()` —— 一个**硬编码三项全 true** 的函数，**根本没读**房间声明的那份。
  ⇒ 98F 每扇门都要「先清房 + 消耗房间钥匙」（人报「98 层每个房间都有钥匙」），且运行时零报错。
- 修法：新增 `_door_policy_towards(room_id, target_room_id)` —— 先用 `door_targets` 把目标房反查回
  方向，命中 `room.door_policies` 就用那份，缺失才回落 `_door_policy_for_edge()`。
  对非和平区**行为逐值不变**（`_door_policies_for_record` 给它们的本来就是同一份默认策略）。
- 守卫：真机验收 F 段断言四房策略三项全放行 + **源码级守卫**（开门函数体必须含 `_door_policy_towards(`，
  退回旧函数即变红）。

## ② 开局第一间房的灯默认打开
- 玩家在新游戏开场落在 `floor_01_exit`（主人办公室，COMBAT）。`DungeonRoom3D` 原先只有
  `room_type in ["STAIR_LOBBY", "BOSS"]` 才 `starts_on = true` ⇒ 普通房开局是**黑的**。
- 修法：新增**按房间声明**的 `authored_room_light_on`（全链透传：区块00 房表 → 塔楼 record →
  Dungeon3D / TowerDescent3D **两处 configure** → `DungeonRoom3D`），办公室声明 true。
  `starts_on := authored_room_light_on or room_type in ["STAIR_LOBBY", "BOSS"]`。
  ⚠️ `_apply_pending_detail_runtime_state()` 里 `room_light_on` 的**默认值**也必须跟着声明走
  （写死 false 会在重建时把「初始灯亮」顶掉）。
- ⛔ 只补一处 configure 是不够的（第一遍就漏了 `TowerDescent3D:4553` 那处，办公室仍黑的）——
  与 playbooks 里「两处 `configure()` 都要补」的老教训同源。
- 守卫：真机验收 G 段断言办公室 `is_room_light_on()` 为真 + **反向对照**会议室仍默认关（不是全层点亮）。

## ③ 第二段刷怪：再往东 15m + 南北交错排列
- `scene.spawn` 新增三种能力（与触发器同一套锚法）：
  - **房间相对锚点** `point_room` + `point_offset`（`room.to_global(offset)`，运行期解析）——
    触发器改成位置触发后玩家落点会在半径内浮动，玩家相对的站位跟着抖，钉不住；
  - `axis`：`"forward"`（默认沿视线）/ `"x"`（东西）/ `"z"`（南北）决定队列**沿哪个方向排开**；
  - `stagger_m`：相邻两只沿**排列轴的垂直方向交替错开**（`Dungeon3D.narrative_spawn_enemies` 新增
    `stagger` 形参），避免一条笔直的队。
- 剧本 02 定稿：`point_room: floor_01_main_02` + `point_offset: [6.0, 0.0, 0.0]` + `axis: "z"` +
  `spread: 1.6` + `stagger_m: 1.4`（原来的 `side/distance/forward_m` 撤下）。
- **真机实测**：会议室中心 `(-5, -24, 2.5)` ⇒ 刷怪点 **`(1.0, -24, 2.5)`**（离西门 26m），
  队列沿 z 从南到北排开、相邻两只在 x 上交错 ±0.7m。刷怪点在房内（G 段断言）。

## 验收
- `verify_narrative_timeline`：103 → **105 项**（C2 换位置触发 + 三条房间相对/排列轴/交错断言）。
- `verify_opening_script_runtime`：29 → **52 项**（E 几何 / F 门策略+源码守卫 / G 灯+刷怪点）。
- 途中踩坑：① 我在 `Dungeon3D` 插入交错代码时**缩进少一层**（`for` 循环外 ⇒ `Identifier "index" not declared`）；
  ② 那条「队列最后一只在玩家前方」的旧断言是为**玩家相对**写的，换房间相对后失效，已改写。

## 一句话
98F 的「门只做普通开关」原先只是注释 —— 开门路径读的是硬编码默认策略；现在优先读房间声明的策略。
开局第一间房（办公室）的灯按房间声明默认打开；第二段刷怪改为**房间相对**钉点、南北排列、相邻交错。
"""

save(TX, BODY)

ROW = (
    "| 11:52 | [开局阶段三改：98F 门锁 / 第一间房灯 / 第二段刷怪排列](1152_开局阶段三改_门锁灯与刷怪排列.md) "
    "| **故障修复 + 体验调整** "
    "| ① **98F 每扇门都要钥匙**（人报）：区块00 的 `PEACEFUL_ZONE` 只算出了策略、**开门路径却读硬编码默认**"
    "（`_door_policy_for_edge` 三项全 true）⇒ 新增 `_door_policy_towards()` 优先读房间声明的 `door_policies`"
    "（非和平区行为逐值不变）。② **开局第一间房（办公室）灯默认开**：新增按房声明的 `authored_room_light_on`"
    "全链透传（**两处 configure 都要补**，第一遍漏了塔楼那处），初始态默认值也跟着声明走。"
    "③ **第二段刷怪**：`scene.spawn` 新增房间相对锚点 + `axis`（南北）+ `stagger_m`（相邻交错）；"
    "定稿 offset `[6,0,0]`、`axis:\"z\"` ⇒ 真机实测刷怪点 `(1.0,-24,2.5)`（离西门 26m）。"
    "验收：假世界 103→**105 项**、真机 29→**52 项**（含开门路径**源码级守卫**与灯的反向对照） |"
)
if os.path.exists(IDX):
    t = load(IDX)
    assert sum(1 for l in t.split("\n") if l.startswith("| 11:52 |")) == 0
    lines = t.split("\n")
    out = []
    hit = 0
    for i, l in enumerate(lines):
        out.append(l)
        if hit == 0 and l.startswith("|---") and i > 1:
            out.append(ROW)
            hit = 1
    assert hit == 1, "索引表头未找到"
    save(IDX, "\n".join(out))
else:
    save(IDX, "# 2026-09-22 事务索引\n\n> 约定见 [`../README.md`](../README.md)。\n\n"
              "| 时间 | 事务 | 类型 | 结论一句话 |\n|---|---|---|---|\n" + ROW + "\n")

NOTE = """### 开局 · 98F 门策略 / 房间灯 / 剧情刷怪锚点（2026-09-22）
- ⛔ **「和平区门只做普通开关」曾经只是注释**：`_door_policies_for_record()` 算出的放行策略存进了
  `DungeonRoom3D.door_policies`，但**门开启路径** `_try_open_room_door()` 读的是 `_door_policy_for_edge()`
  ——硬编码 `requires_clear/requires_key/triggers_fate` 全 true ⇒ 98F 每扇门都要清房+钥匙，零报错。
  现改为 `_door_policy_towards()`：按 `door_targets` 反查方向 → 优先读房间声明，缺失才回落（非和平区逐值不变）。
- **房间初始灯亮**：`DungeonRoom3D` 原按房型给 `starts_on`（只有 STAIR_LOBBY/BOSS 亮）。要「开局第一间房
  默认开」得加**按房声明**的 `authored_room_light_on`，全链透传到 `starts_on`；⚠️ 还要把
  `_apply_pending_detail_runtime_state()` 里 `room_light_on` 的**默认值**改成它，否则重建时被顶掉。
  ⚠️ 注意有**两处 `room.configure()`**（Dungeon3D + TowerDescent3D），漏一处该房仍黑。
- **`scene.spawn` 三种新参数**：房间相对锚点 `point_room`+`point_offset`（`room.to_global()`）、
  `axis`（forward/x/z 决定队列沿哪排开）、`stagger_m`（相邻两只沿垂直方向交替错开）。
  触发改位置触发后玩家落点会浮动 ⇒ 刷怪站位要钉住就得用房间相对（实测会议室 offset `[6,0,0]` ⇒ (1,-24,2.5)）。
- 守卫：真机验收里 F 段带**源码级守卫**（开门函数体必须含 `_door_policy_towards(`），G 段带灯的反向对照。"""
t = load(PB)
save(PB, t.rstrip("\n") + "\n\n" + NOTE + "\n")

print("ALL_DONE")
