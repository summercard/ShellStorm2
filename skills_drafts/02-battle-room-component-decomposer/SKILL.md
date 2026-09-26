---
name: 02-battle-room-component-decomposer
description: 当把已验收的战局房间种类 Blender 源拆成可复用组件 Blender 文件时使用。先用「组件拆分判断」把场景实例按归并键聚类成组件清单，再按清单建组件包并导出实例清单，最后以拼装还原概念图验收；负责墙、地板、门、固定设施、装饰和环境支撑的拆解，保持 AssetID、原点、包络、PaletteUV 和账本追溯；禁止一格一件的伪通用组件。
agent_created: true
metadata:
  display_name_zh: 02 战局房间组件拆解
---

# 战局房间种类源拆解为组件源

## 目标与边界

把已经通过 `blender-game-prop-standard` 验收的“房间种类源”拆成可复用的组件 Blender 文件。拆解单位是房间种类组件，不是具体房间编号。

**组件 ＝ 一份几何（可复用）＋ 一份实例清单（位置/旋转）。** 两者必须分开存放：几何进组件库，位置进实例清单。房间种类源里“看起来已经是组件结构”的那些对象，**默认是实例、不是组件**——本 Skill 的工作就是把它们**归并**成组件。

```text
房间种类源（概念图 + 已摆好的场景）
  -> ① 组件拆分判断：实例聚类 -> 组件清单 component_plan.json
  -> ② 按清单建组件包（一项 = 一份几何）
  -> ③ 导出实例清单 component_instances.json（还原原摆放）
  -> ④ 拼装还原验收：清单拼回场景，与概念图逐项比对
  -> ⑤ component manifest / catalog -> 交给 Godot 导入 Skill
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

1. 读概念图/效果图与房型源场景，列出场景里**全部对象**（含 Collection）。
2. 用归并键给对象打组：**一组 = 一个组件**。
3. 为每组起一个**不依赖位置的名字**（见下「命名规则」），这一步产出的表即 `component_plan.json`。
4. 自检两条：
   - **覆盖自检**：`Σ 每组的实例数 == 场景对象数`（一个都不能漏）；
   - **必要性自检**：把某个组件从清单里删掉，概念图是否**仍然拼得出来**？能拼出来说明它多余，应并入别的组。
5. 清单冻结后再建 Blender 文件。**清单外不得新增组件。**

### 命名规则

组件名描述「**这是什么**」，不描述「**它在哪**」：

| 允许 | 禁止 |
|---|---|
| `wall_standard_5m`、`wall_door_5m`、`floor_tile_5m`、`server_rack`、`work_terminal` | `north_00`、`wall_x_00_front`、`WALL-NORTH-SLOT-01`、`tile_-1_-3`、`bridge_girder_-1`、`pit_side_-1_2` |

- 禁方位词 `north / south / east / west / front / rear / inner / outer`；
- 禁坐标或槽位数字（`_00`、`_-1`、`_4.8`、`SLOT-01`）；
- 同一造型的**真实几何变体**（不同尺寸、损坏态）允许编号，但编号必须挂在**语义维度**上（`wall_standard_5m` / `wall_standard_10m`），不得用序号表达“同一造型的第 N 个”。

### 变体上限（硬约束，2026-09-26 业主裁定）

**同一组件族的变体数上限 ＝ 3。** 超过即**必须归并**——不请示、不逐条裁定。

- **族名** ＝ slug 归一化后的语义核心：小写 → 去方位词（`north/south/east/west/front/rear/inner/outer/left/right`）
  → 去纯数字段与坐标小数 → 去尾部单字母序号。
  例：`wall_east_-1` → `wall`；`tile_-1_-3` → `tile`；`ceiling_deck_-1` → `ceiling_deck`；
  `work_cluster_a` → `work_cluster`；`door_wall` → `door_wall`；`wall_top_service` → `wall_top_service`。
- **判定**：族内成员数 > 3 → 违规，必须收敛。
- **收敛算法（可自判，无需人工介入）**：
  1. 族内按尺寸相似度贪心聚类，阈值 `SIM_TOL = 0.10 m`（结构件平面模数 5m 的 2%）；
     **结构件比较键必须先按平面排序** `(min(x,y), max(x,y), z)` —— 墙转 90° 是同一件；
     陈设件保持原序 `(x,y,z)`；
  2. 簇数 ≤ 3 → 完成；
  3. 簇数 > 3 → 反复合并**最相似的一对**簇，直到 ≤ 3；
  4. 每簇取**实例数最多**的成员为代表件；簇内其余成员的实例改指代表件，位置全部进实例清单。
- 收敛后仍 >3，或出现「两件几何差异 > 0.5 m 却被归入同一代表」→ 说明**族粒度划错了**（族太粗），
  **修族名，不放宽上限**。
- 🔴 上限的判据是**族内变体数**，不是几何指纹数。指纹用于确认"能否直接并"，族上限用于回答
  "最多留几个"——两者都要过。

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

## 拆解流程

1. 读取源文件、源 manifest、范围锁定记录和白模契约，记录源 SHA-256。
2. **组件拆分判断**：按上节归并键聚类，产出 `component_plan.json`。清单未冻结不得建包。
3. 建立拆解表（**每个清单项一行**，不是每个场景对象一行）：`component_id`、中文名、类别、Collection、根对象、依赖对象、局部原点、包络、正面轴、允许旋转、碰撞责任、是否自发光、`serves_room_types`、`instance_count`。
4. 对**清单里的每个组件**建立独立资产包，并将组件母版统一放入：

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

5. 导出**实例清单** `component_instances.json`（见下节）。
6. 组件根必须稳定；建筑模块默认底部中心原点，设施默认底部贴地；不得通过整体非等比缩放修正尺寸。对将被 `Collection Instance` 链接到房间的每个输出 Collection，还必须显式验证 `collection.instance_offset == (0,0,0)`；只把 ROOT 与 Mesh 归零不够，残留的集合实例偏移会在房间中额外平移整个组件。
7. 输出主体与自发光为独立网格；保留四类材质角色、PaletteUV、公共色盘外链和材质索引。
8. **拼装还原验收**（见下节）：用组件清单 ＋ 实例清单重建场景并与概念图比对。
9. 组件拆解文件必须能单独打开、单独渲染、单独验证；不要只保留房间总场景引用。
10. 生成组件源版本，不覆盖房间种类源，也不覆盖历史组件源。

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

组件拆得对不对，不看包的数量，看**能不能拼回来**：

1. 用 `component_plan.json` ＋ `component_instances.json` 重建房间场景；
2. 逐对象比对源场景：对象总数、每个组件的实例数、每实例的位置与旋转；
3. **包围盒判据（可机验）**：按实例清单拼装后，总 bbox 必须**精确等于房间边界（含墙厚）**，越界实例数必须为 0。这是「位置 ＋ 旋转全对」的一句话证据；
4. 渲染重建结果，与概念图/效果图做**目视比对**（这是“高保真”的唯一证据，headless 结构结果不能代替）；
5. 全过才算完成；任一不符，回到「组件拆分判断」修正清单，**不得靠新增组件绕过**。

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
