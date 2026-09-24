# 0059 远征01 通道桥多层几何运行时装配（第 7 环）

- 提交：`d5cb9a40`（分支 `0.1.2`），6 文件 `610 insertions(+), 1 deletion(-)`。
- 业主口径（本会话逐字）：「上层平台就先做，下层平台先用墙往下做，然后下层的深度的地板用普通砖铺过去就好了。」
  ＋ AskUserQuestion 裁决：坑口 **「坑沿加护栏（推荐）」**；坑深 **「12 m（整层，一件标准墙刚好）」**；下层 **「下不去的，不用下去，就是装饰」**。

## 做了什么

数据层（`bridge_60x50.json` 的 `sunken_pit` 30×20 深 12 m / `bridge_span` 5 m）在上一环已落地；本环把它**接进运行时**。

**生成器 `src/map/FloorPlanGenerator.gd`（纯新增 235 行，0 删除）**
- 新增第 6 环多层规划：`attach_authored_layout_shell()` 房间循环里取 `_bridge_multi_level_plan(room, templates)`（非桥房返回空字典，逐字节不影响其它房间）。
- 上层平台砖**真扣坑区**：`slot_role == "floor_tile"` 且格心落在 `pit_rect` 内、不在 `bridge_rect` 内 ⇒ `continue`（不铺）。每间桥房扣 **18** 格（= 坑 24 格 − 桥面 6 格）。
- 多层件叠加进 `authored_layout_instances`，回写 `room["authored_layout_multi_level_room"] = true`。
- `_bridge_multi_level_instances()` 产出两类：
  - **坑壁/护栏 30 件** = 坑南北壁 6×2 + 坑东西壁 (4−1 桥口)×2 + 桥侧壁 6×2 ⇒ 一件标准墙（11.9 m）按 `scale_y` **纵向拉伸到 12.8 m**，其中 12 m 沉在坑里、**露地面 0.8 m 即护栏**（与坑壁同材质、视觉连贯，不新增资产）。
  - **坑底砖 24 件** = 6×4 满铺，棋盘格 `(i+j)%2` 切 c01/c02。
- 坐标换算钉死：模板 `bbox_nw` → 房局部 `x = vx − size.x/2`、`z = vy − size.y/2` ⇒ 坑局部 `x∈[−15,15] z∈[−10,10]`、桥局部 `x∈[−15,15] z∈[−5,0]`。
- 新增常量块：`MULTI_LEVEL_SLOT_ROLE`、`MULTI_LEVEL_PART_PIT_WALL/PIT_FLOOR_TILE`、`COMPONENT_WALL_STANDARD_5M`、`COMPONENT_FLOOR_TILE_C01/C02`、`MULTI_LEVEL_PIT_DEPTH_M=12.0`、`MULTI_LEVEL_WALL_HEIGHT_M=11.9`、`MULTI_LEVEL_RAILING_HEIGHT_M=0.8`、四个朝向常量。

**装配层 `src/world3d/DungeonRoom3D.gd`（新增 `multi_level_component` 分支 + `_spawn_authored_multi_level`）**
- `match role` 新增 `multi_level_component` 分支，计数写进 `set_meta("authored_layout_multi_level_count", …)`。
- `pit_wall`：**y 不归一**（完整 Vector3，y = 所在水平面标高）、`scale = Vector3(1, scale_y, 1)`、**自带碰撞**（组件 `collision_owner = self` ⇒ 露出 0.8 m 护栏即挡人）。
- `pit_floor_tile`：y + `snap_to_walk_plane_offset_m`、关内嵌静态碰撞（与所有授权地砖同口径）。
- 🔴 **两类都绝不写 `tower_wall_direction`**：该 meta 是门槽判据（`classify_door_lane` 只吃墙分支的 `authored_wall_records`）与塔楼墙验收的索引键；坑壁写上去会被当房墙统计 ⇒ 门槽归属与墙数全错。

**验收 `tests/verification/verify_expedition_level01_flow.gd`**
- `_verify_room_shell_seal()` 走线探针高度 **1.5 → 0.5 m**：坑沿护栏只有 0.8 m，1.5 m 探针**从护栏上方飞过**，把「坑壁就在现场」误判成「边界没有墙」⇒ 4 条假红。0.5 m 同时高于地砖顶面（0.056）、低于门洞下沿（0.3）⇒ 既不飞越护栏、也不会把门洞当实墙。
- L577 / L671 的 `Vector3(0, 1.5, 0)`（承重楼面 / 兜底矩形判据）**未动**。

**新建守卫探针 `probe_expedition01_bridge_multi_level.gd/.tscn`**
- A 纯规划级 ~18 条（坑/桥矩形、深度、层件数、格线、墙底标高、拉伸比、桥口开洞、朝向、确定性、非桥房返回空）。
- B 真实生成路径（`_generate_constrained_floor` → 房记录级 7 条 × 12 种子）：平台砖真扣坑区、多层件真进清单、component_id 能在注册表解析。
- 关键常量：`EXPECTED_PIT=Rect2(-15,-10,30,20)`、`EXPECTED_BRIDGE=Rect2(-15,-5,30,5)`、`EXPECTED_DEPTH=12.0`、`EXPECTED_PIT_WALLS=30`、`EXPECTED_PIT_TILES=24`、`EXPECTED_PLATFORM_TILES_DROPPED=18`、`EXPECTED_WALL_SCALE_Y=12.8/11.9`。

## 关键认知与证据

- **玩家无跳跃能力**（状态机无 jump 态、无 InputMap jump action）⇒ 0.8 m 护栏足以挡人 ⇒ **坑区保留承重、承重系统零改动**。这是本环能低风险落地的关键。
- 透传链本就完整（生成器 → `room_from_source` → `TowerDescent3D._append_plan_room_record` → `DungeonRoom3D.configure`）⇒ **无需改透传层**。
- 证据（全绿）：`probe_expedition01_bridge_multi_level` **`BRIDGE_MULTI_LEVEL_OK checks=95 failures=0`**（首次即全绿）、`probe_expedition01_authored_shell` **`PROBE_OK`**（`room_06` 实测 `{corner_l:4, solid_wall:24, door_wall:1, floor_tile:102, multi_level_component:54}`；12 种子累计 `floor_tile=12591` 恰减 **450 = 25 间桥房 × 18**、`multi_level_component=1350 = 25 × 54`）、`verify_expedition_level01_flow` **`EXPEDITION_LEVEL01_FLOW_OK` + `^ERROR` = 0**、`probe_expedition_authored_runtime` **`PROBE_OK`**、`probe_door_lane_guard` **`checks=14`**、`verify_block00_floor98_assembly` **`checks=230`**（矩形房逐字节不变，未回归）。
- 自洽旁证：30 = 12+6+12 ✓；24 = 6×4 ✓；18 = 24 − 6 ✓。

## 踩坑

- `_build_base_facility_shell` 函数头被 Edit 的 `old_string` 尾部误吞 ⇒ `--import` 才暴露 parse error；补回函数头。
- `--check-only --script` 在缺 autoload 的环境报 `EliteRosterService / AudioManager` **假错**，别用它判语法。
- 新探针 `.gd/.tscn` Write 出 LF ⇒ 按约定转 CRLF（`.gd.uid` 保持单行 LF）；转换先断言无 `\r`。
- `.uid` 暂存时 git 报 `LF will be replaced by CRLF` 是 `core.autocrlf=true` 的提示，索引 blob 仍是 LF（20 字节），与既有 `.uid` 一致，无需处理。

## 未做 / 下一步

- **#42-B 通道桥短边约束**（生成器**放置层**：「通道开始的 6,7,8,9,13 号房以通道桥房旋转 90°、短边对 5 号房；长边不连、只在短边开门」）—— 口径已给，未开工。与多层几何无关。
- 把 `verify_3d_parity_core` 两条既有基线红补进 triage 基线清单（未动）。
