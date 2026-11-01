# ShellStorm2 项目长期记忆

> 只留跨会话必须知道的硬结论；明细见 `.workbuddy/memory/<日期>.md` 与 `docs/v0.1/development/`。

## Git / 工作区（多会话并发）
- 先 `git -c core.quotePath=false status --porcelain -uall`；已跟踪改动的「完成」**以提交为准**。分支 `0.1.2`，不是 main。
- 远端领先：**提交 → fetch → `rebase origin/<分支>` → push**。用户说「推送」常等于「先提交再推」（HEAD 0 ahead 但工作区上千项）。
- 判据：`git fetch` 后 HEAD 与 `origin/<分支>` 逐字相同。含大 LFS 对象时首次 push 几乎必「传完就断」，原样重跑。上行 46–515 KB/s。
- 冲突面：① `.workbuddy/memory/<日期>.md`（两侧块都留，旧在前）；② `MODULE_INDEX.md` 的 `| FEATURE-ID |` 行（**逐行取较新一侧**）。
- 僵尸冲突态（`UU` + `REBASE_HEAD` 但无 `MERGE_HEAD`/`rebase-merge/`，且 `rev-list --count` 为 `0 0`）：备份后 `reset --hard HEAD` + `rm -f .git/REBASE_HEAD .git/AUTO_MERGE`。
- **`*.import` 引擎改写不入库**：Godot 4.7.2 常驻全量重导入，给每个 glb 加三行默认键。判据 `numstat` 得 `+3N/−0`。提交用 `git add -A -- . ':(exclude)**/*.import'`；**别 `checkout --` 洗**（mtime 一变触发全量重导入）。
- `.gd.uid` 挡拉取：`diff --diff-filter=A ... | grep '\.uid$'` ∩ `status --porcelain`，`git show origin/<b>:<f>` 比内容，**一致直接删**；孤儿 uid（宿主已删）备份后清。
- 跨夜记忆可能丢：04:00 前写的段落若被 `reset --hard`/远端覆盖会静默消失，判据 `git log --oneline -- <file>`。
- `.workbuddy/` 除 `tmp/` 都入库；技能三处镜像必须逐字相同＝`.codex/skills` + `skills_drafts` + `.workbuddy/skills`。改前备份 `.workbuddy/backup/<YYYYMMDD>_<主题>/`。

## 本机（两台，别混）
- **macOS**：Godot `/Applications/Godot.app/Contents/MacOS/Godot`（4.7.2.stable）。**无 git-lfs/brew/sudo** ⇒ `art_source/**/*.blend|*.psd` 全是 131B 指针（1284 个），`assets/` 运行资产不受影响。判伪别用 `git lfs ls-files`（未装时静默返 0），用 `head -c 20 <f> | grep git-lfs`（不能 grep 整串）。
- **Windows**：Godot `F:/Godot/4.7.2-stable/...win64_console.exe`；单跑 `--headless --path . res://tests/verification/<case>.tscn --quit-after 900`，`APPDATA`/`LOCALAPPDATA` 指 `F:/wxgame/ShellStorm2-work/verify_appdata`。
- 两台都**无 `timeout`**；`ps` 被禁，查端口用 `lsof -nP -iTCP:<port> -sTCP:LISTEN`。
- 系统 `python3` 缺 `openpyxl`（`check_documentation_contracts.py` 用裸 `python3`）⇒ 造 ASCII 目录放 wrapper（**独立普通文件**，绝不能 `>` 写到符号链接）；`ln -s` 无效。
- **门禁本就常红**：判据是改动前后逐项数值相同 = 0 新增，不看退出码。

## 自动化接力
23:50 写记忆 → **04:00 先提交推送、再清回收站**（不可逆排后）→ 05:00 打包。回收站残余永不为 0 不是失败；`E:/G:/H:` 报 `OSError(22)` 正常；`scan -o <中文>` 曾无声 SIGTERM ⇒ 走 stdout。

## 碰撞与命中体积
- **受击体积不能挂在怪自己的 `CharacterBody3D` 上**：贴模型盒子伸进地面/墙，`move_and_slide` 把怪顶起（0.417 m）。另起 `StaticBody3D` 被动体（同层、`collision_mask = 0`）逐帧跟骨、命中转发回本体（`src/enemy3d/EnemyHitVolume3D.gd`）；转发清单是隐形契约，漏转发静默不掉血。
- **老碰撞体必须移出子弹层**（`collision_layer = 0`）：Boss 圆柱半径 2.016 m 比屏幕宽，子弹 1.0–1.3 m 就被吃。诊断打印 `collision.get_collider().name`。
- 层：1 = 世界/玩家，3（值 4）= 敌人，4（值 8）= 投射物；玩家子弹 mask = 5，视线射线 mask = 1。
- AABB 当碰撞盒**每轴外扩 3 cm**（否则顶点被舍入判出，残余 1.85%）。动画包络必须**逐帧**求；只有「单骨权重恰 1.0」的刚性顶点能定骨局部盒（混合权重把 `hand.L` 撑到 9.5 倍），伸缩件例外。
- 探针要**冻结被测对象**（`set_physics_process(false)` + 手动同步），否则量出 3 m 假误差；命中精度瞄模型顶点、用**中位数**。

## 「动画抽一下」先分类再改
- 三类：① 数据（首末帧相同 ≠ 平滑，量**单帧步长**与 `Hip.dY` 峰值）；② **换段无过渡**（最常见）；③ 分母被玩法阶跃改写（`get_effective_move_speed()` 手电照到**阶跃** ×0.40，与指数衰减的真实速度不同步 ⇒ 瞬穿 `RUN_SPEED_RATIO=0.62`）。
- **② 三件套**：ⓐ `fmod(_clock, 段长)` 绝对时钟 ⇒ 走路 1.6s / 跑步 0.8s 把同一时刻映射到差 35~67° 的姿势 ⇒ 换**跨段保留的归一化相位**；ⓑ 手臂垂摆 vs 抬起相位对齐**消不掉** ⇒ 必须 `play(name, blend)`（60.4°→0.0°），但攻击/受击/死亡不参与（判定帧靠 seek 钉）；ⓒ 迟滞（进 0.62 / 出 0.50）。
- **`MANUAL` 模式下单独 `seek()` 不驱动骨架**：`play()+seek()` 成对或 `advance()`。同段**不能每帧 `play()`**（打断淡化）；淡化期**不能 `seek()`**，要 `advance(delta)`。
- 别信"像冻结"的读数：0.04° 中位跳变 = 骨架没被驱动（判活读 `Hip.Y` 走路段应有 0.40~0.44 波动）。GLB 无 post-import 脚本时 `loop_mode` 全 `LOOP_NONE` ⇒ 相位恒 0 **画面定格**，`_ready()` 钉 `LOOP_LINEAR`。

## 远征03 美术层
- **复用键 = `<模板>_<签名前12>_<原型指纹6>`**。第三段**不是门位**（门位来自 `_shared_door_lane()` 几何求交，每局都变，单模板 53 种）⇒ 旧键跨 24 种子缺口 335。原型是 `(room_type, 短边)` 纯函数 + hub 特判。
- **墙/地砖运行时生成**：`ManorShellPlan`（配方）+ `_rebuild_manor_shell()`（删 `manor_*` 按本局门位重铺，幂等）；烘焙文件只承载陈设 ⇒ **工坊拖墙/地砖不进游戏**。窗位依赖门位 ⇒ 换门位要整面墙重算。
- `start` 的 `procedural_shell=false` 走「整个静态场景照常用」：白盒件不剥、烘焙器过滤会跳过、config 不带 `art_layer_keep_structure` ⇒ 靠 `_build_shell()` 按路径推导。
- `SPAWN_GROUND_TOP_MAX_M = 0.15`（原 0.05）：公馆地砖厚 0.1046、原点在底面中心 ⇒ 盒顶越线 ⇒ 整间地面判障碍 ⇒ 出生点非有限值 ⇒ `_spawn_enemy_batch()` 返 -1（一只不刷）。**修美术覆盖必须连带跑 `probe_expedition03_playable`**。
- **写死 `SEED` 的验收器 = 单样本**。覆盖跑 `tools/_exp03_art_coverage_probe`（24 种子）；单种子全绿也可能 14/17 白盒。烘焙器 `--only=<room>` / `--sweep`。布局预检查**别用 `ResourceLoader.exists(f00_<room>_static_layout.tscn)`**（那是目录锚点，真美术在 `runtime_rooms/`），用 `has_runtime_room_art()` 枚举（含 `.scn/.res/.remap` 免疫导出转二进制），否则单局 641 条误报。
- **门墙/连接归种子与装配；陈设（含 `Furn_*`）与作者灯光归正式 TSCN**，禁止运行时删重摆（契约 `src/world3d/RoomArtLayoutContract.gd`）。三间冻结房（入口15×15 / 事件25×25 / 大堂45×40）默认退出后续选房与批量烘焙。

## 探针 / 工具链
- 裸 `Enemy3D.new()` 无碰撞体（`@onready` null ⇒ `apply_profile` 跳过）⇒ 穿地板后搬回出生点判死，表现骗人（满血、只跑 26 帧）。一律 `instantiate()` 自 `enm_ecosystem_kit_root_top3d_v001.tscn`；假玩家要给 `current_hp`。
- 脚本解析失败 ⇒ 不 `quit()` ⇒ headless 挂死，一律 `--quit-after 600` 才见 `SCRIPT ERROR`。`--script` 加载不了 autoload ⇒ 用 `--scene`。
- 周期/间隔只能用**墙钟** `Time.get_ticks_msec()`；按 `await physics_frame` 累加会快 N 倍。
- `_egt_cadence_probe` / `_egt_enemy_motion_probe` 刷 0 只怪仍报 OK ⇒ 逐只体检用 `tools/_egt_ai_flow_probe.gd`。
- **速度算术**：`_steer_planar(ZERO, delta×k)` + `_push_planar(v)` 是稳态放大器（≈ v/(k·dt)，实测 11 倍）。「位移由外推决定」的 flee/grab/wander/immobile 应**直接赋值** `velocity.x/z`；拿当前速度当 steer 目标（`clampf(len,…)` 恒等）同类错，限速用独立上限。只有逐只量「路程」才暴露。
- `_physics_process` 在 `_target == null` 时提前 return 会跳过转向 ⇒ `_tick_search/_return/_patrol` 各补一次。朝向用 `move_and_slide()` **之后的位置差**（不能用 `velocity`，撞墙时仍指墙外）。
- `retune_egt_monsters.py --apply` 会写重复 `projectile_speed` 行（重复键静默取后者 = 没生效）⇒ 先 dry-run，落盘后清。换出厂枪两处：`DEFAULT_STARTING_GUN_ID` + 剧本 `nar_tower_opening_01_wake` 的 `spawn_item.item_id`；持枪移速 sidearm 0.5 / longgun 0.8 / machinegun 1.1。

## 材质与管线代价（实测，别猜）
- **翻这些 = 重建 GPU 管线**（ms）：`emission_enabled` 107、`transparency` 107、`vertex_color_use_as_albedo` 109、`no_depth_test` 105、`billboard_mode` 94、`depth_draw_mode` 86、`receive_shadows` 77、`shading_mode` 19。**随便改**：`albedo_color` / `emission_energy_multiplier` / `roughness` / `cull_mode`，及**实例级** `GeometryInstance3D.transparency`、`cast_shadow`（≈0）。规律＝进 `MaterialKey` 的位才是变体，**不能按名字猜**。
- 「灭/暗/淡出」用**能量、颜色、实例级 transparency** 表达，**不在热路径翻开关**；开关只在建材质时设一次。
- **管线缓存挂在"使用中的材质实例"上**：全释放后再建同变体要重付（101→0.15→96→0.15ms）⇒ 每实例 new 材质 = 每次重建；`MaterialPipelineKeeper.pin()` 留长命引用，签名只取 `MaterialKey` 的位，且**先翻完开关再登记**。
- **`load()` 不是稳定引用**（资源缓存弱引用，末位释放后重读盘 100~118ms）⇒ 静态字典缓存 PackedScene。
- 合起来 = 刷怪 100~300ms/只，**headless 只 2ms** ⇒ 无渲染验收完全免疫。**headless 只能当报表不能当门禁**（变体不重建，同 bug 全读 0）；计时必须真渲染 + `--disable-vsync`。
- **VFX 冷启动贵在"节点带材质进渲染场景"，不是绘制**（相机背后不绘制也 64ms）⇒ `VfxPool3D.prewarm()` 逐帧一件，与影子怪预热合并成一条循环。
- 门禁 `tools/_hit_flash_binding_probe.tscn`：判「表现层 `_materials` 的 instance_id == 渲染面 `get_active_material()`」。唯一能区分"写给自己看"和"写进画面"的断言 —— 出过 `_apply_formal_tint()` 把 override 顶成孤儿、闪白全空但验收全绿。
- 美术资产脚本（`assets/art/**/runtime/*.gd`）别写裸全局类名，用 `const X := preload("res://src/...")`。

## VFX 与账本
- `VfxPool3D.create_unpooled()` 返回 `Node`，只丢引用不回收 ⇒ `Leaked instance` + exit 4 红项，探针试完必须 `probe.free()`；`queue_free()` 排帧末而 `quit()` 不等最后一帧。
- 特效账本加资产改 4 处：① 《资产主表》行（T 列 SHA-256 = Prefab `.tscn` sha256）；② 《3D-特效》分页；③ 《总览》公式区间**共 8 处**（`A6/C6/E6/G6` + `B10/C10/B11/C11`，后四条 SUMPRODUCT，`overview_formula_scope_wrong` 专抓）；④ 基线 json + `refresh_ledger_baseline_<tag>.py`。
- 房间账本记「保留日期 + SHA 快照」；SHA 漂移**单列 T 列待核对**、不改原 M 列、不宣称重新验收。
- `verify_ledger_split.py` 的 `moved_sheet_mutated` 可能是「已提交但没刷基线」的历史遗留，先看 `git status`。
