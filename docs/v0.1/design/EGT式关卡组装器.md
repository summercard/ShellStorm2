# EGT 式关卡组装器 · 实现说明

代码：`src/map/EgtFlowAssembler.gd`（1137 行，纯静态类，不改动现有 `FloorPlanGenerator`）
验收：`tests/verification/verify_egt_flow_assembler.gd`（已登记进 `run_verification_suite.sh`）
出图：`docs/art/egt_flow_layouts/index.html`

---

## 1. 一句话原理

> **房间不存坐标，只存出口。** 拼装 = 从新房间取一个出口、从已放好的结构取一个出口，
> 凑成一对、对齐 —— 新房间的位置就确定了。

反编译原文：*"Exits are pre-defined locations in the metadata for each room."*

所以整套系统分两半：

| 一半 | 谁负责 | 本项目落点 |
|---|---|---|
| 出口在哪 | 房间模板 | `room_templates/*.json` 的 `wall_lane_table` |
| 怎么配对 | 组装器 | `EgtFlowAssembler._aligned_center()` |

---

## 2. 五段管线

| 段 | 函数 | 做什么 | 随机 |
|---|---|---|---|
| 1 选骨架 | `pick_flow()` | 从一层 4~8 张 flow 抽一张 | ★ |
| 2a 选模板 | `assign_templates()` | 每节点挑模板；池子够大时优先未用过的 | ★★ |
| 2b 注入 | `apply_injections()` | 按规则插特殊节点 | ★★ |
| 3 拆最小环 | `cut_loops()` | 每条 loop 边 + 它在树上的路径 = 一个环 | — |
| 4+5 拼装 | `_layout_all()` | 树 DFS + 补齐所有未落的边 | 部分 |

### 2.1 对齐公式（核心）

`_aligned_center(a, side_a, lane_a, b_size, side_b, lane_b)`：

```
side_a = east:  b.x = a.x + (a.w + b.w) / 2
                b.y = a.y + lane_a - lane_b      ← lane 是沿墙轴的偏移
side_a = west:  b.x = a.x - (a.w + b.w) / 2,  b.y 同上
side_a = south: b.y = a.y + (a.h + b.h) / 2
                b.x = a.x + lane_a - lane_b
side_a = north: b.y = a.y - (a.h + b.h) / 2,  b.x 同上
```

方向约定与 `RoomDoorLane.port_pair()` 一致：**north = −z，south = +z，east = +x，west = −x**。

`_best_pair()` 遍历「锚点侧全部空闲槽 × 子房侧全部候选槽」，先筛掉会重叠的，
再按"到锚点最近"打分（紧凑优先，图更容易连成一片）。

### 2.2 回溯 = 重抽模板，不是改边

原文：*"it will backtrack and regen the choice of room, up to 3 times."*

第一版理解错了，做成"接不上就换一个已放置房间当锚点"。后果很严重：

> 图上 `hub_01-n03` 相连，实际把 `n03` 接到了 `entry` 上 —— **生成的地图和设计不符，等于没复刻。**

正确做法（本实现）：某间房贴不上就**整次布局重来并重抽池子模板**，
最多 24 次（一张骨架 17 间房，3 次远远不够）。拓扑自始至终由 flow 决定。

### 2.3 环的处理

原文：*"loop composites are laid out by adding entries alternately at either end of a line …
Once the loop is half constructed, it starts to prefer exit pairs that bring the two
unclosed ends closer together. … Otherwise it pathfinds between the exits, and makes a
'room' that is just a narrow corridor."*

**踩过的坑**：曾试图把环成员从树 DFS 排除、让环"独立两端合"。结果环在 flow 里
常常是"树的一段 + 一条回边"，挖走这段后，挂在环下面的整棵子树（boss / shop / exit…）
再也走不到 —— 实测 flow_01 每次都有 7 间房"与主图不连通"。

**现在的做法**：

1. 树 DFS 一次铺**全部**节点（连通性由它保证）；
2. `_connect_remaining_edges()` 对**每一条还没落门的边**补连接，环的闭合边走这条路；
3. 补法：先试"两房已共墙、直接对齐门"（`_try_direct_close`），否则补走廊
   （`kind = "corridor"`，长度 = 门距向上取整到 5m）。

所以图上的走廊**只出现在环的闭合那一段**，其余全是房间直接贴合 —— 这正是 EGT 的形状。

---

## 3. 注入

原文四要素：`{注什么类型, 注在哪, 概率, 前置条件}`。

- `dead_end_first`：只在死胡同（度 1 且非根）挂；没有死胡同按 `anchor_fallback_probability` 决定是否退到任意房间。
- `scope: "run"`（跨层预算）：**本层不决定**，如实记进 `skipped`，不静默忽略。
- 注入房的模板是**推定值**（`INJECTION_TEMPLATE`）—— flow 只声明 kind，不声明用哪个模板。

---

## 4. 验收

```
ASSEMBLE flow_01  12/12 ok  loops=1.0 corridors=1.0
…
ASSEMBLE_CHECKED runs=72 ok=72 checks=17797
EGT_ASSEMBLER_OK runs=72 checks=17797
```

六张骨架 × 12 个种子 = 72 次，**全部成功**，17797 项检查全绿：

| 断言 | 内容 |
|---|---|
| 不重叠 | 两两求矩形交集，面积 > 0 即失败（共墙贴合面积为 0，允许） |
| 每条边都落门 | `_verify_edges`：图上每条边都必须有对应 connection |
| 门位合法 | 每个门槽必在 `RoomDoorLane.lane_offsets(墙长)` 里 |
| 门坐标一致 | `direct` 连接：两门绝对坐标差 ≤ 1cm；`corridor` 连接：走廊长度盖得住门距 |
| 无孤立房 | 每间房至少一个门 |
| 确定性 | 同 seed 两次坐标逐字节相同；换 seed 布局必须变 |

### 4.1 反向对照（证明门禁真的会红）

| 注入的错 | 结果 |
|---|---|
| 跳过环的闭合边 | ✅ 报「边 n06-reward_02 没有落门」 |
| 走廊长度只算一半 | ✅ 报「走廊 28m 盖不住门距 53.85m」 |
| 关掉重叠检查 | ✅ 报「boss 与 shop 重叠 10.00×5.00」 |

> 另有一条对照**没抓到**：把 `east` 分支的贴合距离改错。原因是算法会绕开那个方向、
> 用其他方向拼出合法图 —— 房间都贴合、门都重合，只是形状变差。这不算漏洞
> （契约仍然成立），但也说明「改坏一处 ≠ 一定失败」，所以门禁要验的是**契约**而非**形状**。

---

## 5. 已知偏差（如实记录）

| 项 | 现状 | EGT |
|---|---|---|
| 走廊长度 | 观测到最长 **70m** | 原文 4~30 单位（矿坑 50） |
| 环的"两端合" | 已实现（后半段朝另一侧开口拉近），但树 DFS 往往先铺完，实际多由走廊闭合 | 独立两端合，未闭合段较短 |
| 注入权重 | 只有 flow 声明的 3 条（隐藏房/NPC/壁炉） | 还有商人、牢房、电梯等，权重未公开 |
| 跨层预算 | 未实现（`scope: "run"` 只记录不执行） | 开局抽一次分配给将来某一层 |

**70m 走廊的原因**：树 DFS 铺满后，环两端可能相距较远。要缩短得让环成员参与
"拉近"决策，即真正实现两端合 —— 但那会重新引出 2.3 里那个连通性坑，
需要"环内子树归属"的完整解法。当前选择先保证**拓扑正确、每条边都连通**。

---

## 6. 复现

```bash
# 组装 + 出图
godot --headless --path . --script res://tests/verification/export_egt_layouts.gd
python3 scripts/render_egt_flow_layouts.py

# 验收
godot --headless --path . res://tests/verification/verify_egt_flow_assembler.tscn
```

---

## 7. 还没接的地方

组装器输出的是**房间表**（中心坐标 + 尺寸 + 门槽），还没有：

- 没有转成 `Dungeon3D` 的 record 结构并真的进游戏；
- 没有消费 `door_catalog.json`（哪种门落哪条边）；
- 没有消费 56 种 `egt_*` 白盒（目前用的是远征03 的 8 个模板）；
- `level_plan.json` 的 `generation_policy.mode = "flow"` 仍是 `runtime_enabled = false`。

**下一步**应该先做「房间表 → Dungeon3D record」这一层，才能真进场看。
