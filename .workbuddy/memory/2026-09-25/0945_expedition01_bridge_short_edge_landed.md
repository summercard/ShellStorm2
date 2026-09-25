# 0945 · 远征01 #42-B 通道桥短边连接 —— 裁决落地（规则 → 设计 → 代码 → 图，全绿）

> 接 `0112`（阻断待裁决）与 `0838`（规则文档裁定）。本轮把三条裁定**落进运行时实现侧**，
> 并补齐用户要的「最终版图 + 每房平面图」。核心：**撤销 `bridge_50x60`、改走 `template_rotation_deg:90`；
> 场地边界与面积上限全项目取消；桥房只在短边开门、不能挂支线。**

## 一、业主三条裁定（原话口径）

1. **房型 id 锁定**：未获明示不得新增/改名/删除；转置只用 `template_rotation_deg` 表达。
   ⇒ 先前为方案 A 新建的 `bridge_50x60` **撤销**（属「两批代号」，管理混乱）。
2. **支线不另起代号**：支线只是设计页标注 ＋ L2 `role="branch"`，房型从锁定池取。
3. **不超出场地这条推广到全部关卡**（不只是单层）：拼接房间不考虑越界，面积只给最终数据。
4. **桥房只在短边开门**（中间是桥、两边才是门）⇒ 最多 2 连接且**必须同轴** ⇒ **不能挂支线**。
   连接轴与桥跨不平行时用 **90° 转置**让短边对齐；因放开总面积，这一步现在可行。

## 二、运行时实现侧（`src/map/`）

### `FloorPlanGenerator.gd`
- **删 `MAP_SIZE_M` 常量、`_map_rect()`**；`_constrained_fits` 去掉边界剪枝（只剩「过 5m 模数 + 不与已放重叠」二连）；
  `validate_expedition` / `validate` 删 `outside_floor_bounds`；`validate` 另删 `area_budget_exceeded` 判定。
- **桥房取向**：删 `_axis_pose_pairs` / `_is_transposed_pair`（`axis_pose_of` 配对）与「非正方形即可取向」的 `orientable` 字段。
  🔴 **踩坑**：`orientable` 原先兼职两件事（可转置 + 父房长边封锁子房）。改成「非正方形即 orientable」后
  **全体内容房**（`db_70x50`/`office_60x70`/`corridor_45x40`）都触发父房长边封锁、每条主路被迫换轴 ⇒ **300/300 种子全回落**。
  修复：拆开两件事，**只用桥房的唯一功能判据 `sunken_pit`（= `_requires_short_edge_links`）当 `short_edge_locked`**，其余房型无取向。
- 新增 `_transposed_size(size)`（正方形返回 `Vector2.ZERO`）、`_is_rotated_size`、`_template_rect_to_local(rect, size, rotated)`（x/y 互换）。
- **蛇形折返软引导**（边界退出剪枝后主路会一路直走）：新增 `_anchored_direction_order(per_direction, anchor)`
  —— 主路按候选位到入口锚点距离升序重排方向，**软引导、无硬上限**；`_direction_anchor_distance` 取行内最近候选距离。
- `_constrained_floor_from` 房间记录 `rotation_deg`（原硬编码 0.0）；`_bridge_multi_level_plan` 按 `rotated` 传参。
- 删死代码 `_rect_contains_rect`。

### `LevelPlanValidator.gd`
- 删场地边界与面积判定（`outside_floor_bounds` / `area_budget_exceeded`）；注释说明「面积只报数据、不设上限」。
- 已有 `expected_size_for_rotation(template_size, room)` + `_validate_short_edge_links`（错误码
  `bridge_long_edge_link:<房>:<邻房>:side=<面>:wall=<长>><短边>`，桥房判定键 = 模板带 `sunken_pit`）。

## 三、验证结果（本轮亲跑）

| 项 | 结果 |
|---|---|
| `verify_level_plan_design_source` | exit=0；`LEVEL_PLAN_LEVEL_OK expedition_01 floors=1 rooms=13 templates=8 checks=99`；`VALIDATE_OK checks=234 rooms=33 templates=17`；`RUNTIME_GUARD_OK` |
| `verify_expedition_level01_flow` | **OK**（修 `branch_04` 父房断言 `room_05`→`room_06` 后转绿） |
| `probe_expedition01_bridge_multi_level` | `BRIDGE_MULTI_LEVEL_OK checks=157` |
| `probe_expedition01_bridge_short_edge` | `seeds=324 bridge_rooms=620 links=971 violations=0 fallback=4 native=378 transposed=242` |
| `probe_expedition01_constrained`（300 种子） | 成功 **296** / 回落 **4**（1.3%）、校验不通过 0；房型分布 office 607 / db 611 / corridor 601 / std 568 / bridge 573 |
| `check_expedition_room_footprints.py` | `EXPEDITION_FOOTPRINTS_OK templates=8 contours=4 pit_templates=1 axis_aliases=0` |
| 其自测 | `EXPEDITION_FOOTPRINT_CHECKER_OK: 对照 + 11 类不一致` |
| `check_expedition_room_asset_status.py` | OK |
| `check_documentation_contracts.py` | `issues: []`（documents 140 / links 980 / features 37） |

⚠️ **回落率 1.3% 不是 0** —— 别按「0 回落」宣传。回落时清单/尺寸/内容池仍正确，只是该局版图不再随机。

## 四、门禁与自测的反向改造（配合「不许两批代号」）

- `scripts/check_expedition_room_footprints.py`：判据 6 与 `check_axis_pose_links` 整段替换为
  **`check_no_axis_pose_aliases`**（任何模板声明 `axis_pose_of` 即报红）；`check_pool_excludes_poses`
  去掉「池含替身」分支（保留存在性与 `room_templates` 双向核验）；结论行改 `axis_aliases=0`。
- `tests/tooling/test_check_expedition_room_footprints.py`：**13 类 → 11 类**（删配对类，新增「任何模板声明轴替身」「池引用不存在模板」）。
- `probe_expedition01_bridge_multi_level.gd`：常量改单模板 + 两旋转（`BRIDGE_TEMPLATE="bridge_60x50"`、`BRIDGE_ROTATION_NATIVE=0`、`BRIDGE_ROTATION_POSE=90`），加**反向断言「存在 `bridge_50x60` 即 PROBE_FAIL」**。
- `probe_expedition01_bridge_short_edge.gd`（新）：删 `bridge_50x60` 存在性要求、加反向断言；回落不再直接判失败，改 **5% 阈值**。

## 五、设计源与文档

- `floor_00.json`：桥房两间（`room_05`、`branch_04`）**都是 `template_rotation_deg:90`、`size_m=[50,60]`**；
  `branch_04` 父房 `room_05` → **`room_06`**（桥房不能挂支线）。`level_plan.json` templates=8（去掉 `bridge_50x60`）；
  `bridge_60x50.json` 补 note。
- `docs/v0.1/design/远征关卡01设计.md`：改 §3 引言/§2 动线图/§3.1 总表抬头/§3.2 room_05·room_06/§3.3 支线房（含 branch_04）/
  §3.4 池表与锁定段/§4.2 版本变化/§4.3 摆位表/§4.4 门数表/§4.6/§4.7（**改名「场地边界与面积上限（全项目取消）」**）/§5 边界表/§5.1/§7 第 4 条/§7.2 支线挂法 —— 全口径一致。
- `docs/v0.1/05.2_关卡版图白盒与生成规范.md`：§3.2 `enforce_area_budget` 描述**校正**（该键已不再被校验器读取，比「打印日志开关」更准确）；
  §3.4 模板 id 锁定 + 转置不是新模板；§3.6 新增第 6·7·8 条（id 锁定 / 支线不另起代号 / **桥房只在短边开门**）；§3.7 取消场地外边界 + 面积只报数据。

## 六、图纸（`scripts/render_expedition01_plan_sheet.py`，文档即数据源）

修 4 个真实缺陷 + 2 处口径：
1. **总平面图被裁**：画幅原按 250×250 场地定比例，改动后包络 190×320（y 探出场地）⇒ 裁掉大半。
   新增 `_overview_bounds()` = **房间包络 ∪ 场地参考框**，比例与 viewBox 按它算；另设 `TOP_BAND=56` 标题带与 `LEGEND_H=140` 图例带。
2. **桥房详图出血**：`branch_04` 直接复用 `room_05` 的 60×50 画法，画进 50×60 画布。
   新增 `bridge_rot`（转置姿态：坑 30×20 → 20×30、桥改沿 y），并**按房间实际占位自动选姿态**（不是按「哪一间是主路」写死）。
   ⚠️ 修完发现**示例版图里两间桥房都是 90°**（此前我误写「room_05 用 0°」）—— 设计页已同步更正。
3. 窄房文字溢出：`text()` 加 `outline=True`（白色描边 + `paint-order:stroke`）。
4. 核心区 65×65 文字压住 `room_04`/`branch_03`：改放框**右侧外侧**；序号角标加 `floor_y` 下限不许越进标题带。
5. 文案口径：面积段改「只报数据、不设上限」（删占用率分母）；补桥房短边与转置两条要点；支线改「各挂一间主路房」。

## 七、收尾状态

- 行尾：本轮改动的 14 个 `md/gd/json/py` **全部 CRLF、无 BOM、无孤立 LF/CR**（脚本逐字节核过）。
- 清理：删 `tests/verification/_diag_bridge_attribution.{gd,uid,tscn}`。
  新增保留：`tests/verification/probe_expedition01_bridge_short_edge.{gd,uid,tscn}`（短边守卫，5% 阈值）。
- **未提交**（工作区 WIP）：等主人看过图再决定是否落提交。
- 设计页 §4.2 坐标表**已核对**：13 房中心与尺寸与 `floor_00.json` **逐值一致**（`room_05` −55,−50 / 50×60；`branch_04` −55,−160 / 50×60 挂 `room_06`），无需重算。
