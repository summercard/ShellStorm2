# 2026-10-19 把 99F 西侧那个交互点从「怪物档案室」换成「武器改造台」

功能 ID：`BASE-FACILITY` / `RUN-SYNTHESIS`。

## 业主口径

> 然后这个武器构建的这个界面嘛，现在的功能在 99 层基地里面还是没有的，呃 99 层基地里面的这个左下角的部分有一个建筑设施是怪物档案馆，就是在西边的门的下面有一个建筑设施，帮我把这怪物档案馆的这个意见按钮开始的这个指向给它转到这个呃转到这个这个这个功能的这个界面这边来，就是同样的设置换一个功能。

拆成三条硬要求：

1. **位点不变** —— 左下角、西边门下面那台机器；
2. **"同样的设置"不变** —— 模型、朝向、E 键交互都是原来那套；
3. **只换功能** —— 按 E 打开的是武器改造台，不再是怪物档案室。

## 落地前的事实核查

动任何东西之前先确认"玩家实际进的是哪个场景"：

- `project.godot` 的 `run/main_scene` = `StartupLoadingScreen.tscn`，启动后进 `TowerDescent3D.tscn`
  （`GameDesignConfig.MAIN_SCENE`）；
- `BaseWorld3D.tscn` 是 **历史兼容基地**（`GameDesignConfig.BASE_SCENE_3D`），只在个别旧路径上被引用。

而 `TowerDescent3D` 的基地设施来自 `Blocks/Base/Art` = `assets/art/environments/tower_zones/base/runtime/zone_base.tscn`，
再经 `env_base99_remaining_facilities_root_top3d.tscn` 里的一批资产包包装场景挂上来。

跑一次探针（打印 `base_facility` 组）确认了真正的那个位点：

```
id=monster_archive name=怪物档案室
path=.../Art/场景装饰_可自由增删/BlenderV021剩余非门非墙设施/49_武器工作台与弹药附件_资产包
menu=res://scenes/MonsterArchiveMenu.tscn
pos=(-13.83845, -10.56121, 10.35894)
```

三条都被这条打印钉死了：**西侧（x 负）、下方（z 正）**、用的是
`49_武器工作台与弹药附件` 这个资产包 —— 业主说的"左下角、西边门下面"就是它。

## 改动

| 文件 | 改动 |
|---|---|
| `src/base/BaseFacilityCatalog.gd` | 新增 `weapon_forge` 条目（名字/描述/menu 路径/紫色标识）。`legacy_building_type: -1`、`level_property: ""` —— 改造台没有建筑等级，它的能力由"持有什么材料"决定 |
| `src/base/BaseFacilityService.gd` | 新增 `weapon_forge` 的 summary 分支。**刻意不写"配方 N 条"**：那个数字的真源在 `SynthesisCatalog.RECIPES`，在这里抄一份就会在改配方时悄悄过期 |
| `src/ui/WorkbenchMenu.gd` + `scenes/WorkbenchMenu.tscn` | **新增**：把 `WorkbenchPanel` 包成 `CanvasLayer` 的适配层 |
| `env_base99_remaining_facilities/weapon_workshop_station/weapon_workshop_station_facility_top3d.tscn` | **真正生效的那个节点**：`facility_id` / `display_name` / `description` / `menu_scene_path` / `NameLabel` 全部改向改造台，`position` 与资产包实例一字未动 |
| `env_base_facility_art_layout_top3d.tscn` | 同一改动同步到另一份布置层（未参与运行时，但两份不能出现"同一个位点两个功能"的分歧） |

## 为什么需要一个包装层

`WorkbenchPanel` 是纯 `Control`：自己铺满视口、自己处理 ESC、关闭时 `queue_free`。
而 `TowerDescent3D._open_facility_menu()` 的契约是"实例化一个 `CanvasLayer`，
依次调 `set_inventory_module` / `set_player` / `set_facility`，再 `add_child`"。两边对不上。

**没有把面板改成 CanvasLayer**，理由是面板被 `verify_synthesis_catalog` /
`verify_synthesis_gate` 直接 `new()` 挂在普通 `Node` 下跑，靠 `_fit_to_viewport()`
拿视口矩形；改继承会连带改掉那两条验收的搭建方式，而它们验的是规则与表现，不是入口。
入口形态（CanvasLayer）与功能本体（Control）本来就是两件事，分开更稳。

时序也要注意：`_open_facility_menu()` 在 `add_child(menu)` **之前**调三个 setter，
所以 setter 只能存字段，真正转发在 `_ready()`。面板的 `_ready` 里会
`_resolve_inventory()`，那时 `get_inventory_module()` 必须已经能返回。

## 一个靠截图才看出来的问题：基地 HUD 没让位

第一版接完，实拍 `workbench_panel_opened.png` 是这样的：炼炉格子中间压着
基地的血条、金币数、小地图、状态栏 —— 不是"两个界面"，是"界面坏了"。

原因：改造台遮罩是 `PRISM_DIM`（alpha 0.58，**刻意**让 3D 实景可见），
而基地 HUD 是**另一个 CanvasLayer**、层号与菜单相同（实测都是 `layer=1`），
所以它不会被遮罩盖住，而是隔着 0.58 的底色与面板叠在一起。

改法：`_ready()` 里 `_hide_gameplay_hud()`、关闭时 `_restore_gameplay_hud()`。
这不是新发明 —— 衣柜菜单早就这么做了（`WardrobeMenu3D._hide_gameplay_hud`），
本轮沿用的是同一套做法，只是之前没人把它抽象出来。
另外补了 `_exit_tree()` 兜底：菜单被外部摘掉（场景切换/强制卸载）时 HUD 也要回来，
否则玩家会回到一个"什么都没有"的基地。

## 顺手修掉的两条陈旧断言

都是**本轮之前就红**的（我用 `git show HEAD:` 对比确认过，不是我改出来的）：

1. `verify_base_facility_framework`：`world_ids.size() != 8`，而 `BaseWorld3D.tscn`
   早就只有 7 个设施（怪物档案室在 `verify_base_optional_facilities_removed` 那次下线时
   忘了同步这条）。改成 7 并把原因写进注释 —— **不再让一条错数字长期红着，
   它会把真正的新红项盖住**。
2. `verify_base_optional_facilities_removed`：要求 `func _create_standalone_elevator(`，
   而实现里早已改名成 `_create_level_elevator(`（返回 `BaseFacility3D`）。验收脚本没跟着改。

## 验收

新增 `tests/verification/verify_workbench_menu_entry.gd/.tscn`（`core`）。
在**真 `TowerDescent3D`** 里跑整条装配链，9 组断言：

| # | 断什么 |
|---|---|
| 1 | 99F 仍是 8 个常驻设施（只换功能，不增不减） |
| 2 | `monster_archive` 不再出现在 99F |
| 3 | `weapon_forge` 在，且 `x <= -5`、`z >= 5`（西侧・下方，**半空间**判定，允许美术微调位置但不能搬到另一边） |
| 4 | `asset_source` 仍含 `weapon_workshop_station` —— **模型没跟着换** |
| 5 | `display_name == "武器改造台"`，E 提示 `[E] 打开 武器改造台`（`action_kind=menu` 时动词取"打开"） |
| 6 | catalog 里 `action_path == res://scenes/WorkbenchMenu.tscn` 且场景可加载；**`monster_archive` 的 catalog 条目与菜单场景仍保留**（下线的是入口，不是能力） |
| 7 | 真激活一次：打开的是 `WorkbenchMenu`，里面真的挂着 `WorkbenchPanel`，背包/玩家/熔炼按钮/炼炉栏都非空 |
| 8 | 打开期间基地 HUD 必须隐藏；已开菜单时再激活别的设施不得叠出第二个 |
| 9 | 关闭后 `_active_facility_menu` 清空、HUD 恢复、玩家输入解锁 |

`WORKBENCH_MENU_ENTRY_OK`，exit 0。

### 真渲染实拍（3 张）

`tests/verification/capture_workbench_entry.gd` → `outputs/verification/`：

| 图 | 内容 |
|---|---|
| `workbench_facility_in_base.png` | 站在这台机器前：还是原来那台武器工作台，位点没动 |
| `workbench_panel_opened.png` | 按 E 之后：改造台面板，**基地 HUD 已让位**，5×5 炼炉 + 右侧背包格 + 页脚读数 |
| `workbench_panel_catalog.png` | 切到「合成目录」页：四段曲线九条配方齐全，「蓄力萝卜炮」那行带「保底 0/3」 |

### 回归

| 场景 | 结果 |
|---|---|
| `verify_workbench_menu_entry` | **exit 0**（新增） |
| `verify_base_facility_framework` | **exit 0**（修了两处陈旧数字） |
| `verify_base_optional_facilities_removed` | **exit 0**（修了函数名断言） |
| `verify_base_facility_interaction_zones` | **exit 0**（交互区未因换节点而失效） |
| `verify_synthesis_catalog` | **exit 0** |
| `verify_synthesis_gate` | **exit 0** |
| `verify_weapon_forge` | **exit 0** |

### 一条未关闭的红（与本次改动无关）

`verify_formal_asset_placement_visual` → exit 1，卡在
「中央冷色主灯 在单灯基地契约下仍参与运行时照明」。

`zone_base.tscn` 与 `BaseFixtureGlow3D` / `BaseLampDynamics3D` 本轮**一个字都没改**
（`git status` 对这两个文件无输出），这条属灯具那条并发线。
它已经挡住了这轮要验的"武器改造台绑在 49_武器工作台资产包上"那一条 ——
我自己用探针单独验了 `asset_source`，结论是绑对了。

## 没做

- 怪物档案室没有"搬到别处"：它现在只有 catalog 条目与菜单场景，没有地面入口。
  要在别的位置装回来，贴一个 `facility_id = "monster_archive"` 的节点即可。
- 历史兼容基地 `BaseWorld3D.tscn` 没有加改造台 —— 那不是玩家实际进的 99F，
  不值得把新功能摊进去。
- 改造台在基地里**没有**做"耗材提示"（比如门口显示"背包里有 3 个碎片可合成"）。
  现在的 summary 是固定文案。
