# 远征03 美术层放行结构件（公馆拼装）

日期：2026-10-31。功能：WORLD-PLAN。依据：业主「结构要进美术层，作为远征03的特例，然后修改文档，让这些资产都能在远征03 使用拼装。好了之后 git 需要追踪这批原始资产，不然其他电脑用不了」。

## 一、改了什么

| 文件 | 改动 |
|---|---|
| `src/world3d/RuntimeRoomArtSource.gd` | 新增 `ART_LAYER_STRUCTURE_ALLOWLIST`（`manor_` 族）与 `is_art_layer_structure()` |
| `src/world3d/DungeonRoom3D.gd` | `art_layer_keep_structure` 开关；`_strip_art_layer_geometry()` 放行；新增 `_art_layer_coverage()` 按覆盖接管；程序化地板/墙/角柱按覆盖跳过 |
| `src/world3d/TowerDescent3D.gd` | flow 房间记录 `art_layer_keep_structure = true`，并下发到房间配置 |
| `tools/_exp03_manor_art_probe.gd` | 新探针：铺满 vs 只摆一件，两条路径都断言 |
| `tools/_struct_classify_probe.gd` | 补 12 条放行边界断言（88 条 0 失败） |
| `tools/_manor_batch_probe.gd` | 40 件资产体检（206 条 0 失败） |

## 二、为什么默认剥、这里不剥

默认规则（2026-10-31 早先定）是：**墙和门是玩法几何**，烘焙场景里的墙按保存那一局的门位摆，换局就错位，所以美术层只承载装饰/陈设/灯/材质，壳体由程序化按本局 `ports` 重建。

远征03 的美术方向恰好相反 —— 它要用公馆的护墙模块、门墙模块、5m 地砖**拼出房间本身**。剥掉之后工坊里摆的东西静默消失，这套资产就没有意义了。所以开例外。

例外刻意做得很窄：

- 只放开 `manor_` 名字族，且必须是结构件（`solid_wall` / `door_wall` / `floor` / `floor_tile`）。
- **程序化壳体 `prp_room_*` 永不放行** —— 它们每次都由 `_build_shell` 重建，留着必然两层墙两层地板。
- 只有远征03 的 flow 房间带这个开关（`procedural_shell` 那一支），塔楼与远征01/02 逐字不变。

## 三、接管必须按覆盖判定

这是本次唯一的实质风险点：放了结构件就整套接管，只摆一面墙时房间会漏风。

`_art_layer_coverage()` 的做法是**逐格采样**，不是「有就跳」：

- 地板：房间按 5m 分格，**每个格中心**都被某块地砖的 AABB 水平投影压住，才算铺满；
- 墙面：该面**每个 5m 槽位**的中心都被某块墙件的 AABB 压住，才算覆盖；采样点贴边内侧 0.12m（护墙半厚 0.25 / 铅条窗半厚 0.305 都覆盖得到，房间中央的陈设不可能被误算成墙）；
- 只有铺满/覆盖才 `set_meta("procedural_floor_skipped")` / `procedural_walls_skipped_sides`；
- 四面都覆盖时另跳过四角角柱。

门扇**不受影响**：`_build_door()` 始终按本局 `doors` 生成，美术只负责洞口（`manor_wall_door`）。

## 四、顺手修掉的两个缺陷

**1. 剥离函数会中断整轮。** 原来是「祖先也在名单里就跳过」，判据是 `tops.has(parent)` —— 父节点被 free 之后，这个比较落在失效实例上，抛 `Cannot call method 'get_parent' on a previously freed instance`，而 GDScript 这类运行时错误**不中断函数后续语句之外的循环逻辑**：实测美术层里一旦出现「结构件嵌结构件」，一轮剥离可能一件都没做完，且**没有任何门禁发现**。改成按深度升序 + `is_instance_valid()`，父子顺序天然正确。

这是既有缺陷，不是本次引入的 —— 只是白盒快照是扁平的（21 件互为兄弟），所以从没触发过；公馆包装场景（`env_manor_*_root_top3d.tscn` 里嵌 `_visual_top3d.glb`）一进来就命中了。

**2. 包装件与内嵌件会被数成两件。** `env_manor_wall_standard_root_top3d` 与它内嵌的 `env_manor_wall_standard_visual_top3d` slug 同族，都命中放行；不去重时 45 件被数成 90 件（探针第一轮实测就是这个数）。改为只数**顶层**那一件（`_has_allowlisted_ancestor()`）。

## 五、验证

```
godot --headless --path . --scene res://tools/_exp03_manor_art_probe.tscn
MANOR_FULL    kept=45 stripped=0 floor_full=true sides=[north,south,west,east] floor_skip=true wall_n=no
MANOR_DOORS   2
MANOR_PARTIAL kept=1  stripped=0 floor_full=false sides=[]                     floor_skip=false wall_n=yes
MANOR_ART_PROBE_OK failures=0
```

铺满 → 保留 45 件结构（25 地砖 + 19 护墙 + 1 门墙）、程序化地板与四面墙全部让位、门扇仍在；
只摆 1 件 → 程序化壳体原样保留，地板与四面墙齐全。

回归（全部与改动前逐值一致）：

| 项 | 结果 |
|---|---|
| `_exp03_reuse_probe` | 一份美术命中 5 间房，`failures=0` |
| `_exp03_reuse_key_probe` | 17 键 / 28 房，14 / 29，`failures=0` |
| `_exp03_shell_source_probe` | `static=0 procedural=111 unknown=4` |
| `_struct_classify_probe` | `checks=88 failures=0` |
| `scene_builder/test_runtime_source` | `checks=289 failures=0` |
| `check_expedition03_room_layouts.py` | `ok: true` |

关键点是**没有公馆美术时行为不变**：`_exp03_reuse_probe` 里五间房仍是 `stripped=21 / wall_north=true`，说明例外只在真的摆了公馆结构件时生效。

## 六、代价（写进规范，避免以后当成 bug）

- 门位变化不会自动修正美术里的墙。装配时门的位置必须放 `manor_wall_door`，放实心护墙会把人挡死（实心件 `collision_owner: self`）。
- 复用键仍是「模板 + 尺寸 + 房型 + 安全角」，所以重排一份美术会同时影响所有同模板房间。
- 跨局稳定的是装饰、陈设、灯、材质，以及按覆盖接管的**结构外层观感**。

## 七、没做的事

- **没做半格对齐**。房间都是 5m 整数倍，公馆墙也按 5m 切，所以能对齐；若将来出现非 5 整数倍的房间，覆盖判定会算作「没铺满」，回到程序化壳体 —— 安全，但会静默失去美术。
- **没把 `manor_wall_*` 加入 `STRUCTURE_FAMILIES` 之外的任何默认白名单**。放行只经 `ART_LAYER_STRUCTURE_ALLOWLIST` 一条路。
- **没跑视觉验收**。本次只动放行与接管判定，不宣称观感变化。
