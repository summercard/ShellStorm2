# 事务 2241 — 授权布局门墙断言改 lane 粒度（第 4 环收尾）

## 结论一句话

远征 13 房此前**一条通用件都没消费**；本事务让第 4 环真正产出清单，并修掉消费端断言
按 `side` 判造成的 4 条稳定假红。提交 `b2b89e21`。

## 症状 → 根因 → 修法

症状（修前，seed 77001199）：

```
ERROR: DungeonRoom3D: 授权布局 room_03 的 south 门没有对应门墙组件（清单里该槽位是实墙或缺失）
ERROR: ... room_04 的 east ... / room_06 的 east ... / branch_01 的 north ...
```

出处：`DungeonRoom3D._build_authored_layout_shell` 末尾的「门开在实墙上」断言。

根因**两层**：

1. **粒度错**：断言按 `side` 判「本房该侧有没有墙件」。
   但授权布局是**相邻共墙**，`RoomShellLayoutBuilder3D` 的 lane 归属模型是
   「同一 `(axis, line_m, lane_key)` 全局只出一件」⇒ 门槽那道墙归**声明它的那间房**，
   邻房该侧**只剩别的 lane 的实墙**。于是 `wall_sides` 有该侧、`door_wall_sides` 没有
   ⇒ 被判成「门开在实墙上」。**正确口径是 lane 粒度**（门槽 lane 上坐的是什么）。
2. **取证方式错**（顺带挖出）：原实现 `art_root.find_children("*", "Node3D", true, false)`
   反扫节点树，会把 `_add_camera_only_door_wall_proxy()` 生成的 camera-only 代理件
   （带 `tower_wall_direction` 但不是门墙组件）算成**实墙** ⇒ 即便改成 lane 粒度，
   反扫版本仍会假红。

修法：

- 在**实例循环里精确采集**墙件台账 `authored_wall_records = [{side, along, uses_door}]`，
  不再反扫节点树。`along` = 南北墙取 `local_position.x`、东西墙取 `local_position.z`，
  与 `_authored_wall_door_side()` 读 `tower_wall_door_offset_<side>` 同一个房间局部坐标系。
- 判定抽成 `static func classify_door_lane(wall_records, side, door_offset) -> String` 三态：
  - `"door_wall"` — 门槽 lane 上是门墙 → 本房承接；
  - `"solid_wall"` — 门槽 lane 上是实墙 → **真错位，调用方 push_error**；
  - `""` — 门槽 lane 上没有任何墙 → 墙归邻房，**归入 `delegated_sides`**（藏门扇面板）。
- 新增类常量 `DOOR_LANE_GUARD_TOLERANCE_M := 0.25`。0.25m ≪ 5m lane 间距（不会吃掉邻 lane），
  ≫ 浮点误差（能抓「离门槽只差十几厘米」的近失错位）。
  `_authored_wall_door_side()` 的 **0.01** 容差是「提升成门墙」的口径，**不要动它**。
- `DOOR_WALL_COMPONENT_ASSET_ID`（`ENV-BATTLE-COMMON-WALL-DOOR-5M`）现在**不再被代码引用**，
  留作批次号 alias 存档对照（注册表里它仍是 `ENV-SHARED-GENERIC-WALL-DOOR-5M` 的 alias）。

## 为什么单测是必要的

这条断言**按构造在正常布局下永不触发** —— 坐在门槽 lane 上的实墙会被
`uses_door = role=="door_wall" or not door_side.is_empty()` 提升成门墙。
所以「跑过关卡」只证明安全网没误报，**不证明它还活着**。

⇒ 新建 `tests/verification/probe_door_lane_guard.gd/.tscn`，用合成台账打全三态 + 边界：
①门槽上是门墙→door_wall；②门槽上是实墙→solid_wall（**真错位用例**）；
③该侧只有邻 lane 实墙→空串（远征实际形态，不得误报）；③b 门槽有门墙时邻 lane 实墙不得翻案；
④无墙→空串；⑤别的侧墙件不参与本侧；⑥离门槽 0.8×容差→solid_wall（近失）；
⑦1.5×容差→空串；⑧容差 < 2.5m；⑨台账混入 `null` 不崩。
结果 `DOOR_LANE_GUARD_OK checks=10`，`quit(0/1)` 按失败数。
**这个探针不进套件**（`run_verification_suite.sh` 是显式白名单，且
`check_verification_registry.py` 只盯 `verify_*.tscn`，`probe_*` 免登记），按需手跑即可。

## 第 4 环（生成器侧）落地

`src/map/FloorPlanGenerator.gd`：

- `preload` 组合器：`const ROOM_SHELL_LAYOUT_BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")`
- `_constrained_floor_from(..., policy)` 加 `policy` 形参并在 `LEVEL_PLAN_LOADER.derive_ports(rooms)`
  **之后**调 `attach_authored_layout_shell(rooms, policy)`。
  顺序不能换：门位由 `derive_ports` 现算，清单必须吃现算后的 `ports`。
- 新增三函数：`attach_authored_layout_shell`（逐房投影 + 落 `authored_layout_*` 字段）、
  `authored_shell_block`（**公开**，供验收探针复用）、`_authored_shell_block_room`。
- 坐标换算：`bounds_x_m = [cx − sx/2, cx + sx/2]`、`bounds_y_m = [−cy ∓ sy/2]`（`by = −plan.y`）；
  门位南北向 `bx = center.x + lane_m`（**无镜像**）、东西向 `by = by_center − lane_m`（**减**）。
- 入口房 `role == "stair_entry"` **跳过**（继续走 v007 安全房）；`door_leaf_preview` 角色在导出层剔除。

`source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json`：
`generation_policy` 加 `"authored_layout_shell": true`（置于 `runtime_enabled` 之前）。

## 取证（两个临时探针）

- 区块级 `probe_expedition01_authored_shell.tscn`：12 种子 `PROBE_OK`（门墙 lane 数恒等于边数、
  无实墙压门位、无 `door_leaf_preview`、每房有清单）。每种子 1207–1703 件。
- 运行时 `probe_expedition_authored_runtime.tscn`（seed 77001199）：
  修后 **`ERROR` 计数 = 0**、`PROBE_OK`、`authored 房 = 12 / 13`、未解析件 0、
  `_floor_layout_plan_conflicts` 0、塔楼子树节点 **27020**。
  **新增可断言不变量：每房 `door_wall_sides ∪ delegated_door_sides == doors`**
  （远征 13 房实测逐房成立，结构上由循环保证）。
- 回归：`verify_block00_floor98_assembly` → `BLOCK00_ASSEMBLY_OK checks=230`，失败 0
  （它直接消费 `authored_layout_delegated_door_sides` 并比 `EXPECTED_DELEGATED_DOOR_SIDES`，
  说明「lane 粒度」与 block00 的既有期望**完全一致**，改法没放宽尺度）。

## 坑（本轮新踩）

- **GDScript 缩进即结构**：往实例函数体中间插 `static func` 会把后面所有同为 1 个 tab 的
  `set_meta(...)` 行**吸进 static 函数**，报一串
  「Cannot call non-static function set_meta() from the static function」+「Identifier 未声明」。
  新函数必须插在上一个函数**完全结束之后**。
- **Godot 4.6 没有 `OS.exit_code`**（报 `Cannot find member "exit_code" in base "OS"`）。
  探针要报失败用 `get_tree().quit(0 if ok else 1)`。
- 探针脚本有 parse error 时 `--scene` **不退出、会挂住**（不报错退出，就是一直跑）⇒ 用
  `run_in_background` 起、再 cat 日志，比前台等超时快。
- Bash 里 `> /tmp/x.log` 落不进 Git Bash 的 `/tmp`；一律写 `> /i/ss2_tmp/x.log`。

## 未做 / 待办

- `git push` 仍被凭据阻塞，本地已 ahead 10（`b2b89e21`）⇒ **未获凭据前不动远端**。
- 临时探针待删：`probe_expedition01_authored_shell.*`、`probe_expedition_authored_runtime.*`、
  `probe_expedition01_constrained.*`、`probe_expedition01_plan_dump.*`。
  （`probe_door_lane_guard.*` **保留**，是长期回归用单测。）
- 待办：第 5 环 `exclusive_component` 分支（Boss 6 件专属件，**保留 y 悬空高度**，
  不可走 `to_runtime_instances` 的 y=0）+ `FloorPlanGenerator._load_boss_layout_instances()`；
  通道桥多层几何（上层平台先做、下层用标准墙下延、坑深 12m、坑底铺普通砖、下层不可达）；
  4 个非矩形轮廓写进 `room_templates/*.json`；`support_keep_out_rects` 凹形须拆多矩形。
- 性能信号：`floor_tile` 逐件实例化（≈1150 件/种子）是节点数主因，待评估是否改 MultiMesh。
