# 远征01 非矩形外轮廓 + 通道桥多层几何：数据层落地与门禁

日期：2026-09-25 00:07 ｜ 分支：0.1.2 ｜ 承 2026-09-24/2156 同一事务（本轮交付数据层 + 门禁）

## 本轮做了什么

1. **4 个非矩形外轮廓写进模板真源**（按「模板 + 变体」挂 `variant_footprints`，**不写 `floor_00.json`**）：
   - `room_templates/corridor_45x40.json` → `l_turn`（L 形，[[0,0],[45,0],[45,15],[15,15],[15,40],[0,40]]）、`u_turn`（凹字形单多边形外轮廓）
   - `room_templates/db_70x50.json` → `db_01`（南中段外凸 20×10，**已归一居中**）、`db_02`（左下缺角 20×20 + 右下缺角 20×10）
   - 每个轮廓都带 `kind:"polygon"`、`frame:"bbox_nw_x_east_y_south"`、`note`。
2. **通道桥多层几何写进 `room_templates/bridge_60x50.json`**：
   - `sunken_pit`：rect x[15,45] y[15,35] = 30×20 m，`depth_m=12.0`（= FLOOR_HEIGHT 整层：一件标准墙 11.9 m 可视高 + 0.1 m 沉降缝）
   - `bridge_span`：x[15,45] y[20,25]，`width_m=5.0`
   - `lower_platform`：`enclosure`=通用墙 `wall_standard_5m`、`floor`=通用地砖 `floor_tile_5m`、`accessible=false`
   - `note` 明写：外轮廓仍是矩形 ⇒ **无 `variant_footprints`**；「长边不连、只在短边开门」属**放置层**约束（不是几何约束）。
3. **同步图集真源** `scripts/render_expedition01_plan_sheet.py`（`db1`/`db2`/`c2`）并重生成平面图集（`refs/expedition01/plans/*.svg` ×4 + 图集 html）。
4. **新建门禁** `scripts/check_expedition_room_footprints.py`（纯几何、不依赖 Godot）+ 自测 `tests/tooling/test_check_expedition_room_footprints.py`。
5. **登记进文档**：设计页 §9.4 门禁表两行、`docs/v0.1/design/README.md` 关卡表资产完成情况列。

## 关键口径（本轮钉死）

- **轮廓坐标系 `frame = "bbox_nw_x_east_y_south"`**：顶点以**包围盒西北角**为原点，x 向东、y 向**南**为正。
  - 依据：`render_expedition01_plan_sheet.py::door_marker()` 里 `side=="north" ⇒ yy=0.0`、`side=="south" ⇒ yy=r["d"]`。
  - 映射到 Godot 房间局部：`(x − w/2, 0, y − d/2)`。
  - 🔴 **更正**：`2026-09-24/2156` 记的「原点 = 西南角」是**错的**，以本文件为准。
- **顶点必须落 5m 网格**：图集初稿的顶点是目测像素值（42/22/52/18/38/32 等）⇒ 门禁首跑 10 条 FAIL，已按白盒模数归一。
- **`wall_lane_table` 只是包围盒候选槽**，非矩形轮廓下门禁逐向把它分「可开 / 缺口」（缺口 = 落在轮廓凹口上的槽）。lane 中心：奇数格宽房 = `5k`，偶数格宽 = `5k+2.5`。
- `bridge_span` 落在坑内、宽度与 y 跨一致；`sunken_pit` 必须在包围盒内、下层 `accessible=false`。

## 验证证据（全绿）

- `check_expedition_room_footprints.py` → `EXPEDITION_FOOTPRINTS_OK templates=8 contours=4 pit_templates=1 frame=bbox_nw_x_east_y_south`
- `tests/tooling/test_check_expedition_room_footprints.py` → `EXPEDITION_FOOTPRINT_CHECKER_OK: 对照 + 7 类不一致均按预期判定`
- `check_expedition_room_asset_status.py` → `EXPEDITION_ASSET_STATUS_OK`
- `verify_level_plan_design_source` → `LEVEL_PLAN_VALIDATE_OK levels=3 checks=234 rooms=33 templates=17`、`LEVEL_PLAN_RUNTIME_GUARD_OK`
- `check_documentation_contracts.py` → `issues: []`，rc=0
- 新文件行尾全部 CRLF 纯（`check...py crlf=456`、`test...py crlf=129`、三模板 54/44/46、`render...py crlf=901`）

## 未做（下一步）

- **轮廓的运行时消费**：装配层按 `variant_footprints` 裁切 —— 被切掉的格不放墙 / 地砖 / L 件，**门槽必须落真实墙段**；凹形 `support_keep_out_rects` 须拆多矩形。
- **通道桥多层几何运行时装配**：上层平台先做；下层标准墙下延围合（12 m）；坑底铺通用地砖 `floor_tile_5m`；下层不可达纯装饰。
- #42-B 通道桥短边约束（生成器**放置层**约束）。

## 红线提醒

- 轮廓挂「模板 + 变体」，**不可写 `floor_00.json`**。
- 新增文件须 CRLF 纯。
- 提交时排除测试副作用 `Godot/app_userdata/弹壳风暴2/base_save.json`。
- 本地 ahead（含本轮）待推送；`git push` 仍被凭据阻塞 —— 未获凭据前不得动远端。
