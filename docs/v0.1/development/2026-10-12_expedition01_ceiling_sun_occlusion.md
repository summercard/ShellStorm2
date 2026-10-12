# 远征01 天花板遮光：补碰撞与 Boss 房全封顶

日期：2026-10-12。FeatureID：EXPEDITION-ROOM-COLLISION。依据：主人实测反馈「远征关卡01 的 room2 封顶天花板可以有阴影，但僵尸还是会受到阳光影响；后面有的房间就不会」，要求（1）没碰撞的天花板按「有效遮光天花板」的规范补碰撞，（2）Boss 房做全封顶，并更新对应规则。

主设计：[怪物精英与Boss §7 三态受光](../06_技术施工_怪物精英与Boss.md)、[远征关卡01设计](../design/远征关卡01设计.md)。资产契约同步到 [`assets/art/environments/tower_zones/expedition/runtime/README.md`](../../../assets/art/environments/tower_zones/expedition/runtime/README.md)。

## 根因

`EnemyIllumination3D._evaluate_sunlight()` 不读画面、不读材质，只从怪物身体采样点沿主太阳方向打一条 `occlusion_mask = 1`（关卡静态世界层）的物理射线：命中 ⇒ 在投影里，未命中 ⇒ 判 `sunlight`（每秒掉 2% 最大生命）。

**「画面上有阴影」是渲染层（`cast_shadow`），「玩法判为投影」只认带 `CollisionShape3D` 的 layer 1 静态刚体。** 两者是两套东西 —— 所以顶盖视觉齐全、阴影正常，僵尸照样晒太阳。

实测（`probe_expedition_room_sun_occlusion`，75 个身体采样点/房，seed 77001199）：

| 房间 | 房型 | 修复前直接见太阳 | 修复后 |
| --- | --- | --- | --- |
| `room_02` | db_01 | 81% | **0%** |
| `room_06` | db_02 | 100% | **0%** |
| `room_10` | db_01 | 81% | **0%** |
| `room_03` / `room_09` | office | 0% | 0% |
| `boss` | boss_50x40 | 100% | **0%** |

命中节点名单证实：两处能挡住的房间（`room_03/09`）挡光的**不是天花板**，而是 office 房的 `wall_top_service`（29.4×0.7×39.4，几乎等于房间 30×40）—— 它恰好带碰撞。db 房同名的件是 `visual_only`，所以 db 房漏光。

**进一步定位**：office 的顶盖件之所以有碰撞，是因为生成器里 `slug.startswith("wall_t")` **前缀撞上了墙族**（`wall_top_service` 以 `wall_t` 开头）。靠命名巧合生效的契约。

## 实际改变

### 1. 顶盖遮光规范显式化（组件 prefab）

`scripts/generate_expedition_room_type_prefabs.py` 新增 `TOP_COVER_OCCLUDER_SLUGS`：按稳定房型 + slug 冻结 15 件顶盖件（office 7 件、db 8 件，含两库的 `wall_top_service`），统一下发 `slot_role = room_type_component`、`collision_owner = self`、`collision_policy = structural_box_proxy` ⇒ prefab 内嵌 1 个 layer 1 全包络 `BoxShape3D` @ `y = +高/2`。

三条口径：

- **`slot_role` 用 `room_type_component` 而非 `solid_wall`**：水平顶盖不是墙，写成 `solid_wall` 会被 `classify_door_lane` 当墙统计、并挂上语义为四向墙的 `tower_wall_direction`，污染墙/门槽 lane 台账。
- **用全包络盒，不照几何切段**：顶盖全在 y≈11.15~11.87，远高于玩家与子弹常用高度，包络盒不造成空阻挡；房型顶盖件本身是中空周圈，包络盒恰好把内侧封成整片顶盖。
- **前缀命名巧合改为显式名单**：`OFFICE_SOLID_WALL_SLUGS = {wall_t1110_5m, wall_t615_5m, wall_t970_5m}` 才是墙；`wall_top_service` 归顶盖。

生成器内加 `assert_top_cover_contract()` 三道**硬失败**门禁：① 登记了却查无此件（改名后契约静默失效）② 命中却没拿到碰撞 ③ 叫 `ceiling_*` 却没登记（新增吊顶件不会自动继承规范）。

重跑生成器落地 15 件 prefab。**静态场景不需重生成** —— TSCN 按 `ExtResource` 引用 prefab，碰撞随 prefab 生效。

### 2. Boss 房全封顶

`boss_room` 自身组件库里**一件顶盖都没有**（214 个源包里 roofless）。处置：复用 DB 房已验收的 `ENV-EXPEDITION-L01-DB-CEILING_DECK_40M`（同属远征废土数据中心族、同一条顶盖遮光规范），不新增 Blender 源 —— 同一件资产不出现两份真源。

几何：板局部 40(长)×5(宽)，`rotation_y_deg = 90` 后长轴沿房间 z 跨越整个 40m 纵深，10 条沿 x 每 5m 一条严丝合缝铺满 50m；底面标高 11.38m、顶面 11.87m 落在 11.9m 墙内。

落在**房型布局源**（不是专属件源）：`art_source/.../common_components/v011/component_instances.json`，因为 `FloorPlanGenerator.ROOM_TYPE_LAYOUT_SOURCES["boss_50x40"]` 走 `_load_authored_component_layout` 分支并 `continue`，`_boss_room_exclusive_instances()` / `data/layouts/expedition/boss_room.json` 那条路对本关**是死路**（v011 已有全房 210 件布局）。实例以 `audited_additions` 显式登记来源与重跑警告；`validation.resolved_instance_count` 210 → 220（该字段是加载器优先读取的运行时期望值，漏改会让整房回退成通用壳体）。

同步投影到 `data/layouts/expedition/v011/component_instances.json`（`sync_runtime_design_data.py`，39 份，issues=[]）。

### 3. 场景改动（外科式）

**没有走 `generate_expedition01_room_static_scenes.tscn` 重生成** —— 详见下方「未做的事」。三个 TSCN 手工外科式修改，保持 CRLF 与原有节点顺序：

| 文件 | 改动 |
| --- | --- |
| `f00_boss_static_layout.tscn` | +1 ext_resource、+10 个 `ceiling_deck_NN` 节点（插在 `base_floor_tile_*` 与 `chair_*` 之间）、`layout_instance_total` 210→220、`authored_layout_room_type_component_count` 58→68 |
| `f00_room_03_static_layout.tscn` | `wall_top_service` 的 `authored_slot_role` solid_wall→room_type_component（同时移掉顶盖不该有的 `tower_wall_direction` / `grid_unit_m` / `shadow_policy`）、solid 27→26、room_type 28→29 |
| `f00_room_09_static_layout.tscn` | 同上；solid 27→26、room_type 29→30 |

三份在 `room_instances/f00_*/room_static_layout.tscn` 侧重建硬链接（去重结构保真，sha256 两边一致）。

### 4. 规则落点

| 规则 | 落点 |
| --- | --- |
| 玩法口径 | `docs/v0.1/06_技术施工_怪物精英与Boss.md` 新增 §7.3.1 封顶件（顶盖遮光）硬契约 |
| 资产口径 | `assets/art/.../expedition/runtime/README.md` 新增「顶盖遮光件（TOP COVER）」 |
| 组件分类 | `scripts/generate_expedition_room_type_prefabs.py` `TOP_COVER_OCCLUDER_SLUGS` + 门禁 |
| 守卫断言 | `tests/tooling/test_generate_expedition_room_type_prefabs.py`（新增 `test_top_cover_guard_fails_loudly`）、`tests/tooling/test_expedition_boss_ceiling_contract.py`（新文件，钉住 摆位源→prefab 碰撞→静态场景 整链） |
| 验收期望 | `tests/verification/verify_expedition_room_type_component_replay.gd` 更新 boss / room_03 / room_09 期望值 |

## 本次验证

所有 Godot 进程启动前 `APPDATA` 隔离到工程外，正式用户档未被验收调用。

| 验证 | 结果 |
| --- | --- |
| `probe_expedition_room_sun_occlusion` | 13 房逐房射线实测；`room_02/06/10` 与 `boss` 全部 100%→0%，`room_03/09` 保持 0% |
| `test_generate_expedition_room_type_prefabs.py` | `GENERATE_EXPEDITION_ROOM_TYPE_PREFABS_OK` |
| `test_expedition_boss_ceiling_contract.py` | `EXPEDITION_BOSS_CEILING_CONTRACT_OK` |
| `sync_runtime_design_data.py --check` | `{"files": 39, "issues": []}` |
| `verify_expedition_room_type_component_replay` | `checks=16896 failures=17`；本次改动引入的 7 条期望失败已随期望表更新清零，剩余 17 条为既有失败（见下） |

## 未做的事与既有问题（不在本次范围，但必须记下来）

1. **静态场景重生成会让门位翻面 —— 本次因此没走生成器。** 用 `SS_STATIC_ROOMS` 重生成**未受本次改动影响**的房间（`room_01` / `room_05` / `room_08`）后，`snapshot_tower_wall_door_offset_*` 与 `authored_layout_promoted_walls` 会成对翻转／换边（`room_01` 与 `room_08` 的取值互换了位置）。同一份 seed 下不可复现 ⇒ 提交在库里的 TSCN 与当前生成器已漂移。任何「重生成全部 13 房」的操作都会静默移动门位。**这是独立缺陷，本次不碰。**
2. **静态场景序列化膨胀 4 倍**：重生成同样会把每件 prefab 的 metadata 内联进房间 TSCN（`room_05` 97KB→380KB）。同样是既有漂移。
3. **`verify_expedition_room_static_scenes` / `verify_expedition_room_type_component_replay` 在未改动的树上就已经是红的**：`room_02/03/06/09/10` 的「房型件 metadata ≠ 实际实体数」（差 3~4 件），以及多处「门位门洞被 132 个顶点封住」。本次改动只把 `room_03` 的缺口值 +1（24→25）、`room_09` +1（26→27），缺口本身不变。
4. **`tests/tooling/test_check_expedition_room_asset_status.py` 既有失败**：B 类判据（文档 emoji 级别不符）不报红。级别只由账本 `ShellStorm2_场景账本_v001.xlsx` 的 `status/prefab/glb` 三列推导，与文件系统无关；该行的账本状态已含「已接入」⇒ 推导级别就是 ✅，测试期望过时。
5. **远征 01 仍有 5 类房型未封顶**：`start`(13%)、`room_04`(40%)、`room_01/05/07/08/extraction`(80%)。这些房型（safe / corridor / bridge / std / extraction）**本来就不带顶盖件**，不在「补碰撞」的范围内。若要一并封顶，需要为这些房型补顶盖资产或走房型布局加实例 —— 属于新工作。
6. **组件 prefab 的 `metadata/source_blend` 路径被顺带修正**：`res://assets/.../source/` → `res://art_source/...`（2026-10-11 制作用根迁移后提交在库的 prefab 仍是旧路径）。这是生成器的合法输出，但会让 173 个 prefab 文件出现在 diff 里。
