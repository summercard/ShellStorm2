# -*- coding: utf-8 -*-
"""2026-09-20 收尾记忆：日志追加 + MEMORY.md 两条硬约定 + playbooks 细化。全部 CRLF 字节级。"""
import sys

DAILY = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-20.md"
MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY.md"
PB = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY-playbooks.md"

DAILY_ADD = """
## 11:40-12:05 补齐安全房碰撞的「连带回归」——`wall_floor_facility_kit` 被打红并修复

### 我上一轮判断错了，如实记下

补完 15 件设施的内嵌碰撞后，回归里 `verify_battle_wall_floor_facility_kit` 报 `exit=1 / ERROR=8`。
我当时**只看 ERROR 条数**，判成「PagedAllocator / RID 泄漏噪声、与本次无关」。**错了。**

真相：该场景把 `north_server_00` / `north_server_01` / `central_terminal_island` 当**墙边装饰**实例化
（`wall_floor_facility_kit_root_top3d.tscn` 的 `WallSideFacilities` 下 `DataCabinet_North_01` / `_02` + `WallSideDataDesk`）。
我给前两件加了内嵌 `StaticBody3D` → 这两个实例的 `collision_shape_count` 从 0 变 1 →
撞破脚本里写死的 `if child.get_meta("collision_shape_count", 0) != 0: _fail("FACILITY_COLLISION_NOT_ZERO")`。

那 8 条 ERROR 是**断言提前 `return`、`root.free()` 没执行**而连带泄漏的资源 —— **是结果，不是原因**。
真正标记是 stderr 里不带 `ERROR:` 前缀的 `FACILITY_COLLISION_NOT_ZERO:DataCabinet_North_01`，
而我只 `grep -aE '^ERROR|SCRIPT ERROR'`，所以没看见。
⇒ **教训：别用 ERROR 条数当结论，先找脚本自打的语义失败标记。**

### 修法：把「写死为 0」换成「声明 == 实际」的一致性断言

- kit 声明同步事实（`wall_floor_facility_kit_root_top3d.tscn` + 同目录 `asset_manifest.json`）：
  `visual_only_facilities` `true→false`、`collision_policy` `…facilities_none → …facilities_self_per_package`、
  `WallSideFacilities` 节点补 `collision_inheritance` 说明、版本 `v001 → v002`。
  （该 kit 未登记进任何台账、`check_asset_registry.py` 也不校验 version ⇒ 升版无门禁风险。）
- 断言侧 `verify_battle_wall_floor_facility_kit.gd`：逐件比 `declared == _count_enabled_shapes(child)`，
  加两个哨兵 `checked != 3`、`blocking == 0`（0 样本 / 全不挡都变红），marker 追加 `blocking=%d`。
  `_count_enabled_shapes` 递归数的是引擎里真实 `not disabled and shape != null` 的形，**不读元数据**。

### 顺手清掉最后两处「幽灵结构代理」残留

两个**运行时 prefab**（`central_terminal_island` / `west_glass_office`，即上一轮移出安全房那两件）
的 `collision_owner` 由 `godot_0p30m_structural_proxy` → `none` + `no_blocking_by_design` +
`collision_exclusion_reason`；对应源 `asset_manifest.json` 的 `collision_status` 同改实话。
⇒ 运行时 prefab 里现已 **0 处**引用该代理（只剩历史 Q&A 脚本 / README 与验证脚本注释）。

### 验收（`_scratch/verify_kit_collision_consistency.py` 一次跑完 基线 + 双反向对照 + 还原）

| 场景 / 阶段 | 结果 |
|---|---|
| `verify_battle_wall_floor_facility_kit` | exit 0 / ERROR 0 / `BATTLE_WALL_FLOOR_FACILITY_KIT_OK … blocking=2` |
| `probe_safe_room_facility_collision` | exit 0 / ERROR 0 / `SAFE_ROOM_FACILITY_COLLISION_OK` |
| `verify_expedition_level01_flow` | exit 0 / ERROR 0 |
| `probe_safe_room_v007_integration` | exit 0 / ERROR 0 |
| 对照A：kit 声明改回 `visual_only = true` | 必红 → 实测 `FACILITY_VISUAL_ONLY_STILL_TRUE` ✅ |
| 对照B：`north_server_00` 的 `CollisionShape3D` 加 `disabled = true`（声明仍=1） | 必红 → 实测 `FACILITY_COLLISION_MISMATCH:DataCabinet_North_01 declared=1 actual=0` ✅ |
| 两次还原后复验 | 均重新绿 ✅ |

对照B 是关键：证明断言读的是**真实启用的形**，不是回读元数据。`.rcA` / `.rcB` 备份已由脚本 `os.replace` 还原，无残留。

### 与本次无关的红（并行会话造成，不是基线）

- `verify_base99_floor_player_collision_flow`：`exit=1`，唯一 ERROR 是
  `99层完整新地板与100层正常地板表现高度差过大: 0.1500`。它比的是 base99 完整地板 Y 与
  `TowerFloorStage3D` 天台台面 Y；脚本**零引用**安全房 / kit，与我改的文件集合无交集 ⇒ 不可能受影响。
  对应**另一会话正在做的天台 v002 / base100 上层围护**（工作区里 `env_base100_upper_shell_30x30_h12…` 与
  `DungeonRoom3D` 的 `base100_rooftop_*` 计数已出现）。**不要动。**

### 遗留（未做，等主人定）

kit 的 `WallSideDataDesk` 仍实例化**已被移出安全房**的 `central_terminal_island`。
kit 不是运行时消费件（全仓只有它自己的验收脚本引用它），所以不算回归；
但若「去掉这两个组件」的本意是「哪儿都不再出现」，这个摆放点应一并删
（会让 kit 设施 3→2，连带改 `facilities=3` 断言与 manifest 的 `wall_side_facilities: 3`）。**没擅自改。**
"""

PB_ADD = """
## 共享 prefab 改碰撞的连带面 + 「断言提前 return 连带刷 ERROR」（2026-09-20）

### 改共享 prefab 前先扫外部复用点（本次真踩坑）

给安全房 15 个房间包补内嵌 `BoxShape3D` 后，`verify_battle_wall_floor_facility_kit` 被打红。
根因：`assets/art/environments/tower_zones/battle/runtime/wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn`
把 `north_server_00` / `north_server_01` / `central_terminal_island` 当**墙边装饰**实例化
（`WallSideFacilities` → `DataCabinet_North_01` / `_02` / `WallSideDataDesk`），
而该场景断言写死「设施 `collision_shape_count` 必须为 0」。

**通用动作**（改任何共享 prefab 前先扫）：
```
grep -rln "runtime/<组件目录>/" --include=*.tscn --include=*.gd --include=*.tres assets/ src/ tests/ scripts/ \\
  | grep -v "runtime/<组件目录>/"
```
外部复用点会**继承** prefab 的改动（碰撞 / 元数据 / 版本）。凡「展示件 / kit / 组合包」，
其自检**不能写死被复用件的属性值**，只能断言「声明 == 实际」+ 加 0 样本哨兵。
本次修法：`declared == _count_enabled_shapes(child)`；`_count_enabled_shapes` 递归数引擎里真实
`not disabled and shape != null` 的形（读实时状态，不读元数据）。

### ⚠️ 场景断言失败时，尾部那一屏 RID / 资源泄漏 ERROR 是**结果不是原因**

`verify_battle_wall_floor_facility_kit` 失败时日志有 8 条 `Pages in use exist at exit in PagedAllocator` /
`N RID allocations of type ... were leaked at exit` / `147 resources still in use`。
它们**不是独立的泄漏缺陷**：断言失败走 `_fail()` → `call_deferred("_finish", 1)`，
**`root.free()` 从未执行** → 整棵场景树泄漏。修好断言后 ERROR 归零、exit 归 0。

⇒ 失败排查顺序：① 找脚本自打的语义标记（`*_FAIL` / 专用前缀，多经 `printerr()`，**不带 `ERROR:` 前缀**，
`grep '^ERROR'` 会漏）；② 再看 ERROR 条数；③ 若脚本在失败分支提前 `return`，
把尾部泄漏 ERROR 当**派生现象**处理，别当噪声放过、也别当新缺陷去查。

### 「幽灵契约」清仓口径

`godot_0p30m_structural_proxy` 是房间包 `collision_owner` 里一个**全仓无实现**的样板文（抄自墙件规格）。
2026-09-20 起：11 件阻挡包 → `collision_owner="self"`；4 件按几何不挡的 → `"TowerFloorStage3D._build_support"` / `"none"`；
最后两个已移出安全房的包（`central_terminal_island` / `west_glass_office`）→ `none` + `no_blocking_by_design`
+ `collision_exclusion_reason`。运行时 prefab 已 0 处引用该代理。
"""


def append(path, text):
    with open(path, "rb") as fh:
        data = fh.read()
    eol = b"\r\n" if data.count(b"\r\n") > 0 else b"\n"
    if not data.endswith(eol):
        data += eol
    data += text.encode("utf-8").replace(b"\n", eol)
    with open(path, "wb") as fh:
        fh.write(data)
    print("APPENDED %s" % path)


MEM_ANCHOR_1 = "- **「字段透传 / 行为」类新断言必须做一次反向对照**（改坏 → 须变红 → 还原）。\n"
MEM_ADD_1 = (MEM_ANCHOR_1 +
             "- ⚠️ **失败时尾部一屏 RID / 资源泄漏 ERROR 往往是「断言提前 `return` 未 `free()`」的派生现象，不是独立缺陷**；"
             "语义失败标记多由 `printerr()` 打、**不带 `ERROR:` 前缀**，`grep '^ERROR'` 会漏。"
             "排查顺序：先找脚本自打标记，再数 ERROR。\n")

MEM_ANCHOR_2 = ("- ⚠️ `DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS` 被 `probe_safe_room_v007_integration.gd` **复制了一份**，"
                "增删房间包必须**两处同批改**；验收一律用 `.size()` 动态推导，禁写死数字。\n")
MEM_ADD_2 = (MEM_ANCHOR_2 +
             "- ⚠️ 房间包还被 **`runtime/wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn`** 复用当墙边装饰"
             "（`north_server_00/01` → `DataCabinet_North_01/_02`）⇒ 改这些包的碰撞 / 元数据必须**连带跑** "
             "`verify_battle_wall_floor_facility_kit`；该 kit 自检只能断言「声明 == 实际启用形数」，**不能写死 0**"
             "（2026-09-20 就是这样被打红的）。\n")


def patch(path, pairs):
    with open(path, "rb") as fh:
        data = fh.read()
    eol = b"\r\n" if data.count(b"\r\n") > 0 else b"\n"
    for anchor, new, label in pairs:
        ab = anchor.encode("utf-8").replace(b"\n", eol)
        nb = new.encode("utf-8").replace(b"\n", eol)
        n = data.count(ab)
        if n != 1:
            print("!! %s 锚点命中 %d 次" % (label, n))
            return 1
        data = data.replace(ab, nb)
        print("OK %s" % label)
    with open(path, "wb") as fh:
        fh.write(data)
    return 0


def main():
    append(DAILY, DAILY_ADD)
    append(PB, PB_ADD)
    rc = patch(MEM, [(MEM_ANCHOR_1, MEM_ADD_1, "MEMORY.md 验证与验收"),
                     (MEM_ANCHOR_2, MEM_ADD_2, "MEMORY.md 房间包复用点")])
    print("MEMORY.md PATCHED" if rc == 0 else "MEMORY.md FAILED")
    return rc


if __name__ == "__main__":
    sys.exit(main())
