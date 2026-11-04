# 远征03 关灯底光：0.15（环境光通道实测无效，改走 OmniLight）

日期：2026-11-04。工程版本：0.1.0；代码起点 `38820463` 及当时工作区。
FeatureID：WORLD-BLOCKS、ENEMY-AI。
契约：[关卡接入规范](../关卡接入规范.md) §3（关卡专属内容按 ID 分支）、[远征关卡03设计](../design/远征关卡03设计.md) §7.5.6.1、[怪物受光 §7.3.1](../06_技术施工_怪物精英与Boss.md#731-封顶件顶盖遮光硬契约--2026-10-12-定)。

本次只改**表现数值与表现节点**，不改玩法规则、存档 schema、layout_id、房间资产或怪物受光阈值。

## 症状与根因

业主反馈：远征03 关灯后场景全黑，要求「多一点点灯光，不要全黑」。

首轮判断把原因归到 `TowerAtmosphere3D._apply_expedition_dark_distant()` 把 `ambient_light_energy` 写死为 0，并按 `energy × albedo × exposure` 估出 0.04 能给出约 13% sRGB 灰。**这个判断方向是错的**，随后的实测推翻了它。

实测（同一机位、全 28 间房同步取值、`--headless` 读数）：

| `ambient_light_energy` | 0 | 0.8 | 5 | 20 |
|---|---|---|---|---|
| 画面中位亮度 | 0.0062 | 0.0067 | 0.0067 | 0.0071 |
| 画面 90 分位 | 0 | 0 | 0 | 0 |

把 ambient 染成**纯红**并给到 20，画面像素最大 R 通道仍等于 G 通道（均 0.9533）—— 一点红都没上去。结论：`Environment.ambient_light_energy` 在本工程对远征03 的几何**完全无效**，不是数值太小。因此 `ambient_light_color/energy` 这条通道在 03 上是死的，越调越偏。

同时排除了另外两条：

- **太阳补光**：顶盖在房间基准 Y+12m 挡住全部直射，能量 0.02~0.2 四档画面无变化，符合封顶契约的预期。
- **雾光**：抬 `fog_light_energy` 会让远景整片发灰，直接毁掉 02/03 的「窗外纯黑」定案，不采用。

有效的只有 **OmniLight**：0.3 / 0.8 / 1.5 三档画面中位亮度 0.0060 / 0.0159 / 0.0365，单调且响应明显。

## 实现

`IndoorLightEnvelope._add_dark_fill()`，每间房一盏 `IndoorEnvelopeDarkFill`：

- `dark_fill_energy = 0.15`（`@export`，可在场景内调）
- `omni_range = max(房间短边 × 1.35, 18.0)`，位于房内 Y+4.5m
- `light_color = Color(1.0, 0.86, 0.72)`（偏暖，公馆木质感）
- `omni_attenuation = 0.6`，`shadow_enabled = false`

三条硬边界，动任何一条都会出事：

1. **不登记 `register_supplemental_room_light`** —— 该接口在关灯时把能量归零，底光会被一起熄灭。判据是灯上的 `indoor_envelope_dark_fill` meta，在 `_register_room_light` 唯一入口拦截；meta 必须在 `add_child` 之前写，因为 `add_child` 会同步触发 `_on_node_added`。
2. **不进 `EnemyIllumination3D.LOCAL_LIGHT_GROUP`，也不作为 `KIND_LOCAL_LIGHT` 进空间注册表** —— 详见下节，这条**没有数值余度**。
3. **不投影** —— 无影弱光不产生第二套假影子，也省一份阴影开销。

## 为什么这条排除是硬要求而不是「光弱所以判不到」

按 `EnemyIllumination3D._theoretical_contribution()` 推导单体贡献：

```
remaining    = 1 − distance / omni_range = 1 − 4.35 / 20.25 = 0.785
contribution = energy × remaining^attenuation = 0.15 × 0.785^0.6 ≈ 0.13
threshold    = minimum_light_contribution      = 0.035
```

**是阈值的 3.71 倍。** 一旦底光进入任一候选源，关灯房间会立刻被判 `artificial_light`。让判定保持黑暗的机制只有那两条排除，与底光亮度无关。

实测（`--headless`，全层关灯）：

| 检查 | 结果 |
|---|---|
| 28 盏底光中入 `LOCAL_LIGHT_GROUP` | **0** |
| 28 盏底光中作为 `KIND_LOCAL_LIGHT` 进注册表 | **0**（同期注册表共 175 盏局部灯） |
| 房中心 + 四边内侧 + 贴角共 5 个位置，传感器状态 | **5/5 `darkness`** |
| 底光能量强行拉到 20（133 倍）后同一位置 | 仍 `darkness`，`sun_exposure_ratio = 0` |
| 阳性对照：开房灯，同 5 个位置 | 4/5 `artificial_light`（传感器本身有效，黑暗不是假绿） |

## 数值定档

两轮定档，均由业主看图后指定。下表为**与验收同口径**的中位亮度（`verify_expedition03_indoor_lighting._luma`：step=8、x∈[1/4,3/4]、y∈[1/3,4/5]），同机位、28 间房同步取值：

| energy | 0（纯黑） | **0.15（定档）** | 0.25 | 0.40 | 开灯对照 |
|---|---|---|---|---|---|
| 中位亮度 | 0.0074 | **0.0122** | 0.0213 | 0.0377 | 0.1982 |
| 占开灯比例 | 3.7% | **6.2%** | 10.7% | 19.0% | 100% |

先按「多一点点灯光」取 0.40（轮廓全可辨），业主看图后要求再暗，定 0.15（0.40 的 -68%）。0.15 下仍能看出墙面受光面与少量地砖纹路，家具退成暗轮廓。

**下界说明**：0.10 以下画面与纯黑（0.0074）已无法区分，再降等于白改。上界 0.6 以上是开灯档一半亮度，关灯潜行失去意义。

早期一版探针用了 step=4 采样，读数（0.0075 / 0.0214 / 0.0231 / 0.0274 / 0.0414）与验收口径不一致，**已作废**，仅保留此处作追溯；上表与验收脚本逐字同源。

## 验收

独立 APPDATA 启动，未读取开发者真实存档。过程产物位于
`ShellStorm2-work/sessions/20261104_exp03_ambient/`，截图与对比页见 `outputs/expedition03_dark_fill_20261104/`。

| 项目 | 退出码 / 门禁 | 结果 |
|---|---|---|
| `verify_expedition03_indoor_lighting` | 1 / 0 | 1293 检查、**2 失败**；2 条均为 `ExtractionBeacon3D` 灯开关**既有问题**（`switch off ignored` / `restored off state ignored exit`），与改动前逐字相同。新增 85 项底光候选源审计（28 盏 × 3 + 1） |
| 同入口原生 Forward+ 渲染 `--capture-only` | 0 / 0 | `INDOOR_RENDER` 关灯 0.0129 / 开灯 0.2242 / 无遮挡 0.2552；3 倍比值判据通过 |
| `check_level_decoupling.py` | 0 | 7 个通用容器，0 违规 |
| `check_asset_runtime_naming.py` | 0 | 无新增带版本运行资产 |
| `check_documentation_contracts.py` | 1 | 15 条断链 + 4 个未登记验收入口 + `openpyxl` 缺失，**三项均为既有**（与 2026-11-03 记录逐项一致）；本次改动文件不在断链清单内，未新增断链 |

## 变异测试（证明断言会失败）

新增断言若永远为绿就是摆设，因此各做一次变异并全部还原：

| 变异 | 预期 | 实测 |
|---|---|---|
| 底光 `add_to_group(LOCAL_LIGHT_GROUP)` | 关灯房被判人造光 | `start`、`shop` 两间报 `off room still artificially lit`；28 条入组断言全红，1293 项 / **86 失败** |
| `_register_room_light` 的 meta 守卫改为 `false` | 底光被当作者灯注册并随开关熄灭 | 56 条审计断言全红 + 28 条 `dark fill went dark with the switch off`，1293 项 / **114 失败** |

两次变异后均已还原，最终 1293 项 / 2 项既有失败。

## 边界与回滚

- **只影响远征03**。`Expedition03IndoorLightEnvelope` 由 `ExpeditionLevel03_3D.tscn` 独占引用；远征01/02/99、主塔与 99F 基地不实例化该节点，行为逐字不变。
- **`TowerAtmosphere3D.gd` 只有注释改动**，无功能变更。注释记录「environment ambient 通道在 03 上无效」这一实测事实，防止后续再往那条路走。
- **回滚**：删 `_add_dark_fill()` 及其调用、`_dark_fills` 与三条审计断言即可；`dark_fill_energy` 设为 0 也等价于回滚表现。
- **不改存档**：底光无持久化字段，随场景销毁。

## 后续调整入口

只有一个数：`IndoorLightEnvelope.dark_fill_energy`。当前 0.15，可用区间 0.12~0.20；超界请回看「数值定档」的上下界说明。
