# 远征03 随机家具：判据用错了量（2026-10-30）

## 1. 业主要问的是什么

> 「远征关卡03 的房间，自动刷出的搜索用的设施，这个是写死的嘛？」

**是写死的。** 全部集中在 `DungeonRoom3D._build_content()` 一处：

| 项 | 值 | 性质 |
|---|---|---|
| 数量 | `small/tower_cell`→3、`medium`→5、`large/floor`→7、其他→9；`STORAGE/SCAVENGE/BASEMENT` +2 | 硬编码 |
| 可搜索概率 | `_rng.randf() < 0.5` | 硬编码 |
| 类型 | `theme.furniture_bias`（默认 crate/locker/desk）+ `STORAGE`/`UPGRADE`/`TRAP` 追加 | 主题常量 + 硬编码 |
| 位置 | `x = ±dims.x × 0.34`，`z` 沿 `±dims.y × 0.28` 均分 | 硬编码公式 |
| 掉落 | `4 + difficulty_rank × 2 + (6 if large)` | 硬编码 |

唯一可配的只有**一个开关** `search_facilities_enabled`。

## 2. 但真正的问题不是"写死"

写死本身是既有的塔楼机制，不算 bug。真正的问题在**判据用错了量** ——
三处，都可以用实测坐实。

### 2.1 档位一刀切

`TowerDescent3D._append_plan_room_record()` 传给 `_append_tower_record()` 的
`size` 参数是**字面量** `"tower_cell"`：

```gdscript
_append_tower_record(
    str(spec.get("id", "")), str(spec.get("type", "COMBAT")), "tower_cell", ...
```

`tower_cell` 的语义是"15m 塔楼格子"，对模块壳房间是准确的。但远征03 是 flow 关卡，
房间真实尺寸从 5×5 到 70×50 都有。于是：

```text
45×40 的 hub_01  →  3 件
40×30 的 room_01 →  3 件
5×10 的走廊      →  3 件
5×5 的十字路口   →  3 件
```

**四个不同尺寸拿到同一个数**。尺寸完全没参与计算。

### 2.2 没有尺寸下限

5×5 的十字路口四面都是门。塞 3 件家具后，`_uses_random_interactive_clutter()` 的
门净空逻辑（`door_clearance_m = 2.4`）会把整间房清空 —— 家具却不受这套约束，
直接摆进去，通道堵成迷宫。

对照：**易碎杂物早就用 8m 判据跳过小房**（`min_room_size_m = 8.0`，§7.4）。
家具没有。同一个房间，杂物 0 件、家具 3 件。

### 2.3 没有"专属陈设"排除

排除表只有 `FACILITY` / `STAIR_LOBBY` / `BOSS`。漏了两类：

| 房型 | 专属陈设 | 后果 |
|---|---|---|
| `MERCHANT`（商店） | `_create_service_station()` 服务台 | 家具先摆、服务台后建且**不避让** ⇒ 随机柜子挡在柜台前 |
| `EXTRACTION`（撤离房） | 撤离信标 | 信标是交互主体，家具挤压跑位空间 |

实测 `shop` 房原本有 3 件随机家具、`searchable=0`（恰好都不可搜），
视觉上就是"商店里堆了三个不明箱子"。

## 3. 修法

### 3.1 档位：按真实面积推，只对 flow 房间

新增 `DungeonRoom3D.size_class_for_dimensions()`。阈值取 `ROOM_DIMENSIONS` 四档
面积的**几何平均** —— 面积比才是等距的，取算术平均会让 `large` 档过宽：

```text
small 22×18 = 396㎡
medium 32×26 = 832㎡   ← 分割 sqrt(396×832)  = 574
large 44×34 = 1496㎡   ← 分割 sqrt(832×1496) = 1115
arena 56×42 = 2352㎡   ← 分割 sqrt(1496×2352)= 1876
```

`_append_plan_room_record()` 改为：

```gdscript
var plan_size := (
    DungeonRoom3D.size_class_for_dimensions(plan_dimensions)
    if bool(spec.get("procedural_shell", false))
    else "tower_cell"
)
```

**判据用 `procedural_shell`** —— `FloorPlanGenerator` 只在 flow 分支置真（第 892 行），
所以塔楼模块壳与远征01/02 的 spec 没有这个键，走 `tower_cell` 分支，**行为逐字不变**。

### 3.2 尺寸下限 + 专属陈设排除

`_build_content()` 里把散落的 `if` 收成两条判据：

```gdscript
const FURNITURE_EXCLUDED_ROOM_TYPES: Array[String] = [
    "FACILITY", "STAIR_LOBBY", "BOSS", "MERCHANT", "EXTRACTION",
]
const MIN_FURNISHED_SHORT_SIDE_M := 8.0
```

`8.0` 的推导（不是照抄杂物）：最大家具 2.4m + 两侧各 1.4m 通行净宽 + 离墙间距 ≈ 7.8m。
与 §7.4 杂物的 `min_room_size_m = 8.0` 同值，两个系统对"什么算小房"口径一致。

## 4. 实测对照

| 房间 | 尺寸 | 档位 | 家具（前 → 后） | 可搜 |
|---|---|---|---|---|
| `boss` | 50×40 | arena | 0 → 0（BOSS 排除） | 0 |
| `hub_01` | 45×40 | large | **3 → 7** | 2 → 5 |
| `n04`~`n06` | 45×40 | large | **3 → 7** | 1 → 4 |
| `room_01` | 40×30 | large | **3 → 7** | 1 → 3 |
| `reward_01` | 40×30 | large | **5 → 9**（SCAVENGE +2） | 2 → 3 |
| `reward_02` | 40×30 | large | **5 → 9**（STORAGE +2） | 2 → 4 |
| `n02` / `n03` | 25×25 | medium | **3 → 5** | 2 → 3 |
| `shop` | 30×40 | large | **3 → 0** | 0 |
| `exit` | 25×25 | medium | **3 → 0** | 0 |
| `conn_01` | 10×30 | small | 3 → 3 | 2 |
| `cr00_entry_n01` | 5×10 | small | **3 → 0** | 0 |
| 5×5 十字路口 ×5 | 5×5 | small | **3 → 0** | 0 |

级联：易碎杂物从 78 件降到 75 件（家具变多，`_interactive_clutter_blocked_centers()`
避让导致少放 3 件）。`E3_CLUTTER_DRIFT = 0`，确定性未受影响。

## 5. 为什么这不叫"调大框架"

| 可能被质疑的点 | 实际情况 |
|---|---|
| 新增了档位推导函数 | 只是把**既有四档**（`ROOM_DIMENSIONS`）按真实尺寸选出来，没有新档位 |
| 改了 `size_class` | 只对 flow 房间生效，塔楼/01/02 走原分支 |
| 会不会影响刷怪数量 | `desired` 公式（`Dungeon3D:3910`）只在**塔楼兜底路径**跑；远征03 有 `spawn_placements` / `enemy_spawn_plan`，在 `_spawn_room_enemies()` 前段就 return 了 |
| 会不会影响战利品 | `size_class` 在战利品里只用于 `Dungeon3D:5724` 的容器类型映射（small→crate / medium→locker / else→hidden_cache），属于表现选择；掉落数量不看它 |
| 会不会影响房型标签 | 会：`TOWER_CELL` → `LARGE`/`MEDIUM`。这是修正，不是回归 |

## 6. 验收

新增 `tests/verification/probe_expedition03_furnishing.{gd,tscn}`：

```text
FURNISH small_with_props=0 excluded_with_props=0 large_min=7 medium_max=5
FURNISH PASS 短边 < 8m 的房间不得布置家具
FURNISH PASS 专属陈设房型不得布置随机家具
FURNISH PASS 大房间家具数不得少于中房间（large_min=7 medium_max=5）
FURNISH_PROBE OK
```

三条断言各自对应 §2 的一处问题，且**探针显式复算**判据（不读实现常量），
实现被改错时会红。

回归：

| 套件 | 结果 |
|---|---|
| `probe_expedition03_playable` | `PLAYABLE_OK` |
| `probe_expedition03_clutter` | `E3_CLUTTER_OK`（placed=17 / total_items=75 / drift 0） |
| `probe_expedition03_save_roundtrip` | `STATE_PROBE OK` |
| `tools/_egt_chest_probe` | `EGT_CHEST_PROBE_OK` |
| `scripts/check_level_decoupling.py` | violations 0 |

## 7. 改动清单

| 文件 | 改动 |
|---|---|
| `src/world3d/DungeonRoom3D.gd` | 新增 `size_class_for_dimensions()`、`FURNITURE_EXCLUDED_ROOM_TYPES`、`MIN_FURNISHED_SHORT_SIDE_M`；`_build_content()` 家具数量段改为两条判据 |
| `src/world3d/TowerDescent3D.gd` | `_append_plan_room_record()` 按 `procedural_shell` 选真实档位 |
| `tests/verification/probe_expedition03_furnishing.{gd,tscn}` | 新增：三条断言 + 逐房实测表 |
| `docs/v0.1/design/远征关卡03设计.md` | 新增 §7.5 |

## 8. 未做（留给下一次）

1. **家具数量/密度数据化**：像 `interactive_clutter` 那样进 `level_plan` 段，
   关卡的"家具密度"才可调。本轮只修判据，不扩 schema。
2. **远征01/02 的档位**：它们仍是 `tower_cell`（25×25 也摆 3 件）。这是既有行为，
   不在本次报单范围；要改需先确认它们的美术壳体（constrained / authored）是否
   依赖 `tower_cell` 的家具数量。
3. **`containers` 采集扫场景组**：detail 卸载时会写空表（上次已记，仍未修）。
