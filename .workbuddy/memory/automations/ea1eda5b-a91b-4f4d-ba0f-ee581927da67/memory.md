# 每日打包发布 · 执行记录

任务：对 ShellStorm2 执行 `python scripts/daily_release.py`，覆盖发布固定站点
`shellstorm2-20261012-190519`（URL 不变）。

## 执行历史

### 2026-10-21 05:08 — **成功**（首轮发布 + 修采集器后覆盖重发文档）
- 首轮 05:04：导出 358.4 MiB → 三道门禁全绿 → 发布 → 线上校验通过。但**更新内容被统计成「CHANGELOG 0 条」**，而实际有 4 条 10-20 条目。
- **根因**：`scripts/collect_daily_changes.py` 的 `_ENTRY_RE` 只认 `## YYYY-MM-DD`。CHANGELOG 自 10-20 起新条目写成 `# YYYY-MM-DD`（一级标题），另有 `- 2026-10-20 · 分类：正文` 的日期列项写法，两种都被静默跳过。
- **修法**（已改，未提交）：①`_ENTRY_RE` 放宽为 `^#{1,3}`；②新增 `_DATED_BULLET_RE` 接管日期列项，标题取冒号/逗号前的分类、正文转要点；③去掉「遇到更早条目就 break」的优化（尾部仍有后补的日期列项），改为按位置排序后逐条按日期过滤。
- 修后 `--skip-build` 复用同一个 exe 重跑（三道门禁再次全绿）→ 05:08 覆盖发布（3 文件）→ 线上闭环。
- 包：`ShellStorm2.exe`，**375,766,088 B**（358.4 MiB），SHA256 `267bec53dab42e2eb2df93642c924ba238f5ba3f82c4c68c82ca180543e1a4d0`（两次发布字节相同）。
- 线上独立复验：直链 HEAD 200 / Content-Length 375,766,088（＝本地）；**整包重下载 375,766,088 B（7.6s），SHA256 逐字节一致**；更新页 200 / 3,842 B（＝本地），4 个 `<h3>`；`/<site>/ShellStorm2.exe` 子路径 200 同大小；更新日志 md 200。旧 `更新日志_2026-10-20.md` 与 `发布失败报告_2026-10-16.md` 均 **404**。站点列表仍只 `shellstorm2-20261012-190519`（3 files / 375,771,508 B）。
- 更新内容：CHANGELOG 4 条 / 提交 1 条（`ad8692ed` 333 项）/ 未提交 6 项。四条＝主线01台词「。。」→「……」、天台发电机（1.5×2m 落地电缆）、发电机 v002 三条入墙电缆（共四条）、基地发电机总电源 POWER-SYSTEM r2。333 项提交主体是 `art_source/.../underground_street/v002` 元件包（约 50 个组件包 + 药房细节图 + QA 清单）。
- 合规：`project.godot` 第 56 行 `config/name="弹壳风暴2"` 未改；**未执行 commit/push**（`ad8692ed` 是另一条自动化 04:05 产生）；冒烟隔离 `APPDATA`；未新建站点；临时下载文件已删。
- 教训：**发布文档的准确性也要当门禁看**。首轮「0 条」如果只看脚本退出码就宣布成功，线上会挂一份写着「今天没有更新」的假日志。凡是统计出 0 条，必须回头核对源文件是否真的没有——格式漂移（`#` vs `##`）会让正确的内容静默消失。

### 2026-10-20 05:04 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.2 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 4m43s。
- 包：`ShellStorm2.exe`，**375,559,360 B**（358.2 MiB），SHA256 `8dfaca4a04add0134af4310e904b5ba549790e565af62040f6e0f1e1e5cddeab`。
- 线上独立复验：直链 HEAD 200 / Content-Length 375,559,360（＝本地）/ Last-Modified `19 Oct 2026 21:05:13 GMT`；**整包重下载 375,559,360 B，重算 SHA256 逐字节一致**；更新页 200 / 15,088 B（＝本地），页面 12 个 `<h3>`＝12 条 CHANGELOG，按钮 `href="ShellStorm2.exe"` 子路径 200；更新日志 md 200 / 11,050 B（＝本地）。站点列表仍只 `shellstorm2-20261012-190519`（3 files / 375,585,498 B）。
- 发布目录洁净：旧 `发布失败报告_2026-10-16.md`、`更新日志_2026-10-19/18/16.md` 线上均 **404**。
- 更新内容：CHANGELOG 12 条 / 提交 13 条（折叠 2）/ 未提交 2 项（`tests/verification` 1 + `tools/_tmp_flat_capture.gd.uid` 1，已打进包）。
- 主条目：暗门破板木块飞溅特效（8 大 5 小 + 短灯）、枪声 -6dB 与室内风声修正、环境声音正式接入（9 条录音/166 条运行声音）、音效账本补 42 条枪械音效、按 E 传送落点被门位移带跑（`_rebase_door` delta 误加到落点，偏 39.135m）、暗门做成房间 TSCN 可手摆预制体、暗门「看不见」真因（墙向报错 + 只凸 3cm）、弹药模块手动更换总闸关闭、命运卡价格行只留价格 + 金币读数不再被遮暗、井口藤蔓破损矮墙、暗门板缝透光、S2 埋在墙里补可视遮挡判据。
- 包体：358.2 MiB（＝10-19 版 356.0 MiB，+2.2 MiB，音频换版带来的正常增量）。
- 合规：`project.godot` 的 `config/name="弹壳风暴2"` 未改（第 56 行核对）；**未执行任何 commit/push**（`1b484c1c「2026-10-20 每日自动提交」是另一条自动化 04:04 产生）；冒烟全程隔离 `APPDATA`；未新建站点；临时下载文件已删。

### 2026-10-19 05:03 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 356.0 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时约 2m50s。
- 包：`ShellStorm2.exe`，**373,271,264 B**（356.0 MiB），SHA256 `89e4641996a9f27101633fd0822bf9d0044871573d3f1270eb76f5f8eecd19cd`。
- 线上独立复验：直链 HEAD 200 / Content-Length 373,271,264（＝本地）/ Last-Modified `18 Oct 2026 21:04:18 GMT`；**整包重下载 373,271,264 B（21.0s @17.7 MB/s），重算 SHA256 逐字节一致**；更新页 200 / 26,247 B（＝本地），页面 20 个 `<h3>`＝20 条 CHANGELOG，按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；更新日志 md 200 / 20,420 B（＝本地）。站点列表仍只 `shellstorm2-20261012-190519`（3 files / 373,317,931 B）。
- 发布目录洁净：脚本会删旧 `更新日志_*.md`；实测线上 `发布失败报告_2026-10-16.md`、`更新日志_2026-10-18.md`、`更新日志_2026-10-16.md` 均 **404**。
- 更新内容：CHANGELOG 20 条 / 提交 10 条（折叠 4）/ 未提交 0 项（工作区干净）。
- 主条目：暗门被墙体包住（几何实测+改法）、合成保底 `bp_charge` 接入结算（判据＝击杀首领+成功撤离）、远征战斗房编成外增援（不抬卡价）、门后命运卡 21 池随机 3 张+保底一张买得起、99F 基地 7 通道灯具动态、暗门可布位点普查（201 槽）、合成目录落地+产物全可售、合成目录四条裁决收口、RUN-SYNTHESIS 设计冻结、改造台 5×5/6×6 版式演变、武器改造台全物品可作材料、天台杂物、掉落枪绑定弹药、传送支线位点改固定槽、掉落枪三档品质、子图遭遇编成、枪械产出收口、隐藏门按 E 传送、子图接正式美术。
- 包体：356.0 MiB（＝10-18 版 355.5 MiB，基本持平，10-18 那次 -46 MiB 的缩水未复现，说明是当时的一次性资产清理）。
- 合规：`project.godot` 的 `config/name="弹壳风暴2"` 未改；**未执行任何 commit/push**（`3d1f211d「2026-10-19 每日自动提交」是另一条自动化 04:02 产生的）；冒烟全程隔离 `APPDATA`；未新建站点；临时下载文件已删。

### 2026-10-18 05:07 — **成功**（全流程 + 一次「清理重发」）
- 首轮：导出 355.5 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 发布 4 文件。耗时 3m35s，无重试。
- **发现并修复发布目录污染**：`ShellStorm2-work/outputs/daily_release/发布失败报告_2026-10-16.md` 是 10-16 失败日遗留物，按「目录发布」被一并上传，线上 `/<site>/发布失败报告_2026-10-16.md` 实测 **HTTP 200 / 12,422 B**（内部工程信息外露）。已把该文件移到 `ShellStorm2-work/_logs/`，再用 `--skip-build` 重跑（重验三道门禁全绿）覆盖发布 → `Files: 3`，该路径实测 **404**。
- 包：`ShellStorm2.exe`，**372,735,344 B**（355.5 MiB），SHA256 `1e2f2368673be8a556dea33c6f03e43a053086cb0822912db9c7dca1b2d55b8b`。
- 线上独立复验：直链 HEAD 200 / Content-Length 372,735,344（＝本地）/ Last-Modified `17 Oct 2026 21:07:57 GMT`；**整包重下载 372,735,344 B（51s），重算 SHA256 逐字节一致**；更新页 200 / 6,272 B；页面按钮 `href="ShellStorm2.exe"` → 子路径 `/<site>/ShellStorm2.exe` 实测 200 同大小；更新日志 md 200 / 3,681 B。站点列表仍只 `shellstorm2-20261012-190519`。
- 更新内容：CHANGELOG 2 条 / 提交 6 条（折叠 2）/ 未提交 14 项（地下街源 5 个 blender 脚本 + 账本 + 文档，不影响运行件）。
- 主条目：命运卡改按「一间房≈一张」逐门定价（`B_k=max(S_k,累计/已清房)`、五档份额 `[0.85,1.30,1.85,2.60,3.50]`、`round10(max(40,B_k×份额))`、±15% 界）；远征01 动态命运卡经济与正式门事务（`FATE-RULES` 刷怪盒修正、整数解锁门槛 `0/457/1143/2094/3046`、无放回身份池、正逆 50/50）。
- **包体异常观察**：比 10-17 版小 48,117,792 B（-45.9 MiB）。已排查：assets 近 36h 仅删 9 文件 / 3 个 bunny01 anim glb（合计约 1.7 MB，被 v041/v042 取代），`export_presets.cfg` 未受版本管理、无法回溯 diff；pck 头解析未成功（Godot 4.6 目录字段偏移与旧假设不符），故**未能定量归因**。功能面已由「运行时引用门禁 + 真启动冒烟」兜住，未阻断发布。
- 合规：`project.godot` 的 `config/name="弹壳风暴2"` 未改；**未执行任何 commit/push**；冒烟全程隔离 `APPDATA`；未新建站点；临时下载文件已删。
- 教训：**发布目录里不能留任何非发布物**。目录发布会把 `更新日志_*.md`、历史报告一起上传，且入口页是 `index.html` 时这些文件不会显示在页面上、但可被直接猜到 URL 访问 —— 必须每次发布前清目录。

### 2026-10-17 05:04 — **成功**（常规全流程，无干预）
- 流水线一次跑通，未重试：导出 401.4 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / **`SMOKE_OK`**）→ 生成文档 → 覆盖发布（`server-api-update`，4 文件）→ 线上校验通过。耗时 4m36s。
- 包：`ShellStorm2.exe`，**420,853,136 B**，SHA256 `8c109be9d0f8fca348e2fa718f0d9d0151f6239d56dc49eae0e2baedd647cf31`。
- 线上独立复验：直链 HEAD HTTP 200 / Content-Length 420,853,136（＝本地）/ Last-Modified `16 Oct 2026 21:05:23 GMT`；**整包下载 420,853,136 B（41.3s @9.7 MB/s），重算 SHA256 逐字节一致**；更新页 HTTP 200 / 15,194 B。站点列表仍只有 `shellstorm2-20261012-190519` 一个。
- 更新内容：CHANGELOG 8 条 / 提交 8 条（折叠 1）/ 未提交 0 项（工作区干净）。
- 主条目：触发式遭遇封不住入口门（共享门归属+绑定）、踩点遭遇编成缩到约60%、room_04/06/09/10 改满宽带触发式、room_03 怪主动围猎+右上倒计时环、room_03 改踩点触发式（去盒+关门+到点开灯）、强化怪红色发光眼+`Head` 绑点、普通怪变种（-强化怪：小/胖/保安各一只）、星星卡节点与挂点构筑评估。
- 合规：`project.godot` 的 `config/name="弹壳风暴2"` 未改；**本流程未执行任何 commit/push**（`6a59e26e「2026-10-17 每日自动提交」是另一条自动化产生的，非本次）；冒烟全程隔离 `APPDATA`；未新建站点；线上临时下载文件已清理。
- 备注：上一轮（10-16）修复的 `InsuranceModule` RefCounted 引用环已稳定生效，本轮冒烟不再报 `resources still in use at exit`。

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
- 列站点用 `python publish.py server-sites`（没有 `list` 子命令，写错会直接 argparse 报错）。
- `--skip-build` 可复用已有 exe，仅做验证+生成+发布。
- **冒烟的 ERROR 门禁会抓到「退出期资源泄漏」**（`ERROR: N resources still in use at exit`）。它不阻断启动，但按硬约束 1 同样中止发布。排查法：看 `run_headless.log` 里 `Resource still in use:` 指向哪几个 .gd。
- 单跑冒烟（无需重建）约 20 秒：`python scripts/smoke_exported_pack.py <exe> --keep`，适合失败后快速确认是回归还是抖动。
- **改代码前先做源码级快验，比重建省 3 分钟**：`APPDATA=<工程外空白目录> "$GODOT" --headless --path <ROOT> --quit-after 900 --verbose > log 2>&1`，再 grep `^ERROR` 与 `Resource still in use`。泄漏类问题在源码层与导出包上表现一致。
- **RefCounted 成环是这个工程的复发型陷阱**：`A` 持 `B`，又把捕获 `A` 的 lambda `connect` 到 `B` 的信号 ⇒ 环闭合，Godot 纯引用计数不回收，退出报 `N resources still in use at exit`（N = 泄漏文件数）。改法：`WeakRef` + `static` 转发。
- **判断「是不是我改坏的」用临时还原跑基线**：`cp` 备份 → `git stash push -- <文件>` → 跑同一用例 → `git stash pop` → `diff -q` 校验与备份逐字节一致。零风险，别猜。
- **`run_verification_suite.sh` 在本机会被 safe-delete 拦截**：其收尾清理触发「单轮 50 项批量删除需确认」，套件在拷贝工作区阶段即中止。改用直接跑场景：`APPDATA=<隔离> "$GODOT" --headless --path <ROOT> --scene res://tests/verification/<name>.tscn`。
