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

## 八、端到端复核（同日 11:00，回答「能不能拼装后游戏内呈现」）

业主问：「能不能用新组件对这些房间进行美术拼装，然后游戏内会呈现，只看远征03」。

新增 `tools/_exp03_manor_e2e_probe.tscn`，**复刻工坊真实保存动作**，不做简化：
取工坊采集出的真实快照（`Room_<id>` → `WhiteboxShell` → `ShellPart_NNN`）→ 在 `ArtComponents`
下按 5m 网格摆 45 件结构 + 5 件陈设（正确设 `owner`，否则 pack 不进去）→
`PackedScene.pack()` + `ResourceSaver.save()` 落到 `CONTRACT.art_path()` —— 与
`editor_plugin.gd::_finish_runtime_room()` 及用户按保存完全同一条路径 → 重新实例化关卡。

```
E2E_TARGET upgrade_25x25_2154658c5c32.tscn
E2E_ROOM  boss_foyer art_layer=true  kept=45  floor_skip=true  sides=[north,south,west,east]
E2E_NODES total=50 in_tree=50 visible=50 with_mesh=50
E2E_AABB  local_center=(0.00, 1.40, 0.00) size=(25.50, 2.80, 25.50)
E2E_DOORS 2
E2E_OK    failures=0
```

判定「游戏内会呈现」用四个硬指标，缺一不算：`art_layer_loaded` 为真、manor 节点在活动场景树里、
`is_visible_in_tree()` 为真、有 MeshInstance3D 且 AABB 落在房间内。50 件全部满足，尺寸 25.50×2.80×25.50
正好贴合 25×25 房间（墙高 2.8），局部中心 (0, 1.40, 0)、底面贴 y=0。门扇 2 扇仍在。

### 房型适配（`tools/_exp03_manor_fit_probe.tscn`）

运行时程序化地板恒为**一整块矩形**，尺寸精确等于房间尺寸（实测 50×40 / 25×25 / 45×40 / 30×40 / 40×30），
全部 5 的整数倍 ⇒ **18 间真房间都能用这套方形件铺满**。非矩形轮廓只存在于白盒壳
`rt_*_l_turn` 那类离线参考物上，运行时并不加载。

| 尺寸 | 地砖 | 墙件 | 房型 |
|---|---:|---:|---|
| 15×15 | 9 | 12 | 入口安全房 |
| 25×25 | 25 | 20 | 战斗 / 升级 / 撤离 |
| 30×40 | 48 | 28 | office_60x70 |
| 40×30 | 48 | 28 | db_70x50 |
| 45×40 | 72 | 34 | corridor_45x40 / 枢纽 |
| 50×40 | 80 | 36 | Boss |

**摆装工作量是下一个瓶颈**：50×40 要 80 块地砖 + 36 段墙，逐件手刷不现实。已在规范文档标为未做项（需要工坊「按 5m 网格批量铺装」）。

### 顺带修正工坊面板分组

`catalog_tags.gd::kit()` 原来只用 `path.contains("/expedition/")` 判前缀 —— 而 `expedition/`
这个目录远征01/02/03 共用，于是 40 件公馆件在工坊面板里显示为「**远征01 / 通用建筑套件**」，
名字错到会让人以为拿错了资产。改为按 `component_id` 前缀判（`ENV-EXP03-*` 40 条 /
`ENV-EXPEDITION-*` 212 条），并拆成两栏：

```
远征03 / 复古公馆·建筑模块   6   （护墙 / 门墙 / 铅条窗 / 三种地砖）
远征03 / 复古公馆·陈设      34
```

远征01 各组数量未变（38 / 46 / 25 / 27 / 35 / 6 / 35），`test_layout_model` 299/0。

### 三个探针自身踩过的坑（记下来，避免重犯）

- **快照要按文件名取，不能按 mtime 取最新**。缓存里有多批次的旧签名快照，按 mtime 会拿到签名不符的那份，
  运行时静默不加载（工坊遇到这种情况会明确报「关卡缓存已过期」）。正确对应关系是
  `cache_dir.path_join(art_path.get_file())`。
- **`AABB.position` 是最小角不是中心**，要比中心得 `position + size/2`；且必须换算到房间局部空间 ——
  房间不在世界原点（实测 `boss_foyer` 在 x=104.75 z=-55.25），拿世界坐标比局部半宽会每条都假失败。
- **量地板前必须 `ensure_shell_built()`**，且 `Floor` 是 `Node3D`（prefab 根，mesh 在子树里），
  直接 `as MeshInstance3D` 会转换失败、量到「缺」，把所有房间误判成非矩形。

## 九、没做的事

- **没做半格对齐**。房间都是 5m 整数倍，公馆墙也按 5m 切，所以能对齐；若将来出现非 5 整数倍的房间，覆盖判定会算作「没铺满」，回到程序化壳体 —— 安全，但会静默失去美术。
- **没把 `manor_wall_*` 加入 `STRUCTURE_FAMILIES` 之外的任何默认白名单**。放行只经 `ART_LAYER_STRUCTURE_ALLOWLIST` 一条路。
- **没跑视觉验收**。本次只动放行与接管判定，不宣称观感变化。
- **没做批量铺装**。一间 50×40 要 80 块地砖 + 36 段墙，逐件手刷不现实 —— 这是下一个瓶颈，需要工坊侧加「按 5m 网格批量铺装」的动作。
- **没接远征01/02**。放行只对 flow 房间（远征03），其它关卡逐字不变。
