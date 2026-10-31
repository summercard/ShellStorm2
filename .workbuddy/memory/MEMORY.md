# ShellStorm2 项目长期记忆

## Git / 工作区（多会话并发，踩过多次）
- 动手前先 `git -c core.quotePath=false status --porcelain -uall`，别信上一轮快照；已跟踪改动的「完成」必须以**提交**为准。
- 回退矢量：`git reset`（静默回退已跟踪改动）、`git pull --rebase`（把本地未提交改动「并」掉）。未跟踪文件不受影响。
- 远端领先时的顺序：**提交 → fetch → `rebase origin/<分支>` → push**。反过来会吃掉未提交改动。
- 推送唯一判据：`git fetch` 后 `HEAD` 与 `origin/<分支>` 逐字相同。含新大 LFS 对象时第一次 push 几乎必定「传完就断」（LFS 上去了 ref 没更），原样重跑一次即可。本机上行 46–515 KB/s，大批 blend 按小时排窗口；GitHub Free 1 GB/月。
- 高频冲突面：① `.workbuddy/memory/<日期>.md`（两侧块都留，按时间旧在前）；② `docs/v0.1/MODULE_INDEX.md` 的 `| FEATURE-ID |` 表格行（**逐行取各自较新一侧**，不是整块取一边）。
- 「僵尸冲突态」：有 `UU` 行 + `.git/REBASE_HEAD`/`AUTO_MERGE`，但无 `MERGE_HEAD`、无 `rebase-merge/`。判据 `git rev-list --left-right --count HEAD...origin/<b>` 为 `0 0` ⇒ 先备份，再 `git reset --hard HEAD` + `rm -f .git/REBASE_HEAD .git/AUTO_MERGE`。
- `.git/index.lock` 陈旧锁只会在首次写操作时暴露。删前需：无 git 进程 + `status --porcelain` 第一列全空。
- Godot 常驻会把 `.glb.import` 批量改写（新增 `mesh_library/use_node_names_as_mesh_names` 等）——引擎版本差异，**不要提交**。
- Godot `.gd.uid` 跨机器不一致：以仓库已跟踪版本为准；本机那份未跟踪会挡 rebase，先移走。本项目 `.tscn` 多用 `path=` 引用，uid 差异通常无影响。
- 改前备份：`.workbuddy/backup/<YYYYMMDD>_<主题>/`（`before_edits/` + 重放脚本）。

## 本机环境
- **Godot 在 `F:/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe`**（旧「本机没有引擎」的结论作废；另有 `F:/安装包/Godot_v4.6.3-stable_win64_console.exe`）。单跑用例 `--headless --path . res://tests/verification/<case>.tscn --quit-after 900`，并把 `APPDATA`/`LOCALAPPDATA` 指到 `F:/wxgame/ShellStorm2-work/verify_appdata` 隔离存档。
- **没有 `timeout` 命令**；长命令别用它包裹。
- 系统 `python3` 缺 `openpyxl`，而 `check_documentation_contracts.py` 用裸 `python3` 起子检查 ⇒ 造 ASCII 目录放 `python3` wrapper（`exec <venv>/bin/python "$@"`）前置进 PATH（`ln -s` 无效）。
- 门禁本就常红（既有债务），判据是**改动前后逐项数值相同 = 0 新增问题**，不是看退出码。
- 账本门禁：`scripts/check_asset_registry.py`、`tools/asset_pipeline/verify_ledger_split.py`、`scripts/check_asset_runtime_naming.py`；基线 `assets/registry/ledger_split_baseline.json` 需按 `refresh_current_baseline` 口径重建。

## 自动化接力（改时间要一起看）
23:50 工作总结写记忆 → **04:00 先 git 提交推送、再清空回收站**（不可逆必须排后）→ 05:00 打包发布。
分支是 `0.1.2` 不是 main。回收站清空后残余永不为 0（常驻探针每写档丢 `base_save.json.bak`），不是失败；`E:/G:/H:` 报 `OSError(22)` 属正常；`scan -o <中文路径>` 曾无声 SIGTERM ⇒ 走 stdout 重定向。

## 引擎/玩法约定
- **敌人受击体积不能挂在自己的 `CharacterBody3D` 上**：贴模型的盒子会伸进地面/墙里，`move_and_slide` 把怪顶起（实测抬 0.417 m）。做法＝另起 `StaticBody3D` 被动体（同层、`collision_mask = 0`），逐帧跟骨，命中转发回本体（`src/enemy3d/EnemyHitVolume3D.gd`）。转发清单是隐形契约，漏转发会静默不掉血。
- **同时必须把老碰撞体移出子弹层**（`collision_layer = 0`）：显示器 Boss 的固定圆柱半径 2.016 m 比可见屏幕宽得多，子弹在前方 1.0–1.3 m 就被吃掉。诊断＝打印 `collision.get_collider().name`。
- 层语义：1 = 静态世界/玩家，3（值 4）= 敌人，4（值 8）= 投射物。玩家子弹 mask = 5；所有视线/遮挡射线 mask = 1 ⇒ 加受击形状不影响视线。
- 实测 AABB 当碰撞盒要**每轴外扩 3 cm**（否则表面顶点落在边界被舍入判出，残余 1.85%）。
- 动画包络必须**逐帧**求（抽帧漏极值）；「单骨且权重恰 1.0」的刚性顶点才能定骨局部盒子（混合权重会把 `hand.L` 撑到 9.5 倍体积）。伸缩件例外。
- 验收探针要**冻结被测对象**：`set_physics_process(false)` + 手动 `_process` 同步，否则怪边走位边挨打量出 3 m 假误差。量命中精度瞄模型顶点、用**中位数**判回归。

## 远征03 美术层（2026-10-31 重构后的口径）
- **复用键 = `<模板>_<签名前12>_<原型指纹6>`**。第三段**不是门位**：门位来自
  `_shared_door_lane()` 的几何求交，每局都变（单模板实测 53 种组合）⇒ 旧键跨 24 种子
  缺口 335。原型是 `(room_type, 短边)` 的纯函数 + hub 特判，零随机。
- **墙/地砖由运行时生成**：`ManorShellPlan`（配方，只算不建）+ `DungeonRoom3D._rebuild_manor_shell()`
  （删掉美术层里 `manor_*` 再按本局门位重铺，幂等）。烘焙文件只承载装饰陈设
  ⇒ **工坊里拖墙/地砖不进游戏**。
- **窗位依赖门位**（`window_cells` 的 pair/double_pair/clerestory 都要避开门位格）
  ⇒ 换门位不是"换一块门墙"，整面墙序列都要重算。
- `start` 的 `procedural_shell=false` 走「整个静态场景照常用」分支：白盒件不剥、
  烘焙器原过滤会跳过它、`_instantiate_dynamic_room()` 的 config 也不带
  `art_layer_keep_structure` ⇒ 靠 `_build_shell()` 按路径推导。
- `_collect_spawn_blockers()` 的「地面豁免」阈值现为 `SPAWN_GROUND_TOP_MAX_M = 0.15`
  （原硬编码 0.05）：公馆地砖厚 0.1046、原点在底面中心，盒顶 0.1046 越线
  ⇒ **整间房地面被判成障碍** ⇒ `_resolve_spawn_position()` 返非有限值
  ⇒ `_spawn_enemy_batch()` 返回 -1 ⇒ 一只怪都不刷。**修美术覆盖必须连带跑
  `probe_expedition03_playable`**（它会把这条打出来）。
- **写死 `SEED` 的验收器 = 单样本，不是门禁**。远征03 覆盖必须跑
  `tools/_exp03_art_coverage_probe`（24 种子）；单种子 `_exp03_manor_shell_verify`
  全绿也可能 14/17 是白盒。
- 烘焙器：`--only=<room>` 单房、`--sweep` 跨 24 种子补齐（每个
  `(模板,签名,原型)` 只铺一次）。

## 探针/工具链的坑
- 裸 `Enemy3D.new()` 没有碰撞体（`@onready` 解析 null ⇒ `apply_profile` 整段跳过）⇒ 穿地板自由落体后被搬回出生点判死。表现极具欺骗性：满血、在出生点、只跑 26 帧。造怪一律 `instantiate()` 自 `enm_ecosystem_kit_root_top3d_v001.tscn`。
- 探针假玩家必须提供 `current_hp`，否则 `_target_is_legal()` 抛 `Nonexistent 'float' constructor`。
- 脚本解析失败 ⇒ 永不 `quit()` ⇒ headless 挂死。一律带 `--quit-after 600` 才能看到 `SCRIPT ERROR`。
- 周期/间隔指标只能用**墙钟** `Time.get_ticks_msec()`；按 `await physics_frame` 累加步长会快 N 倍。
- `_egt_cadence_probe` / `_egt_enemy_motion_probe` 刷 0 只怪仍报 OK ⇒ 逐只体检用 `tools/_egt_ai_flow_probe.gd`。`verify_monster_ai_system_complete` 有 2 条既有红项（token budget `1/0`、melee token 不复用），HEAD 同样红。
- **速度算术**：`_steer_planar(ZERO, delta×k)` + `_push_planar(v)` 是稳态放大器（稳态 ≈ v/(k·dt)，实测放大 11 倍）。「位移由外推决定」的 flee/grab/wander/immobile 应**直接赋值** `velocity.x/z`。把当前速度当 steer 目标（`clampf(len,…)` 恒等于 len）也是同类错，限速移动要用独立上限。这两类错只有逐只量「路程」才暴露。
- `tools/retune_egt_monsters.py --apply` 会写出重复 `projectile_speed` 行（GDScript 重复键不报错只取后者 = 改了没生效）⇒ 先 dry-run 看行数，落盘后清重复行。
- 换出厂枪改两处：`DEFAULT_STARTING_GUN_ID` + 剧本 `nar_tower_opening_01_wake` 的 `spawn_item.item_id`；持枪移速按枪族取（sidearm 0.5 / longgun 0.8 / machinegun 1.1）。

## VFX 与账本
- `VfxPool3D.create_unpooled()` 返回 `Node`，只丢引用不回收 ⇒ `Leaked instance` + 本项目 exit 4 红项，探针试完必须 `probe.free()`。`queue_free()` 排帧末而 `quit()` 不等最后一帧 ⇒ 探针自建场地/怪用 `free()`。
- 给特效账本加资产要改 4 处：① 《资产主表》行（T 列 SHA-256 = Prefab `.tscn` 的 sha256）；② 《3D-特效》分页（分组标题 + 数据行）；③ 《总览》公式区间**共 8 处**（`A6/C6/E6/G6` + `B10/C10/B11/C11`，后四条 SUMPRODUCT 分类统计，`overview_formula_scope_wrong` 专抓）；④ 基线 json + 写 `scripts/refresh_ledger_baseline_<tag>.py`。
- `verify_ledger_split.py` 的 `moved_sheet_mutated` 可能是「已提交但没刷基线」的历史遗留，先看 `git status`。

## 材质属性：变体 vs uniform（2026-10-31 实测，别再猜）
- **翻这些 = 重建 GPU 管线**（真渲染 `--disable-vsync`，单材质、一个实例）：`emission_enabled` +107ms、`transparency` +107、`vertex_color_use_as_albedo` +109、`no_depth_test` +105、`billboard_mode` +94、`depth_draw_mode` +86、`disable_receive_shadows` +77、`shading_mode` +19。
- **这些随便改**：`albedo_color` / `emission_energy_multiplier` / `roughness` / `cull_mode`，以及**实例级** `GeometryInstance3D.transparency`、`cast_shadow`（全 ≈0）。
- 规律：进 `MaterialKey` 的位才是变体。**不能按"听起来像不像结构属性"猜** —— `cull_mode` 不贵、`shading_mode` 只 19ms。
- 正确姿势：「灭/暗/淡出」一律用**能量、颜色、实例级 transparency** 表达，**不要在热路径翻开关**。开关只在**创建材质时**设一次。
- 门禁 `tools/_hit_flash_binding_probe.tscn`：判「表现层 `_materials` 的 instance_id == 渲染面 `get_active_material()` 的 id」。这是唯一能区分"写给自己看"和"写进画面"的断言 —— 本项目出过 `_apply_formal_tint()` 把 override 顶成孤儿、闪白全空但所有验收都绿的事故。
- 量帧时差必须 **真渲染 + `--disable-vsync`**，判 `hit_p50 − idle_p50` 差值。**headless 下材质变体根本不重建**，同一个 bug 全读 0 ⇒ headless 只能当报表，不能当门禁。
- `--script` 模式加载不了 autoload（`MonsterAIManager` 直接编译失败）⇒ 探针一律用 `--scene`。
- 美术资产脚本（`assets/art/**/runtime/*.gd`）别写裸全局类名，用 `const X := preload("res://src/...")`：资产脚本可能被单独实例化，`.godot` 类缓存不一定扫到。

## 管线缓存与资源弱引用（2026-10-31 实测，解释"每只怪都卡"）
- **管线缓存挂在使用中的材质实例上**：全释放后再建同变体要重付（101ms → 0.15 → 96ms → 0.15）。所以「每实例 new 材质」= 每次重建。`MaterialPipelineKeeper.pin()` 留一份长命引用即可，签名只取 `MaterialKey` 的位；**要先翻完变体开关再登记**。
- **`load()` 不是稳定引用**：资源缓存是弱引用，最后一个使用者释放后从磁盘重读（100~118ms/次）。静态字典缓存 PackedScene，别用 preload 铺启动。
- 这两条加起来 = 刷怪那一帧 100~300ms/只，**headless 只有 2ms** ⇒ 无渲染验收对它完全免疫，必须真渲染 + `--disable-vsync` 才看得见。
- **VFX 冷启动贵在"节点带材质进渲染场景"，不是绘制**：摆相机背后不绘制也照样 64ms。预热只需让它进一次树，`VfxPool3D.prewarm()` 逐帧一件。
