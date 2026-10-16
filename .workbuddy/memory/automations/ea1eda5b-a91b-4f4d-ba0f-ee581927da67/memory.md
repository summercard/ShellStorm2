# 每日打包发布 · 执行记录

任务：对 ShellStorm2 执行 `python scripts/daily_release.py`，覆盖发布固定站点
`shellstorm2-20261012-190519`（URL 不变）。

## 执行历史

### 2026-10-16 08:25 — 修复后发布**成功**（主人指令「修复测试一下」）
- 修复：`src/game/InsuranceModule.gd` 的 `_board.inventory_changed` 连接由「捕获 self 的 lambda」改为 `WeakRef` + 静态转发 `_relay_inventory_changed`，解开 `InsuranceModule ↔ InventoryModule` 的 RefCounted 引用环。`set_max_slots` 同步改，连接时机保持在 `restore_slots_snapshot` 之后。
- 修复后：①源码 headless 复跑 `^ERROR` 0 行 / `Resource still in use` 0 条 → ②导出 394.1 MiB → ③三道门禁全绿（**`SMOKE_OK`**）→ ④生成文档 → ⑤覆盖发布（`server-api-update`）→ ⑥线上校验通过。
- 包：`ShellStorm2.exe`，**413,202,552 B**，SHA256 `8d348a0c72ce720f85558599412b2ce3733854e123c5c2c9fd0250859f73dbfd`。
- 线上独立复验：直链 HEAD HTTP 200 / Content-Length 413,202,552（＝本地）/ Last-Modified `16 Oct 2026 00:29:31 GMT`；**整包下载 8.07s @51.2 MB/s，重算 SHA256 逐字节一致**；更新页 HTTP 200 / 19,427 B。站点列表仍只有 `shellstorm2-20261012-190519` 一个。
- 更新内容：CHANGELOG 14 条 / 提交 6 条 / 未提交 2 项（＝本修复 + 本记忆文件）。
- 功能回归：`verify_grid_inventory_layout`、`verify_runtime_autosave_flow` 均 rc=0；`verify_weapon_instance_fate_ownership_flow` 失败但**已证实与本修复无关**（用临时还原的修复前源码跑基线复现同一处 87 行越界）—— 根因是该用例写死 `InsuranceModule.new(2)`，格子化后装不下 `[4,2]` 的出厂枪（需 capacity ≥ 16），属夹具过期；生产默认 16/24 不受影响。未擅自改。
- 开发记录：`docs/v0.1/development/2026-10-16_insurance_module_refcount_cycle_fix.md`（新增）。
- 合规：`project.godot` 的 `config/name="弹壳风暴2"` 未改；无 commit/push；测试与冒烟全程隔离 `APPDATA`；未新建站点；线上临时下载文件已清理。

### 2026-10-16 08:19 — 重试，**同样失败**（主人指令「重试」）
- 源文件自 05:01 无变化（HEAD 仍 `595fee21`，泄漏模块 mtime 10-15 21:42/21:52）→ 结果与首次逐项一致：`run_headless.log:2780` 同一条 `ERROR: 2 resources still in use at exit.`，同样 2 个 .gd、26 个泄漏实例。**证明确非抖动。**
- 重试构建未发布包：413,202,136 B，SHA256 `02708b8e0c8aa96a4cef1c94d860d2f9ee726a01f2a988452c406d2f5a6a7412`。
- **根因已定位到代码行**：`src/game/InsuranceModule.gd:9/13/20` —— `_board.inventory_changed.connect(func(): insurance_changed.emit())` 中 lambda 闭包捕获 `self`，被存进 `_board` 的信号表，与 `InsuranceModule → _board` 的强引用构成 **RefCounted 引用环**；Godot 纯引用计数无环收集 ⇒ 两实例永远不归零 ⇒ 正好 2 个脚本资源未释放。与外部持有者 `Dungeon3D._insurance` 无关。
- 修法（行为不变，反向引用改弱）：`static func _relay_inventory_changed(owner_ref: WeakRef)` + `_board.inventory_changed.connect(_relay_inventory_changed.bind(weakref(self)))`；`set_max_slots` 连接时机保持在 `restore_slots_snapshot` 之后。**未擅改源码，待主人确认。**
- 线上仍未被覆盖：411,913,504 B / Last-Modified 10-14 23:40 GMT（＝10-15 版）。
- 报告已更新（含重试对比表与完整补丁）：`发布失败报告_2026-10-16.md`

### 2026-10-16 05:01 — 失败（发布中止，线上保持 10-15 版）
- 卡点：**第 2 步验证的第 3 道门禁**（隔离冒烟 `smoke_exported_pack.py`），退出码 1。①②静态门禁均通过。
- 包：导出成功 394.0 MiB（413,093,856 B），SHA256 `d6a248663920e435912435e12bdcc724a8233d54d4cf4bb262211361f11cb734`，**未发布**。
- 失败原文：`SMOKE_FAILED / ❌ 日志出现 1 行 ERROR` → `ERROR: 2 resources still in use at exit`。泄漏资源为 `res://src/game/InventoryModule.gd`、`res://src/game/InsuranceModule.gd`。
- 性质：**不是启动即失败**（退出码 0、存档新建 revision=4、无 Can't open/启动失败/Failed loading）。是退出期脚本资源未释放。10-14/10-15 均 SMOKE_OK，故为**本轮新回归**（10-15 20:30–23:20 背包/保险 UI 提交）。
- 确定性：重跑冒烟复现同一条 ERROR，非抖动。导出未失败，故未触发「重试一次」。
- 线上：直链 HTTP 200 / Content-Length 411,913,504（＝10-15 版 SHA256 `1e501fa2…`，Last-Modified 10-14 23:40 GMT）；更新页 HTTP 200 / 30,425 B。**未被覆盖。**
- 更新内容（本应发布）：CHANGELOG 14 条 / 提交 7 条（折叠 1）/ 未提交 0 项。
- 报告：`I:\工作项目\shellstrom2\ShellStorm2-work\outputs\daily_release\发布失败报告_2026-10-16.md`
- 合规：project.godot `config/name="弹壳风暴2"` 未改；无 commit/push；隔离 APPDATA；未新建站点。

### 2026-10-15 07:40 — 成功
- 流水线：导出 392.8 MiB → 三道验证全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。
- 包：`ShellStorm2.exe`，411,913,504 B，SHA256 `1e501fa2b5014328c6823c70c39b3beae56775279da11fdd151d32faa097612d`。
- 线上独立复验：直链 HEAD HTTP 200 / Content-Length 一致；**整包下载（393 MiB，~50 MB/s）重算 SHA256 逐字节一致**；更新页 HTTP 200（30,425 B）。
- 更新内容：CHANGELOG 18 条 / 提交 12 条（另 5 条折叠）/ 未提交改动 16 项。
- 主条目（12 条独立标题）：武器链路中文化 UI-LOCALE-TEXT、背包胸前挂点修复、剩余物品双模型接入、血条延迟白段+小怪×0.80+Boss上移、胖子僵尸自爆 VFX+伤害场、怪物启动过渡+吼叫图标、枪械射程字段独立化、新增初始步枪替换出厂配发、已购命运卡灰阶压暗70%、门后命运卡买后翻背、命运卡改局内魂购买制、警察僵尸数值+货币独立掉落、远征01 monster_rules、远征01 Boss房换深井竞技场、Boss房南进端口重对、竞技场首领一死即开闸、调试相机复位键 R→F12。
- 备注：`project.godot` 的 `config/name="弹壳风暴2"` 未改动（存档目录契约）；无 git commit/push；无重试。

### 2026-10-14 05:03 — 成功（首次记录）
- 流水线：导出 378.6 MiB → 三道验证全绿 → 生成文档 → 覆盖发布 → 线上校验通过。
- 包：`ShellStorm2.exe`，397,024,440 B，SHA256 `4fea10686f886d8d9a332a1ded69105cc3bf476d61d49607b76d4675ace7cc27`。
- 线上独立复验：直链 HTTP 200 / Content-Length 一致；另**整包下载重算 SHA256 与本地逐字节一致**；更新页 HTTP 200。
- 更新内容：CHANGELOG 15 条 / 提交 12 条 / 未提交改动 19 项。
- 备注：`project.godot` 的 `config/name="弹壳风暴2"` 未改动（存档目录契约）。

## 关键坐标（复用）
- 工程根：`I:\工作项目\shellstrom2\ShellStorm2`
- 产物目录：`I:\工作项目\shellstrom2\ShellStorm2-work\outputs\daily_release`
- Godot：`I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe`（脚本自动回退定位）
- 发布 skill 客户端：`C:\Users\zhuangmenghong\.workbuddy\skills\sofunny-resource-sharing\scripts\publish.py`
- 发布耗时约 3.5 分钟（导出占大部分），需后台运行。

## 经验
- 线上校验不要只靠脚本的 HEAD：本次额外做了「整包下载 + SHA256 比对」才算真正闭环（成功日适用；失败日只需 HEAD 确认线上未被覆盖）。
- `--skip-build` 可复用已有 exe，仅做验证+生成+发布。
- **冒烟的 ERROR 门禁会抓到「退出期资源泄漏」**（`ERROR: N resources still in use at exit`）。它不阻断启动，但按硬约束 1 同样中止发布。排查法：看 `run_headless.log` 里 `Resource still in use:` 指向哪几个 .gd。
- 单跑冒烟（无需重建）约 20 秒：`python scripts/smoke_exported_pack.py <exe> --keep`，适合失败后快速确认是回归还是抖动。
- **改代码前先做源码级快验，比重建省 3 分钟**：`APPDATA=<工程外空白目录> "$GODOT" --headless --path <ROOT> --quit-after 900 --verbose > log 2>&1`，再 grep `^ERROR` 与 `Resource still in use`。泄漏类问题在源码层与导出包上表现一致。
- **RefCounted 成环是这个工程的复发型陷阱**：`A` 持 `B`，又把捕获 `A` 的 lambda `connect` 到 `B` 的信号 ⇒ 环闭合，Godot 纯引用计数不回收，退出报 `N resources still in use at exit`（N = 泄漏文件数）。改法：`WeakRef` + `static` 转发。
- **判断「是不是我改坏的」用临时还原跑基线**：`cp` 备份 → `git stash push -- <文件>` → 跑同一用例 → `git stash pop` → `diff -q` 校验与备份逐字节一致。零风险，别猜。
- **`run_verification_suite.sh` 在本机会被 safe-delete 拦截**：其收尾清理触发「单轮 50 项批量删除需确认」，套件在拷贝工作区阶段即中止。改用直接跑场景：`APPDATA=<隔离> "$GODOT" --headless --path <ROOT> --scene res://tests/verification/<name>.tscn`。
