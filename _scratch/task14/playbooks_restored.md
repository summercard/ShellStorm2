# ShellStorm2 详细操作手册（MEMORY.md 的展开版）

> 本文件是 `MEMORY.md` 的存档展开版，保留全部原始细节。MEMORY.md 只留索引与高频判据；
> 需要「为什么」「怎么做」的完整步骤时读本文件。

## 环境与运维坑（都踩过）
- 项目根 `I:\工作项目\shellstrom2\ShellStorm2\`（比常用简写多一层）。Godot 控制台版 `I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe`，**只认 Windows 路径**（MSYS `/i/…` 报 Invalid project path）。
- Bash shim 丢 PATH → 每条命令前置 `export PATH="/c/Users/zhuangmenghong/.workbuddy/binaries/PortableGit/versions/1.2.0/bin:/usr/bin:/bin:$PATH"`。
- python 用 venv `C:/Users/zhuangmenghong/.workbuddy/binaries/python/envs/default/Scripts/python.exe`（已装 openpyxl）。**跑前 `cd /tmp`**：父目录 `I:\工作项目\shellstrom2\inspect.py` 遮蔽标准库 `inspect`（表现为 openpyxl 报 `ModuleNotFoundError: bpy`）。
- PowerShell 重定向默认 UTF-16 / 控制台 GBK → 中文乱码；用 `$env:PYTHONIOENCODING="utf-8"` + `| Out-File -Encoding utf8` 再 Read。
- **`git push` 挂死、长时间无任何输出** = PortableGit 的 `helper-selector` 在等凭据（不是「在传输」）。改用 `git -c credential.helper="C:/Program Files/Git/mingw64/bin/git-credential-manager.exe" push`（GitHub 凭据在 Windows 凭据管理器里）。

## 资产路径命名契约（2026-09-17 去版本化后唯一口径）
- 运行资产路径**恒定、不含版本号**：`components/<套件>/<slug>/<slug>_visual_top3d.glb`、`runtime/<套件>/<slug>/<slug>_root_top3d.tscn`（目录名也不含 `vNNN`）。**替换 = 覆盖同路径同名文件**；`.import`/`.uid` 留原位。
- `v###` 只允许出现在：`source/`、`assets/art/asset_manifest_v001.json`、台账 O 列、Prefab 根 `metadata/asset_version`。
- 唯一实现处 `tools/asset_pipeline/godot_runtime_naming.py`；生成器必须 import 它，禁止自拼版本号、不许再产 `*.bak_*`。`LEGACY_VERSIONED = _v\d{3}(?=\.)`（旧写法 `\.[A-Za-z0-9]+$` 会被 `.glb.import` 绕过）。
- 门禁 `scripts/check_asset_runtime_naming.py`：新增违规 exit 1、快照陈旧 exit 2；**每清一批必须 `--update-debt` 缩表**（快照 `scripts/asset_runtime_naming_debt.json`）。批量工具 `deversion_batch.py <批> --plan|--apply-renames|--apply-deletes|--fix-scene-refs`。
- 计划/批次表 `docs/v0.1/development/2026-09-17_godot_asset_deversioning_plan.md`（B1 = `tower_zones/battle` ✅、B2 = 五根 + 2 zone 场景 ✅ 均已完成；**B3 = `environments/base_facility_3d`** 已完成预备调研、**未开工**，443 文件最大。**B1→B2→B3→B6 共用 `DungeonRoom3D.gd`，必须串行**）。
- **出清单工具** `_scratch/scan_batch_debt.py <套件根>`（2026-09-17 新增，参数化，**B4–B9 直接复用**）：打印该套件的门禁欠账构成（`.glb`+`.glb.import`+`.tscn`）/ 版本目录 / `source/` 豁免侧 / 备份残留 / 同名收敛（A 类同目录多版本 / B 类跨目录两代并存）/ 引用分布（src·tests·tools·scripts）。
- 导入 skill 有 **4 份副本**（`skills_drafts/`、`ShellStorm2/.codex/skills/`、`~/.workbuddy/skills/`、`~/.codex/skills/`）——改一份同步四份。
- **`preload` 是编译期解析**：引用不存在的 `res://` 会让整个 `.gd` 解析失败（不是丢单个资产）→ 重命名与改引用必须同一批内完成。

### B1 完成记录（2026-09-17）
- 提交 `704eb7d`（B1: tower_zones/battle 运行资产去版本化，167 文件 +657/−3508）+ `6427017`（chore: 修 `.import` 行尾幻影脏 + 补齐忽略规则，42 文件）。
- 实际改动分布：`assets/art/environments/tower_zones/battle/**` 重命名（common_components 的 door_5m / floor_tile_5m / wall_door_5m / wall_standard_5m 及其 runtime 镜像；entry_safe_room 的 v006/v007 模块去掉目录版本号）+ `tests/verification` 15 处 + `scripts` 3 处 + `tools/asset_pipeline` 2 处。
- 退役 4 个 v003 时代 verifier（`verify_common_floor_tile_components` / `verify_common_wall_door_components` 及 `_visual` 变体，共 12 文件），已从 `run_verification_suite.sh` core/renderer 名单删除。
- 代码引用更新：`src/world3d/DungeonRoom3D.gd` 5 处 `preload` 去版本化 + 1 处动态路径改 `entry_safe_room/%s/%s_root_top3d.tscn`；`SAFE_ROOM_ART_VERSION` 常量保留（仍写 Prefab `metadata/asset_version`）。
- 台账 B1 补丁：r86/r87/r92–r96 的 C(Prefab)/D(GLB) 去版本化，O(版本) 列保留（XLSX sha256 前后不变）。
- 收尾统计：命名欠账缩表 1345→1216 文件、22→13 目录、14→1 备份、112→107 gd 引用、702→675 tscn；台账门禁 38 条（基线）；文档契约 issues []。

### B2 完成记录（2026-09-17，提交 `7d41a29`）
- 范围：`props/dungeon_3d` + `environments/dungeon_3d` + `environments/base_world_3d` + `environments/tower_descent_3d` + `props/base_world_3d` 五根，**外加 B1 残留的** `tower_zones/base/runtime/zone_base_v002.tscn`、`tower_zones/rooftop/runtime/zone_rooftop_v021.tscn`。
- 提交构成：**187 条目 = 96 R / 64 D / 23 M / 4 A**。改名 96 = GLB 15（`R100` 逐字节）+ `.glb.import` 15（Godot 重生成，`R077…R098`）+ tscn 66（46 `R100` + 20 仅内部 `ext_resource`/`metadata/source_glb`）。删除 64 = 冗余 GLB 31 + `.glb.import` 31 + 退役探针 `probe_tower_module_art.gd` 与其 `.uid`。
- 改引用 18 个非资产文件：`src/**/*.gd` 6（`DungeonRoom3D` 36 处、`Dungeon3D` 5、`TowerDescent3D` 5、`TowerFloorStage3D` 4、`TrainingRange3D`、`TrainingRangeEnvironment3D`）、`scenes/*.tscn` 2、`tests/verification/*.gd` 6、`tools/asset_pipeline/validate_base99_corner_wrapper.gd` 1、资产侧参照方 3。
- **越界改动是正常的**：`fix_code_refs` 的判定是「旧带版本路径已消失 + 稳定路径存在」，所以 `environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v001.tscn`（**B3 的资产**）会因内部指向 B2 的 `ext_resource` 被改，而它**自己的文件名/版本不动**；同理 B1 残留的 `tower_zones/battle/source/.../probe_floor_tile_components.gd`（仍写着 `_v003` 地砖）被 B2 顺手补齐。
- 台账补丁 16 格（`3D-场景通用` r5/r7/r8/r42–r46/r48/r61 的 C/D）；O 列与 AssetID 逐字节不变。
- 缩表：1216→**1058** 文件 / 13 目录 / 1 备份；gd 107→**50**、tscn 675→**635**；五类整类清零。
- 验收：`verify_formal_3d_asset_import` `[PASS]`、`verify_formal_3d_asset_gallery_visual` `FORMAL_3D_ASSET_GALLERY_VISUAL_OK`（后者非 headless 渲染）；`aggregate core` 68 场景 16 红**全部落回 09-12 审计基线**（见「验证套件」条）；台账门禁 38（基线）、文档契约 `issues: []`、命名门禁 exit 0。
- 退役探针的判据（可复用）：`probe_tower_module_art.gd` 是**版本比较**探针（列出各候选版本、判断哪一版符合运行时契约）；稳定路径化后「没有候选版本」→ 存在前提消失。**断言活契约**的 `verify_tower_module_prefabs.gd` / `probe_tower_palette_visible.gd` 必须保留。
- 纯度复核脚本写法（**必须按块**）：`git diff --cached -U0 -M -- '*.gd' '*.tscn'` 后**按 `diff --git` 分块**，只统计块内**同时**出现 `--- a/` 与 `+++ b/` 的对，再比较「两侧剥掉 `_vNNN` 后逐行相同」。⚠️ 若按「最后一个 `+++ b/`」归属改动行，**纯删除的二进制文件（glb，无 `---`/`+++`）会把 `-` 行算到上一个文件**，误报出「105 删 2 增」这种假异常。

### B3 预备调研（2026-09-17，**未开工**，提交 `75a376b4`）
用 `_scratch/scan_batch_debt.py assets/art/environments/base_facility_3d` 实测（数据已入计划文档「B3 预备」节）：
- **欠账 443** = 152 `.glb`（各带 1 个 `.glb.import`）+ 139 `.tscn`，与批次表一致；**版本目录 0 个**（无 `vNNN/` 目录层，比 B1/B2 少一条 collapse 规则）；`components/**` 另有 3 个 `.json`（不计门禁）。
- **引用面 67 条 / 35 文件**——批次表写的「8 处」只是 `src/**/*.gd` 硬引用数：**src 8**（`DungeonRoom3D.gd` 6 + `TowerDescent3D.gd:12` + `TowerFloorStage3D.gd:40`）/ tests 26（16 文件）/ tools 25（12 文件）/ scripts 8（4 文件）。**同批要改的引用方是 35 个文件，不是 8 个。**
- **两种目录布局混存**：两级 `components/<slug>/…`（同 B1/B2）+ 三级 `components/env_base99_{remaining_facilities,wall_contents,structural}_v021/<slug>/…`（中间批次分组目录自身带 `_vNNN`，rules 要一并去版本）。
- **同名收敛**：A 类（同目录多版本）80 组正常；**B 类 1 组**（跨目录两代并存，归一后互相覆盖）＝ `runtime/env_base99_floor_visuals_v0{17,20,21}/…_root_top3d_v00{1,2,3,4}.tscn` → 都会落 `…/env_base99_floor_visuals/env_base99_floor_visuals_root_top3d.tscn`，**须先查引用方（`verify_base99_floor_visuals_v021.gd` 等）定留哪代**。
- **开批第一步**：`deversion_batch.py` 的 `BATCHES` 只有 `b1`/`b2`，`--plan b3` 会报 `invalid choice` → 先加 `b3` 定义（含 root + 两级/三级 rules + B 类冲突策略）。
- ⚠️ `DungeonRoom3D.gd` 是 B2 与 B6 共用引用方，B3 会再改它 6 处 → 开批前确认该文件无未提交改动。
- 备份残留 3 个 `source/**/previews/*.png.import<digits>.tmp` 在豁免区，留 B9。

## 角色 / 武器资产布局（先看这里，别按「高版本号」直觉删）
- 角色：`assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/vNNN/{source/model|animation/*.blend, exports/*.glb, runtime/*.tscn}`，**最新 v021**。早期单文件散落在 `chr_player_capsule01_3d/source/`、`variants/bunny01/source/`（v006–v008）、`chr_player_avatar_template_3d/source/`、`accessories/head/chibi_anime_head_v001/source/`。
- 枪械：`assets/art/weapons/weapon_3d/{source,runtime,components}/<slug>/`，**18 把 × v001–v003 blend**；**在用的是 v003**（runtime tscn 引 `components/<slug>/..._visual_top3d_v003.glb`）。挂点契约：根 origin = 握把、`forward_axis="-Z"`，Marker3D 含 Grip / SupportHand / Muzzle / MuzzleAttachment / Scope / Magazine / Stock / Tactical / Mutator / GroundPivot / IconPivot。
- **近战 3 把（baseball_bat / greatblade / waraxe）无美术源**：`melee_3d/*.tscn` 只挂 `src/combat3d/MeleeWeaponVisual3D.gd` + `weapon_style` → 纯程序生成。
- **武器总入口（「大集合」）= `assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn`**：本体仅 202 字节空壳（Node3D + `src/combat3d/WeaponModel3D.gd`），真正的武器目录是该脚本里的 `GUN_VISUAL_SCENES`(7) + `MELEE_VISUAL_SCENES`(3)。引用方：`Player3D.gd:927,1483`(load)、`TrainingRack3D.gd:81`(load)、`ItemModelFactory3D.gd:5`(preload)、`tests/verification/verify_player3d_weapon_grip_visual.gd`(preload)。**18 把枪里只有 7 把进了这个集合**（余 11 把在 `src/` 内零引用）。文件名里的 `_v001` 是「唯一版本」，必须保留。
- 敌人 `assets/art/enemies/`；Boss 源 `source/art/blender/bosses_v01/`。
- ⚠️ 武器 `components/**` 仍带 `_v003`（去版本化 B5 未做）；另有 2 个 `.tmp` 残留名字含 `v002/v003` → **绝不能用「名字含 vNNN 就删」清理**。
- ⚠️ **删角色旧版前必须先解两处引用**：① `src/ui/wardrobe/WardrobeMenu3D.gd:13` 用 **preload**（编译期）引 `variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v008.tscn`，该 tscn 又牵出 `components/*_v007.glb`×6 + `chibi_anime_head_v002` + `chr_player_capsule01_root_top3d_v001.tscn`；② `src/player3d/CharacterMotionLibrary3D.gd` 的**回退版本号是 v009**（`LIBRARY_PATH.replace("v009", _version)`，版本来自运行时 meta `assembly_version`）→ 典型「动态拼接」，引用扫描必须按**字符串模板**查。台账 `资产主表` / `原型角色` 登记的也是 v006/v007/v008 这批。
- 删任意版本化资产后必须 `check_asset_runtime_naming.py --update-debt`（否则 exit 2）并同步台账；**别绕过 `deversion_batch.py` 手工删**。删除只回收工作区磁盘、不缩小 `.git`。

## ⭐ 仓库外的上游美术源（Blender）——`C:\Users\zhuangmenghong\Documents\图片制作\`
**18 把枪的「大集合」blend 不在仓库里**，在这个外部目录：
- **`新建文件夹/中文游戏资产成品/风格统一重制V3/01_正式版本_待验收/06_卡通枪械库_风格统一源文件_v003.blend`**（5.4M）＝**18 把枪同一个文件**，对象名形如 `NN_<中文枪名>_主体_<材质>`；488 个输出网格 / 221374 面 / 4 材质（`01_精工金属_紫色骨架`、`02_细腻哑光_青绿大面`、`03_清漆反光_紫粉点缀`、`04_柔和自发光_UI灯光`）。
- 同目录 `00_六类游戏资产_风格统一总合集_v004.blend`（8.0M）＝**总合集**：5 设施 + 18 枪 + 维修圆凳 + 指挥椅；验收说明 `00_正式版本验收说明.md`。
- 历史版本在同级 `99_历史版本_归档/`（含 `06_卡通枪械库…_v002.blend`、`…_v003_面岛转换前备份_112637071.blend1`）。
- **生成器脚本在 `Documents/图片制作/` 顶层**：`build_cartoon_weapons.py`（31K，**18 个 `weapon_*()` 函数**，`bpy.ops.wm.save_as_mainfile` 一次输出一个集合 blend）。同类：`build_cyber_locker_station.py` / `build_cyber_repair_workbench.py` / `build_retro_gaming_tv_station.py` / `build_tactical_command_desk.py` / `build_cat_supply_terminal.py` / `build_cyberpunk_loft.py`。**改武器外观应改脚本重跑，而不是手改仓库内单枪 blend。**
- ⚠️ **该目录的 git 是空仓库**：`Documents/图片制作/.git` 存在但 `master` **零提交**、91 项未跟踪 → **上游源文件无版本控制保护**。
- 中英对照（编号 = 大集合里的对象前缀）：01 水箱爆能枪=water_tank_blaster、02 扩音器加农炮=megaphone_cannon、03 吉他爆能枪=guitar_blaster、04 锅铲步枪=spatula_rifle、05 平底锅加农炮=frying_pan_cannon、06 烤面包机发射器=toaster_launcher、07 瞄准镜加农炮=scope_cannon、08 爆米花爆能枪=popcorn_blaster、09 口香糖机加农炮=gumball_cannon、10 双管炮=double_barrel_cannon、11 饮料管爆能枪=soda_straw_blaster、12 鳄鱼加农炮=crocodile_cannon、13 糖果狙击枪=candy_sniper、14 相机爆能枪=camera_blaster、15 纸巾盒加农炮=tissue_box_cannon、16 扫帚步枪=broom_rifle、17 风扇爆能枪=fan_blaster、18 吹风机=hair_dryer。
- 上游色盘报告 `ShellStorm2/.codex/reports/palette_uv_repair/guns_face_islands_v003.json` 记录该 blend 路径，**`passed: false`**——失败项全在自发光：`emissive_not_mixed_with_body` / `emissive_objects_clearly_named` / `emissive_has_one_material`，问题对象 `Accessory rail.010`~`.017`（附件导轨英文名 + 数字后缀、自发光与主体混用）。

## 正式美术接入（Prefab 替换 GLB）——不做这两件就「换了看不见」
1. Prefab 根须声明 `metadata/preserve_authored_palette = true`；引擎（`DungeonRoom3D`/`TowerFloorStage3D`）读到后必须**跳过**主题材质覆盖，否则非 FACILITY 房的墙/地砖 MultiMesh 被套单色材质、盖掉 PaletteUV。
2. `_find_first_mesh(prefab)` 取「首个非空 MeshInstance3D.mesh」，走 MultiMesh 的模块只抽到一个 Mesh；若 GLB 首个网格是附属件（如带门墙的静态门扇），instantiate 时须显式 `visible=false`，交互件交运行时。
- Prefab 一律 `visual_only`，碰撞交回引擎（`TowerWallCollision_*_Run`/`OuterBoundaryCollision_*` 0.30m 代理、地砖 `FloorSupport`）。
- 原点契约：tower_descent/base99 墙与地砖 GLB 均**底面中心原点**（地砖板厚居中），运行时按 `-mesh.get_aabb().position.y` 反算 Y 贴楼面 → 换 GLB 无需烘焙位移。
- 实墙/女儿墙 GLB **单表面**（PaletteUV 在单材质 UV 内取色），只有地砖双表面；别要求墙「多表面」。
- 探针：`assets/art/props/dungeon_3d/qa/probe_tower_palette_visible.gd`（→`TOWER_PALETTE_VISIBLE_OK`）、`qa/verify_tower_module_prefabs.gd`（→`PREFAB_PROBE_OK`）。

## 「运行时看到但认不出」怎么定位
- **颜色不能读 `albedo_color`**：GLB 走 **PaletteUV**，albedo 恒白（0.9063/1.0），颜色由顶点 UV 指向 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png` 的格子。按颜色找资产必须**按 UV 反查色盘**，否则整类被判无色（曾白跑两轮）。
- **一刀区分美术 vs 代码生成**：读 `albedo_color`/`emission` 原始值——美术资产恒白会被筛掉，剩下的偏色命中一定是脚本 `new StandardMaterial3D` 出来的。
- **最快锁定 = 正交俯视截图 + 逐个 `visible=false` 对比**（比读 AABB 快）。`Camera3D`+`PROJECTION_ORTHOGONAL`+`size≈26`，房间中心 +11.6m 往下看；`await RenderingServer.frame_post_draw` ×2 后 `save_png(绝对路径)`。**必须非 headless**。
- 现成工具 `tests/verification/probe_safe_room_visual_inventory.gd|.tscn`：列指定层 STAIR_LOBBY 跨度 ≥2m 可视件（世界 AABB/房间局部坐标/顶面高/UV 采样真实色），改 `TARGET_FLOOR` 换层。
- **树遍历探针的坑**：门墙（`Imported_DoorWall5M_*`）/门扇是普通 Node3D 子树，**不走 MultiMesh**；判定写在 `MultiMeshInstance3D` 的 `continue` 之后会被整批跳过、误报「未接入」。门墙模块需房间 `set_stream_state(1)` 后才实例化。

## 安全房（STAIR_LOBBY）——查可视异常先分两层
- **壳体层** `_build_safe_room_shell()`（SHELL_READY）：墙 10 / 门墙 2 / 门扇 2 / 地砖 9 / **房间包 17（v007 美术）** / camera-only 门墙代理 —— **全是美术资产**。
- **细节层** `_build_content()`（ACTIVE）：**代码生成** —— `RoomCeilingLight`、`RoomLightSwitch3D`、`RuntimeNavigationRegion3D`；`prop_count=0`。两批程序地面标线 2026-09-17 已移除（`StairLobbyRouteGuide`、`StairLobbyThresholdGuide_A/B`，`_build_stair_lobby_markings()` 与调用点整体删除）。守卫 `probe_stair_lobby_markings_removed.gd|.tscn`（→`MARKINGS_REMOVED_OK`，**必须 `set_stream_state(2)`**，否则 `_build_content()` 不跑会误判已移除）。
- **教训**：曾连续两轮把「地上那个奇怪的东西」答成美术件（`overhead_services`/`LockStripe`），实际是 `_build_content()` 的代码生成件。**先分两层再找。** 完整清单 `docs/v0.1/development/2026-09-17_安全房运行时内容清单.md`。
- 坐标：层高 12，100F y=0 / 99F −12 / 98F −24 / 97F −36；98F 入口 `floor_01_entry @ (27.5, −24.0, 2.5)`。门扇在 ±7.5 网格线（v007 门洞切向偏移 0）。房间包按各自 `metadata/room_placement_position` 摆位（y 减 `SAFE_ROOM_WALK_LIFT_M`）。
- 门上的青色发光横条曾是 `RoomDoor3D._build_procedural_panel` 的 `LockStripeFront/Back`，**已移除**；判据仍有效：门有程序门板 = 没给 `_panel_visual_scene`（未换美术门扇）。
- 碰撞：沿用 v004 组件 `collision_owner=self`，墙/门墙自带 0.30m 碰撞即阻挡，**不要再叠代理**；地砖/门扇自带碰撞按层关闭去重（楼板承重归 `TowerFloorStage3D._build_support()`，门扇通行归 `RoomDoor3D`）。南北向门留唯一 camera-only 门墙代理。
- 楼板可视洞：`TowerFloorStage3D` 为每个 STAIR_LOBBY 注入 `additional_visual_holes`（15×15m → 挖 3×3 地砖，**承重碰撞不变**）；记账 `_additional_visual_hole_tile_count`（与楼梯洞按点去重），`verify_tower_grid_component_alignment` 期望值须减它。
- 验收 `probe_safe_room_v007_integration`（→`SAFE_ROOM_V007_INTEGRATION_OK`）；`probe_stair_lobby_geometry` 是无断言只读 dump。

## 台账（已分册化，2026-09-18）
- ⚠️ **本节的 `sheet10.xml` / 行号坐标全部是「拆分前单体账本」的**。资产条目现在落在 `assets/registry/ledgers/ShellStorm2_*_v001.xlsx` 的《资产主表》，sheet 索引与行号都已平移；总目录只剩索引、不含资产行。唯一映射源 `assets/registry/ledger_index.json`（`scripts/ledger_registry.py` 解析），人读入口 `assets/registry/README.md`。
- **权威顺序**：`资产主表` M（版本）/O（文件路径）> `3D-场景通用` D/P（后者常登记旧版）。
- `3D-场景通用` 列义：A AssetID、B 中文名、C Prefab、D GLB、E Blender源、F 说明、G 脚本、H 碰撞开关、I 碰撞归属、J 碰撞方式、K 标准尺寸、L 原点与朝向、M 使用位置、N 制作状态、O 版本、P 备注。升版/改登记**就地改**不追加行；AssetID 全表唯一无版本后缀。
- **外科式 XML 补丁**：只改 `xl/worksheets/sheet10.xml`，其余 zip 条目原样复制（保 styles/sharedStrings/mergeCells/表格）。单元格形如 `<x:c r="C42" s="192" t="inlineStr">`；**大量单元格是 `s="393" t="str"` 且文本落 `<x:v>` 而非 `<t>`** —— 只找 `<t>` 会把整张 sheet 读成空（曾据此误判「空行」）。
- 工具 `_scratch/search_ledger.py <关键字>`、`dump_ledger_rows.py`、`patch_ledger_*.py`。
- **落盘用就地写**（`zipfile.ZipFile(LEDGER,"w")`），不要 `os.replace` —— 有进程持有 xlsx 且未开放 delete 共享，重命名会 `WinError 5`（实测连续 8 次失败）而 `r+b` 可开。
- 门禁 `check_asset_registry.py --scope structure [--workbook <xlsx>]`（**支持 `--workbook`**，冲突两侧对比靠它）。基线 **38 条**（invalid_status 6 + missing_dedupe 10 + stale_overview 22），只看**是否新增**。

## 台账 git 冲突（二进制 xlsx）恢复手册
- **症状**：登记升级整批消失（回旧版路径），且 `git hash-object <f>` == 某历史 `git rev-parse <sha>:<f>`。**根因**几乎总是 `pull --rebase`/merge 命中 xlsx 冲突后整份取一侧（查 `git reflog`：`pull --rebase … Fast-forward` 紧接一个 `commit`）。
- **判哪侧是真**：① 磁盘——两侧登记路径逐个 `os.path.exists`（最硬）；② 代码——grep 运行时是否真引用该版本；③ 门禁——两侧各跑 `--workbook`，问题数**少**的通常更新。
- **恢复＝重放补丁脚本**（`_scratch/patch_ledger_*.py`、`assets/.../v00N/qa/update_ledger_rows_*.py`，幂等 + AssetID 断言），按 r 行号从小到大重放；**远端新增行不动**。脚本 `BACKUP` 会覆盖 git 跟踪的既有 `.bak_*` → 重定向临时名或跑完 `git checkout -- 'assets/registry/*.bak_*'`。
- **复验四件套**：① zip 条目集合不变且除目标 sheet 外逐字节相同；② 目标 sheet 的 `dimension/rows/max_col/mergeCells/dataValidation` 不变；③ 逐格差异闭包 == 预期行集合（**别 `head` 截断**：工作表按名排序 `sheet1 < sheet10 < sheet2`，极易漏 `资产主表`）；④ 门禁问题数不增。
- 同名 skill：`xlsx-git-conflict-resolution`（用户级），完整流程以它为准。

## 验证套件
- 跑法：`export GODOT_BIN="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"`，然后 `bash scripts/run_verification_suite.sh {scene|smoke|core|aggregate|visual|full} [参数]`（aggregate 第二参可为 smoke/core/full）。
- **`visual_scenes`/`renderer_scenes` 名单里的场景不能 headless 直跑**（会挂住等 viewport 纹理），必须走套件（自动去 `--headless` + 看门狗）。
- `run_scene()` 判定链：先 headless 跑 `verify_scene_preflight.gd`（返回 2=装载失败、3=preflight 日志有意外错误），再跑场景本体（scene_result），最后用 `check_verification_log.py <log> <expected_errors>` 判日志（0 通过 / 3 意外引擎错误 / 4 leak）；`scene_result==0 && log_result!=0` 时返回 log_result。
- `check_verification_log.py` 把 `ERROR: N resources still in use at exit` 判为 leak 返回 **4**。白名单文件 `tests/verification/expected_errors/<scene>.txt`（现 3 个：`verify_base_shop_save_flow`、`verify_extraction_points_spend_transaction`、`verify_music_system`）。
- **BGM 泄漏已于 2026-09-17 修复**（详见 `docs/v0.1/development/2026-09-17_music_manager_headless_exit_leak.md`）。旧结论「补一个 `_exit_tree()` 就好」**不完整**，完整根因有三层：
  1. autoload 先于当前场景退出树：`BaseWorld3D._start_base_music_with_delay()` 用 `await get_tree().create_timer(0.1).timeout` 再 `play("base_passion")`，该协程若在 `MusicManager._exit_tree()` 之后恢复，会把 stream 重新挂回播放器。
  2. **`stop()` + `stream = null` 压不住 Ogg 回放对象**：补上 `_exit_tree()` 后 `verify_door_passability` 干净了，但 `verify_base_facility_framework` 仍 6 次里 2 次泄漏；插桩证明泄漏/干净两次的 `play()` 轨迹完全相同 → 泄漏来自 `AudioStreamPlaybackOggVorbis` 在 Ogg 解码收尾阶段无法确定性释放。反向验证（去掉运行期 Music 总线回收）仍 4/6 泄漏 → 与总线无关。
  3. 最终修法 = **headless 早退**：`_play_track()` 在 `DisplayServer.get_name() == "headless"` 时不 `load()`、不播放，只落 `_current_music_id` / `_current_track_path` 并发 `music_changed`。**这是本仓第一条「headless 不真播」约定**，先例在 `src/core/AudioManager.gd:72`。
  → 遗留影响：headless 下 `is_playing()` 恒 `false`，判「在放哪首」必须用 `get_current_music_id()`。真实运行（渲染场景）路径不变（已用 `verify_tower_descent_visual` 非 headless 复验 exit 0）。
- **套件只报 exit 4，不告诉你漏了什么**。要定位泄漏对象，危险做法是直接加 `--verbose` 单跑该场景：
  `"$GODOT_BIN" --headless --path <项目根> --verbose --scene res://tests/verification/<场景>.tscn`
  日志里会出现 `Resource still in use: <res://路径> (类型)`。⚠️ 但**别手搓这条命令**：`visual`/`renderer` 场景会挂死。正确做法是复制 `run_verification_suite.sh` 到临时脚本、只在两处场景分支加 `--verbose --scene`，走套件自身的隔离工作区跑。泄漏条数按曲目数增长（播 1 首 = 2：`AudioStreamOggVorbis` + `OggPacketSequence`；`verify_music_system` 播 3 首 = 6），**恒为偶数**。
- 套件已接入命名门禁与文档契约门禁（core/aggregate/full；命名门禁 exit1=新增违规、exit2=欠账快照陈旧）。
- ⭐ **core 套件的唯一基线**：`docs/v0.1/audits/2026-09-12_engineering_audit.md` §5 + `docs/v0.1/audits/evidence/core_results.json`（**61 项 / 11 项 exit1 / 1 项 exit143**）。
  **判据是「红项集合 ⊆ 基线」，不是「core 全绿」** —— 本仓 core 从来不是全绿，拿全绿当门禁会永远过不了。
  B2 复跑 `aggregate core` = 68 项 / 16 红，逐条落回：6 项断言类（`verify_3d_performance_budget` `HUD 267>171`+`HUD+预览 278>190`、`verify_graphics_settings_ui_flow` 缺 9 项效果控制、`verify_base_world_flow` 移动动画+locked 环、`verify_3d_melee_feedback_flow` slash/impact、`verify_3d_enemy_behavior_flow` 3D 飘字+VFX 回收、`verify_base_fixture_glow` assert 后 180s 超时 143）+ 10 项**纯泄漏**。
  泄漏侧还有一条**强判据**：若 10 个场景的泄漏签名**恒为同一句 `2 resources still in use at exit`**，则必是 autoload 级（资产引起的泄漏会随各场景加载的资产不同而变数值）。
  🆕 **2026-09-17 修掉 BGM 泄漏后复跑 = 68 项 / 6 红**，`ERROR: N resources still in use at exit` **0 条**（只剩 1 条非 ERROR 级的 `WARNING: ObjectDB instances leaked at exit`，日志门禁不判）→ 那 10 项纯泄漏全部消失，剩下的 6 红就是上列 6 项断言类，仍 ⊆ 基线。**修复后的期望值就是「6 红」；此后多出任何一条泄漏即回归。**（另有 6 项基线红已由其它会话/改动转绿：`base99_remaining_facilities_v021`、`base99_structural_asset_integration`、`base99_wall_content_v021`、`full_3d_game_flow`、`scene_facility_shared_palette`、`tower_lighting_wall_combat_regressions`。）
- **判「重命名有没有弄坏资产」的最快一招**：对全部 `*.scene.log` grep `Cannot open file|Failed loading resource|Failed to load|does not exist|No loader found` —— **=0 条即证 `preload`/`ext_resource` 全部可解析**。理由：`preload` 是**编译期**解析，漏改一条会让整个 `.gd` 解析失败（响亮报错），不会静默降级。B2 实测 68 个日志 0 条（`SCRIPT ERROR` 只有既有的 `verify_base_fixture_glow` 1 处）。
- ⚠️ **裸退出码会被本机 safe-delete 守卫污染**：套件 EXIT trap 里要 `rm -rf` 临时工作区，守卫拦下并返回非零 → 覆盖原退出码，表现为**打印 `VERIFICATION_SUITE_OK` 却 `EXIT=1`**（还会打 `SAFE_DELETE_BULK_CONFIRM_REQUIRED`）。**判定一律看 `VERIFICATION_SUITE_OK` / `FAILED_SCENE` 行，不看裸退出码。**
- 单跑**不在任何名单里**的场景（如 `verify_formal_3d_asset_import`）也走 `bash scripts/run_verification_suite.sh scene <名>`：它照样做 preflight + 判日志，且 `is_renderer_scene` 命中时会**自动切非 headless**（`verify_formal_3d_asset_gallery_visual` 即走此路，Vulkan/RTX 4060 Ti 渲染出图）。别手搓 Godot 命令行。

## 并发风险（未消除）
- **环境内常驻/瞬时起 Godot 进程**（编辑器/其他会话）：会持续重写 `*.import`、持有 xlsx（→ `WinError 5`）、随时触发重新导入。**动手前先取 `git status` + sha/mtime 快照。**
- **`_visual` 场景禁止直接 `--headless` 跑**：会永久挂住等 viewport 纹理（实例：`verify_wall_alignment_visual.tscn` 于 2026-09-17 07:49 挂到 13:50，空转烧 40 分钟 CPU，句柄 486）。**必须走 `run_verification_suite.sh`**。查挂死残留：`Get-CimInstance Win32_Process | Where Name -like '*Godot*'`；判活用 CPU 6 秒增量（<0.5s = 空转挂死）。**编辑器/游戏进程也可能是别的会话起的**，杀之前先看命令行。
- 另有会话/进程在同步改并提交：曾提交 P1/P2（`0678d33`/`a10ea90`）、改台账、改 `RoomDoor3D.gd`/`TowerDescent3D.gd`；B1 之后仍观察到**瞬时起 Godot 跑验证**的活动会话。
- **palette `.import` 的 `detect_3d/compress_to` 必须保持 0**（Disabled）：`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` 是全项目 PaletteUV 的取色盘，被 3D 压缩（=1 VRAM Compressed）会让**所有** GLB 取色失真。编辑器会把它自动改成 1（2026-09-17 13:36 实测 mtime 比当时时间戳还新），发现后 `git checkout --` 改回 0。

## git 行尾与「幻影 M」（2026-09-17 已治理）
- **判据**：`git status` 说 M 但 `git diff` 为空 —— 别急着归因行尾。依次查：① `git ls-files --debug -- <f>` 的 `size` vs 实际 `stat -c %s`；② `git ls-files --eol -- <f>`（`i/`=索引 blob 行尾，`w/`=工作区行尾）；③ `git hash-object -- <f>` vs `git ls-files -s -- <f>` 的哈希；④ `git status --porcelain=v2 -- <f>`。
- **根因（B1 实测）**：仓库 `core.autocrlf=true` 且**无 `.gitattributes`**。git 期望文本文件检出为 CRLF，而 Godot 生成 `.import` 一律写 LF → 索引里缓存的 **stat**（size=1314，CRLF 时代）与实际（size=1272，LF）永久不匹配。**索引 blob 其实一直是 LF**（`cmp` 逐字节验证过），所以 `git diff` 空、`git add` 零内容变化；连 `git update-index --refresh` 都拒绝清理（400 条 `needs update`，exit 1）。
- **修复（已落地）**：新增 `.gitattributes` = `*.import text eol=lf` + 对全部已跟踪 `.import` 跑一次 `git add -u`（只刷新 stat 缓存，blob 零变化）。效果 M 353→11、全库 status 513→173。
- ⚠️ **绝不给 `*.gd`/`*.tscn`/`*.md` 加 `eol=lf`**：它们当前是 `i/lf w/crlf` 且状态一致、无噪声；声明 `eol=lf` 会要求工作区改成 LF，造成数千文件的巨型差异。要治需先独立做全库 renormalize。
- **判「谁改的」先跑 `git diff --numstat`**，别信 `git status` 的行数。核提交后果用临时索引：`GIT_INDEX_FILE=<temp> git read-tree HEAD && git add -- <pathspec>`（真实索引不动）。注意 `GIT_INDEX_FILE` 要用 **Windows 路径**，MSYS 路径会 `Unable to create ...lock`。
- 2026-09-17 11:52–11:56 `assets/art/**` 整树被**文件系统层删除**（`git reflog` 该窗口无条目、`.git` 零写入 → 非 git 行为，起因未定；环境中 OneDrive 在运行）。恢复：`git checkout -- assets/art`；未跟踪的 `.import` 用 `godot --headless --import` 重建。
- `.gitignore` 已于 2026-09-17 补齐：`__pycache__/`、`*.pyc`、`*.bak_*`、`*.import[0-9]*.tmp`、`_scratch/b2_baseline/`；并从索引移除 39 个误提交的 `.pyc`（磁盘保留）。`*.import` 白名单仍未覆盖全部资产目录（characters/weapons 等 134 个 `.import` 从未被跟踪）。
- `assets/art/weapons/**` 有 2 个 `*.png.import<digits>.tmp`（Godot 中断的导入写盘残留，名字含版本号），现已匹配忽略规则；**编辑器在跑时不要删**，留到武器批处理。
- ⚠️ **`git status` 在本仓会漏报索引/工作区差异（B2 实测，危险）**：暂存 186 项、`git diff --name-only` 列出 **16** 处真实差异，而 `git status --porcelain` 只报了 **1** 处。漏掉的是 `godot --import` 重建后的 15 个 `.glb.import` —— **索引里存的仍是重建前的内容**（`source_file=` 指向已被删除的旧版 GLB）。若按 status 判「已干净」直接提交，仓库里会留下指向不存在目标的 `.import`，Godot 加载即失败。**→ 暂存完整性一律用 `git diff --name-only` 判定；`git status` 只当参考。**
- **提交前护栏**：`_scratch/validate_b2_index.py`（B3 起应做成通用脚本）—— 用 **`git cat-file --batch` 批量读索引 blob**（不是工作区）校验 ① 每个 `.import` 的 `source_file=` 可解析；② 每个 `.tscn`/`.gd` 的 `res://assets/**` 引用可解析；③ 本批各根下无带版本运行资产。**专治上一条**（B2 实测：334 个 `.import` / 781 个 tscn+gd / 971 处引用全通过）。
  - 性能坑：逐文件 `git cat-file -p` 在 2500+ 文件上会跑到超时被 SIGTERM；**必须单次 `--batch`**（实测 7 秒）。
- `deversion_batch.py <已应用的批> --plan` 现在会打印「**本批已应用（正常终态）**」并 exit 0（新增 `batch_applied()`）。此前误报「superseded 声明要删的废弃版不存在」，读起来像数据损坏，**会诱导你去「恢复」一个故意删掉的文件**。
- ⚠️ **资产侧 `.gd` 不在命名门禁的引用扫描口径内**：`check_asset_runtime_naming.py` 只数 `src/**/*.gd` 与 tscn 里的带版本引用，`assets/art/**/*.gd`（各套件 `source/**/qa/*.py|gd`、探针）**不数**。后果：B1 期间 `tower_zones/battle/source/common_components/v003/qa/probe_floor_tile_components.gd` 残留的 `_v003` 地砖引用漏改，直到 B2 才被 `fix_code_refs` 顺手补齐。后续若要自动发现，需把口径扩到 `assets/art/**/*.gd`（会改欠账数，需独立一批）。**⛔ 用户 2026-09-17 明确指示：此项「先不动」（本轮只修 BGM 泄漏），不要顺手扩口径。**



## B4 执行记录 / 复盘（2026-09-17，`environments/rooftop_shelter_3d`）

**形状**：`runtime/` **扁平布局**（不是 `components/` + `runtime/` 三件套），多代同名并存 ——
`50m_game` v003–v011、`90x80m_game` v012–v016、`90x80m_root_top3d.tscn` v012–v016、
`facilities` v017/v019/v021、`facilities_root_top3d.tscn` v017/v019 +
**`layout_v016/` 与 `layout_v017/` 两套并行 69 件组件目录**。311 欠账 / 0 `.gd` 耦合。

**工具扩展**：原 `collapse`/`keep_version`/`superseded` 表达不了「整代退役、一份不留」→ 新增第 4 种模式
**`obsolete_globs`**；并让 `--apply-renames` **跳过未跟踪旁文件**（否则会把构建产物误当改名源）。

**两处裁决**：① 死岛随批删除（`layout_v016/**` 138 + `90x80m_game` 10 + `root_top3d` 5）；
② 规范名归**当前在用代**、旧代加 `_genNNN` → `..._facilities.glb`←v021（真运行时 `zone_rooftop.tscn:3`）、
`..._facilities_gen017.glb`←v017、`..._facilities_gen019.glb`←v019；场景 `..._facilities_root_top3d.tscn`←v017（契约代）、
`..._root_top3d_gen019.tscn`←v019。`runtime/layout_v017/` → `runtime/layout/`。

**⚠️ 口径自我纠正：50m 不是死岛**。初判整代删 v003–v011；收尾核账发现 `资产主表!O300` 是 50m 场景在权威台账里的
**唯一运行文件登记**（M300=v011、K300=已完成、P1）→ 按「绝不静默破坏被引用资产」从 HEAD 原样恢复 v011 并改名
`env_rooftop_shelter_50m_game.glb`（sha 逐字节相同），只删 v003–v010。源 `.blend` 29 MB 与 `reports/asset_manifest_v011.json` 始终在。

**数据**：改名 145（73 `.glb` 全 R100 + 70 `.glb.import` 重生成 + 2 `.tscn` R091/R099 含内部 `ext_resource` 改写）/
删除 158 / 外部引用 **3 文件 4 处**（`zone_rooftop.tscn`1 + `verify_rooftop_shelter_asset_contract.gd`2 + `export_godot_rooftop_reference.gd`1）/
套件内引用 69 处（v017 场景 68 + v019 场景 1）/ `.gitignore` 9 行→3 行 / 台账 **2 格**（`3D-场景通用!D61`、`资产主表!O300`）/ 缩表 **601→290**、tscn 引用 236→93。

**验收**：`aggregate core` `count=68 / failed=6`（与 B3/B6 同一组，⊆ 基线）；加载失败类 0；
两个 rooftop 契约场景在**最终状态**单跑 PASS；`_scratch/b4_index_imports.py` 断言 B4 根 70 个暂存 `.import` 索引==工作树且 `source_file=` 存在；
`index_refs_scan.py` → `BATCH_DANGLING=0`；三道门禁全绿。

**坑 1：调色板陷阱在 `--import` 时被触发**。编辑器把 `设施低亮多巴胺色盘_10x10_512.png.import` 的
`detect_3d/compress_to` 由 0 改成 1（会让所有 GLB 取色失真）。`git checkout --` 还原，sha1 与基线 `23d13998…` 一致。
**结论：`--import` 后必查该项，不要只看 ERROR 数（当时 ERROR=52，与本项无关）。**

**坑 2：49 个文件「无记录消失」**。`--apply-renames` 与 `--apply-deletes` 之间工作区丢了一批（22 个 `layout_v016` 组件 + 27 个死岛），
`stage_roots()` 的 `git add -A` 把「工作区缺失」顺带暂存成删除 → 删除日志只报 116（实际 158）。
三视图（HEAD / 索引 / 磁盘）逐字节核对：**内容级无损** —— `layout/` 与 HEAD `layout_v017` 136 文件逐字节一致（缺 0 / 多 0 / 不符 0）。
且 `git diff --cached -M` 把 33 对内容相同组件的改名源归给字典序在前的 v016 **只是展示假象**：
修改前的 `b4_plan.txt` 证明 `collect()` 取的源 **100% 是 v017**（`group.sort(key=version_of, reverse=True)` 留最高版）。
**结论：跨步骤执行器不能把「工作区缺失」等同于「本步骤删除」；判「工具取错了源」要看 `--plan` 输出而不是 `git -M`。**

**`.import` 跟踪口径（B4 复核准）**：B4 根 143 个 `.import` = 70 跟踪 + 73 忽略；
白名单只有 3 条（`facilities_gen017` / `facilities` / `layout/**`），其余（`gen019`、`50m`、`references`）为未跟踪构建产物，**这是既有约定不是遗漏**。

**遗留（按约定保留，非遗漏）**：`tools/asset_pipeline/repair_rooftop_v017_coordinate_contract.py`（→ 旧 `..._root_top3d_v017.tscn`）
与 `build_rooftop_v021_wrapper.py`（→ 旧 `..._root_top3d_v019.tscn` + `..._facilities_v019.glb`）属 `.py` 一次性构建/修复脚本，
`fix_code_refs` 刻意排除 `.py` 与 `docs/`（同 B3/B6 先例），路径属**历史记录**；若要重跑须先更新路径。

**查文件的三个小坑（B4 都遇到）**：
1. 中文路径会让 `git ls-files` 输出**八进制转义** → Python 里按路径做集合比对会「找不到」，先 `core.quotepath=false` 或按 bytes 比。
2. `git ls-files --others --ignored` 与 `rglob` 的口径不同，判「未归类」前先把 tracked / ignored / untracked 三类分别取全。
3. `git cat-file --batch` **不接受 `:path`**；且 `--batch` 的 size 是**字节数不是行数**，按行 join 会错位 → 更稳的替代是
   「索引 SHA vs `git hash-object <path>`」直比（`.import` 已钉 `eol=lf`，工作树即 LF，可比）。

## 远征关卡01（2026-09-19 落地）
- **入口链**：99F 基地中央远征情报室(`mission_operations`, menu) → `RogueMapSelectMenu` → 读取界面 `ExpeditionLoadingScreen` → `ExpeditionLevel01_3D.tscn`。旧墙边终端不得复活。
- **形态**：固定单层 7 房 = `start`(15×15, v007 安全房壳体) + `room_01..05`(各 25×25) + `extraction`(25×25)。格步 35m、网格原点 2.5m；房型池 `[COMBAT,COMBAT,SCAVENGE,STORAGE,EVENT]` 洗牌；排列 = 4 旋转 + 可选 Z 镜像（`run_seed ^ 0x45585031`）。无终点 Boss，撤离信标 `STANDARD`（非锁定），不用 `BOSS_KILL`。
- **区块**：第五个根 `Blocks/Expedition`（`block_id=expedition`，显示名「远征关卡01」，设定名「远征前哨站」）。塔楼主场景仍只有 Rooftop/Base/Battle/Stairs。`_room_block_for_floor()`/`_block_id_for_floor()` 与房间 `block_id` 元数据统一路由。
- **两套房表并存**：远征走 `FloorPlanGenerator.generate_expedition()`/`validate_expedition()`，**不要**挤进塔楼 `generate()`/`validate()` —— 后者硬拒内容房 `maxf<30 || minf<25`，25×25 会被拒。
- **存档**：`runtime_map_id="expedition_01"`；`_runtime_scope_for_save()` 对 `is_expedition()` 直接返回 `combat`（入口安全房 `floor_index=0` 否则会被判 `base`，导致进图快照不可续局）。
- **禁用**：不得对远征复用 `_reset_initial_loop_world_after_retreat()`（会销毁 `start` 安全房并重建塔楼 `floor_01_entry` 空壳）。撤离/死亡/安全房弃局统一走 `Dungeon3D._finish_run()` → `return_scene_path`(BaseWorld3D)。
- **门禁**：`verify_expedition_level01_flow`（`EXPEDITION_LEVEL01_FLOW_OK`，已注册 core）。数可搜索容器前必须先 `room.ensure_detail_built()`（家具懒构建）。诊断探针 `probe_expedition_walls`。
- **既有红项**：`verify_base_world_flow` 基线即失败（563 节点超阈值 + Player3D 动画状态断言），与远征关卡无关。

## 楼面轮廓铁律：`force_standard_map`（2026-09-19 修复「新关卡没有房间阻挡」）
- **症状**：远征 7 房里只有 `room_01`/`room_02` 有楼面与墙，`start`/`room_03..05`/`extraction` 脚下为空，玩家踩空下坠（y=-0.857）。
- **根因**：`src/world3d/TowerFloorStage3D.gd` 以 `floor_index == 0` 判 100F 天台，返回 `ROOFTOP_WORLD_RECT=Rect2(-50,-35,90,80)`（18×16 格）+ 99F 中庭贯通洞 + `ROOFTOP_PARAPET_HEIGHT=0.75` 女儿墙。远征是单层、`floor_index` 也是 0，整层照抄了天台窄轮廓 → 6/7 房无承重楼面与外圈墙。
- **修复**：`TowerFloorStage3D` 新增 `force_standard_map`（`configure()` 第 5 参 `use_standard_map`）；所有天台分支改走 `_uses_rooftop_profile() = floor_index == 0 and not force_standard_map`；`TowerDescent3D._rebuild_floor_stage()` 传 `is_expedition()`。命中函数：`_floor_grid_dimensions/_floor_map_dimensions/_floor_world_rect/_outer_grid_dimensions/_outer_map_dimensions/_outer_world_rect/_outer_wall_height/_outer_visual_transform/_hole_rects/get_snapshot`。修复后网格 50×50、`Rect2(-125,-125,250,250)`、墙高 12m、无中庭洞；7 房全部落地落墙，玩家 y=0.03。
- **走廊澄清**：`Corridor_*` 可见性与碰撞由 `_update_corridor_streaming(current_id)` 按 `_open_edges[edge] and current_id in edge` 开关；门未开时 `visible=false` + 碰撞休眠是**既有契约，不是缺陷**（本次未改走廊代码）。
- **门禁**：`verify_expedition_level01_flow` 增 `_verify_level_enclosure()`（断言 stage `force_standard_map==true` / 网格 `(50,50)` / `floor_world_rect==Rect2(-125,-125,250,250)` / `support_rect_count>=1` / `base_99_100_atrium_enabled==false` / `outer_wall_height==12` / stage `block_id==expedition`；并逐房下射命中楼面、四向射线命中墙；走廊开门后 `visible==true` 且两侧 3.5m 射线命中墙）。回归全绿：`ROOFTOP_WEST_EXPANSION_CONTRACT_PASS` / `TOWER_FLOOR_ROOM_AUTHORITY_OK` / `TOWER_RUNTIME_RESTART_OK` / `CENTRAL_EXPEDITION_HOLOGRAM_FACILITY_OK`。文档：`docs/v0.1/development/2026-09-19_expedition_level01_buildout.md` §6。

## 技能链路细化
- **场景美术 00–04**（编号即执行顺序）：`00-battle-room-layout-assembler`（总入口路由）→ `01-battle-room-type-art-authoring`（房间种类源）→ `02-battle-room-component-decomposer`（拆组件）→ `03-battle-room-instance-layout-authoring`（具体房间布局）→ `04-battle-room-runtime-assembler`（Godot 装配双分支）。`display_name_zh`、目录名、`name:` 三处必须一致且带同一编号。
- **道具与武器 05–08**：`05-items-weapons-pipeline-entry`（账本取尺寸功能、冻结 `asset_contract.json`、判动画档位）→ `06-items-weapons-blender-authoring` → `07-items-weapons-godot-prefab-assembly` → `08-items-weapons-code-integration`（内容ID映射、验收、台账转正）。统一资产根 `assets/art/items_weapons/`（`_templates/` + `props/` + `weapons/`，三段式 `source/→components/→rig/→runtime/`）。**只建了根与规范，存量 props/weapons 未迁移**；迁移必须「先建映射表→改引用→再移动→全量重导入」。
- **正本与镜像**：唯一正本 `~/.workbuddy/skills/`；副本三处：项目 `ShellStorm2/skills_drafts`、项目 `ShellStorm2/.codex/skills`、用户 `~/.codex/skills`；另有工程级 `I:\工作项目\shellstrom2\.workbuddy\skills\`（不在镜像脚本管理范围）。改内容只在正本改，再跑 `skill-mirror-sync` 的 `--sync` + `--check`（判据 `SKILL_MIRROR_CHECK_OK`，要求所有文件 CRLF）。skill 交付压缩包放 `I:\工作项目\shellstrom2\outputs\`；被替代的旧名包归入 `outputs/_superseded_skill_zips_<日期>/`，不直接删。
- **Blender 与账本**：Blender 4.5 后台跑加 `--factory-startup`；未挂载材质保存会被丢弃（需 `use_fake_user`）。账本取数：尺寸/功能/碰撞读 3D 分页「标准尺寸」+「功能说明」+「原点与朝向」，账本无结构化尺寸列。动画三档 `tier_0_static`/`tier_1_articulated`/`tier_2_deform`。

## 远征关卡01：干净场景实现（2026-09-19）〔运行时减法版，已被下下节的「结构性独立重建」取代〕
主人要求「新关卡必须是干净场景，只保留游戏基础逻辑 + 新关卡内容」。落地四项：
1. ~~**`Blocks/Base/Art` 必须整棵释放**~~ —— **已被取代**：新场景根本没有 `Blocks/Base/Art`，`_remove_tower_base_art()` 降级为防御性空操作。保留本节以存历史根因（塔楼里 Art 靠 `_install_facilities()` 被 reparent 到 `facility` 房 y=-12；远征无 facility 房、该函数早退 → Art 留在 y≈0 成隐形阻挡；**只设 `visible=false` 不够**）。
2. **远征包络两道开关**（`TowerFloorStage3D.configure()`）：第 5 参 `force_standard_map=true`（否则 `floor_index==0` 命中 100F 天台窄轮廓）；第 6 参 `content_bounds` = `TowerDescent3D._expedition_content_world_rect()`（7 房包围盒外扩 5m 对齐 5m 网格，实测 `Rect2(-10,-50,135,70)` = 27×14 格）。原实现铺满 250×250 → 远处立空墙圈、地砖 2500→369。**仍然有效**。
3. **水平走廊改路由** `_connector_block()`：远征→`Blocks/Expedition`、塔楼→`Blocks/Battle`。**垂直楼梯走廊禁止走它**（塔楼会返回 Battle，把节点挪出 `Blocks/Stairs`，打挂 `verify_tower_level_blocks`）。**仍然有效**。
4. ~~`Blocks/Rooftop|Base|Battle|Stairs` 空容器保留~~ —— **已被取代**：新场景的 `Blocks` 子节点**恰好只有 `["Expedition"]`**。

门禁：`verify_expedition_level01_flow` 增 `_verify_clean_scene()`；原有 `_verify_level_enclosure()` 断言内容外框对齐 5m 网格 / 包住 7 房 / `floor_world_rect==content_world_rect` / 整墙高 / `outer_visual_scale_y==1.0` + 逐房楼面与四向墙体射线。

## 远征关卡01：「继承场景」血统追查（2026-09-19，主人判定不对）
- **结论：没有任何约束要求「继承」。** 它是从被删的旧场景整份复制改名来的。
- 证据链：① `scenes/ExpeditionLevel01_3D.tscn` 与 `git show HEAD:scenes/RogueMap01TowerSegment3D.tscn` **结构同源**——同为 `instance=ExtResource("1_parent")`（父 = `TowerDescent3D.tscn`），只把 `standalone_rogue=true`/`rogue_map_id` 换成 `expedition_mode=true`/`expedition_run_id`；② 文档 `05.1_关卡区块设计.md` §3.0 的「继承塔楼主场景…**不复制一套区块树**」是 09-18 那版独立副本条款的**字符串替换**（继承部分原文未动）；③ 需求记录里写的是「**从零生成一个新关卡 / 从零生成一个完全不同的新关卡**」。
- **那条条款自身的逻辑漏洞**：同一句说「运行时不生成 `Blocks/Rooftop` 与 `Blocks/Base` 的游玩内容，也不生成 `facility` 房」——把「运行时不生成」当成「场景里没有」，但 `instance=ExtResource` 语义下父场景**全部节点无条件加载**；而「没有 facility 房」恰恰是 Art 留在 y≈0 的原因。
- **文档自相矛盾**：同一 §3.0 又说远征「不复用 `Blocks/Battle`…两者是并列的关卡内容」；区块表新行写远征「仅存在于 `scenes/ExpeditionLevel01_3D.tscn`」——都指向独立场景。
- **真正独立的代价**：`Dungeon3D.gd` 有 15 处硬 `$` 路径（`$Player3D`/`$WorldEnvironment`/`$DirectionalLight3D`/`$HUD/...`），`TowerDescent3D.gd` 另有 6 处 `$HUD`；`Dungeon3D.tscn` **没有 `Blocks` 节点**。要独立得先抽一个共享「关卡基座」场景，或把节点树复制一份。
- 结构根因（污染机制）：`TowerDescent3D` 里 `is_expedition()` 判断**散落 31 处**、三种风格（显式 `return` / 靠 `facility_floor == null` 隐式早退 / 无守卫）。**默认分支 = 塔楼形态** → 远征只能靠逐处减法，漏一处就是一次污染。`_install_facilities` 的早退、`floor_index==0` 的天台语义、走廊路由到 `Blocks/Battle` 三处同源。

## 远征关卡01：结构性独立重建（2026-09-19，主人拍板 A，取代「运行时减法」）
主人：「**把远征关卡重头新建一份，把这个污染的直接删了，然后基地内的指向远征情报设施的传送指向到达关卡的放到这里来。**」
- **唯一结构改动**：`scenes/ExpeditionLevel01_3D.tscn` 父场景 **`TowerDescent3D.tscn` → `Dungeon3D.tscn`**。`Dungeon3D.tscn` = 公共关卡基座：已含 WorldEnvironment / DirectionalLight3D / Player3D / HUD 整棵子树 / GeneratedCorridors·GeneratedRooms·ActiveEnemies·ProjectilePool3D·CombatEffectPool3D → **上文 §247 说的 15 处硬 `$` 依赖全部满足**；但**没有 `Blocks`** → 新场景自带 `Blocks`(index 9) 只挂 `Blocks/Expedition`(index 0)。
- 新场景还需覆写 `script = TowerDescent3D.gd` + 三个导出行（`expedition_mode`/`expedition_run_id`/`return_scene_path`），并自带 WorldEnvironment + DirectionalLight3D（变换表从塔楼场景抄）。旧场景备份 `.workbuddy/_backup_ExpeditionLevel01_3D.tscn.inherited`。
- **为何不需要 Rooftop/Base/Battle/Stairs**：`_room_block_for_floor()` 对 `is_expedition()` 直接返回 Expedition；垂直楼梯走廊（`_block("Stairs")`）只在多层塔楼生成（远征单层永不建）；`_install_facilities()` 早退（无 facility 房）。
- **一处结构改动取代 31 处运行时排除**：塔楼节点不再参与加载，「干净」由场景结构保证，不再由 `is_expedition()` 分支保证。
- **传送链单一真源** `GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D`（`src/framework/GameDesignConfig.gd`）：`RogueMapSelectMenu.LEVEL_SCENE` / `ExpeditionLoadingScreen.LEVEL_SCENE` / `TowerDescent3D.RUNTIME_MAP_SCENE_BY_ID`（续局路由）都由它取值；`BaseFacilityCatalog.mission_operations` 的下一跳是选关菜单、本身无需改。验收脚本 `EXPEDITION_SCENE` **有意保留字面量**做独立旁证。
- **门禁升级** `_verify_clean_scene()`：① 场景源文不含 `TowerDescent3D.tscn`（新增 `_read_text()` 读源文）；② 运行时无 `Blocks/Base/Art`；③ `Blocks` 子节点**恰好 `["Expedition"]`**（不再是「允许空容器」）；④ Rooftop/Base/Battle/Stairs **不得存在**；⑤ 走廊父节点为 `Blocks/Expedition`。
- 实测 `EXPEDITION_LEVEL01_FLOW_OK` / `EXIT=0` / **0 泄漏 / 0 USER ERROR / 0 SCRIPT ERROR / 0 FAIL**；OK 行含 `Blocks/Expedition only (scene is structurally independent of TowerDescent3D.tscn)` + `default tower unchanged`。

## 05.2 三层设计源与关卡设计源门禁（2026-09-19）
- **目录**：`source/art/whitebox/tower_zones/<level_id>/v001/data/` 下 —— L1 `level_plan.json` / L2 `floors/floor_NN.json` / L3 `room_templates/<id>.json`。远征 3 个模板 = `safe_15x15`(SAFE_ROOM) / `std_25x25`(COMMON_ROOM) / `extraction_25x25`(EXTRACTION_ROOM)；`wall_lane_table` 安全房四向 `[0.0]`、其余 `[-5,0,5]`。
- **数据驱动第三入口** `FloorPlanGenerator.generate_from_level_plan(level_id, …)`，与 `generate()`/`generate_expedition()` 并列。`data_driven_enabled(level_id)` 默认 **false**（须设计源 `policy.runtime_enabled==true` 才开）→ **D4 存档兼容未裁决前不得开**。
- **内容类型分派** `_assign_content_types_data_driven`：设计源钉死的 `type` **优先**；缺失才取 `content_type_pool`（缺省 = `CONTENT_TYPES`）；`stair_entry`/`stair_exit`/`extraction` 一律跳过；`boss`/`boss_prep` 恒 BOSS。**旧的 `_shuffle_content_types` 会覆盖钉死值并误给 `extraction` 派类型，已弃用。**
- **种子**：`rng.seed = run_seed ^ absi(str(level_id).hash()) ^ (floor_number << 17)`。⚠️ `^` 两侧必须 int；`absf()` 返回 float 会 parse error。
- **门禁 `verify_level_plan_design_source`**（S7，core，单层无引擎依赖可直接 `--headless` 跑）：判据 `LEVEL_PLAN_VALIDATE_OK levels=2 checks=135 rooms=23 templates=9`（`expedition_01` 1 层 7 房 3 模板 / `battle_level01` 1 层 16 房 6 模板）。带 `--emit-ports` 逐房打印 `PORT_JSON <level> <floor> <key> <ports>` + `PORT_DATA declared/derived`，**做新关卡时拿它取门槽，禁止手推**。
- **南北约定红线**：平面 `+y → 世界 +z → south`（`TowerDescent3D._plan_world_position` = `Vector3(x,-层高,y)`；`_direction_between` = `delta.z>=0 → "south"`）。门侧（north/south）写反 **不会让任何几何校验失败**（lane 仍对）→ 必须靠 `LevelPlanValidator._validate_port_derivation` 断言（报 `port_derivation_mismatch:<房>:<目标>:side south vs north`）+ `port_count_mismatch` / `port_target_not_neighbor`。
- **`LevelPlanLoader` 改「数据优先」**：设计源显式写 `ports` 就原样采信（另存 `derived_ports` 供比对），缺失才用 `RoomDoorLane.port_pair` 派生并置 `ports_derived=true`——**绝不静默用派生值覆盖设计值**（S1 导出 N/S 整体反向的病根）。`RoomDoorLane.port_pair` 南北分支 = `a_side = "north" if delta.y < 0.0 else "south"`。

## 下沉自 MEMORY.md 的长条目（2026-09-19 整合瘦身，MEMORY.md 只留一行指针）

### 远征门禁构成（关卡01 / 测试关卡99 同一套口径）
- `_verify_level_enclosure()`：包络对齐 5m 网格 / 包住全部房 / 整墙高 / `outer_visual_scale_y==1.0`。
- `_verify_hud_labels()`：顶栏房名与地图区文案无塔楼语义。**必须真实驱动一次 `_on_room_entered` 再读真字符串** —— HUD 是运行时拼串，几何/区块/包络校验看不见。
  - 故障史：远征曾显示 `100F · 天台避风港`（入口房 `room_id` 恰叫 `start` → 命中塔楼 100F 分支）与 `高塔外层 · LIVE`。改法：`Dungeon3D` 抽虚方法 `_hud_floor_label_text()`，`TowerDescent3D` 覆写 + 新增 `_expedition_room_label()`。
- `_verify_clean_scene()`：① 场景源文**无指向塔楼的 `[ext_resource`**（不是「不含塔楼字样」—— 退出落点 `return_scene_path` 指向塔楼是合法内容，用 `contains()` 会假红）② 运行时无 `Blocks/Base/Art` ③ `Blocks` 恰为 `["Expedition"]` ④ Rooftop/Base/Battle/Stairs 不存在 ⑤ 走廊父节点正确。

### 远征包络两道开关（缺一即回归）
`TowerFloorStage3D.configure()` 第 5 参 `force_standard_map=true`（否则 `floor_index==0` 命中 100F 天台窄轮廓 → 房无楼面无外墙、玩家踩空）；第 6 参 `content_bounds=_expedition_content_world_rect()`（实测 `Rect2(-10,-50,135,70)` = 27×14 格；否则铺满 250×250，地砖 2500→369）。

### 门扇（A 套正式美术）
`ENV-TOWER-DOOR-LEAF-5M`；GLB `assets/art/environments/tower_descent_3d/components/env_tower_door_leaf_5m_top3d.glb`（**带 `_top3d` 后缀**，与墙体 GLB 同命名规矩）；prefab `assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn`。`DungeonRoom3D.gd` 以**整 prefab 实例化** `DoorPanel/ImportedDoorVisual`，**底边中心为原点**（`visual.position.y = -DOOR_CLEAR_HEIGHT_M*0.5`）；包络 `2.2×2.492×0.18`m、**底边悬 8mm**（如实登记，非贴地 bug）。门扇分支二分：FACILITY→`env_base99_door_lift_2p2x2p5`，其余→门扇 prefab（旧 STAIR_LOBBY 支已退役）。**B 套 `door_5m` 已成孤儿件**（文件保留未删）。

### 台账写入
分账本带表对象/数据校验/派生列数组公式，改行走**外科式 XML 补丁**（`t="inlineStr"` + 保留 `s=`，其余条目按原 `date_time/compress_type` 字节复制），别用 openpyxl/Office 整本往返。内容编辑**必然**触发 `verify_ledger_split` 的 `row_content_mutated` → 口径 = `missing=0 extra=0` 且 `column_digest_drift` 仅命中被改列。**资产级改动写《资产主表》备注列；总目录《版本记录》是全局粒度、不登记单件。**

### Blender 导出三坑
① `--factory-startup` 不打开文件，要 `bpy.ops.wm.open_mainfile`；② glTF 默认写**全部** Scene（`use_active_scene` 默认 False）→ 源含审阅场景时会导出空场景，须收敛到 1 个；③ 删朝下面要**先三角化再删**（n-gon 平均法线可能高于阈值而其三角形低于，先删会残留隐藏面）。

### 视觉探针（关卡99）取景三事实
`TowerDescent3D._physics_process` 每帧覆写 `player.camera`（自定机位须先 `set_physics_process(false)`）；`PlayerFlashlight3D.start_enabled` **默认 false**（要玩家按 F，探针须显式开）；本关 `fog_density=0.04` → 134m 俯瞰被雾糊住（俯瞰图临时关雾 + 加诊断光，标注「诊断性偏离，不代表游戏观感」）。房间图**把玩家放房间正中央**（游戏相机在玩家局部系偏出约 `(6.2,10.3,6.2)`m，站偏就穿墙）。**必须用 `scripts/png_diff.py` 做像素差异客观比对，别只信 `*_OK`**。

### 远征运行时三反直觉事实（2026-09-19 探针实测）
- **敌人挂 `$ActiveEnemies`，不在房间子树里** → `room.find_children("*","Enemy3D")` 恒为 0；查 `_enemy_nodes_by_room` / `$ActiveEnemies`。
- **战斗房多波次**：`wave_count = [1,2,2,3][floor_level]`；`_alive_by_room` 是**首波**存活数，不是该房总数；待发波次在 `_room_wave_queues`，当前波号在 `_room_wave_numbers/_room_wave_totals`。
- **房间流送按玩家实际位置算**：只写 `_current_room_id` 或只 `force_enter_room_for_test()` 而不挪玩家 → 房间进 hibernate → `_hibernate_room_entities()` 当场 `queue_free` 该房全部敌人；此时 `_alive_by_room` 仍留着首波数，看起来「有怪但节点是 0」。
- **`_try_open_room_door()` 对已开启的边直接返回 true**（"通道已经开启"）→ 探针**不能**先 `force_open_edge_for_test` 全开边再测「未清房不能开门」，会测出假阳性。

### 测试关卡99 玩法配套实测结论（2026-09-19）
| 项 | 实测 | 判读 |
| --- | --- | --- |
| 房型 | `start`=STAIR_LOBBY(15×15) / `room_01`+`room_02`=COMBAT(25×25) / `extraction`=EXTRACTION(25×25) | 功能房 `type` 契约生效 |
| 刷怪 | 进战斗房首波 3 只、波次 1/2、待发 1 波 | 配齐（多波次） |
| 搜刮 | 可搜刮家具 6 件（room_01:2 / room_02:3 / extraction:1），`searched` 回调 6/6 已接 | **配齐**（COMBAT 房自带可搜刮家具，`content_type_pool=[COMBAT]` 不等于无搜刮） |
| 门策略 | 入口 `start→room_01` 三开关全 false；主路 `room_01→room_02`、`room_02→extraction` 全 true | 与关卡01 同口径 |
| 清房联动 | 未清房开门=false；清房+钥匙后=true 且钥匙 1→2（消耗 1 把） | 正确 |
| 命运卡 | 开门后 `_door_fate_active=true`、三选一、`HUD/DoorFateOverlay3D` 已构建、抽到 3 张不同卡 | 正确 |
| 局内命运 | `MapFateTriggers3D` 触发 `ENTER_ROOM ×7` → 应用 `fate_curse_map`（房间怪伤害 +15%） | 正确 |
| 撤离 | `has_expedition_extraction=true`、`beacon_type=STANDARD`、挂在 `extraction`/EXTRACTION、未锁 | 正确 |
| HUD | Minimap3D / TopBar / StatusPanel / ReferenceCombatHUD / ExtractionPanel 全存在 | 正确 |

探针：`tests/verification/probe_test_level_99_gameplay.gd`（+`.tscn`，非门禁，只打印）。

### 房间生成「数据 → 代码 → 积木」三层（编辑器里看不到房间，属正常）
- **房间不是可直接拖的 tscn**。布局真源 = 设计源 JSON（`rooms[].center_m` / `size_m` / `ports[]`，**坐标手写、不是算法算的**）→ `FloorPlanGenerator.generate_from_level_plan()` 纯代码出 plan → `TowerDescent3D._build_expedition_records()` 转 `_records` → `Dungeon3D._generate_layout()` 实例化房间容器 + `configure()` + `ensure_shell_built()` 用代码铺墙/地板（MultiMesh）、摆门/家具/灯（prefab 实例）→ 挂 `$GeneratedRooms`。
- **证据**：`scenes/ExpeditionLevel99_3D.tscn` 仅 51 行、**0 个房间节点**；容器模板 `assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d.tscn` 仅 6 行（空 `Node3D` + `DungeonRoom3D.gd`，无 mesh）。⇒ 编辑器里打开关卡**看不到房间**，改布局只能改 JSON 再跑校验器。
- `source/art/whitebox/tower_zones/99/` 只有 5 个 json、**无 .blend/.glb** ——「白盒」= 数据不是白模。
- 塔楼回退路径（`Dungeon3D._build_records()`，`main_%02d` 内置房表）坐标是代码硬编码 `index*62.0`。

### 房间装饰「配置 → 房间读」的既有实现（先例是抄常量，不是运行时读文件）
- 安全房 v007 先例：`assets/art/.../room_instances/entry_safe_room/v007/`（布局 blend + `component_packages_v007/` + `qa/slot_table.json` / `component_slot_replay.json`）→ `DungeonRoom3D._build_safe_room_shell()` 按**硬编码 `const SAFE_ROOM_WALL_SLOTS`**（`:126`，注释「逐项源自 slot_table.json」）实例化 prefab。即**已有管线但落地方式是抄成常量**。
- **全 `src/world3d/` 无任何 `room_layout` / `room_instance_layout` 运行时 JSON 解析器**（`Dungeon3D._plan_room_layout():1792` 是**程序化规划器**，写 meta 不是读文件）。99 战斗房装饰走 `_build_content()` **程序化**（公式 `side*dimensions.x*x_factor` + `_rng`），**无按房间读配置的入口**。
- 做「配置文件让房间读」只有两条路：① 抄常量（照 v007）；② 新写运行时读取器。**别假装已有运行时读取器。**

### 刷怪唯一入口与房间级 override（`enemy_spawn_plan`，2026-09-19 落地）
- **刷怪唯一入口 `Dungeon3D._spawn_room_enemies()`**：首次进房触发（`HOSTILE_ROOM_TYPES` = COMBAT/ELITE/BOSS/TRAP/BASEMENT/STORAGE/SCAVENGE），**只刷一次**。刷在 `room.enemy_spawn_points`（环形均布 0.23×尺寸），容器是 `$ActiveEnemies`，**不在房间子树**。
- 无 override 时，数量/波次/种类全是**全局公式 + 主题**：`floor = visual_theme.difficulty_rank`、`floor_level = 按 _records 序号折算`、COMBAT `wave_count = [1,2,2,3][floor_level]`、`desired = 4 + floor*2`，种类读 `MonsterInjector` + `MapThemeProfile.enemy_rules`。**设计源 JSON 原本只能定 `content_type`，定不了刷怪。**
- **`enemy_spawn_plan`（房间级刷怪计划）现在把波次/每波数量/构成全部接管**。schema：`{"waves":[{"monsters":[{"type":"<6 类>","count":<正整数>}]}]}`；`type` ∈ `BASE_ENEMY_TYPES` 去掉 `boss` = `melee_chaser`/`ranged_caster`/`summoner`/`shielded`/`exploder`/`ambusher`；上限 6 波 / 每波 24 / 单房合计 64；只允许写在 `GameDesignConfig.is_spawn_plan_authorable_room(content_type)` 为真的房间（= 会刷怪 且 **非 BOSS**；BOSS 房禁写，单列错误码 `enemy_spawn_plan_on_boss_room`）。
- **接管范围**：波数、每波数、每波构成**全按填写**；全局 `desired` / COMBAT 波表 / 主题 `enemy_pool` 被绕过。**但每只怪的 hp/伤害/速度仍由 `MonsterInjector` 按主题倍率 + 楼层缩放算**（单一真源，不随填写改变）。
- **6 个接线点缺一个即静默丢弃**：设计源 `floor_NN.json` → `LevelPlanLoader.normalize_floor()`（白名单重建）→ `FloorPlanGenerator.generate_from_level_plan()` → `TowerDescent3D._append_plan_room_record()`（写 `record["enemy_spawn_plan"]`）→ **`Dungeon3D._generate_layout()` 与 `TowerDescent3D._instantiate_dynamic_room()` 两处 `configure({...})`** → `DungeonRoom3D.enemy_spawn_plan` → `_spawn_room_enemies()` → `_authored_spawn_waves()` → `MonsterInjector.build_waves_from_plan()`。
- ⚠️ **两个 `configure()` 调用点**（塔楼/通用基座路径 + 远征实例化路径）都是显式白名单；**只补一处 → 远征里字段被 `{}` 覆盖，plan 到了生成结果却没到房间实例**（实测报「room_02 的 enemy_spawn_plan 没有落到房间实例上」）。`DungeonRoom3D.configure()` 已改**保留式**：`enemy_spawn_plan = (config.get("enemy_spawn_plan", enemy_spawn_plan) as Dictionary).duplicate(true)`。
- **命运卡状态必须在两条路径都记账**：`_room_enemy_hp_multipliers` / `_room_enemy_damage_multipliers` / `_room_currency_multipliers` 要在刷怪时记录，`_next_room_enemy_hp_multiplier` / `_next_room_enemy_damage_multiplier` / `_next_room_currency_multiplier` / `_next_room_enemy_count` 要复位 —— authored 分支的 early-return 一度跳过这段 → 倍率**泄漏到后续房间**。统一走 `Dungeon3D._note_room_enemy_modifiers(room)`，两条路径都调。
- 校验器 `LevelPlanValidator._validate_enemy_spawn_plan`（`:350`，13 个错误码，前缀全写）：`enemy_spawn_plan_not_object` / `enemy_spawn_plan_on_boss_room` / `enemy_spawn_plan_on_non_hostile_room` / `enemy_spawn_plan_waves_empty` / `enemy_spawn_plan_too_many_waves` / `enemy_spawn_plan_wave_not_object` / `enemy_spawn_plan_wave_monsters_empty` / `enemy_spawn_plan_monster_not_object` / `enemy_spawn_plan_unknown_monster` / `enemy_spawn_plan_monster_not_authorable` / `enemy_spawn_plan_monster_count_invalid` / `enemy_spawn_plan_wave_too_large` / `enemy_spawn_plan_total_too_large`。上限常量 `SPAWN_PLAN_MAX_TOTAL` 等。
- **两道门禁证据**：① `verify_level_plan_design_source` 的两条 OK 行都带 `plans=N`（N = 有计划的房间数；99 实测 `plans=1`；`plans=0` = 根本没接通，属假绿）② `verify_test_level_99_flow` 的 `_verify_enemy_spawn_plan` 真驱动 `_spawn_room_enemies`，断言 authored 房（2 波×3）与 formula 房并存、命运卡倍率记账后复位。对应的填表入口 = `docs/v0.1/design/新关卡设计表.md` §1.7 + skill `09-level-plan-authoring` 第 2 步补充。

### 房间级首领指派 `boss_content_id` + 刷怪口径收敛（2026-09-19 落地）
- **主人拍板两条**：①「没写 boss 代表是没有 boss 就好了，**不刷 boss**」→ 空的 Boss 房是**合法状态**，不是错误，`push_error` 一律不加；②「**只指定 Boss 身份**」→ 设计源只能点将，编成（波次/技能袋/竞技场/结算）全归 `BossContentCatalog` 名册条目。
- **唯一解析入口 `BossContentCatalog.resolve_profile(authored_content_id, floor_number)`**：作者明确给了 id 就**用作者那条**（`floor_number` 取该内容固有层号，不是当前楼层）；作者没给才 `get_for_floor(floor)`；**任何情况下都返回一条 profile 或空字典** —— 未知 id **绝不静默换成别的首领**（作者只会看到「我明明指定了却没出现」）。空字典 = 本房无首领。
- **「空 Boss 房」五处落点**（少一处就出 Bug）：① 校验器不加错（空字段直接 `return`）；② `MonsterInjector.generate_enemies` 的 `"boss"` 分支**必须空守卫**（`if not boss.is_empty(): enemies.append(boss)`）—— 不守卫就是「单层未指派首领的 Boss 房仍刷出 1 只敌人」；③ `DungeonRoom3D.configure` 保留式写 `boss_content_id`；④ `TowerDescent3D._append_plan_room_record` BOSS 分支走 `resolve_profile` + `room.set_meta("boss_content_id", ...)`；⑤ `Dungeon3D`：`enemy_configs.is_empty() and room.room_type == "BOSS"` → `_alive_by_room[room_id]=0` + `_mark_room_cleared(room, true)` + 状态栏「首领房未指派首领 · 区域已放行」+ `return true`（**必须放行**，否则挡死下楼门）。
- **口径收敛（旧 `SPAWN_PLAN_FORBIDDEN_ROOM_TYPE` 已删除）**：现在两条唯一定义都在 `GameDesignConfig` —— `is_boss_room(content_type, role)`（`content_type == "BOSS" or role == "boss"`，两个消费方都走它）与 `is_spawn_plan_authorable_room(content_type)`（`ROOM_TYPES_WITH_HOSTILES.has && != "BOSS"`）。**为什么 role 也要认**：`FloorPlanGenerator._assign_content_types_data_driven` 把 `role == "boss"` 的房间**钉成** `type = "BOSS"`，只看 content_type 会漏判。
- **新增两个错误码**：`enemy_spawn_plan_on_boss_room`（BOSS 房**不是「不刷怪」，而是不归设计源管**）、`boss_content_id_on_non_boss_room` / `boss_content_id_unknown`（`BossContentCatalog.floor_number_for_content_id(id) <= 0` 即未知）。
- **`FloorPlanGenerator.room_from_source(src)`**：从 `generate_from_level_plan` 循环里**提取的单一透传注册点**（新字段一律在这里过一道），是「字段有没有透传到运行时」的**唯一可断言处**（也是本页下方手写 patch 探针的挂钩）。
- **⚠️ 空跑门禁怎么防**：出厂三个关卡**没有任何 BOSS 房** author 该字段 → `_verify_boss_content_id_carried` 是 **0 样本**（断言恒真 = 假绿）。两道补丁：① `LEVEL_PLAN_RUNTIME_GUARD_OK ... boss_ids=0` 把样本数**打印出来**，`boss_ids==0` 时再打 `LEVEL_PLAN_RUNTIME_NOTE` 明说「无样本，透传由 99 门禁的手写 patch 探针覆盖」；② 99 门禁里用 `FloorPlanGenerator.room_from_source({...})` **手工造**一个带 `boss_content_id` 的 boss 房 + 一个普通房，断言前者透传、后者为空。
- **⚠️ 反向对照（证明门禁真会红）**：① 把 `resolve_profile` 的「作者分支」中性化 → 3 条错误、0 个 OK、exit 1；② 把 `room_from_source` 里的键改名（`boss_content_id` → `boss_identity`）→ `FloorPlanAudit ... FloorPlanGenerator 未把 boss_content_id 透传进运行时房间`、exit 1。两者随后**都已还原**。凡新增「字段透传」类断言，都要这样先证伪一次。
- **存档安全**：`layout_id` 的规范化**不含内容字段** → 新增 `boss_content_id` **不会**破坏旧存档还原（`LevelPlanLoader.normalize_floor` 的白名单重建只是逐条透传）。


### 门墙与 L 墙角（几何 / 朝向 / 导入）
- **门墙** = `ENV-TOWER-WALL-DOOR-5M`（场景账本第 57 行），v004 自 v007 `wall_door_5m_通用包` 派生（旧 v003 是塔楼旧套件的程序生成方块：41,760 B、无 PaletteUV、`.import` 未绑色盘）。结构 `5×11.9×0.30`、**可视 `5×11.9×0.4915`**（装饰面朝房内 +Z 凸到 0.3415）、门洞净空 `2.2×2.5`（**射线从门洞内部实测，不采信源文件自报包络**）；4 个材质角色全都有面（实墙 / L 角是 3 角色 + 丢空槽 03）。
- ⚠️ **带门楣 / 悬挑的件不能照实墙「全剔朝下面」**：门楣底面朝下且高于地面，全剔会让玩家仰头看穿墙体。门墙只剔**贴地那一层**（`|z| ≤ GROUND_BAND_M = 0.05`，派生态 z = 高度轴），实测剔 116 / 保留 1376，派生脚本内建 `lintel underside was culled` 断言。顺序仍是**先三角化再剔面**。
- **门墙没有** `source_visual_version` 三处纪律（那条只属被 `TowerDescent3D` preload 裸 GLB 的实墙）；门墙版本串只有 prefab `metadata/asset_version` 一处。
- **L 墙角** = `ENV-TOWER-CORNER-L-5M`（`prp_corner_l_5m.tscn`），**由两份通用墙刚性拼成**（长臂 `T(+2.5,0,0)@Rz(+180°)`、短臂 `T(0,+2.5,0)@Rz(+90°)`），每臂 5319 面、L = 10638。**先优化再复制**（Stage1/2 分离），否则二次 `transform_apply` 的 float 舍入会差 7 面。
- **L 墙角朝向口径（2026-09-19 修正）**：原点在转角、两臂向 `+X` / `−Z` 伸出时，**房间内侧 = 两臂之间的凹象限（`+X`/`−Z`）**，不是 `−X`/`−Z`。两臂装饰面都必须朝房内（长臂 **Godot −Z**、短臂 **+X**）；包络外壳面（长臂 `+Z`、短臂 `−X`）是结构背。口径只认运行时：`DungeonRoom3D._spawn_room_corner()` 注释 + `_build_corner_aware_wall_run()` 的南墙 `rotation_y = PI` / 西墙 `+PI/2`（A 套直墙装饰面永远朝房内）。
- ⚠️ **朝向类缺陷（面朝反）包络 / 面数 / 材质角色 / 原点约定四类断言全绿** —— 长臂反 180° 后仍是 10638 面、角色不变、`bottom_corner` 仍成立，只有 `z_max` 从 0.3175 悄悄变 0.15，「房内那面变光滑」没有任何数值在管。**两道闸**：① 派生脚本 `ARM_FACING_GODOT` 逐臂 AABB 离面轮廓断言（装饰面凸 0.3175 / 结构背 0.15，反了报 `CORNER_ARM_FACING_WRONG`）；② 画面探针 `FACE_GAUGES` 逐面朝向判据（房内面/外侧高通能量 ≥ 1.6，实测 3.220；反向对照 0.149 → exit 1）。
- **原点契约有四套**：`bottom_center` / `centered_slab` / `bottom_corner`（L 墙角：原点 = 转角，两臂向 +X/−Z 伸出，**禁止重新居中**）/ 基地 `center_bottom`。
- L 墙角是六件里**唯一自带碰撞**的件（`visual_only=false` / `collision_owner=self`）；两个 `StaticBody3D` 节点名 `WallCollisionLong` / `WallCollisionShort` 是镜头下压契约，**改名即回归且不触发数值门禁**。
- ⚠️ **新生成的塔楼 GLB，Godot 自动写的 `.import` 不绑共享色盘脚本**（`import_script/path=""` + `embedded_image_handling=1`）→ 渲染成白板且**不触发任何 `*_OK` 门禁**，必须手工改成绑 `scene_facility_shared_palette_post_import.gd` + `=0`。
- 派生导出断言要 band-aware：墙 60° 倒角面停在 `nz = −0.4999999`，阈值 −0.5 是刀刃，用 `DOWN_BAND_M = 1e-4` + `DEGENERATE_FACE_AREA_M2 = 1e-9` 只 fail 真朝下且有面积的面。
- **GLB 稳定路径在 `assets/art/...`**（别按 Blender 源目录找）；`TOWER_WALL_SCENE` preload 裸 GLB → **导出前 ROOT 归零**。
- **版本串三处同批改**（**只适用于被 `TowerDescent3D` preload 裸 GLB 的实墙**）：prefab `asset_version` + `TowerDescent3D.gd source_visual_version` + `verify_tower_grid_component_alignment.gd`。
- `bounds_size_m` 与 `visual_bounds_size_m` **刻意分离**；门禁判结构盒 ⊂ 可视包络。

### 竖直构件做「双面装饰」（门墙 v005 先例）
- **先判需求**：只有两侧都会被玩家看到的件才需要（门墙夹在房间与走廊之间 → 需要；实心墙 / L 墙角 → 不需要，保持单面）。别默认单面，也别无脑双面。
- **只镜像装饰面，绝不镜像整物体**。整物体镜像会 ① 与保留的背板/隧道**共面闪烁**（z-fighting）② 把门洞复制成两条。做法：复制网格 → 在副本上删掉 `y > −(结构面 + 2mm 容差)` 的面 → 加 **Mirror** 绕基准面翻转 → 应用后 `join`。
- **Mirror 参数**：`use_axis=(False, True, False)`（绕 Blender Y = 网格中心线/基准面）、**`use_mirror_merge = False`、`use_clip = False`**。门洞隧道与背壳横跨该平面，开合并会把它们粘到基准面、开裁剪会把它们钉死；两项都关后**修改器自动翻转绕向**，镜像面法线朝外，**不要手工 `flip_normals`**。
- **镜像阶段的位置**：排在 180° yaw 烘焙**之后**、朝下剔面**之前**。这样镜像是在已经对齐塔楼 A 套 `+Z` 之后发生的，结果是**真镜像（z → −z）**而不是旋转 180° 复制。
- ⚠️ **对称性验证禁用「面色心」**。镜像顶点存 **float32**，色心/法线差约 **1e-5**：排序后逐项 `zip` 会整体错位（误报 911 条），容差桶贪心匹配不保证传递性（仍误报 29 条；对拍发现两侧顶点位置多重集差异其实为 0、未匹配行最近邻 `dpos=0.000000`）。改用两个逐位稳定的不变量：
  - **顶点位置键多重集**（镜像只翻 `abs(y)`，逐位精确）→ `mirror_position_key_mismatches == 0`；
  - **有向面积（向量面积和）相对偏差** → 抓「面反了」（绕向没翻正 → 法线朝内、背面渲染不可见，但面积绝对值不变，只有有向面积能抓到）。
- ⚠️ **`cross_side coincident twin ≈ 0` 是硬判据**：镜像面只要与保留几何共面就会闪烁。源本身可能就有共面孪生（薄片双面写法，本件 132 组），镜像后应恰好 **2×**（264），**新增必须为 0**。
- ⚠️ **零面积退化面会让「朝下面」计数在存盘/重载间翻转**（本件 24 个 `area < 1e-9`，其法线是数值垃圾 → 朝下计数在 1367/1368 摆动）。所有朝下统计加 `DEGENERATE_AREA_M2 = 1e-9` 跳过并单独报告；计数类断言加小容差。**结构件（门楣等）的存在性不要靠计数证明** —— 用射线测出的净高（`clear_height_m = 2.5`）精确证明。
- **门洞判据从两向扩到三向**：`±X` 净宽、`+Z` 净高、**`±Y` 贯穿厚度**（`ray_plus_y is None and ray_minus_y is None` ⇒ `clear_through_thickness`）。第三条专门证明镜像面没把门洞堵死。
- **包络变化只动可视字段**：`bounds_size_m`（结构阻挡）不变，`visual_bounds_size_m` 由单面的 `0.4915` 变双面的 `0.683`（`z ∈ ±0.3415`，关于 `z=0` 对称）；prefab 补 `metadata/double_sided = true`。
- **探针判据必须跟着改向**（改完资产不改判据 = 留着假绿）：`probe_door_wall_visual` 的 `DETAIL_RATIO_MIN`（「房内侧 ≫ 外侧」）退役 → `SIDE_DETAIL_MIN`（**两侧都**须达装饰级：素结构背 0.0004 过不去、装饰面 0.0015 过）+ `SIDE_RATIO 0.5..2.0`（两侧比值须回到 1 附近）。**「单侧远大于另一侧」这类判据本身就是「一面是白板」的许可证**。
- **画面取证两张表**（v004 → v005 实测）：亮/细节 `room 7层/0.0015 不变`、`outer 2层/0.0004 → 6层/0.0018`、`ratio 4.247 → 0.829`；像素比对 `room v004 vs v005 = 0.04/255（几乎同一画面）`、`outer v004 vs v005 = 1.98/255 / 12.5%（不同画面）`。再加**镜像性对拍**：把走廊侧图水平翻转后与房内侧比，`v005 1.59 → 0.96/255`（翻转后更近）、`v004 2.75 → 2.73`（素板翻转等于没翻）。肉眼铁证 = 走廊侧图上 **B1 标牌 / 警示三角 / 门楣警示条全部左右翻转**。残差来自键光 1.1 与补光 0.5 的**照明不对称**，不是几何差异。
- 台账：**升级既有行**（第 57 行），只动 `M/N/P/T/W/Y`；`O` 稳定路径未变就原样回写（于是字节相同、不出现在「变化单元格」清单里，**这是预期不是漏改**）。复核脚本 `_scratch/verify_ledger_door_row57_v005.py` 判据 `LEDGER_ROW57_PATCH_OK`（zip 只有 `sheet3.xml` 变、变化格恰好那 6 个、`R/S` 原样、`T` 与磁盘 GLB 哈希逐字符一致）。
- 分账红项：**重复改同一行不再累加**。第 57 行在换 v004 时已进 `row_content_mutated` 名单，所以 v005 落地后 `failures` **仍是 475（+0）**——第 10 节的「每次有意变更恰好 +1」只对**某行第一次被改**成立。

### 验证与验收 · 本地实操补充
- 逐场景 `--headless --path . res://tests/verification/<场景>.tscn` 再 grep `*_OK`；先 `--import`。visual 场景不带 `--headless`。**不看裸退出码**；日志放 `_scratch/`。
- ⚠️ **「本机 Bash 缺 coreutils」是个假象**：缺的只是 PATH。先 `export PATH="/c/Program Files/Git/usr/bin:$PATH"`（PortableGit 自带 `dirname/find/awk/mktemp/ln/cygpath/date`），`run_verification_suite.sh` 就能**直接跑**（`GODOT_BIN=<console.exe> bash scripts/run_verification_suite.sh scene <门禁名>`），它会自己复制 `project.godot` 注入 `use_custom_user_dir` + `custom_user_dir_name` 到临时隔离目录，退出时清理。**没前置 PATH 时**才退回 Python `subprocess` 直跑 Godot + 临时把 `config/use_custom_user_dir` 注入 `project.godot` 的 `[application]`（该文件是 **LF**，其余 `.gd/.tscn/.md` 才是 CRLF），`finally` 还原并删临时 userdata。
  - ⚠️ **用完必须确认 `project.godot` 没留残留注入**（`git diff project.godot` 应只有你自己有意的改动）。残留 `config/use_custom_user_dir=true` 会让**下一次**直跑 Godot 的门禁行为异常，排查时极易误判成 autoload 编译坏了。
  - ⚠️ **门禁一律按场景跑**：`--scene res://tests/verification/<名>.tscn`。用 `--script res://.../<名>.gd` 跑引用了 autoload 的项目脚本会报一串 `Compile Error: Identifier not found: AudioManager/RuntimePerformanceManager/BaseManager` —— 那是 `--script` 模式下 autoload 未注册，**不是脚本坏了**。（`_scratch/` 下 `extends SceneTree` 的临时探针不碰 autoload，可以用 `--script` 跑。）
  - 可复用跑手：`_scratch/gates/run_jobs.py [--nonheadless] scene:res://…  script:res://…`（自动注入/还原用户目录隔离，日志落 `_scratch/gates/`）。
- ⚠️ **`I:\工作项目\shellstrom2\inspect.py` 遮蔽 stdlib `inspect`**：在该目录下用 Python 跑 openpyxl 会炸 `ModuleNotFoundError: bpy`（openpyxl → `import inspect` → 命中这个假模块）。跑账本工具要 **`cd ShellStorm2`** 并用**项目 venv**（`~/.workbuddy/binaries/python/envs/default/Scripts/python.exe`，只有它装了 openpyxl；托管 `python3` 没装）。
- `--check-only --script` **不能**验证本项目脚本（不加载 autoload → 假报 `Identifier not found: BaseManager/AudioManager`）；必须真跑场景，再 grep `ERROR`。
- **新验收脚本要带「防假绿」哨兵**（如 `_probe_completed` / `plans=N`）：脚本错误会**静默中断协程并留下空失败表** → 照样打印 OK。
- 既有环境红项基线：`verify_ledger_split` / `check_asset_registry` / `verify_base_world_flow` / `verify_3d_performance_budget`；**红项 ⊆ 基线才算过**。
- 分账本 `verify_ledger_split`：**每次有意变更恰好 +1 条红项**、不级联（新增资产 → `asset_not_in_baseline`，改既有行 → `row_content_mutated`）；判据「红项 ⊆ 基线 ∪ 本次有意变更」。基线冻结于分账前，永远报 `extra`，属已知债。现构成 **475** = 场景账本 R/S 派生列公式红项 470（既有）+ `row_content_mutated` 3（第 55/69/57 行，均有意）+ `asset_not_in_baseline` 1（门扇行）+ `moved_sheet_mutated` 1（既有）。
- ⚠️ **该门禁的 JSON 只保留 `failures[:40]`**，直接看会误读成「只有 40 条」且看不到靠后的 `row_content_mutated`。拿全量**必须重放行级检查**：`_scratch/ledger_split_audit.py`。
- ⚠️ **换资产后审一遍「描述旧资产缺陷」的断言**：门墙换 v004 后，`probe_tower_palette_visible` 原「必须有隐藏门扇且 visible=false」在**正确**资产上假失败 → 反转为「子树不得出现任何含 `DoorLeaf` 的节点」。
- ⚠️ 节点名前缀 `Imported_DoorWall5M_*` 被两条路径共用（塔楼 A 套 `ENV-TOWER-WALL-DOOR-5M` 与基地 99 层 `ENV-BASE99-WALL-DOOR-5X12`，后者包络 1.051m 深）→ 运行时核对**必须按 `asset_id` 过滤**，否则量出假失败。
- **AssetID 已存在就必须升级既有行，不得新增行** —— 否则门禁报 `duplicate_asset_id`（L 墙角第 69 行、墙第 55 行都是升级既有行；门扇是真空缺才新增第 241 行）。
- **GDScript 陷阱**：① Node3D 变量方法返回值勿用 `:=`；② `%` 不支持 `%g` → 跑完必须 grep `ERROR`；③ 协程不 await 只跑到第一个 await；④ 类型化数组元素是对象读属性；⑤ `var x := <Node>.get("prop")` 是错。
- `verify_level_plan_design_source` **两条判据缺一不可**：`LEVEL_PLAN_VALIDATE_OK` + `LEVEL_PLAN_RUNTIME_GUARD_OK`；门槽用 `--emit-ports`，**禁止手推**。
- **南北红线**：平面 `+y` → 世界 `+z` → south；门侧靠 `_validate_port_derivation` 断言；`LevelPlanLoader` 数据优先，绝不静默覆盖。
- **画面验收**：`verify_test_level_99_visual` 出 6 图；必须 `scripts/png_diff.py` 像素比对，**别只信 `*_OK`**。
- ⚠️ **同一文件多处编辑必须串行**（同一条消息的多个 `Edit` 会互相覆盖，最后一个静默胜出 —— 本轮 `plans=0` 假绿即由此产生）。

## 天台女儿墙 = 参考组件库 v002 的两件（2026-09-19 落地）

**结论**：100F 天台周边不再用塔楼 A 套 `prp_tower_wall_parapet_5m.tscn`（5×0.30×1.50m，再靠 0.5 纵向缩放凑成 0.75m），改用参考组件库 v002 `02_女儿墙` 的两件真尺寸模块。

| | 直段 | 外角 |
|---|---|---|
| AssetID | `ENV-ROOFTOP-REF-PARAPET` | `ENV-ROOFTOP-REF-PARAPET-OUTER` |
| prefab | `prp_rooftop_parapet_5m.tscn` | `prp_rooftop_parapet_outer_2p5m.tscn` |
| GLB | `tower_zones/rooftop/components/env_rooftop_ref_parapet_top3d.glb` | `..._outer_top3d.glb` |
| 包络 | 5×0.50×1.80m | 2.5×2.5×1.80m |
| 摆法 | MultiMesh 64 槽位 | 四角各 1 件（单独 Node3D） |

- 高度 `ROOFTOP_PARAPET_HEIGHT` 0.75 → **1.80**；厚度 `ROOFTOP_PARAPET_THICKNESS=0.50` 与普通层 `WALL_THICKNESS=0.30` 不同 → **必须**走按层取值的 `_outer_wall_thickness()/_outer_wall_inset()`，否则边界内缩口径与模块厚度错台。
- **0.5 纵向缩放补偿已删除**：`_outer_visual_transform` 现在恒为单位缩放。历史上它把远征层也误缩到半高，一并消掉。现在视觉包络 = 碰撞高度 = 1.80m。
- 让出 2.5m 给转角件后正好整格：90−5=85m=17 格、80−5=75m=15 格 → 直段 2×(17+15)=64 段 + 4 转角。西侧楼梯口门洞命中 3 段（15m = 楼梯厅外宽）→ MultiMesh 实际 61 实例 + 3 件门洞补位墙 + 4 转角 = 68 件。
- ⚠️ **段起点整体后移 2.5m 会平移门洞相位**：命中 `_is_in_wall_door_gap` 的段从 2 变 3。别把「64−2」写死，按节点名 `ParapetDoorWall_` 动态计数（门店名要带序号，否则 Godot 自动去重会让 `find_child` 取错）。
- ⚠️ 旧 prefab `prp_tower_wall_parapet_5m.tscn`（`ENV-TOWER-WALL-PARAPET-5M`）**不是孤儿**：仍被 `DungeonRoom3D.gd:34` 引用、且在 6 件 `PREFAB_CONTRACT` 清单内 → 新件必须用新身份，**不要去改建/删除它的台账行**。
- 朝向口径（换件时核对）：外角两臂中心线在局部 `x=-1.0` / `z=+1.0`，开口朝 `+X/-Z`；四角放位 SW=(−48.75,0,43.75) rot 0 / SE=(38.75,0,43.75) rot π/2 / NE=(38.75,0,−33.75) rot π / NW=(−48.75,0,−33.75) rot 3π/2（俯视逆时针）。这些已写进 prefab 的 `metadata`（`corner_arms` / `corner_arm_centerlines` / `corner_open_facing`）。
- 新 GLB 的 `.import` **必须手工绑** `tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`，否则白板（同「新塔楼 GLB 不绑共享色盘」那条）。
- 「模块种类 ↔ `floor_kind`」是跨函数隐形契约，已在 `_build_outer_shell()` 留 `assert(_uses_rooftop_parapet_modules() == (floor_kind == "rooftop"))`。

### 探针两个坑（`probe_rooftop_parapet_alignment`）
1. ⚠️ **必须带窗口跑，不能 `--headless`**。MultiMesh 实例变换存在 RenderingServer 侧，dummy 渲染器下 `get_instance_transform()` 一律回读成单位阵 → 直段全部「消失」、误报每条边缺 85m。这是读法限制，不是装配错。
2. 竖边（west/east）的 boundary 是 **X** 值 → 跨界判定要用 X 轴；一律拿 Z 判会让竖边恒报「没有任何模块」。
- 实测：四边 `coverage=全长 / gap=0.000 / overlap=0.000`；四转角件各 2.500×2.500 精确落座。门禁 `ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`（断言 `outer_segment_count=64 / outer_corner_count=4 / outer_wall_thickness=0.5 / outer_wall_height=1.8`）。

### 台账口径：这两件在 Prefab 分页里，不在资产主表
- 参考组件库 44 件当初**只登记在 `3D-场景通用` 分页**，`资产主表` 里没有它们（主表只有父库行 `ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY`）。
- 这两件 AssetID **已存在**（`3D-场景通用` R102 `ENV-ROOFTOP-REF-PARAPET` / R104 `-OUTER`）→ 按「AssetID 已存在必须升行」只升这两行，不新增行。资产主表未增删行 → 总览跨度 `$239` 不动，也**不需要** `rescope_asset_sheet()`。
- ⚠️ `check_asset_registry` **只查《资产主表》，不查 `3D-*` Prefab 分页** → 改分页行不会产生任何 issue。判红项时必须知道这条口径，否则会误以为「没报 = 没登记」。
- 母版：`assets/art/environments/tower_zones/rooftop/source/export_env_rooftop_parapet_v001.py`（headless Blender 导出，含「网格 rebase 到包内 `根_` 空物体再丢弃变换」拿到 XY 居中 / 底面 Z=0 的原点契约）。

### 破损变种 3 件 + 随机排布（2026-09-19 追加，直段专属）
需求：给直段做 3 种破损变种（崩顶 A / 贯穿 B / 塌脚 C），要能首尾相接，导入后随机排布外墙（约 1/4）。**只动直段，外角件不动。**

| | A 崩顶 | B 贯穿 | C 塌脚 |
|---|---|---|---|
| AssetID | `ENV-ROOFTOP-REF-PARAPET-DMG-A/B/C` | | |
| prefab | `assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_{a,b,c}_5m.tscn` | | |
| GLB | `tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_{a,b,c}_top3d.glb` | | |
| visual 节点 | `女儿墙直段破损{A,B,C}_主体` | | |

- 包络与直段**完全相同** 5×1.8×0.5m，`origin_contract=bottom_center`、`forward_axis=+Z`、`runtime_instantiation=batched_multimesh`、`collision_owner=TowerFloorStage3D`。
- **「能接起来」的判据 = 端带（`|x|>=2.05m`）与直段逐比特一致**：源层 `tower_zones/rooftop/source/verify_env_rooftop_parapet_damage_bands.py` 直接比 GLB POSITION 字节；Godot 导入会引入 ≤0.07mm 顶点焊接偏移 → 运行时探针容差 `BAND_MAX_DEVIATION_M=1.0e-4`。损坏只做中段，端带 312 顶点原样保留。
- ⚠️ **单 MultiMesh 只能装一个 mesh** → 变体排布必须「1 完好 MultiMesh + 每变体 1 个 MultiMesh」= 4 个 `MultiMeshInstance3D`（`_outer_visual` + `_outer_damage_visual: Array[MultiMeshInstance3D]`）。
- 拆分逻辑抽成 `TowerFloorStage3D.split_outer_parapet_damage(transforms, seed_value, enabled) -> Dictionary`（static，可在不建 stage 的情况下单测）；`rng.seed=_outer_damage_seed`，判定序「先 `randf()<0.25` 再 `randi_range(0,2)`」。
- 槽位真源 `_outer_straight_slot_transforms`（+`get_outer_straight_slot_transforms()` / `get_outer_damage_slot_kinds()`）——**排布探针读它，不读 MultiMesh**，于是 `probe_rooftop_parapet_alignment` 已能 headless 跑（旧「必须带窗口」坑对新链路消除）。
- 实测 seed=20260919：`slots=64 intact=46 dmg_a=7 dmg_b=3 dmg_c=8 damaged=18 ratio=0.2813`，四边均有破损。（⚠️ 同一 seed 下**槽位一变分布整体重排**；封西侧围栏缺口前是 `slots=61 intact=44 damaged=17 ratio=0.2787`。**别把某一次实测数字写成断言**。）
- 门禁：`verify_rooftop_32x32_contract`（+3 变体齐/计数自洽）、`probe_rooftop_parapet_damage_prefabs`、`probe_rooftop_parapet_damage_layout`、`probe_rooftop_parapet_alignment` 四道全绿；已做反向对照证明断言真会红（不是假绿）。
- 台账：AssetID **全新** → `3D-场景通用` **新增 3 行**（不是升行）；资产主表不动、不需 `rescope_asset_sheet()`。
- 坑：GDScript `%` 无 `%e`（用 `%.9f`）；`%.5f` 做 key 会在 1e-5 边界撞号（改用排序点云 + 容差）；新 `.import` 行尾 **LF**（与源 import 一致），`.tscn`/`.gd` 仍 CRLF。


## 天台地板换件 + 低一层外立面环 + 封闭西侧围栏缺口（2026-09-19/20 落地）

三件资产（**均为既有 AssetID 升行，不新增行**）：

| AssetID | prefab | GLB | 包络 / 原点 |
|---|---|---|---|
| `ENV-ROOFTOP-REF-FLOOR-FULL`（行97） | `prp_rooftop_floor_5m.tscn` | `env_rooftop_ref_floor_full_top3d.glb` | 5×0.3×5 / `bottom_center` |
| `ENV-ROOFTOP-REF-FACADE-SOLID`（行132） | `prp_rooftop_facade_solid_5m.tscn` | `env_rooftop_ref_facade_solid_top3d.glb` | 5×11.9×0.3 / `bottom_center` |
| `ENV-ROOFTOP-REF-FACADE-WINDOW`（行133） | `prp_rooftop_facade_window_5m.tscn` | `env_rooftop_ref_facade_window_top3d.glb` | 5×11.9×0.3 / `bottom_center` |

导出脚本 `tower_zones/rooftop/source/export_env_rooftop_ref_floor_facade_v001.py`。三件 `visual_only=true` / `collision_owner=TowerFloorStage3D` / `preserve_authored_palette=true`。

### 铁律① 换 prefab 前必须先量「新件原点契约」
新地板是 **`bottom_center`（几何 Y=0..0.30）**，旧 `POLISHED_FLOOR_SCENE` 是**几何中心**。
旧代码 `Vector3(x, -FLOOR_THICKNESS*0.5, z)` 对新件会**沉/浮半块**。
改法：`_floor_visual_origin_y(mesh) -> return -mesh.get_aabb().end.y`，用 AABB 把**顶面对齐 Y=0**。
⇒ 通用：**替换任何 prefab 前，先读新件 AABB 与 `origin_contract`，再决定摆放偏移**；不要假设沿用旧偏移。

### 铁律② 天台西侧楼梯洞是「内部洞」，不是「外墙门洞」
- 事实：楼梯洞 `Rect2(-45,0,15,30)` **整个在轮廓内部**，西墙（x=-50）到洞口还有 5m 通道。
- 旧代码误按「楼梯洞 = 外墙门洞」在西墙挖 3 段（z=10/15/20）塞系统占位矮墙 `ParapetDoorWall_West_*`（scale.y=1.2）→ 就是主人看到的「系统栏杆 + 缺口没连起来」。
- 改法：`_wall_side_has_door_gap(side) -> return side in stair_hole_sides and not _uses_rooftop_parapet_modules()`（对天台恒 false）；`_add_wall_collision` 也改用它 → 西墙碰撞由「断成两段」变**一条连续 Box**。
- 结果：直段 **61→64**、`ParapetDoorWall_*` **3→0**、`side=west segments=15 door_gap_indices=[]`、物理扫描 z∈[-30,40] 全部 x=-50.000 命中 `OuterBoundaryCollision_West`。
- ✅ 不挡下降：100F→99F 的下降沿在西侧，但用的是房间 `DungeonRoom3D` 的 `start` 房门，**不是 stage 外墙**。

### 铁律③ 外立面环（「99 层外墙」）= 天台同一圈、低一层 y=-12
- `_build_rooftop_facade_ring()`：同轮廓、`y=ROOFTOP_FACADE_BOTTOM_Y=-12.0`、内缩 `THICKNESS/2=0.15`（**外皮与女儿墙共面**）、节奏 **实 1 : 窗 2**（`index % 3 == 0` 为实墙）。
- 朝向约定（照抄 `reference_assembly.json`，与 prefab 声明的「装饰面朝外」自洽）：north(最小Z)=**PI**、south(最大Z)=**0**、west(最小X)=**-PI/2**、east(最大X)=**+PI/2**。
- 碰撞 `_install_rooftop_facade_collision()`：每边一个 `FacadeBoundaryCollision_{North/South/West/East}`，0.30m 厚 × 12m 高、中心 y=-6、内缩 0.15；四角互相咬合 0.3m 不留缝。
- 实测：`facade=68`（实 24 / 窗 44），四边 coverage 满、gap=0、overlap=0，`facade_bottom_y=-12.000`。
- 根因解释「看到底下是空的」：`Floor_99` 的 `_outer_world_rect` 是 **160×160（x -80..80）**，远在天台圈外 → 天台边缘（y=0）到 99F 楼面（y=-12）那条 12m 竖带**本来什么都没有**。

### 铁律④ 期望值必须由几何/常量推出，禁止硬编码
`probe_rooftop_parapet_damage_layout` 硬编码 `SLOT_COUNT_EXPECTED := 61`；封缺口后槽位 64 → **误红**（排布其实完全正常）。
正解：`_expected_straight_slot_count()` 由 `ROOFTOP_WORLD_RECT` + `ROOFTOP_CORNER_ARM_M` + 模块 5m 算出（`2×((90-5)/5) + 2×((80-5)/5) = 64`），再**与 stage 快照对账**（`outer_straight_slot_count`、`outer_doorway_wall_count`）。反向对照已做（`+1` → exit=1、两条断言同时红 → 还原）。

### 铁律⑤ 暗场景「这层渲染了没有」用**可见性 A/B 像素差**判
本场景雾重、立面与背景都是低对比灰 → 单看一张图**极易误判成「什么都没画」**。
做法（`probe_rooftop_facade_visual_ab`）：同机位拍两张（正常 / 把 `ImportedRooftopFacade{Solid,Window}Grid5M` 设 `visible=false`），`ImageChops.difference` 逐像素比。
- 实测 `changed=21730/921600 ratio=0.0236 max_delta=184` ⇒ `facade_rendered=true`。
- 判据用 `ratio >= 0.005`（立面占画面很大一块，真渲染必有显著差异）。
- ⚠️ 机位也要对：原 `02_edge_look_down` 相机 y=4，视线与 x=-49.75 相交处只有 ~2.85m（虽勉强越过 1.8m 女儿墙顶，但擦边）→ 改成 y=8 才稳妥。**「从天台边缘往下看」的机位必须让视线在与墙相交处明显高于女儿墙顶。**
- 截图类场景**不加 `--headless`**。

### 验证与台账
- 回归批跑 17 场景：绿 14；红 3 = **既有基线**（`verify_verification_runner_contract` 2 / `verify_base_world_flow` 4 / `verify_3d_performance_budget` 2），与上一轮 **marker 逐项相同** 且日志**零引用** `TowerFloorStage3D|rooftop_facade|prp_rooftop` ⇒ 与本次无关。**对基线要逐项比 marker 数 + grep 引用确认**，别只看「有没有红」。
- 契约门禁 `ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`（`[外立面环] plan solid=24 window=44 total=68 | actual 24/44`）；构件验收 `ROOFTOP_FLOOR_FACADE_COMPONENTS_PASS: 3 件 / 5 个表面`。
- 台账：`3D-场景通用` 只升既有 3 行（97/132/133：补 prefab/GLB 路径、碰撞归属、制作状态→正式美术已接入、原点改 Godot 口径、备注追加实测）+ `域变更日志` 追加 **v0.1.2 / 2026-09-19 / 资产升版**。
- ⚠️ **改台账 xlsx 安全手法**：①先 `cp` 快照 → ②改到临时文件 → ③与快照**逐格比对**（本次 21 处 diff 全为预期列；原本为空的路径列不产生 diff，故 3行×7格）→ ④确认无图表/图片（`zipfile` 列条目，本次仅 sheet3 一张 table 且未触碰）才落盘。
- ⚠️ 跑 openpyxl 脚本必须 **`cd` 到仓库外**（仓库根 `inspect.py` 遮蔽 stdlib `inspect` → openpyxl 导入崩、假报 `ModuleNotFoundError: bpy`）。
- ⚠️ 批跑脚本要 **`export PATH=.../Git/usr/bin:$PATH` 先于** `bash script.sh`（脚本内部 export 在 bash 启动之后才生效；否则 `bash`/`tee` not found）。
- ⚠️ **本文件（以及其它记忆 .md）禁止用 shell heredoc 追加**：本轮 `cat >> file <<'EOF'` 把文件头 51 行顶掉、正文被截断，靠「本会话自动备份」才救回。**一律用 Write/Edit 工具，或 Python 读 bytes 后拼接写回**（同目录 `_scratch/final/append_playbook.py` 就是这个安全范式）。
