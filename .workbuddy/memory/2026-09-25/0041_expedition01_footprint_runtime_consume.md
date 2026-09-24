# 远征01：非矩形外轮廓的**运行时消费**（第 6 环）+ 轮廓房两类假红收口

日期：2026-09-25 00:41 ｜ 分支：0.1.2 ｜ 承 `2026-09-25/0007` 同一事务（本轮：消费端落地 + 修 bug + 收假红）
提交：`a8e2f97b`（6 文件 +988/−154），**已 push**（`de83d90b..a8e2f97b`，本地 14 个提交一并推上，凭据阻塞解除）

## 本轮做了什么

1. **`RoomShellLayoutBuilder3D`：轮廓消费主链**
   - `footprint_vertices_m` / `footprint_frame` 进 block 输入契约；`normalize_footprint()` 校验（顶点落 5m 格线、轴对齐、无自交、在包围盒内）。
   - 墙**沿多边形边界逐段铺**（`boundary_edges()` 把每段归到 side）；**L 角件只放凸角**；**地砖只铺格心落在多边形内的格**。
   - 规则升级：**① 共角去重 → ①.5 门让位于角件（新）→ ② L 臂 lane 预留 → ③ 共面 lane 归属**。
   - ①.5：角件任一条 arm lane 落在**任一房**的门/出口 lane 上 ⇒ 角件整件让位（`corners_dropped{provided_by:"door_lane"}`），该 lane 不预留、由普墙/门墙补齐。
   - ③：门/出口**只认该侧包围盒外边段**（`_bound_outer_edge` / `_room_port_lane_key_sets`）——否则轮廓房同一侧多段会把同一门偏移计两次（门墙 lane 翻倍）。
2. **`FloorPlanGenerator`：透传 + 按门位筛变体**
   - `attach_authored_layout_shell(rooms, policy, templates)`、`authored_shell_block(rooms, templates)`、`_authored_shell_block_room(room, templates)` 三级透传 `templates`。
   - `_room_variant_footprint()`：模板 `size_m` 不符只告警不挂轮廓；按 **声明变体优先 → 模板 `variants` 声明序 → `variant_footprints` 多出的键** 取第一个能承接全部门/出口的变体（`footprint_accepts_ports()` 与 build_block 同源），全不兼容才退矩形。选中的变体**回写** `room.template_variant`（+ `template_variant_reconciled`）。
   - 为什么必须筛：变体与落位无关 ⇒ 凹口很容易压在门位上 ⇒ builder 报 `door_offset_off_lane` ⇒ **整层**退回程序化壳体（局部冲突放大成全图回退）。
3. **修真 bug：凹角被当凸角放 L 件**（`_corner_records`）
   - 原判据「4 象限探针找唯一内侧方向」把「≥2 象限在内」当成有效方向 ⇒ 凹角（内角 270°，3 个象限在内）也放 L 件，`room_02 db_01` 多放 2 件。
   - 改为 `inside_count != 1: continue`。`corner_l` 累计 655 → **584**，`solid_wall` 3060 → **3098**。
4. **`DungeonRoom3D`：门槽判据加墙平面法向距离**（修轮廓房假红）
   - `classify_door_lane(records, side, door_offset, door_depth)`；装配台账采集 `depth`（南北墙取局部 z、东西墙取局部 x）；新增 `door_plane_depth(side, half)`。
   - 起因：seed 77001199 `branch_01` 北侧外边 y=−15 开门、凹口内墙 y=−40 有实墙，**局部 x 都是 0** ⇒ 只比 `along` 会假报「门槽上坐着实墙」。
5. **`verify_expedition_level01_flow`：走线判据轮廓感知化**
   - 原「按包围盒整边遍历 lane、一条侧边最多 1 条打空」是矩形房假定 ⇒ `branch_01.west` 假报 2 条打空。
   - 新判据**不问轮廓**、只看房间里有什么：取本房地砖（格心过滤 ⇒ 凹口不出砖），逐砖看 4 个 5m 邻格，**邻格无砖即该面是房间边界**（轮廓按 5m 格线切分 ⇒ 等价），从砖心朝该面外打 `2.5m + 0.5m`，打空且**不是门洞**才报错。门洞判据 = 任一门的世界坐标（`room_door_world_<side>` meta）与该格面中心水平距离 ≤0.75m。
   - 无地砖清单的房（入口安全房走 v007 整房）回落原矩形判据 `_verify_room_shell_seal_rect()`。
6. **探针**
   - `probe_expedition01_authored_shell`：由「临时」转**长期**，新增 ⑦ 轮廓消费（透传 + 变体回写一致 + **砖数 == 多边形面积/25**）、⑧ **角件账目守恒**（保留 + 让位 == 凸角数，凸角数由多边形现算）。
   - `probe_door_lane_guard`：补 ⑩/⑩b/⑩c/⑪（凹口内墙不误判 / 外边实墙仍开火 / 门墙优先 / 法向距离表）；**⑪ 原写错**（把整边长当半跨度传）已修。
   - 删除本轮临时探针 `probe_footprint_debug.*`。

## 验证证据（全绿）

- `verify_expedition_level01_flow` → **`EXPEDITION_LEVEL01_FLOW_OK`**（13 房；12 房走轮廓感知判据、`start` 走回落判据）
- `probe_expedition01_authored_shell` → **`PROBE_OK`**：12 种子、轮廓房 38 间（db_01×13 / db_02×12 / u_turn×8 / l_turn×5）、角件账目复核 144 间全平；`slot_role` 累计 `corner_l=584 / door_wall=144 / exclusive_component=72 / floor_tile=13041 / solid_wall=3098`
- `probe_door_lane_guard` → `DOOR_LANE_GUARD_OK checks=14`
- `verify_block00_floor98_assembly` → `BLOCK00_ASSEMBLY_OK checks=230`（矩形房逐字节不变）
- `probe_expedition_authored_runtime` → `PROBE_OK`
- 行尾：6 个改动文件全 CRLF 纯（Python 逐字节数）

### 负对照（必须做，否则「通过」等于没验）

临时插桩跑一次（已回滚）：给 `room_01` 塞一个房间外假格心 ⇒ **`misses=4/4`、`door_exempt=false`** ⇒ 判据真的会开火，且门豁免不会把远处格面一起放过。
自洽旁证：`branch_01`(u_turn) 60 砖 = 1500 m²/25、`room_03`(db_02) 116 砖 = 2900 m²/25 —— 与多边形面积逐值吻合（凹口当实心房就会多砖）。

## 关键口径（本轮钉死）

- **轮廓房「一条侧边多条边界段」是常态**：任何「按 side 判」的几何判据都要先问「这条 lane 在不在真实边界段上」。
- **门/出口 lane 只认包围盒外边段**：凹口恒在包围盒内部 ⇒ 那里没有邻房 ⇒ 门落上去就是开向虚空。
- **门让角件、不让门**：门位是运行时契约（`derive_ports` → `_plan_room_layout`），几何件能动，门位不能动。
- **地砖格心集合 == 房间内部格集合**：轮廓按 5m 格线切分 ⇒ 「邻格无砖」⇔「该面在多边形边界上」，验收里可据此判边界而**不必搬多边形**。
- `door_plane_depth(side, half)` 第二参数是**半跨度**（调用点传 `dimensions * 0.5`）。

## 未做（下一步）

- **通道桥多层几何运行时装配**：上层平台先做；下层标准墙下延 12 m 围合；坑底铺通用地砖；下层不可达（纯装饰）。数据源已在 `bridge_60x50.json` 的 `sunken_pit` / `bridge_span` / `lower_platform`。
- **#42-B 通道桥短边约束**（生成器**放置层**约束：长边不连、只在短边开门；6/7/8/9/13 号房以通道桥房旋转 90°、短边对 5 号房）。
- `verify_3d_parity_core` 两条既有基线红补进 triage 基线清单（未动）。

## 红线提醒

- 轮廓挂「模板 + 变体」，**不可写 `floor_00.json`**。
- 新增文件须 CRLF 纯；提交排除测试副作用 `Godot/app_userdata/弹幕风暴2/base_save.json`（本轮未动它）。
- `git push` 凭据姿势见跨项目记忆（`credential.helper=manager` + `credential.interactive=never`），本轮实测可推。
