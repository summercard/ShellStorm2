# 远征关卡01 白模 v001 QA

## 结论

本版只含 **1 件**资产：远征关卡01 Boss 竞技场 `50×40m` 白模。Blender 构建与只读探针复核均通过，**121 个独立网格，校验 `PASS`，0 failure / 0 warning，`FIXED_TRIM` 收边数 = 0**。未导出 GLB，未接入 Godot，碰撞未制作。

| 项 | 值 |
|---|---|
| AssetID | `ENV-EXPEDITION-L01-BOSS-ARENA` |
| 尺寸（实测包络） | 50.0 × 40.0 × 11.9 m，world `x[-25,25] y[-20,20] z[0,11.9]` |
| 网格槽数 | 10 × 8 = 80 个地砖 + 1 整板 + 38 件墙 + 2 件门墙 = 121 |
| 层高契约 | 逻辑 12.0m / 可见 11.9m / 地坪 0.30m |
| 门洞契约 | 净宽 2.2m、净高 2.5m、底 Y 0.30m、门楣底 2.80m |
| 导出状态 | `blend_only`（未导 GLB） |
| 碰撞 | `not authored` |
| 运行时 | `not connected` |

## 尺寸来源与偏差（**必读**）

需求原话是「把大小做成 1/3 的」。**1/3 线性缩放落在 63.33×30m，无法直接落地**，原因有两条同时成立：

1. 63.33 不是 5m 的整数倍 → 末端必然挂一个 3.33m 非标墙件，破坏 v003 立下的「墙件最长 5m、非整模数边缘只用 2.5m 收边」契约；
2. `create_floor_grid` 用 `round(width / 5)` 铺砖 → 非整模数时地砖网格会溢出资产包络，包络校验直接 `FAIL`。

且 v003 的组件策略明令 **禁止缩放与合并**（`no scaling or joining`），所以「缩小 copy」这条路本身走不通。经业主裁决，最终尺寸取 **50×40m**（10×8 槽，两轴均为 5m 整数倍，`FIXED_TRIM` 归零）。

⇒ **本资产是「1/3 意图」的合规解，不是精确 1/3。** 相对来源竞技场 190×90m 的实际轴比为 X `0.2632`、Y `0.4444`。

## 来源与制作方式

| 项 | 内容 |
|---|---|
| 来源资产 | `ENV-BATTLE-L01-BOSS-ARENA`（局内关卡01 Boss 竞技场 190×90m 白模 v003） |
| 来源文件 | `source/art/whitebox/tower_zones/battle_level01/v003/blender/局内关卡01_白模_Boss竞技场_190x90m_v003.blend` |
| 制作方式 | `procedural_rebuild_on_5m_grid` —— **不是**对来源 .blend 做缩放 |
| 复用资产 | 复用来源脚本的 5m 槽位框架、四角色材质、PaletteUV 与原点契约；几何按新尺寸重算 |

这是**具体竞技场实例的派生**，不是「房间种类」。远征 01 若后续还要别的尺寸竞技场，应先按 `01-battle-room-type-art-authoring` 沉淀出 `BOSS_ROOM` 房间种类源，再由此派实例——当前这一步没有做，**不要**把本文件当成房间种类源复用。

## 墙体与门位结果（探针实测，非脚本意图）

墙体按 5m 槽位拼装，实墙每槽单件，带门墙每槽保留左右门柱与门楣三件独立网格：

| 面 | 实墙槽 | 门墙槽 | 门目标 | 净门心 |
|---|---|---|---|---|
| NORTH | 10 | — | — | — |
| SOUTH | 9 | 1（SLOT 06） | `boss_prep` | +2.5 m |
| EAST | 8 | — | — | — |
| WEST | 7 | 1（SLOT 04） | `boss_exit` | −2.5 m |

- 最长墙件：**5.0 m**（含门柱与门楣），超过 5m 的墙件为 **0**。
- 门洞净跨实测：两门均 **恰为 2.2 m**（门柱 1.4 + 2.2 + 1.4 = 1 个完整 5m 槽）。
- 全部门洞都完整占用一个 5m 槽，**没有半槽门墙**。
- 两轴均为 5m 整数倍，`FIXED_TRIM` 收边 **0 件**。

**门位推导**（把来源竞技场的门位按墙面比例投影后吸附到净门心集合 `{±(2.5+5k)}`）：

| 面 | 来源 offset | 来源半墙 | 比例 | 目标半墙 | 投影值 | 吸附 | 偏折 |
|---|---|---|---|---|---|---|---|
| SOUTH → `boss_prep` | +5.00 | 95.0 | 0.0526 | 25.0 | +1.32 | +2.5 | +1.18 m |
| WEST → `boss_exit` | −2.50 | 45.0 | 0.0556 | 20.0 | −1.11 | −2.5 | −1.39 m |

吸附到 2.5m 的奇数倍是刻意的：净门心落在 `±(2.5+5k)` 时，门槽前后两侧都剩下整数个 5m 模数，才可能做到 `FIXED_TRIM` 归零。

**两层语义标签未同步。** 来源与目标资产都是**无头白盒**：`.blend` 里只有墙/地/门墙网格，不存在「boss_prep / boss_exit」这两间房。`door_target` 是从来源竞技场继承的**门位语义标签**，用于对照「哪扇是进、哪扇是出」，不是运行时房间引用。

## 与来源竞技场对照

| 项 | 来源（battle_level01 v003） | 本资产（expedition_01 v001） |
|---|---|---|
| AssetID | `ENV-BATTLE-L01-BOSS-ARENA` | `ENV-EXPEDITION-L01-BOSS-ARENA` |
| 尺寸 | 190 × 90 × 11.9 m | 50 × 40 × 11.9 m |
| 槽数 | 38 × 18 | 10 × 8 |
| 组件数 | 802（684 地砖 + 1 整板 + 115 墙 + 2 门墙） | 121（80 地砖 + 1 整板 + 38 墙 + 2 门墙） |
| 门 | 西侧 1 组 → `boss_exit` | 南侧 1 组 → `boss_prep` + 西侧 1 组 → `boss_exit` |
| `FIXED_TRIM` | 0 | 0 |
| 最长墙件 | 5.0 m | 5.0 m |
| 层高/墙厚/门洞 | 12.0 / 0.30 / 2.2×2.5 | 同左（沿用同一契约常量） |

两处差异需要留意：

1. **门数不同。** 来源只有西侧一组门；本资产为南（进）+ 西（出）两组。多出的南侧门是按「竞技场需要一个进场门」补的，来源 .blend 里没有对应的门可继承。要还原来源的单门形态，把 `ARENA_PORTS` 里的 `boss_prep` 项删掉重跑即可。
2. **地砖数不符线性比例。** 684 → 80 而非 684/9=76，因为尺寸换了，砖数由 `round(50/5) × round(40/5)` 直接重算，不沿用来源砖数。

## 验证

| 检查 | 结果 |
|---|---|
| Blender 构建 | `EXPEDITION01_WHITEBOX_V001_ASSET_OK` / `..._READY`，`failed_assets: []` |
| 资产级校验 | `status = PASS`，failures `[]`，warnings `[]` |
| 台账级校验 | `data/validation/task_level_validation.json` → `PASS`，`asset_count = 1` |
| 只读探针复核 | 直接打开 .blend 复测：对象数 121、包络 `[-25,-20,0]..[25,20,11.9]`、最长墙件 5.0m、门洞净跨 2.2m、非 1 缩放对象 `[]`、原点契约违规 `[]` |

探针脚本：`scripts/blender/audit_expedition01_whitebox_v001.py`（纯只读，不改文件）。

## 与远征01设计源的缺口（**阻塞项，非本版责任**）

远征 01 的设计源 `data/floors/floor_00.json` 目前是 **entry + room_01…05 + extraction 共 7 间房，没有 BOSS 房席位**；`level_plan.json` 的 `room_templates` 也只有 `safe_15x15 / std_25x25 / extraction_25x25`，**没有 50×40 的房型模板**。

同时 `FloorPlanGenerator.gd` 里 **没有远征 Boss 房生成器**：`_expedition_rooms()` 是写死的 7 间蛇形排布。塔楼的 Boss 竞技场走 `generate()` 那条链（`ROOM_SIZES.BOSS_ARENA = 90×90`），远征不走。

⇒ 本白模是**美术侧先行**的独立资产。要真正接进运行时，需要 A 段（`09-level-plan-authoring`）先补：① `floor_00.json` 的 Boss 房记录；② 一个竞技场房型模板；③ 远征生成器里的 Boss 房产出；④ 运行时放置与门连通。在这一步完成前，本资产**不得**被当作「已接入」。

另注：来源竞技场的 190×90 与代码 `BOSS_ARENA = 90×90` 之间的尺寸分歧（`docs/v0.1/05.2` 决策项 D2）至今**仍为「待裁决」**。本资产没有加剧该分歧——它不依赖塔楼的 `BOSS_ARENA` 常量，走的是远征独立链。

## 渲染

- `renders/远征关卡01_白模_Boss竞技场_50x40m_v001_参考.png` —— 720p 参考机位，可见壳体与南侧门洞
- `renders/远征关卡01_白模_Boss竞技场_50x40m_v001_俯视.png` —— 俯视足印

**俯视图口径说明：** 相机为正交、`ortho_scale = max(宽,深) × 1.18`，11.9m 高的墙体在此投影下几乎不产生可见侧影，因此俯视图**几乎只呈现地板足印**，看不到墙槽与门洞。这与来源竞技场 v003 的俯视图表现**一致**（对照 `battle_level01/v003/renders/局内关卡01_白模_Boss竞技场_190x90m_v003_俯视.png`），不是本资产的渲染缺陷。墙与门的证据请以上表（探针实测）与参考图为准。

## 产出清单

```
source/art/whitebox/tower_zones/expedition_01/v001/
├─ blender/远征关卡01_白模_Boss竞技场_50x40m_v001.blend
├─ data/
│  ├─ level_plan.json / floors/floor_00.json / room_templates/   ← A 段设计源（本次未改）
│  ├─ component_packages/
│  │  ├─ catalog.json
│  │  ├─ tree.txt
│  │  └─ boss_arena/远征关卡01_白模_boss竞技场_50x40m/asset_manifest.json
│  └─ validation/
│     ├─ 远征关卡01_白模_boss竞技场_50x40m_v001_validation.json
│     └─ task_level_validation.json
└─ renders/（参考、俯视各 1 张）
```
