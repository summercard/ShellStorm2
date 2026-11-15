# 远征01 room_08 中庭局内自动贩卖机

日期：2026-11-15。功能：WORLD-PLAN / RUN-MERCHANT / ASSET-PIPELINE。工程版本 0.1.0 不变。
设计依据：[远征01设计](../design/远征关卡01设计.md#room_08--拐角走廊01-45--40)、
[局内商人](../04.1_玩法系统_局内商人.md)、[关卡接入规范](../关卡接入规范.md)。

## 授权与边界

业主 2026-11-15：「先阅读设计文档和游戏框架，然后我把 room08 的结构改掉了。你帮我把这个关卡改一下。
改成这里的中间地方增加一个自动贩卖机，局内用的，你参考一下远征03的局内自动贩卖机。完成后更新一下对应的设计文档和账本。」

- 业主已自行重排 `f00_room_08_static_layout.tscn`（内转角改阶梯/斜墙、新增 9 块通用地砖形成中庭）。
  本轮**不改业主的结构改动**，只在其上增加一台可在局内交易的自动贩卖机。
- 复用远征03 的既有链路：99F `prp_base_vending_machine` 视觉 + `ServiceStation3D` 交互 +
  `Dungeon3D` 库存/购买 + `RunMerchantService` 货架 + `MerchantUI` 页面。**不新建**商店、货架表、价格表或物品定义。
- 不改房型源、组件库、GLB、Prefab、资产哈希与 AssetID；不新增资产行。
- 商店视觉由**锚点自己**声明（`service_station_config.visual_scene`）。**不走主题**：
  `env_iron_frontier` 还供远征02 / 99F / 塔楼 flow 共用，且每张 flow 都有 1 间 `SHOP→MERCHANT` 房 ——
  第一版把 `merchant_visual_scene` 写进了那个共用主题，会连带改掉那些关卡的商店外观，已回退。
  远征03 的「主题显式配置」先例只对它自己的主题文件成立。
- 视觉不写进房间 TSCN 的组件实例，因此不占房型组件计数、不改 `layout_instance_total`。

## 实施

### 1. 服务点改由作者锚点声明（通用能力，不认关卡 ID）

新增 `DungeonRoom3D._build_authored_service_stations()`：扫 `AuthoredLayoutArtRoot` 下带
`metadata/service_station_config` 的 `Marker3D`，按锚点实例化服务点。位置与朝向取锚点在**房间帧**的姿态
（`global_transform.affine_inverse() * marker.global_transform`，只留平面位置与绕 Y 朝向、y 归零）——
静态布局根会被 `_align_static_layout_to_room()` 整体四向对齐，只有房间帧读数才是「朝房间哪一边」。

- 合同与既有 `treasure_chest_config` 同源：锚点是**作者事实**，运行时只建点、接信号、套主题视觉。
- 同类型服务点已由房型自建存在时跳过（`get_service_station(type_id) != null`），不会建第二个。
- 排在 `_build_content()` 里房型自建之后，调用点带注释说明顺序依赖。
- 抽了 `_instantiate_service_station()`：`visual_scene` 必须在**入树前**写好
  （`ServiceStation3D._ready()` 就在那时建视觉并销毁基地包装根）。

### 1.1 视觉来源：锚点声明，不碰共用主题

`_instantiate_service_station(type_id, visual_override)` 多了一个可选的视觉覆写：锚点写了
`visual_scene` 就用它，否则沿用 `type_id == "merchant" and theme.merchant_visual_scene != null` 的旧逻辑。
两者都在**入树前**赋值（`ServiceStation3D._ready()` 那时才建视觉）。

### 2. 交互区改为绕实体居中（`ServiceStation3D.center_interaction_on_body()`）

99F 包装的 `InteractionShape` 偏在一侧（`pos.z=-0.74`、深 3.35 ⇒ 只到 `z=+0.93`），那是「机器背靠基地墙面」
那个摆法的算法。作者锚点不保证背靠墙，照抄偏置会导致**站在货窗前点不到、绕到背面才触发**，
而 `visible` 由 `PlayerVision3D` 的视野剔除控制，玩家根本看不到背面有东西。

改为绕实体碰撞盒居中、两侧各留 `INTERACTION_REACH_M = 1.6 m`。**只对作者锚点服务点调用**（入树之后，
因为 `InteractionShape` 是 `_ready()` 里建的）；基地 99F 的摆法逐字不变。

### 3. 交易撤离改为逐服务点声明

`ServiceStation3D.unlocks_trade_extraction`（默认 `true`）→ `Dungeon3D._merchant_unlocks_trade_extraction`
在 `_on_service_activated()` 取用。锚点写 `"trade_extraction": false` 时，成交**不**在本房开交易撤离点。

- 原因：room_08 是普通战斗房，本关契约是「只有撤离房能结算」。购买顺手开一个撤离点会改掉这条规则。
- **没有按房型或关卡 ID 分支**：判据是服务点自己的声明，既有商人房（远征03 商店、塔楼商人）不写该键 ⇒ 逐字不变。
- 曾短暂写成 `room.room_type == "MERCHANT"`，被既有回归 `verify_run_merchant_integration` 抓到
  （它在商人房里断言「成交后交易撤离条件未解锁」）—— 说明那条测试真的在守这条契约，改回声明式。

### 4. room_08 落位

`f00_room_08_static_layout.tscn` 末尾追加 `Marker3D`：

```text
[name=ServiceStation_Merchant_00]  美术根帧 (2.75, 0, -2.5)
metadata/service_station_config = {"type":"merchant","display_name":"贩卖机","trade_extraction":false}
```

- 位置在中庭里、离房心 3.72 m；整块占地（4.34 × 1.55 m）脚下有楼板，四周留 ≥0.7 m。
- 朝向按**美术根帧**写，使货窗朝玩家来路（`room_07` 那侧）。四向对齐后关系随房间一起转。
- 正面判据 = **模型 +Z**（货窗与「UI灯光」发光网格都在 +Z，单独渲染四面实测：
  `+Z` 面有展示格玻璃门与 `AUTO VEND` 字样，`±X` 是侧面）。包装里 `InteractionShape` 偏 −Z 是 99F 的
  「背靠墙」口径，**不能**当正面判据 —— 第一版按它摆，玩家看到的是机器侧面。

## 验证

APPDATA / LOCALAPPDATA 隔离到 `I:/ss2_probe_appdata/*`，不碰业主存档。真实渲染用真实 Compatibility 渲染器。

| 项 | 结果 |
|---|---|
| `tools/_exp01_room08_vending_probe.tscn`（新，真实远征流程） | **exit 0，23 项断言全通过**，`EXP01_ROOM08_VENDING_OK` |
| 服务点唯一性与来源 | 房内 merchant 服务点恰好 1 台，来自作者锚点，`get_service_station("merchant")` 可取 |
| 「中部」 | 离房心 3.72 m（阈值 7.0 m） |
| 脚下楼板 | 占地 9 点向下射线全部落在 |y| ≤ 0.35 的楼板上 |
| 视觉 | 引用 `vending_machine` GLB，非程序化占位盒 |
| 实体碰撞 | `StaticBody3D.collision_layer ≠ 0`（挡人） |
| 交互盒 | 覆盖 z −2.37 ~ +2.37，正面站位在覆盖范围内 |
| 正面可站 | 货窗前 2.3 m 处 0.9×1.1×0.9 盒放得下 |
| 门→机器连通 | 从门内落点 0.75 m 格 4 邻域洪泛到机器正面，访问 849 格连通（不是直线距离） |
| 交互链 | 交互后商人页打开且可见，货架以 `room_08` 建立 |
| 撤离契约 | 普通战斗房成交前不解锁交易撤离 |
| 出怪点 | 无出怪点落在贩卖机体内 |
| `verify_run_merchant_integration` | **exit 0**，`RUN_MERCHANT_INTEGRATION_OK`（写盘失败回滚/重开/读档/坏快照/旧档全过） |
| `verify_expedition_room_static_scenes` | exit 1，**与改前基线同为 20 条**（用 `git stash` 暂存本轮源码改动后重跑对比，逐条一致）；room_08 那 3 条是业主改结构后「生成器清单 42 块 / 实际 51 块」的既有债 |
| `check_level_decoupling.py` | exit 0（7 容器、0 违规） |
| `check_asset_runtime_naming.py` | exit 0（未新增带版本运行资产） |
| `check_ledger_refs.py` | exit 0（pending=0） |
| `check_domain_boundaries.py` | exit 0（0 违规） |
| `check_verification_registry.py` | exit 0（306 场景、各套件唯一归属） |
| `check_documentation_contracts.py` | exit 1，**11 条既有断链**（与改前一致，本轮新增记录链接已通） |
| `verify_ledger_split.py` | exit 1，**40 条失败全部在敌人账本**（39 条 R/S 公式形状 + 1 条 `ENM-TRAP-SPIKEWORM01` 行内容，均非本批改动）；本批所改行与场景账本 0 命中 |

真实渲染截图（工程外 `I:/ss2_shots/room08_vending/`）：`10_vending_front.png`（玩家站位正视货窗）、
`11_vending_oblique.png`（斜视，可见展示格与 `AUTO VEND`）、`13_vending_plan.png`（整房俯视）。
玩家站位由探针搬到机器正前方——不搬则 `PlayerVision3D` 会把整台机器剔成不可见（玩家还在入口房）。

### 塌过的坑（保留，不要重犯）

1. **探针选中了旧快照帧**：先用 `test_mode = true` + 固定种子，得到 `doors=["south","west"]`、
   `enemy_spawn_points=0`、美术根 `-90°`——那是旧快照分支（朝向 0）。改用真实流程（`test_mode = false`，
   新战局朝向 180）才是玩家那一局。**探针帧选错会把好摆放判成 bug。**
2. **站立采样球扎进地板**：半径 0.45 的球放在 y=0.35（球底 −0.10 m）⇒ 任何点都「站不下」；
   抬到 y=0.5 后又撞上中庭 `y=0.08/0.16` 的地砖碰撞。最终用底在 0.20 m 的盒（0.9×1.1×0.9）。
3. **足迹口径失效**：`_inside_authored_footprint()` 读的是**生成器产出的**地砖清单（42 块），
   不认业主新增的 9 块中庭地砖。改用物理地板射线判定。（该口径债本身未修，见下。）
4. **把 `visible_in_tree=false` 当成渲染 bug**：实际是 `PlayerVision3D` 的视野剔除（服务点在 `service_station_3d` 组），
   玩家不在本房时必然不可见。用 `visibility_changed` + `print_stack()` 定位，避免误改渲染。

## 未做与已知边界

- **足迹口径债（未修）**：`authored_layout_instances` 仍是 42 块地砖，中庭那 9 块只活在 TSCN 里。后果是
  敌人不会在中庭生成（该帧 `enemy_spawn_points` 为空，探针里只能记 NOTE 不做断言）。修法二选一
  （回填房型布局源 / 运行时把 TSCN 地砖并进足迹），都会改动 13 房共用的足迹口径，需业主先裁定。
- 未跑真实整关游玩（进房、付款、撤离全流程）、Forward+、移动端与完整 smoke/core/full 套件；
  整关状态保持 partial，不因本次局部通过提升。
- 战斗封门期间仍可开商人页（UI 会锁输入）。是否要在封门房禁用交易，留给后续裁定。
- 未验证多个种子下「门→机器」连通性；已验的种子是真实新局（朝向 180）。

## 追溯登记

- 账本：`ShellStorm2_场景账本_v001.xlsx` 《资产主表》Y242 追加本轮备注；《域变更日志》**v0.1.91**
  （v0.1.90 已被同日「新九组件」批次占用，并行会话不得覆盖）。
  `ENV-EXPEDITION-L01-L-CORRIDOR` 的版本/哈希与其余 24 列不动（本轮未改房型源与 GLB）；不新增资产行。
- `ledger_split_baseline.json`：**只刷新本行指纹与第 25 列（备注）列指纹**，其它行/列/分页一律不动。
  备份后缀 `.before_room08_vending_20261115` 与 `.before_room08_vending_note_fix_20261115`。
  磁盘上另有并行会话留下的既有漂移（`ENM-TRAP-SPIKEWORM01` / `ENM-ELITE-ARMS-TAKER-3D` /
  `VFX-ELITE-RENT-TRANSFER-TRAIL-3D` 三行改动、两行宝箱新增）**刻意不吸收** —— 基线是回归守卫，
  不能顺手刷新掩掉别人的改动；脚本每次运行都把这份「未吸收清单」打印出来。
- 备注里关于视觉来源的说明写了两次（第一版误记为「主题 `merchant_visual_scene` 声明」），
  第二支脚本 `fix_expedition01_room08_vending_note.py` 定点改成「锚点 `visual_scene` 声明」。
- 文档：[远征01设计](../design/远征关卡01设计.md) room_08 段、[局内商人](../04.1_玩法系统_局内商人.md) §1.2、本记录。
