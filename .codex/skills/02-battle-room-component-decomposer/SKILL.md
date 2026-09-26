---
name: 02-battle-room-component-decomposer
description: 当按概念图制作战局房间种类 Blender 源，或把历史整屋源重建为可复用组件时使用。正式建模前冻结不超过 50 个组件的计划，同族常规最多 3 个、有明确状态轴最多 5 个；房型源只用组件母版实例拼装，并导出可由 Godot 重放的实例清单。
agent_created: true
metadata:
  display_name_zh: 02 战局房间组件拆解
---

# 战局房间种类源拆解为组件源

## 目标与边界

把“房间种类”从概念图开始按可复用组件制作，并产出能在 Blender 与 Godot 中重放的组件库和实例清单。拆解单位是房间种类组件，不是具体房间编号。

**本 Skill 不是“整屋做完以后再拆包”的事后工序。** 它有两种入口：

- **新房型（默认）**：在创建正式 Blender 几何前先冻结 `component_plan.json`；只建计划内的组件母版，整屋只用 Collection Instance 拼装。
- **历史整屋源（兼容）**：先盘点已有对象并归并，再重建为组件母版＋实例布局；不得继续维护一格一件的旧结构。

**组件 ＝ 一份母版几何（可复用）＋ N 条实例记录（位置/旋转）。** 几何进组件库，位置进实例清单；房型 Blender 源本身就是这些母版实例的可视化拼装场景。

```text
概念图 + 白模
  -> ⓪ 制作前组件规划：component_plan.json（唯一组件定义 <= 50）
  -> ① 每个计划项只制作一份组件母版；同件复用只建实例
  -> ② 房型 Blender 源以 Collection Instance 拼装概念图
  -> ③ 冻结 component_instances.json（位置/绕 Blender Z 旋转）
  -> ④ 逐组件独立包 / GLB 导出契约，不导出整屋 GLB
  -> ⑤ Blender 重放 + Godot 重放双验收
```

只处理场景美术组件。不得修改玩法、规则、房间连接、敌人、掉落、存档、门 FSM、导航或 `TowerDescent3D`。

## 触发语句

- `拆解通用房种类 Blender 源`
- `把撤离房源文件拆成组件`
- `按组件规范拆解这个 BOSS 房`
- `从这个安全房源生成组件文件`

必须确认输入是房间种类源，而不是 `main_02` 之类的具体房间布局源。若输入是具体房间编号，停止并转交 `03-battle-room-instance-layout-authoring`。

## 组件拆分判断（概念图 → 组件清单）

**这一步在建任何 Blender 文件之前完成，是本 Skill 的核心。** 目的：用**最少的组件**拼回概念图。

### 判断依据：归并键

两个实例属于**同一个组件**，当且仅当下面四项全部相同：

```text
归并键 = ( 局部尺寸[包络], 接口[原点 + 正面轴 + 允许旋转集合], 材质角色集, 几何指纹 )
```

- **不得**把以下任何一项放进归并键：世界位置、朝向（东南西北）、槽位号、出现次序、所在房间。
- 位置与朝向属于**实例**，写进 `component_instances.json`；把它们写进组件名即视为拆分失败。
- 🔴 **包络相同 ≠ 几何相同**。归并前必须算一次**几何指纹**（归一化后顶点数 ＋ 量化顶点哈希），
  见 `references/component_split_decision_contract.md` §1.1。实测（办公室 30×40，2026-09-26）：
  36 块同尺寸地砖有 **36 个不同指纹**，4 组同尺寸工位 4 个不同指纹 —— 只按包络聚类会把它们误判为同一组件。

### 操作顺序

#### 新房型：制作前规划（默认）

1. 读概念图/效果图与白模，把画面拆成“结构组件、设施组件、装饰组件、环境支持”四层；先列**候选组件定义**，再估算每个定义的实例数。
2. 对候选项应用归并键和变体规则：位置/朝向不能产生新组件；配色优先材质变体；破损/轮廓差异才考虑几何变体。
3. 为每组起不依赖位置的名字并分配 `component_id`，写出 `component_plan.json`；检查唯一组件总数 `<= 50`。
4. 自检：
   - **概念图覆盖**：每个可见结构和陈设都有计划项或已声明共享组件来源；
   - **必要性**：删掉某定义后仍能高保真拼回，则该定义多余；
   - **变体理由**：同族第 4–5 个变体必须有明确状态轴；
   - **接口可复用**：每个定义都能在局部原点单独打开、旋转、导出。
5. 清单冻结后才创建正式网格。一个计划项只建一个母版 Collection；概念图中的重复项全部用 Collection Instance 摆放。**清单外不得直接新增几何。**
6. 每次美术迭代都从实例场景回看概念图；要增加造型时先更新计划和预算，再改 Blender。

#### 历史整屋源：兼容归并

1. 列出源场景全部输出对象/Collection；
2. 用归并键聚类，一组等于一个组件母版；
3. 将世界位置与朝向迁入 `component_instances.json`；
4. 用母版实例重建房型场景，替换旧的一格一件结构；
5. 同样执行 `<= 50` 总预算和 3–5 变体门禁。

### 命名规则

组件名描述「**这是什么**」，不描述「**它在哪**」：

| 允许 | 禁止 |
|---|---|
| `wall_standard_5m`、`wall_door_5m`、`floor_tile_5m`、`server_rack`、`work_terminal` | `north_00`、`wall_x_00_front`、`WALL-NORTH-SLOT-01`、`tile_-1_-3`、`bridge_girder_-1`、`pit_side_-1_2` |

- 禁方位词 `north / south / east / west / front / rear / inner / outer`；
- 禁坐标或槽位数字（`_00`、`_-1`、`_4.8`、`SLOT-01`）；
- 同一造型的**真实几何变体**（不同尺寸、损坏态）允许编号，但编号必须挂在**语义维度**上（`wall_standard_5m` / `wall_standard_10m`），不得用序号表达“同一造型的第 N 个”。

### 组件预算与变体上限（硬约束，2026-09-26 业主裁定）

#### 房型组件预算

- 单个房型（含自有组件和从共享库引用的组件）使用的**唯一 `component_id` 总数必须 `<= 50`**；实例数量不限。
- 预算统计的是定义，不是场景对象数。例：1 种地砖摆 60 次，预算占 1，不是 60。
- 计划冻结时写 `component_budget: {limit: 50, planned: N, remaining: 50-N}`；`planned > 50` 时不得开始正式建模。
- 制作中新增组件必须先更新计划；若会超 50，按“删除位置型拆分 → 归并同件 → 复用共享件 → 收敛变体 → 重新划分语义族”的顺序自动收敛，不能靠提高预算通过。

#### 同族变体：3 为目标，5 为绝对上限

- **常规目标 `<= 3`**：无明确设计维度的近似件必须收敛到最多 3 个。
- **允许 4–5 个的唯一条件**：该族全部成员都对应概念图中可解释、可复用的同一状态轴，例如 `damage_state`、`colorway`、`structure_state`；每个成员都必须填写 `variant_axis`、`variant_value`、`variant_reason`，并确保只改该状态轴，不夹带世界位置。
- **绝对上限 `= 5`**：族内超过 5 个一律失败并收敛，不请示、不以“细节不同”为理由放宽。
- 仅配色变化优先共用同一几何＋材质/PaletteUV 变体；只有轮廓、碰撞或拓扑确实变化时才占新的几何组件。

- 新计划必须显式写 `component_family`；不得只靠 slug 猜族。例：`cabinet_damage_heavy` 与 `cabinet_color_blue` 的 `component_family` 都写 `cabinet`，差异写进变体字段。
- 历史清单缺字段时才按 slug 兼容推断：小写 → 去方位词 → 去纯数字段/坐标 → 去尾部单字母序号；推断结果必须回写成显式字段。
- **收敛算法（可自判，无需人工介入）**：
  1. 先按真实状态轴分组；没有状态轴的成员进入默认组；
  2. 组内按尺寸相似度贪心聚类，`SIM_TOL = 0.10 m`；结构件键为 `(min(x,y), max(x,y), z)`，陈设件保持 `(x,y,z)`；
  3. 无状态轴的族收敛到 `<= 3`；有合法状态轴的族收敛到 `<= 5`；
  4. 每簇取实例数最多的成员为代表，其他实例改指代表件；
  5. 如果为满足上限而需要把轮廓/碰撞明显不同的件强并，说明族太粗，应细分真实语义族，但细分后仍计入房型 50 个总预算。
- 🔴 几何指纹回答“是不是同一件”；变体轴回答“是否有意保留差异”；50 个预算回答“整个房型是否足够模块化”。三道判据必须同时通过。

### 双轴分类（两类判据不同，不可混用）

| | 结构件 | 陈设件 |
|---|---|---|
| 例子 | 墙、门墙、门扇、地砖、天花 | 机柜、终端、花箱、管线、标识 |
| 尺寸来源 | 网格模数（硬约束） | 设计意图 |
| 判「够通用」 | `bounds_size` 有轴**恰等于**模数 | 服务 **≥2 个房间种类** |
| 数量预期 | **个位数**，先冻结 | 十几到几十，但每个都跨类 |
| 归属 | 一律进共享组件库 | 只服务 1 个房型 ⇒ `scope=room_type_local`，**留房型源、不进共享库** |

**顺序硬约束**：先拆结构件并冻结，再在冻结网格上做陈设件；结构件未冻结不得开始陈设件。

## 组件分类

按以下所有权拆解：

| 分类 | 例子 | 处理要求 |
|---|---|---|
| 建筑结构 | 5m 墙、带门墙、地砖、天花、转角 | **每种型号**一个包，保留接口、锚点和网格尺寸 |
| 房间设施 | 终端、机柜、工作台、固定装置 | 每种型号一个包，主体与发光分离 |
| 房间装饰 | 墙面装甲、门禁、压边、标识 | 优先并入宿主结构组件；不能随方位复制 |
| 环境支持 | 管线、跨设施支撑、固定灯带 | 跨设施内容单独包；宿主不可分内容并入宿主 |
| 撤离信标 | `extraction_beacon` | 固定设施组件，必须独立可替换，不得作为拾取道具 |

🔴 表中的「一个包」= **每种型号一个包**，不是每个槽位一个包。同一型号在场景里出现 N 次，是**一个组件 ＋ N 个实例**，不是 N 个组件。

能服务多个房间种类的组件进入战局共享组件库；只服务一种房间种类但会在该类型的多个房间复用的组件，进入该房间种类组件库。禁止把同一几何复制到两个库后各自维护。

## 组件优先制作与拆解流程

1. 读取概念图/源文件、manifest、范围锁定记录和白模契约；历史源记录 SHA-256，新房型记录概念图与白模来源签名。
2. **组件拆分判断先于正式建模**：产出并冻结 `component_plan.json`，断言 `unique_component_count <= 50`。清单未冻结不得创建正式输出网格。
3. 建立组件表（**每个清单项一行**，不是每个场景实例一行）：`component_id`、中文名、类别、Collection、根对象、依赖对象、局部原点、包络、正面轴、允许旋转、碰撞责任、是否自发光、`serves_room_types`、`instance_count`、`variant_axis/value/reason`。
4. 在 Blender 的 `01_制作组件` 中每项只建一份母版，在 `02_游戏输出` 中只放 Collection Instance；房型源既是美术制作场景，也是实例清单的可视化真源。严禁为每个槽位复制 Mesh datablock。
5. 对**清单里的每个组件**建立独立资产包，并将组件母版统一放入：

```text
assets/art/environments/tower_zones/<block_id>/source/common_components/v###/
├─ *.blend                    # 组件库母版
├─ 01_制作组件_按组件拆分
├─ 02_游戏输出_独立资产包_v###
├─ component_plan.json        # 组件清单（拆分判断的产物）
├─ component_instances.json   # 实例清单（位置/旋转）
├─ component_catalog.json
├─ component_tree.txt
└─ component_packages/<component_id>/asset_manifest.json
```

组件 GLB 不放在该过程目录，而放入同级稳定目录：

```text
assets/art/environments/tower_zones/<block_id>/components/<component_slug>/
assets/art/environments/tower_zones/<block_id>/runtime/common_components/<component_slug>/
```

历史 `source/common_components/v###/` 目录继续兼容读取；新组件源不得再创建到房间种类目录或具体房间编号目录。

6. 导出**实例清单** `component_instances.json`（见下节）。
7. 组件根必须稳定；建筑模块默认底部中心原点，设施默认底部贴地；不得通过整体非等比缩放修正尺寸。对将被 `Collection Instance` 链接到房间的每个输出 Collection，还必须显式验证 `collection.instance_offset == (0,0,0)`；只把 ROOT 与 Mesh 归零不够，残留的集合实例偏移会在房间中额外平移整个组件。
8. 输出主体与自发光为独立网格；保留四类材质角色、PaletteUV、公共色盘外链和材质索引。
9. **双重拼装还原验收**（见下节）：先在 Blender 用组件清单＋实例清单重建，再交由 Godot 逐组件导入并用同一实例清单重放；两边都与概念图比对。
10. 组件拆解文件必须能单独打开、单独渲染、单独验证；不要只保留房间总场景引用。
11. 生成组件源版本，不覆盖房间种类源，也不覆盖历史组件源。

## 实例清单（位置与旋转的唯一载体）

组件**不带位置**；房间的摆放由实例清单承载，这样“组件可复用”与“布局能完整还原”同时成立。

保存到组件库同级：`<block_id>/source/common_components/v###/component_instances.json`

```json
{
  "schema": "shellstorm2.battle.component_instances",
  "schema_version": 1,
  "library": "v###",
  "source_room_type_blend": "...",
  "source_room_type_sha256": "...",
  "coordinate_contract": {
    "blender_plane": "XY",
    "blender_up": "+Z",
    "rotation_y_deg_semantics": "rotation_about_blender_Z",
    "godot_mapping": "declared_by_import_manifest"
  },
  "instances": [
    {
      "component_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
      "instance_id": "wall_x_00_front",
      "position_m": [0.0, 0.0, 0.0],
      "rotation_y_deg": 0.0,
      "scale": [1.0, 1.0, 1.0],
      "source_object": "结构_WALL_X_00_FRONT_输出_部件00"
    }
  ],
  "validation": {
    "source_object_count": 121,
    "instance_count": 121,
    "coverage_ok": true
  }
}
```

- `source_object` 保留到源对象的追溯，是“能还原”的证据；
- 组件包里**不得**让摆位字段参与几何；`source_world_origin_m` 一类只作追溯元数据保留；
- 同一份实例清单可被 `03-battle-room-instance-layout-authoring` 与 Godot 运行时共同消费。

## 必须记录的契约

每个组件 manifest 至少包含：

```json
{
  "component_id": "ENV-BATTLE-ROOMTYPE-COMPONENT-EXAMPLE",
  "slug": "wall_standard_5m",
  "component_family": "wall_standard",
  "variant_axis": null,
  "variant_value": null,
  "variant_reason": null,
  "room_type": "COMMON_ROOM",
  "serves_room_types": ["COMMON_ROOM", "SAFE_ROOM"],
  "scope": "shared",
  "instance_count": 12,
  "source_room_type_blend": "...",
  "component_blend": "...",
  "collection": "...",
  "root_object": "...",
  "bounds_size_m": [5.0, 0.3, 11.9],
  "local_origin": [0.0, 0.0, 0.0],
  "front_axis": "-Z",
  "allowed_rotations_y_deg": [0, 90, 180, 270],
  "collision_owner": "godot_wrapper",
  "palette_uv_layer": "PaletteUV",
  "asset_ledger": "resolved_by_ledger_index"
}
```

三个字段的硬约束：

```text
front_axis                必须是枚举：-X / +X / -Y / +Y / -Z / +Z（单一值）。
                          禁止写入整句描述（如 "inward_normal=-Y (Blender world); Blender +Y maps to ..."），
                          下游无法解析，等同于缺字段。
allowed_rotations_y_deg   必须是角度集合，按几何对称性判定，不得一律填 [0]。
                          四面墙类、地砖类通常应为 [0,90,180,270]；非对称设施按实际可转位填写。
                          凡填 [0] 的，manifest 必须写明几何为何不可转位。
serves_room_types         该组件实际服务的房间种类集合。
                          为空或仅 1 项时，scope 必须为 room_type_local（留房型源，不进共享库）。
```

撤离信标额外必须记录：

```text
component_id = stable and unique
facility_role = extraction_beacon
pickup = false
activation_socket = optional visual socket only
runtime_logic_owner = gameplay layer, not component
```

## 拼装还原验收

组件拆得对不对，不看包的数量，看**Blender 和 Godot 能否用同一份实例数据拼回来**：

1. 用 `component_plan.json`＋`component_instances.json` 在 Blender 重建房间；
2. 逐组件导出 GLB、组装稳定 PackedScene，再由 Godot 用同一实例记录重放；不得导入房型整屋 GLB作为捷径；
3. 两端逐实例比对：`component_id`、实例数、位置、绕垂直轴旋转、单位缩放；坐标转换只能由显式 `coordinate_contract` 完成；
4. **包围盒判据（可机验）**：Blender 重建、Godot 重放的总 bbox 均须等于房间边界（含墙厚），越界实例数为 0；
5. 分别渲染 Blender 重建与 Godot 验收场景，与概念图做目视比对；Godot 必须检查材质、发光、碰撞责任、门扇所有权，不只看节点数；
6. 检查预算：唯一组件 `<= 50`，无理由族 `<= 3`，有合法状态轴族 `<= 5`；
7. 全过才算完成；任一不符，回到组件计划或导入映射修正，**不得靠整屋 GLB或临时专用组件绕过**。

反例：把「同一道 5m 墙出现在 10 个槽位」建成 10 个组件 —— 重建也能过，但组件数虚高 10 倍、互用性为 0，属于**未做归并**，验收必须判失败。

### 🔴 实例旋转必须显式记录（实测坑，2026-09-26）

拆出来的每个包，**几何自带朝向**：源对象旋转通常全为 0，朝向被烘焙进顶点。
归并若按「朝向无关尺寸」聚类（把转了 90° 的同一件并成一个组件），
**必须同时为每条实例记录它相对代表件的旋转角**；漏记 ⇒ 拼装时那一半实例躺倒。

实测（bridge_room 工字型 30×60，v005 → v007）：36 块墙按朝向无关尺寸归成 2 个组件后，
实例旋转全填 0，**18 块墙横躺穿过平台**；补齐旋转后拼装 bbox 精确等于房间边界。
同批修复也命中 office 30×40（9 条）。

三条硬约束：

```text
① 旋转轴是 Blender Z（世界垂直轴；房间平面为 XY）。
   字段名 rotation_y_deg / allowed_rotations_y_deg 沿用历史命名
   （源自 v005 的 allowed_rotations_blender_z_deg），语义是绕 Z。
   拼装写入 rotation_euler.z；写成 .y 会让墙直接躺倒。

② 旋转判定用「主轴方向」：比较组件平面两维中较大者所在轴。
   同轴 ⇒ 0°；异轴 ⇒ 90°；平面长短比 > 0.87（近正方形）⇒ 视为无主轴、不旋转。
   不得用点集 Hausdorff 去猜 —— 成员几何本身有差异（厚度/长度微差）时会被带偏：
   实测把 29 m 的纵向腰梁误转 90°，捅出房间 4 根长刺。

③ 90° 与 270° 不区分（统一取 90°）：中心对称件无差别。
   不对称件若确有端部特征，应改「朝向敏感归并」拆成两个组件，而不是靠猜旋转。
```

## 门禁

- **制作顺序门禁**：新房型没有冻结的 `component_plan.json`，或在计划冻结前已创建正式输出几何，即失败。
- **组件预算门禁**：单房型引用的唯一 `component_id` > 50 即失败；实例数不计入预算。
- **变体门禁**：无合法 `variant_axis/value/reason` 的族 > 3 即失败；任何族 > 5 即失败；纯配色却复制几何组件也失败。
- **母版实例门禁**：同一组件的重复摆放必须共享母版 Collection/Mesh datablock；一槽位一份复制网格即失败。
- **归并门禁**：同归并键的组件包数 > 1 即失败，必须归并为一个组件。
- **命名门禁**：`slug` 或 `component_id` 命中方位词、坐标或槽位序号即失败。
- **接口枚举门禁**：`front_axis` 不在枚举集内、`allowed_rotations_y_deg` 为空或全为 `[0]` 且无理由说明即失败。
- **拼装守恒门禁**：`Σ instance_count == 源场景对象数`，组件清单 ＋ 实例清单必须能 1:1 还原源场景。
- **互用率门禁**：陈设件中 `serves_room_types` ≥2 的比例 ≥ 0.6；结构件接口达标率必须 = 1.0。
- 组件包不可为空；对象不得跨包重复归属。
- 组件不能携带房间编号布局位置作为固定世界坐标；房间位置属于实例清单。
- 禁止从具体房间实例反向生成“伪通用组件”。从具体房间派生组件本身是允许的（房型源本就按一个具体房间制作），但**必须先按归并键聚类**；未归并、一个槽位一个包的产物视为伪通用组件。
- 禁止输出房间专用整屋 GLB/PackedScene。
- `room_owned_geometry` 对后续实例布局必须为 `false`。
- 所有组件必须有 AssetID、稳定原点、包络、旋转和来源追溯。
- 锚点验收必须同时覆盖三层：ROOT 对象变换、Mesh 相对 ROOT 的局部变换、输出 Collection 的 `instance_offset`。三层任一非零都不得交给房间布局；尤其要做同族差异检查（普通墙、门墙、门扇），防止只有少数组件残留制作场景偏移而被整体抽查漏过。
- 源文件必须通过范围锁定、材质、UV、尺寸和包络验收后，才可交给 `godot-model-asset-import-standard`。

## 批量拆解已有房型源的实操口径（2026-09-26 远征01 四批 506 包实测）

对**已经存在**的房间种类源做组件独立化时，走「只读探测 → 建母版库 → 逐包独立化」三段，全绿才算完成。
ShellStorm2 里已有通用化脚本：`scripts/blender/dump_room_type_packages.py`（探测）、
`decompose_room_type_components.py`（建母版库 + manifest/catalog/tree/report）、
`finalize_room_type_component_files.py`（逐包另存独立 `.blend` + 逐个重开验收）。
三个实测坑，任一没处理都会让整批假红：

1. **各批的包清单结构不一致，禁止假定**：
   - `objects` 可能是「纯名字列表」，也可能是「对象字典列表」（`{name, location_m, dimensions_m}`）⇒
     统一取 `d if isinstance(d, str) else d["name"]`。首轮 121 包全红就是这个。
   - 批级清单有三种形态：`component_packages/catalog.json`（有的**只有 `package_id/path/object_count`、没有 `collection`**）、
     顶层 `component_inventory.json`、字段齐全的 catalog。⇒ **一律以每包 `asset_manifest.json` 为准**，批级清单只兜底。
     拿不到 `collection` 就定位不到包集合，整批 100% 失败。
   - 源 blend 里包集合的父集合名各批不同（如 `02_游戏输出_独立资产包_v001` / `_v002`）⇒ 按集合**名字**全局查，别硬编码父链。
2. **自发光件必须命名带标记**：`validate_game_prop.py` 的 `emissive_objects_clearly_named` 要求含自发光材质的 mesh
   名字里出现 `自发光 / ui灯光 / emissive / glow`（大小写无关）。复制网格时按材质判定并写进对象名，
   **输出包与制作源两份都要带**，否则只挂这一项（其余 16 项全过，最容易被误判成"验证器太严"）。
3. **锚点三层 + 原点口径一起验**：原点 = 包围盒 `x/y 中心 + z 底`，断言 `abs(local_low[2]) < 1e-5`；
   同时验 ROOT 变换恒等、Mesh 相对 ROOT 恒等、输出 Collection 的 `instance_offset` 为 0。

落位：**每房型一个组件库**（`<block_id>/source/common_components/v###/`，一库一份 `component_catalog.json`），
不建到房间种类目录下。母版库保留为「分离式集合实例画廊」，独立文件每个一个 `Component_<slug>` 场景并自带相机灯组。
验收判据：独立 `.blend` 数 == catalog 声明数 == 每包 `asset_manifest.json` 数，且每包 11 项几何契约 + 标准材质量/UV 验证器全过；
首尾各校验一次源 blend 的 SHA-256，确认房型源零改动。

**⚠️ 这一段是「分」的口径，不含归并**：按它跑完会得到「一个源对象一个包」。用「组件拆分判断」重跑一遍归并键聚类、
把同键包合成一个组件后，才算符合本 Skill 的交付判据。实测四批的降幅见
`references/component_split_decision_contract.md`。
