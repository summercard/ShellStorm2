# 易碎陈设接入场景工坊（2026-10-30）

## 1. 业主的问题

> 「我有一个场景编辑器里面你看一下易碎物品是不是也能放进这个场景编辑器里面，作为那个组件去刷。」

答：**能，而且现在就能刷。** 但"能刷"和"刷了能用"是两件事 —— 只把 prefab
注册进组件目录，摆出来的东西会自己复原。下面分三层说。

## 2. 现状勘查（改之前）

| 事实 | 位置 |
|---|---|
| 组件目录只有一份权威：`shell_component_catalog.json`，218 条 | `assets/art/environments/tower_zones/shared/runtime/` |
| 易碎件 prefab 早就存在，5 件齐全，结构完整（Visual + HitReceiver + PlayerContact） | `battle/runtime/common_components/breakable_*/` |
| 但目录里 `breakable` 命中 **0 条** | 逐条扫过 |
| 场景工坊只认目录，不扫目录 | `layout_model.catalog()` |
| 易碎件当前只有两个来源：安全房固定五件、关卡数据段随机撒点 | `DungeonRoom3D._build_interactive_clutter()` |

所以"刷不出来"不是因为资源缺失，纯粹是**没登记**。

## 3. 第一层：登记（让卡片出现）

`catalog.json` 追加 5 条，`slot_role = breakable_clutter`：

```json
{
  "component_id": "ENV-SHARED-BREAKABLE-JAR",
  "aliases": ["ENV-BATTLE-INTERACTIVE-JAR"],
  "kind": "generic",
  "slug": "breakable_jar",
  "category": "易碎陈设",
  "slot_role": "breakable_clutter",
  "prefab_path": "res://.../common_components/breakable_jar/breakable_jar_root_top3d.tscn",
  "bounds_size_m_godot": [0.66, 0.81, 0.645],
  "collision_owner": "self",
  "collision_policy": "projectile_hit_only_no_player_blocking"
}
```

`component_count` 218 → 223。

`catalog_tags.gd` 两处：`kit()` 把 `slot_role == breakable_clutter` 归到
「共享 / 易碎陈设」；`type_tag()` 同样。否则它们会掉进「通用建筑套件」，
和墙、地砖混在一起。

**踩到的坑**：`caption()` 取 `display_name`，取不到才落 `category`。
五件的 `category` 都是「易碎陈设」⇒ 五张卡片全叫「易碎陈设」，没法挑。
补 `display_name`（易碎罐子 / 散落书本堆 / 易碎花瓶 / 易碎椅子 / 易碎木箱）。
探针 F7 专门盯这个退化。

## 4. 第二层：运行时认领（让"砸了"算数）

摆进静态布局的 `BreakableClutter3D` 挂在 `AuthoredLayoutArtRoot` 下，随壳体常驻。
而房间现有的易碎件逻辑全部围绕 `RuntimeDetail` 写：

| 现有逻辑 | 判据 | 对手摆件的后果 |
|---|---|---|
| `_on_interactive_clutter_broken` | 由 `_instantiate_interactive_clutter()` 连信号 | 手摆件**没接线** ⇒ 砸了不进账 |
| `_restore_interactive_clutter` | `_detail_root.is_ancestor_of(clutter)` | 手摆件在壳体下 ⇒ **被跳过** |
| `_interactive_clutter_blocked_centers` | 扫 `_detail_root` 直接子节点 | 手摆件不在清单 ⇒ 随机撒点叠上去 |

`_adopt_authored_breakable_clutter(root)` 补第一项，在 `_build_shell()` 静态分支
（`add_child(static_layout)` 之后、`return` 之前）调用：

```gdscript
var clutter_id := "authored_" + str(clutter.name)
clutter.set_meta("clutter_id", clutter_id)
clutter.set_meta("clutter_authored", true)
clutter.broken.connect(_on_interactive_clutter_broken)
_authored_clutter_nodes.append(clutter)
```

id 用节点名不是随便挑的：场景工坊放置沿用 prefab 根名，同名由 Godot 自动加序号
（`BreakableJar` / `BreakableJar2` …），所以同一份布局每次实例化的名字逐字一致
⇒ id 天然稳定，不需要额外存一份映射表。

`_restore_interactive_clutter()` 判据放宽成 `is_ancestor_of(clutter)`，
并跳过空 id（防旧流程遗留的野节点往账里写空键）。

## 5. 第三层：撒点避让（别叠两件）

避让放在**候选生成**里，不放选点循环：

```gdscript
if (
    _interactive_clutter_point_is_free(point, blocked_centers, clearance)
    and not _interactive_clutter_near_point(point, authored_points, spacing)
):
    result.append(point)
```

**为什么不在选点循环里做**：随机撒点只取 3~6 个，从几百个候选里抽，
落在手摆件 1.1m 内的概率很低。第一版就在选点循环里判，探针把整段避让
删掉照样 PASS —— 断言没有牙齿。改到候选阶段后，反事实验证立刻红
（`越界 11 / 共 1456 个候选`）。

同时加了 `get_interactive_clutter_candidates()` 作为探针入口，
让断言可以检查**整个候选集合**而不是抽样。

## 6. 探针

`tests/verification/probe_authored_breakable_clutter.{gd,tscn}`
+ `tests/fixtures/authored_clutter_room.tscn`（2 件：罐子在房心，花瓶在旁边）。

走真实接入点：自建 `DungeonRoom3D`，`static_layout_scene_path` 指向 fixture，
调 `ensure_shell_built()` / `ensure_detail_built()` —— 不手工调私有函数自证。

```text
A1 2 件全部认领（实得 2）
A2 id 带 authored_ 前缀：authored_BreakableJar / authored_BreakableVase
A3 broken 已接到房间记账
A4 两件 id 不重复
B1 砸碎后房间账记下 { authored_BreakableJar: {broken, direction} }
C1 detail 卸载重建后仍是已碎
D0 候选落点非空（1445 个）
D1 候选落点不贴手摆件（越界 0）
D2 实际撒出的 6 件不重叠
E1 回灌存档后恰好 1 件已碎
F1 组件套件里 5 件易碎陈设
F2/F3 分组「共享 / 易碎陈设」、类型标签「易碎陈设」
F4 5 个 prefab 都能 load
F5 目录读取 errors 为空
F6 5 张卡片都有标题
F7 5 张卡片标题互不相同
AUTHORED_CLUTTER_PROBE OK
```

## 7. 回归

| 套件 | 结果 |
|---|---|
| `probe_authored_breakable_clutter` | `AUTHORED_CLUTTER_PROBE OK` |
| `probe_expedition03_clutter` | `E3_CLUTTER_OK` |
| `probe_expedition03_furnishing` | `FURNISH_PROBE OK` |
| `probe_expedition03_save_roundtrip` | `STATE_PROBE OK` |
| `tools/_egt_chest_probe` | `EGT_CHEST_PROBE_OK` |
| `scene_builder/test_layout_model` | `SCENE_BUILDER_MODEL_OK checks=299 failures=0` |
| `scene_builder/test_workbench` | `SCENE_BUILDER_WORKBENCH_OK checks=15 failures=0` |
| `check_level_decoupling.py` | violations 0 |

## 8. 改动清单

| 文件 | 改动 |
|---|---|
| `assets/.../shared/runtime/shell_component_catalog.json` | +5 条 `breakable_clutter`，`component_count` 218→223 |
| `tools/scene_builder/catalog_tags.gd` | `kit()` / `type_tag()` 认 `breakable_clutter` |
| `src/world3d/DungeonRoom3D.gd` | `_adopt_authored_breakable_clutter()`、`get_authored_clutter()`、`get_interactive_clutter_candidates()`、`_authored_clutter_planar_points()`；`_build_shell()` 接入；`_restore_interactive_clutter()` 放宽判据；候选生成排手摆件；快照加 `authored_clutter_count` |
| `tests/verification/probe_authored_breakable_clutter.{gd,tscn}` | 新增探针 |
| `tests/fixtures/authored_clutter_room.tscn` | 新增测试用静态布局 |
| `scripts/run_verification_suite.sh` | 探针入清单 |
| `docs/v0.1/design/场景可交互低模物件设计.md` | 新增 §r5 |

## 9. 用之前要知道的两件事

1. **远征03 目前没有 per-room 静态布局**（全走程序化壳体）。要把手摆件用上，
   得先用场景工坊「打开 → 关卡房间」创建并保存该房间美术 TSCN，
   命中 `runtime_rooms/<房间ID>_<几何签名>.tscn` 后才走静态布局分支、认领才生效。
   远征01/02 已有静态布局，直接可用。
2. **标高按 0 摆**。易碎件原点在底面中心；5m 地砖那套 `0.08` 标高套上来会浮空。

## 10. 未做

1. **手摆件是否该自动加进家具避让**：目前只看玩家可穿过 ⇒ 不算障碍。
   如果以后易碎件改成能挡玩家，这里要一并进 `_interactive_clutter_blocked_centers()`。
2. **场景工坊的"门口保护"**：现有规则保护门洞不被墙/地砖占住，易碎件体积小，
   没单独处理。真要摆到门口也不会堵路，只是难看。
3. **美术侧批量摆放**：现在是逐件点。如果要在 20 间房各摆 5 件，需要键盘复制粘贴
   或"按区域批量随机"的编辑器能力，不在本轮。
