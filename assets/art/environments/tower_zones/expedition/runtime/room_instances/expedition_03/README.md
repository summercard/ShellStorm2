# 远征关卡03 · 房间 / 通道 / 门静态布局（白盒阶段）

本目录放远征关卡03 的**房间静态 TSCN**与**通道静态 TSCN**。设计页：[远征关卡03 设计](../../../../../../../../docs/v0.1/design/远征关卡03设计.md) §10。

> **当前状态：10 份房间壳 + 9 份通道壳 + 5 种门扇，全部为白盒（whitebox）阶段。**
> 白盒 = 只有地面与墙的几何，**没有任何美术**（地砖、墙板、陈设、陷阱、灯、门扇本体全都没有）。
>
> 两道门禁全绿：文本 `scripts/check_expedition03_room_layouts.py`、
> 真实加载 `tests/verification/verify_expedition03_room_whitebox.tscn`（240 项检查）。

---

## 一、这个目录的规则

### 1.0 白盒阶段的一条例外（2026-10-27 修订，2026-10-27 二次修订）

原文第 1 条是"**手工摆，不许脚本生成**"。白盒阶段**不适用**，理由与边界写清楚：

| | 白盒几何 | 美术组件摆位 |
|---|---|---|
| 来源 | `scripts/build_whitebox_room_tscn.py`，读模板 JSON | 白模 `component_instances.json` 或编辑器手改 |
| 为什么可以脚本化 | 地面格、墙段、门洞的位置是**模板契约的纯函数**：`size_m` 定尺寸、`variant_footprints` 定轮廓、`wall_lane_table` 定门位。没有选择余地，重跑逐字节一致 | 陈设摆哪、朝哪、多密，是美术判断，不可推导 |
| 能否被覆盖 | 可以，重跑即重生成 | 不许被覆盖 |

也就是说：**第 1 条约束的是"美术摆位"，不是"契约几何"。** 白盒不是"生成器推导位置"，
是"把模板 JSON 已经写死的数字画出来"。进入美术阶段后脚本不再产这些文件。

### 1.1 其余规则（美术阶段起生效）

1. ~~手工摆，不许脚本生成。~~ **白盒阶段见 §1.0**；进入美术阶段后恢复：组件位置只能来自白模
   `component_instances.json`，或人在 Godot 编辑器里手改。生成器只许重放，不许推导位置。
2. **缺文件必须报错，不许退灰盒。** 拿不到 TSCN 就让关卡起不来，不能悄悄用盒子顶上。
3. **根节点不写 `metadata/room_id`。** 写了就绑定到某一间房，共享立即失效。
   一份 TSCN 服务该房型在本关**所有**房间位（远征03 的房间号 `n01`/`hub_01` 在 6 张骨架里重复出现）。
4. **改完 TSCN 以 TSCN 为准。** 重跑生成器会覆盖同路径文件；重跑前先把 TSCN 里的手改合并回去。
   **白盒阶段这条不构成风险**（白盒内没有任何手摆内容），进入美术阶段后立刻生效。

---

## 二、房间壳 10 份

命名前缀 `rt_`（room type），与子图共享壳 `f00_secret_shared_*`、远征01 按房号烘焙的
`f00_room_NN_*` 三者**互不混用**，一眼能看出是哪一类。

一个 **(模板 × 轮廓变体)** 一份壳。带 `variants` 的模板一模板多壳，因为它们的**外轮廓不同**，
不是同一份几何换门位。

| # | 文件 | 模板 | 轮廓变体 | 尺寸 | 面积 | 端口 | 承载房型 |
|---|---|---|---:|---:|---:|---:|---|
| 1 | `rt_safe_15x15` | `safe_15x15` | — | 15×15 | 225 m² | 2 | 入口 |
| 2 | `rt_extraction_25x25` | `extraction_25x25` | — | 25×25 | 625 m² | 1 | 撤离 |
| 3 | `rt_boss_50x40` | `boss_50x40` | — | 50×40 | 2000 m² | 2 | 首领 |
| 4 | `rt_std_25x25` | `std_25x25` | — | 25×25 | 625 m² | 3 | 首领前厅 / 连接房 / 战斗房池 |
| 5 | `rt_db_70x50_db_01` | `db_70x50` | `db_01` | 40×30 | **1050** m² | 3 | 宝箱房 / 战斗房池 |
| 6 | `rt_db_70x50_db_02` | `db_70x50` | `db_02` | 40×30 | **975** m² | 3 | 宝箱房 / 战斗房池 |
| 7 | `rt_office_60x70` | `office_60x70` | — | 30×40 | 1200 m² | 3 | 商店 / 战斗房池 |
| 8 | `rt_corridor_45x40_l_turn` | `corridor_45x40` | `l_turn` | 45×40 | **1050** m² | 4 | 枢纽房 / 战斗房池 |
| 9 | `rt_corridor_45x40_u_turn` | `corridor_45x40` | `u_turn` | 45×40 | **1500** m² | 4 | 枢纽房 / 战斗房池 |
| 10 | `rt_bridge_60x50` | `bridge_60x50` | — | 30×60 | 1800 m² | 2 | **本关不使用**（见下） |

### 2.1 四份壳的外轮廓**不是矩形**

这是 2026-10-27 第一版最严重的错误：**全部按包围盒矩形做**。缺角处多出了不存在的地面和墙。

| 壳 | 轮廓缺口 | 包围盒 | 实际 |
|---|---|---:|---:|
| `l_turn` | 缺东南角 30×15 | 1800 m² | 1050 m² |
| `u_turn` | 西侧中部内岛 30×10 是实体 | 1800 m² | 1500 m² |
| `db_01` | 西南/东南角只到 y=25，南中段外凸 10×5 | 1200 m² | 1050 m² |
| `db_02` | 左下缺 15×10、右下缺 15×5，南中段外凸 10×5 | 1200 m² | 975 m² |

真源是模板的 `variant_footprints`（`scripts/check_expedition_room_footprints.py` 已在盯）。
生成器逐条读它：地面只铺**完整落在轮廓内**的格，墙沿**每一条轮廓边**建，门只开在**轮廓外墙真实覆盖到的槽位**上。

> `l_turn` 的南墙只剩 `-15 / -10` 两个可开槽，`-5/0/5/10/15` 都在缺角上 —— 开在那儿等于开个通向室外的洞。

### 2.2 `bridge_60x50` 做了但不接入本关

设计页 §10 明确「本关不使用」。仍然做出来，因为：
它是唯一的**多层几何**房（下沉坑 30×30 深 12m + 中央 10m 跨桥），是最难的一份；
白盒化它等于把「工字型怎么用 5m 格表达」这个问题提前解掉，将来要用不必重来。

模板 note 写死「**短边（南北墙）开门，东西长边一律不许连**」—— 生成器按 `SIDE_OVERRIDES` 遵守，
门禁会复查（在长边开门直接报错）。

### 2.3 端口数怎么来的（不硬编码）

从六张骨架反推，不是拍脑袋定的：

1. 每个房间位的门数 = 它在 `tree_edges` + `loop_edges` 里的**度数**；
2. `NORMAL` 的 `template_id` 是空的 —— 因为它是**四选一模板池**（`template_pool`），
   池里每个模板都可能被选中，都要能承受该房间位的门数；
3. 入口安全屋另 **+1**（弃局门，设计页 §2）。

**改骨架，端口预算自动跟着变。** 旧版把 9 条写死在门禁里，加一份壳就要改门禁。

---

## 三、通道壳 9 份

前缀 `cr_`。**走廊就是一间很窄的房间**，与房间同契约（5m 格、2.2m 门洞、同一套 lane 槽），
不是独立的连接件类型；生成顺序上它排在最后，用来补已摆好房间之间的缝。

| 文件 | 净宽 | 净长 | 端口 | 形状 |
|---|---:|---:|---:|---|
| `cr_straight_05` | 5 | 5 | 2 | 直廊 |
| `cr_straight_10` | 5 | 10 | 2 | 直廊 |
| `cr_straight_15` | 5 | 15 | 2 | 直廊 |
| `cr_straight_20` | 5 | 20 | 2 | 直廊 |
| `cr_straight_30` | 5 | 30 | 2 | 直廊 |
| `cr_straight_45` | 5 | 45 | 2 | 直廊（最长档） |
| `cr_corner_05` | 5 | 5 | 2 | 直角拐角 |
| `cr_t_junction_05` | 5 | 5 | 3 | T 字口 |
| `cr_cross_05` | 5 | 5 | 4 | 十字口 |

**净宽为什么是 5m 而不是 3~4m**：门洞 2.2m 必须居中落在 5m 槽位上，两侧各留 1.4m 墙肩，
才能与房间侧槽位逐米对齐。3~4m 宽的通道会让门位脱离 5m 格线 ——
那正是 `RoomDoorLane` 类头注释里记的历史病根（白盒门槽与运行时门槽静默分叉）。

---

## 四、门 5 型（不在本目录）

门**不在**房间 TSCN 里，在 `common_components/whitebox_doors/`，策略表在
`data/level_plans/expedition_03/door_catalog.json`。

理由与《挺进地牢》同构：**房间只声明"这面能接"，门由运行时按规则落上去。**
把门烘进模板，同一间房就只能有一种开门方式，加一种锁就要重做一份模板。

| 门型 | 运行时类 | 访问策略 | 挺进地牢对应 |
|---|---|---|---|
| `normal` | `RoomDoor3D` | `clear=true` | 战斗门（进房关门，清完开） |
| `locked` | `RoomDoor3D` | `key=true` | 上锁门 |
| `boss` | `RoomDoor3D` | `key+clear+fate` | 首领门（常闭 + 仪式演出） |
| `secret` | **`SecretDoor3D`** | 无 | 隐藏门 = **可打碎的墙** |
| `cell` | `RoomDoor3D` | `key=true` | 牢房门（清怪给钥匙） |

`secret` 刻意**不复用** `RoomDoor3D`：本工程已有 `SecretDoor3D`（`max_hp`/`hp`、被打碎转 `BROKE`）。
隐藏门的核心行为是「被打碎」，门板的升降语义表达不了它。

五型共用同一套 2.2×2.5 门洞与同一份坐标契约（原点＝门洞**底面中心**、朝向 −Z），
差异只在**白盒辨识件**（钥匙孔 / 双柱 / 栅栏）与**策略**。

---

## 五、每份 TSCN 的骨架

```text
ExpeditionRoomStaticLayout   (Node3D)
├── metadata/shell_id / template_id / variant
├── metadata/size_m / grid_unit_m / wall_height_m / door_width_m
├── metadata/footprint_polygon_m / footprint_area_m2 / footprint_is_rect
├── metadata/layout_instance_total    ← 等于实际 MeshInstance3D 子节点数
├── metadata/whitebox = true
├── metadata/whitebox_excludes        ← 明确声明缺什么（floor_art…lights…doors）
├── metadata/walkable_navigation_polygons   ← 轮廓本身 + 每个门洞外扩
├── RoomCeilingLight                  (Node3D，占位；美术阶段换成 WastelandLight3D)
├── RoomLightSwitch3D                 (Area3D，占位；美术阶段换成 RoomLightSwitch3D)
├── Floor_Rxx_Cyy                     (MeshInstance3D, BoxMesh 5×5m)  × 落在轮廓内的格
├── Wall_NNN                          (MeshInstance3D, BoxMesh)       × 轮廓边的实体段
├── Lintel_{Side}_{lane}              (MeshInstance3D，门洞上方过梁)
├── PitFloor_* / PitWall_* / BridgeRail_*   (仅 bridge_60x50)
└── ConnectionPorts/Port_A … Port_N   (Marker3D)
```

美术阶段的目标形态（照抄远征01 已验证的形态，样板 `../expedition_01/f00_room_01_static_layout.tscn`）：

```text
└── <组件实例 × N>
    ├── metadata/authored_component_id
    ├── metadata/authored_slot_role   ("room_type_component" | "door" | "floor" | "wall")
    └── transform
```

运行时会把整份壳按本局朝向旋转、把共享门搬到自持侧、给没门的侧补实墙 ——
所以**不需要**为每种门位组合各做一份，只要端口齐、墙件在候选 lane 上就行。

### 5.1 白盒的几何约定

| 项 | 取值 | 来源 |
|---|---|---|
| 格距 | **5.0 m** | 主人指定；模板 `grid_unit_m` |
| 地面 | 只铺完整落在轮廓内的 5×5 格，顶面 `y = 0.08` | 轮廓 + 与既有 `room_static_layout` 行走面一致 |
| 墙高 | **11.9 m** | 模板 `wall_height_m`（塔楼层高，既有吸顶灯在 y≈10.4） |
| 墙位置 | 沿轮廓边、内表面压轮廓线、厚度在房外 | 保证可走面积 == 轮廓面积 |
| 门洞宽 | 2.2 m | 模板 `door_contract.width_m` |
| 门洞净高 | 2.5 m 净高，2.8 m 处补过梁 | 模板 `door_contract` |
| 坐标 | 房间以包围盒中心为原点；north=−Z，south=+Z，east=+X，west=−X | 与 `Port_*.outward` 一致 |

门位**不等于** 5 m 格线：`wall_lane_table` 里的值是绝对米数（如 `-2.5`、`2.5`），
所以墙按"整段减去门洞区间"切成实体段，而不是"每 5 米切一段再判断有没有门" —— 前者永远精确。

---

## 六、怎么算过（两道门禁，缺一不可）

### 6.1 文本门禁

```bash
python3 scripts/check_expedition03_room_layouts.py
```

期望值全部从数据源算，没有硬编码清单：

| 校验项 | 真源 |
|---|---|
| 该有哪些壳 | `room_templates/*.json` 的 `variants` |
| 每壳端口数 | 六张 `flows/*.json` 的节点度数 |
| 房型外轮廓 | `variant_footprints` |
| 门位合法性 | 轮廓边 ∩ `wall_lane_table` |
| 门套件 | `door_catalog.json` + 门扇 TSCN |
| 通道套件 | `corridor_catalog.json` + TSCN |

### 6.2 真实加载门禁（文本门禁替代不了它）

```bash
godot --headless --path . res://tests/verification/verify_expedition03_room_whitebox.tscn
```

逐份 `instantiate` 并量几何，共 240 项：

- 能加载（`load()` 不返回 null）
- 实际 `MeshInstance3D` 数 == `layout_instance_total`
- **每一块 `Floor_*` 的四个角都在 `footprint_polygon_m` 内** ← 专抓"矩形近似"
- **每个 `Port_*` 到最近轮廓边的距离 < 2cm** ← 端口必须在墙上，不能在缺角处
- 轮廓顶点须为逆时针（点序反了会让内外判定整体反相）
- 门扇：宽≈2.2、高≈2.5、底面 y≈0（原点契约 = 底面中心）

**为什么两道都要。** 2026-10-27 实测：把某个 `Transform3D` 的基写成带括号的
`(-1, 0, 0, …)`，文本门禁 **EXIT=0 照过**，Godot 报 `Parse Error`。
文本自洽 ≠ 引擎能读。这一类只有真加载抓得到。

### 6.3 反向对照（证明门禁真的会红）

改完门禁必须验它抓得到错，否则"全绿"没有意义。实测过四条：

| 注入的错 | 谁抓到 |
|---|---|
| 门位从 `south@-10` 改到 `south@0`（落在 `l_turn` 缺角上） | 文本门禁 |
| 轮廓改成矩形 + 面积改 1800 | 文本门禁（三条一起报） |
| 东南缺角塞一块地板 | 真实加载（越界 + 计数不符） |
| `Transform3D` 基加括号 | **只有真实加载**（文本门禁照过） |

---

## 七、预览与重生成

```bash
# 三批产物
python3 scripts/build_whitebox_room_tscn.py --preview
python3 scripts/build_whitebox_corridor_kit.py --preview
python3 scripts/build_whitebox_door_kit.py --preview

# 总览图集（一屏核对房 / 门 / 通道）
python3 scripts/render_expedition03_whitebox_gallery.py

# 门禁
python3 scripts/check_expedition03_room_layouts.py
godot --headless --path . res://tests/verification/verify_expedition03_room_whitebox.tscn
```

图：`docs/art/expedition03_room_whitebox/`（10 张 + `index.html`）、
`docs/art/expedition03_corridor_kit/`（9 张）、`docs/art/expedition03_door_kit/`（5 张）。

---

## 八、没做的事（说清楚，不是遗漏）

- **房间美术**：地砖、墙板、陈设、陷阱、刷点、灯、门扇本体 —— 全部没有，`whitebox_excludes` 逐项声明了。
- **运行时不消费这些壳**：`TowerDescent3D.expedition_static_layout_path()` 找的是
  `f00_<runtime_room_id>_static_layout.tscn`（按房间号烘焙），本目录的 `rt_*` / `cr_*`
  是按**模板**组织的共享壳。要接进游戏，需要一个「模板 → 壳」的解析层，**目前没有**。
- **门没有装配规则**：`door_catalog.json` 只声明了 5 种门与策略，
  「哪个房间位的哪条边该落哪种门」还没有规则源（对应挺进地牢的 `chanceToLock` 那一层）。
- **通道没有被生成器调用**：壳有了，但 `_build_tower_horizontal_corridor()` 仍按 5m 模块程序化铺，
  没有改成实例化 `cr_*` 壳。
- **关卡场景 `ExpeditionLevel03_3D.tscn` 未建**，`runtime_enabled = false`。

> 白模与资产的完成度以[场景分账本](../../../../../../../../assets/registry/README.md)为准，
> 本文件只列"要做什么 / 做到哪一步"，不判定资产验收。
