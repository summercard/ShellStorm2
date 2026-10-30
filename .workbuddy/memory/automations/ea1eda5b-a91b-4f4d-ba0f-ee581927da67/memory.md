# 每日打包发布 · 执行记录

任务：对 ShellStorm2 执行 `python scripts/daily_release.py`，覆盖发布固定站点
`shellstorm2-20261012-190519`（URL 不变）。

## 执行历史

### 2026-10-30 09:52 — **内容已发布上线，但免登录直链不通**（服务端登录门禁，仅管理员可放开）
- 身份已绑定：飞书设备码授权完成，`/api/v1/me` = 庄孟鸿 / `u_ae23e4a811b703cd` / `role=0 基础用户` / `publish_policy=review`。
- 发布成功两次（第一次用 05:03 旧包，第二次 09:50 重建包），最终线上：`shellstorm2-20261012-190519` **3 files / 377,162,059 B**，与本地三件之和**逐字节相等**。
- 包：`ShellStorm2.exe` **377,135,376 B**，SHA256 `b81fb353cb0d7868af7df54f6c094b95bc869816d3d2890609919b7a16c12562`。三道门禁全绿。
- **唯一未通过项：直链/更新页均 302 → `/oauth/feishu?src=site`。** 站点访问策略「需登录」。带 `--public` 直接 `403 {"error":"免登录链接由管理员设置"}`。全站所有站点同样 302 ⇒ 是服务端 1.9.7 全局策略，不是本站点问题。**要玩家能下载必须管理员设免登录。**
- **踩坑1（关键）**：服务端遇 403 时不等请求体收完就断开，urllib 正在写 241 MB ⇒ 只报 `WinError 10054`，白等 2~3 分钟，客户端自带「403 去 access 重发」兜底永远走不到。诊断用 **179 B 小包 POST `site_id=__diag_not_exist__`**，0.01 秒出真因。
- **踩坑2**：`--skip-build` 复用了 05:03 的包，而源码 08:07/09:26 还改过（`DungeonRoom3D.gd` / `TowerDescent3D.gd`），页面已列 10-30 新条目 ⇒ 页面承诺了包里没有的修复。**教训：`--skip-build` 前必须比对 exe mtime 与工作区最新源码 mtime，源码更新就重建。**
- 脚本改动（未提交）：移除 `--public`（被 403）；`verify_online()` 收紧为只认 200 且**不跟随跳转**（原来跟随 302 到登录页只报 404，看不出真因），已实测输出准确诊断。
- 更新内容 18 条（10-30 门洞黑幕 1 条 + 10-29×17）。未提交 21 项。HEAD 仍 `a72fc0e1`，未 commit/push；`config/name="弹壳风暴2"` 未动；未新建站点。
- 报告：`ShellStorm2-work\_logs\发布报告_2026-10-30.md`。

### 2026-10-30 07:50 — 重试：**仍未发布**，但根因已收敛到「只差一次飞书授权」
- 复核：小包探测仍 403、`/api/v1/me` 的 `user_id` 仍空 ⇒ 服务器侧没变，**没有盲传 377 MB**。
- **已升级客户端**：`git clone` 最新版覆盖 `scripts/publish.py`（54,246 → 112,805 B，旧版备份 `ShellStorm2-work\_tmp\rs_scripts_backup_0751`）。新版才有 `login` 子命令。`npx skills update` 认不到这份手工安装的副本，必须手工 clone 覆盖。
- **飞书登录是设备码流程（RFC 8628）**：`login --feishu` 打印 `accounts.feishu.cn/oauth/v1/device/verify?...&user_code=XXXX-XXXX`，主人在任意设备确认即可，**无需账号密码、无需代操作浏览器**，10 分钟有效。本次码 `PLN2-DK5B` 未获授权已过期。
- **修了 `scripts/daily_release.py` 两处（未提交，留工作区）**：① `publish()` 补 `--public` —— 服务端 1.7.0 起站点默认 `access=login`，不带就 302 跳登录页；② `verify_online()` 原判据 `200 <= code < 400` **会把 302 判成成功**，已收紧为只接受 200 + 必须有 Content-Length 且等于本地字节数。`py_compile` 通过。
- 包未变：`377,134,880 B` / `f5e88a0e…`。授权后只需 `python scripts/daily_release.py --skip-build`（约 1 分钟）。
- **两次设备码（`PLN2-DK5B` / `KDLD-GUSK`）均在 10 分钟内未被确认 ⇒ 410 过期**。结论：**这一步必须业主亲自点链接，自动化跑不通**。以后遇到身份未绑，直接报「需你授权」并把命令给出来，别再连续刷两个码白等 20 分钟。
- **新版客户端兼容性已核对**：成功输出仍含「发布成功」字样（`daily_release.py` 靠它判成败，不受影响）；`--site-id` 更新路径 `maybe_enrich_listing` 里 `is_update` 直接 return ⇒ **不会触发 AIKey 命名、不会挂起**。
- 旧版客户端备份 `ShellStorm2-work\_tmp\rs_scripts_backup_0751\publish.py`（回滚用）。
- **下次运行前置检查（必做）**：`/api/v1/me` 的 `user_id` 为空就直接报告「需先 login --feishu」，不要跑完整流程白等 3 分钟。

### 2026-10-30 05:08 — **失败：未发布**（打包+三道门禁全绿，卡在上传；服务器新增飞书身份门禁）
- 导出 359.7 MiB 一次过 → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 文档生成成功（17 条）→ **上传失败**。首次与 `--skip-build` 重试**逐字同错**，确定性故障。
- 包（未发布）：`ShellStorm2.exe`，**377,134,880 B**，SHA256 `f5e88a0e464b0eb9958e428172119247fa77bd0db7d2abccdad3765178594785`（比 10-29 版 +214,088 B）。留在产物目录，次日可 `--skip-build` 复用。
- **根因不是网络**：daemon 已由 1.6.1 升到 **1.9.7**（`/api/v1/health` 的 `version` + 新 feature `feishu-login`）。用 179 B 小包探测 `POST /api/v1/deploy`（指向不存在的 site_id，零写入）⇒ **HTTP 403 `发布必须绑定飞书身份：请先执行 login --feishu 再发布`**。大包上传时服务器未读完请求体即 403 关连接 ⇒ 客户端只看到 `WinError 10054`。`/api/v1/me` 显示 `authenticated=true` 但 **`user_id=""`**（未绑定）。本机 `publish.py` 无 `login` 子命令（旧客户端），连补救命令都跑不了。
- **线上未被破坏**：站点记录 `shellstorm2-20261012-190519` **3 files / 376,935,880 B** ＝ 10-29 版原样。但直链与更新页现在 **302 → `/oauth/feishu?…&src=site`** 再跳飞书登录页 ⇒ **v1.9.7 起公开链接也要登录才能下载**，内容仍在、未被删。
- 更新内容（本应发布）：CHANGELOG **17 条**（全为 10-29 条目）/ 提交 1 条（`a72fc0e1`）/ 未提交 3 项（2 个 `tools/_egt_*.gd.uid` + `project.godot~RF…TMP`，无害）。主条目：远征03 宝箱房开箱掉落+命运卡、掉落对齐 EGT 一层（普通怪不掉装备/自爆不掉铸币/弹药改清房结算）、弹速 16→8 与伤害统一 17、33 只怪数值按玩家 50 伤重定标并修「子弹飞不出来」、33 种全实装、逐房编成、黑幕垂直密闭还原、场景工坊 r5、出口 EXIT 灯牌、小地图去底缩尺寸、易碎小物件 v002 与随机撒点。
- 合规：`config/name="弹壳风暴2"` 未动（第 56 行，`git diff project.godot` 空）；HEAD 仍 `a72fc0e1`，未 commit/push；未新建站点；发布目录仍 3 个文件；探测临时文件已清。
- 报告：`I:\工作项目\shellstrom2\ShellStorm2-work\_logs\发布失败报告_2026-10-30.md`（**放 _logs 不放发布目录**）。
- 待业主：①更新 skill 到新版并 `login --feishu`，或请管理员为 `auto-zhuangmenghong` 补绑/豁免 `publish_policy`；②确认站点是否要对玩家开登录门禁（否则发了也下不了）。

### 2026-10-29 05:04 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 359.5 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。耗时 3m34s。仍按经验把 `TMP/TEMP/TMPDIR` 指到 `I:\...\ShellStorm2-work\_tmp`（C: 今日 2.8 G 空闲，99% 占用，先防一手）。
- 包：`ShellStorm2.exe`，**376,920,792 B**（359.5 MiB），SHA256 `c1802bd0f0f54b4dd91ab7d9fa999e6dd70b59465a45a011f1303db0b15a6e0c`。比 10-28 版 **+14,864 B**。
- 线上独立复验：直链 HEAD 200 / Content-Length 376,920,792（＝本地）/ Last-Modified `28 Oct 2026 21:04:41 GMT`；**整包重下载 376,920,792 B（3.69s @102 MB/s），sha256 与本地逐字节一致**；更新页 200 / 9,178 B（＝本地），`<h1>弹壳风暴2</h1>`、**11 个 `<h3>`**、按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；md 200 / 5,910 B（＝本地）；旧 `更新日志_2026-10-28/27.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点 `shellstorm2-20261012-190519` 3 files / 376,935,880 B（＝exe+页+md）。未新建站点。
- 更新内容：**CHANGELOG 11 条** / 提交 1 条（`dedaf209` 133 项，另一条自动化 04:03 产生）/ 未提交 3 项（均为 `assets/registry/ledger_split_baseline.json.before_ugstreet02/03/04` 基线备份，无害）。
- **11 条里有 8 条是 10-28 白天已发布过的**（二次 / EGT / 三次~八次）：窗口 `since=2026-10-28 05:04`，采集器按「日期 ≥ since 的日期」匹配 ⇒ 10-28 全天条目全部重计。今天**真新增 3 条**＝（九次）视野封边+房门时序+退出战局、（十次）门扇双扇对开+去掉镜头自动复位、（十一）修掉墙外能看见隔壁房间的浅带（水平遮罩有视差 → 改竖直幕墙）。属采集器粗粒度已知行为，非漏报。
- 昨日发现的渲染缺陷**已不复现**：页面最长行 395 字符（昨日那条 Markdown 表格被压成一行超长文本的情况没有出现）。
- 合规：`config/name="弹壳风暴2"` 未改（第 56 行，`git diff project.godot` 空）；HEAD 仍 `dedaf209`，**未执行 commit/push**；冒烟隔离 `APPDATA`；发布目录事前事后都只有 3 个发布物；临时下载文件已删。
- 待业主处理：`config/features=4.7` vs 实际用 4.6.3 导出**仍未定**（连续第三天），今日包同样由 4.6.3 产出。

### 2026-10-28 14:34 — **成功**（常规全流程，一次跑通，无重试；C 盘已回落）
- 首轮即通过：导出 359.4 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。耗时 3m11s。仍按经验把 `TMP/TEMP/TMPDIR` 指到 `I:\...\ShellStorm2-work\_tmp`（C: 今日 12 G 空闲，昨日仅 327 MB，先防一手）。
- 包：`ShellStorm2.exe`，**376,905,928 B**（359.4 MiB），SHA256 `2f7cae3054c23c6802e579bfcb556d6f731f866760d1eafec8d346418a491905`。比 05:09 版 **+65,960 B**（同日二次打包，工作区又有推进）。
- 线上独立复验：直链 HEAD 200 / Content-Length 376,905,928（＝本地）/ Last-Modified `28 Oct 2026 06:34:55 GMT`；**整包重下载 376,905,928 B（4.01s @94 MB/s），sha256 + `cmp` 逐字节一致**；更新页 200 / 11,967 B（＝本地），`<h1>弹壳风暴2</h1>`、**14 个 `<h3>`**、按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；md 200 / 8,198 B（＝本地）；旧 `更新日志_2026-10-27.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点 `shellstorm2-20261012-190519` 3 files / 376,926,093 B（＝exe+页+md）。未新建站点。
- 更新内容：**CHANGELOG 14 条** / 提交 1 条 / 未提交 91 项（修改 41 / 删除 2 / 新增 48，集中在 `tests/verification` 26、`docs/art` 20、`data/level_plans` 10）。
- **14 条里有 6 条是 10-27 的旧条目（昨日已发布过）**：窗口 `since=2026-10-27 14:34`，但 CHANGELOG 条目只带日期不带时刻，采集器按「日期 ≥ since 的日期」匹配 ⇒ 10-27 全天条目被重新计入。今天**真新增 6 条**＝10-28（三次）连接房改窄长房 + 多种子抽关、（四次）房间表→游戏楼层、五次对齐参考第一层+开放进图、六次修远征03 进不去、七次补连通拓扑与门洞、八次四条实测报单。属采集器粗粒度已知行为，非漏报。
- 观察到渲染缺陷：`（二次）修图里没有通道` 那条正文含 Markdown 表格/引用，被压成一行超长文本塞进单个 `<li>`（第 52 行），页面观感差。非阻断，建议采集器对表格/引用做剥离或按段落切分。
- 合规：`config/name="弹壳风暴2"` 未改（第 56 行，`git diff project.godot` 空）；HEAD 仍 `30ed1264`，**未执行 commit/push**；冒烟隔离 `APPDATA`；发布目录事前事后都只有 3 个发布物；临时下载文件已删。
- 待业主处理：①昨日提的 `config/features=4.7` vs 实际用 4.6.3 导出**仍未定**，今日包同样由 4.6.3 产出；②CHANGELOG 已在 10-28 补回 10-23/24/25/26 四天条目（提交 `06de5c52`），连续四天的挂账问题**已结清**。

### 2026-10-28 05:09 — **成功**（导出一次过，但连卡两处环境故障：C 盘满 + 服务器换 IP）
- 首轮全流程：导出 359.4 MiB → 三道门禁全绿 → 生成文档 → **发布失败：`[WinError 112] 磁盘空间不足`**。根因：`publish.py` 用 `tempfile.TemporaryDirectory` 在 `%TEMP%`（C:）里 staging + 打 tar，359 MiB 包需要 ≈720 MB，而 **C: 仅剩 327 MB**。修法：把 `TMP/TEMP/TMPDIR` 指向 `I:\...\ShellStorm2-work\_tmp` 后 `--skip-build` 重跑（三道门禁重验，全部再绿）。**未删任何 C 盘文件。**
- 二轮：卡在 `无法连接部署 API http://10.41.0.2:41740`（10060 超时）。排查发现 **服务器已迁址**：DNS 把 `sofunny-resource-sharing.hnfunny.com` 解析到 **10.30.40.131**，旧 `10.41.0.2` ping 全丢、41739/41740/443 全超时；新地址 daemon v1.6.1、`/api/v1/health` 200、token 归属与 6 个历史站点都在。修法：`publish.py config-server --base-url http://10.30.40.131:41740 --token <原 token>`（token 未变，同机迁移），再 `--skip-build` 三轮 → 发布成功。
- 包：`ShellStorm2.exe`，**376,839,968 B**（359.4 MiB），SHA256 `0ec6bf0e9aef04c3c99f064885374787c426ceffeeebf683732349fa9f2432a5`。**比 10-27 版 +1,086,872 B**（EGT 关卡组装器/白盒真进包）。
- 修了一个**静默漏报**：`collect_daily_changes.py` 的 `_ENTRY_RE` 要求「日期 + 空白」，而 CHANGELOG 有 `## 2026-10-28（二次）修「图里没有通道」` 这种**日期后紧跟全角括注、无空格**的写法 ⇒ 8 条里漏 3 条（含最新一条）。正则改为日期后允许可选 `（…）` 括注并并回标题，重采得 8 条。首轮生成的 5 条版已被三轮覆盖。
- 线上独立复验：直链 HEAD 200 / Content-Length 376,839,968（＝本地）/ Last-Modified `27 Oct 2026 21:10:12 GMT`；**整包重下载 376,839,968 B（3.63s @103.8 MB/s），sha256 + `cmp` 逐字节一致**；更新页 200 / 8,676 B（＝本地），`<h1>弹壳风暴2</h1>`、**8 个 `<h3>`**、按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；md 200 / 5,620 B（＝本地）；旧 `更新日志_2026-10-27/26.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表 `shellstorm2-20261012-190519` 3 files / 376,854,264 B（＝exe+页+md 之和）。未新建站点。
- 更新内容：**CHANGELOG 8 条**（10-27×6、10-28×2）/ 提交 2 条 / 未提交 11 项。主条目：EGT 式关卡组装器实现、远征03 骨架随机的设计契约、9/9 白盒 TSCN、按 EGT 房型谱做全 56 种白盒、房间按外轮廓重做 + 门/通道套件、参考资料入库 + 情报室加第三关入口，以及最新的「修图里没有通道」（三段式拼装 + 环内紧环外疏）。
- 合规：`config/name="弹壳风暴2"` 未改（第 56 行，`git diff project.godot` 空）；HEAD 仍 `30ed1264`，**未执行 commit/push**；冒烟隔离 `APPDATA`；临时下载文件与 `_tmp` 已清。
- 待业主处理：①**C: 只剩 327 MB（100% 满）**，这是本轮卡点，任何走 `%TEMP%` 的大文件操作都会崩；②昨天提的 `config/features=4.7` vs 实际用 4.6.3 导出**仍未定**，今日包同样由 4.6.3 产出。
- 教训：**报错要读到第一因，不要按「网络抖」重试**。`WinError 112` 与 `10060` 是两个不同层的故障，各自都有确定解（临时目录换盘 / 客户端改指向），盲目重试只会浪费时间。

### 2026-10-27 05:04 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.3 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 4m07s。
- 包：`ShellStorm2.exe`，**375,753,096 B**（358.3 MiB），SHA256 `f3c0284c5369b9772ef1fb05d7f01349f4581bea2db2e06a768db4cf657ef959`。
- **SHA256 与 10-24/25/26 版逐字节全等**，但今天 `project.godot` 确有改动，故专门做了归因（不是复用旧包）：exe mtime `2026-10-27 05:03:18`（今日重新导出），Last-Modified 刷新为 `26 Oct 2026 21:04:41 GMT`。真因＝过去 24h 唯一提交 `941d6769` 的 5 项里，`project.godot` 只改了 `config/features` 引擎标识 4.6→4.7，**已用字节级检索证实该串不进入导出 PCK**（`\x03\x00\x00\x004.7\x0c\x00\x00\x00Forward Plus` 与 4.6 版本均查不到，`GDPC` 头在偏移 43,740,046）；其余 4 项是 `tools/`、`scripts/`、`docs/`（被 `exclude_filter` 排除）+ 本自动化 memory ⇒ 确定性导出同一份游戏内容。**本日包对玩家零玩法变更。**
- 线上独立复验：直链 HEAD 200 / Content-Length 375,753,096（＝本地）/ Last-Modified `26 Oct 2026 21:04:41 GMT`；**整包重下载 375,753,096 B（3.51s @107 MB/s），sha256 + `cmp` 逐字节一致**；更新页 200 / 2,966 B（＝本地），`<h1>弹壳风暴2</h1>`、按钮 `href="ShellStorm2.exe"` 子路径 200；更新日志 md 200 / 799 B（＝本地）；旧 `更新日志_2026-10-26/25.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表 `shellstorm2-20261012-190519` 仍 3 files / 375,756,861 B（＝exe+页+md 之和）。未新建站点（列表无 10-27 新站）。
- **更新内容：CHANGELOG 0 条 / 提交 1 条 / 未提交 4 项**。0 条已回源核对：`grep -nE '2026-10-(2[3-7])'` **全文件零命中**，首条仍是 `# 2026-10-22 …`，mtime 仍 `Oct 22 16:37` ⇒ 真实「没写」，非采集漏报。
- 合规：`config/name="弹壳风暴2"` 未改（第 56 行核对，`git diff project.godot` 空）；HEAD 仍 `941d6769`，**未执行 commit/push**；冒烟隔离 `APPDATA`；发布目录事前事后都只有 3 个发布物；临时下载文件已删。
- 待业主处理（**连续第四天挂账**）：CHANGELOG 自 10-22 后一条未写，更新页连续四天只能显示提交记录。10-23 的素材（`2026-10-23_anim_showcase_reel.md`，128 剪辑重构）现成，补一条即可回填。
- **新发现（本轮首次提出，建议尽快定）**：`project.godot` 的 `config/features` 已于 10-26 13:32 改为 `4.7`，但 `daily_release.py` 仍固定用 `I:\Godot_v4.6.3-stable_win64.exe\..._console.exe` 导出 ⇒ **今日包实际由 4.6.3 产出**。启动冒烟能过，但版本声明与产出引擎不一致是隐患（4.7 编辑过的资源将来可能 4.6 读不了，且 4.7 特性不会进包）。建议把脚本引擎路径切到 4.7 并确认导出模板同版。

### 2026-10-26 05:04 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.3 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 3m38s。
- 包：`ShellStorm2.exe`，**375,753,096 B**（358.3 MiB），SHA256 `f3c0284c5369b9772ef1fb05d7f01349f4581bea2db2e06a768db4cf657ef959`。
- **SHA256 与 10-24/10-25 版逐字节全等**，已核实非复用旧包：exe mtime `2026-10-26 05:03:13`（今日重新导出），Last-Modified 刷新为 `25 Oct 2026 21:04:30 GMT`。全因＝**过去 24h 源码零变更**（唯一提交 `9c424ce2` 只改了本自动化 memory 文件；工作区 4 项均为无源码影响的未跟踪文件）⇒ 确定性导出同一份字节。**本日包对玩家零玩法变更。**
- 线上独立复验：直链 HEAD 200 / Content-Length 375,753,096（＝本地）/ Last-Modified `25 Oct 2026 21:04:30 GMT`；**整包重下载 375,753,096 B（6.94s @51.6 MB/s），SHA256 逐字节一致**；更新页 200 / 2,966 B（＝本地），`<h1>弹壳风暴2</h1>`、按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；更新日志 md 200 / 799 B（＝本地）；旧 `更新日志_2026-10-25/24.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表 `shellstorm2-20261012-190519` 仍 3 files / 375,756,861 B（＝exe+页+md 之和）。
- **更新内容：CHANGELOG 0 条 / 提交 1 条 / 未提交 4 项**。0 条已回源核对：`grep -E '^#{1,3} *2026-10-(2[3-6])'` 与日期列项写法均无命中，CHANGELOG mtime 仍 `Oct 22 16:37`，`docs/v0.1/development/` 最新文件仍是 `2026-10-23_anim_showcase_reel.md` ⇒ 真实「没写」。
- 合规：`config/name="弹壳风暴2"` 未改（`git diff project.godot` 空，第 56 行核对）；HEAD 仍 `9c424ce2`，**未执行 commit/push**；冒烟隔离 `APPDATA`；未新建站点；临时下载文件已删。
- 待业主处理（**连续第三天挂账，已升级为长期问题**）：10-23 有开发记录（`anim_showcase_reel.md`）但没写 CHANGELOG 条目，10-24/25/26 连开发记录都没有。更新页已连续三天只能显示提交记录、无内容摘要，玩家看到的是「没有更新」。建议**先补 10-23 一条**（素材现成），并养成写完开发记录随手加条目的习惯；否则这个采集器再准也采不到不存在的内容。

### 2026-10-25 05:05 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.3 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 5m04s。
- 包：`ShellStorm2.exe`，**375,753,096 B**（358.3 MiB），SHA256 `f3c0284c5369b9772ef1fb05d7f01349f4581bea2db2e06a768db4cf657ef959`。
- **SHA256 与 10-24 版逐字节全等**，已核实不是复用旧包：exe mtime `Oct 25 05:04`（今日重新导出），Last-Modified 也已刷新为 `24 Oct 2026 21:05:52 GMT`。全等原因＝**过去 24h 源码零变更**（唯一提交 `10ef3369` 只改了本自动化 memory 文件；工作区 4 项均为无源码影响的未跟踪文件）⇒ 确定性导出得到同一份字节。**本日包对玩家零玩法变更。**
- 线上独立复验：直链 HEAD 200 / Content-Length 375,753,096（＝本地）/ Last-Modified `24 Oct 2026 21:05:52 GMT`；**整包重下载 375,753,096 B（7.06s @53.3 MB/s），SHA256 逐字节一致**；更新页 200 / 2,966 B（＝本地），`<h1>弹壳风暴2</h1>`、按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；更新日志 md 200 / 799 B（＝本地）；旧 `更新日志_2026-10-24/23.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表 `shellstorm2-20261012-190519` 仍 3 files / 375,756,861 B（＝exe+页+md 之和，对得上）。
- **更新内容：CHANGELOG 0 条 / 提交 1 条 / 未提交 4 项**。0 条已回源核对：CHANGELOG 首行仍是 `# 2026-10-22 …`，无 10-23/24/25 任何形式的条目，`docs/v0.1/development/` 近三日也只有 `2026-10-23_anim_showcase_reel.md` ⇒ 真实「没写」，非采集漏报。
- 合规：`config/name="弹壳风暴2"` 未改（`git diff project.godot` 空，第 56 行核对）；HEAD 仍 `10ef3369`，**未执行 commit/push**；冒烟隔离 `APPDATA`；未新建站点；临时下载文件已删。发布目录事前事后都只有 3 个发布物。
- 待业主处理（**连续第二天挂账**）：10-23 有开发记录（`anim_showcase_reel.md`）但没写 CHANGELOG 条目，10-24 连开发记录都没有。更新页只能显示提交记录、没有内容摘要。建议补 `# 2026-10-23 …` / `# 2026-10-24 …` 两条，下一轮即会带上。

### 2026-10-24 05:04 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.3 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 3m24s。
- 包：`ShellStorm2.exe`，**375,753,096 B**（358.3 MiB），SHA256 `f3c0284c5369b9772ef1fb05d7f01349f4581bea2db2e06a768db4cf657ef959`。
- 线上独立复验：直链 HEAD 200 / Content-Length 375,753,096（＝本地）/ Last-Modified `23 Oct 2026 21:04:08 GMT`；**整包重下载 375,753,096 B（7.0s @51.2 MB/s），SHA256 逐字节一致**；更新页 200 / 2,966 B（＝本地），`<h1>弹壳风暴2</h1>`、按钮 `href="ShellStorm2.exe"` 子路径 200 同大小；更新日志 md 200 / 799 B（＝本地）；旧 `更新日志_2026-10-23.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表 `shellstorm2-20261012-190519` 仍 3 files / 375,756,861 B（exe+页+md 之和，对得上）。
- **更新内容：CHANGELOG 0 条 / 提交 1 条 / 未提交 4 项**。0 条已回源核对：CHANGELOG 文件内不存在 10-23 / 10-24 的标题条目，也不存在这两个日期的日期列项 —— 是真实「没写」，不是采集漏报（`#`/`##` 漂移问题昨日已修）。
- **包体几乎与昨日全等**（+96 B）：因为 10-23 的唯一工作（`2026-10-23_anim_showcase_reel.md`：128 剪辑角色全动画总览 jpg/mp4）全部落在 `tools/` + `scripts/`，而 `export_presets.cfg` 的 `exclude_filter` 明确排除 `tools/*,scripts/*,docs/*` ⇒ **本日包对玩家零玩法变更**。页面上「窗口内 CHANGELOG 没有新增条目」在功能意义上是诚实的。
- 合规：`project.godot` 第 56 行 `config/name="弹壳风暴2"` 未改（`git diff project.godot` 空）；HEAD 仍 `69669435`（「2026-10-24 每日自动提交：9 项变更」，另一条自动化 04:02 产生），**未执行 commit/push**；冒烟隔离 `APPDATA`；未新建站点；临时下载文件已删。发布目录事前事后都只有 3 个发布物。
- 待业主处理：**10-23 有开发记录但没写 CHANGELOG 条目**，导致更新页只有提交记录、没有内容摘要。建议补一条 `# 2026-10-23 …`（开发记录已备好素材），下一轮即会带上。

### 2026-10-23 05:05 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.3 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 4m15s。
- 包：`ShellStorm2.exe`，**375,753,000 B**（358.3 MiB），SHA256 `faa0366a520ea5683b7f5fd2d2dac5c7c415818c1122b4bca188c900949211cd`。
- 线上独立复验：直链 HEAD 200 / Content-Length 375,753,000（＝本地）/ Last-Modified `22 Oct 2026 21:05:27 GMT`；**整包重下载 375,753,000 B（7.96s @47.2 MB/s），SHA256 逐字节一致**；更新页 200 / 5,149 B（＝本地），1 个 `<h3>`；更新日志 md 200 / 2,608 B；旧 `更新日志_2026-10-22/21.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表仍只 1 个 `shellstorm2-20261012-190519`（3 files / 375,760,757 B＝exe+页+md）。
- 更新内容：CHANGELOG **1 条** / 提交 1 条（`22bb0c89` 18 项，另一条自动化 04:03 产生）/ 未提交 4 项（`assets/registry` 3 个 `.before_ugstreet02/03/04` 基线备份 + `tools/_tmp_flat_capture.gd.uid`，无害）。
- 唯一一条＝`# 2026-10-22 支线「位置会飘逸、角色跑到房间外面去」`（L 形凹口三连修：门洞开在凹口上 → 整链共用槽 `_solve_chain_lane()` 实选 +7.5；承重板改只盖真砖 `_branch_floor_boxes()` 278 块；落点取有砖格心 `_branch_landing_point()`；断言 28→30）。**只有 1 条是真实情况不是采集漏报**：窗口 since_date=2026-10-22，而 10-21 那 4 条已在昨日发布，10-23 凌晨无新条目（git 的 18 项是 10-22 工作的补提交）。
- 合规：`project.godot` 第 56 行 `config/name="弹壳风暴2"` 未改（`git diff project.godot` 空）；HEAD 仍 `22bb0c89`，**未执行 commit/push**；冒烟隔离 `APPDATA`；未新建站点；临时下载文件已删。
- 观察：包体 358.3 MiB 与昨日 358.4 MiB 基本持平，无异常漂移。

### 2026-10-22 05:05 — **成功**（常规全流程，一次跑通，无重试）
- 首轮即通过：导出 358.4 MiB → 三道门禁全绿（`EXPORT_RUNTIME_REFS_OK` / `FIXTURE_SHADOW_CASTING_OK` / `SMOKE_OK`）→ 生成文档 → 覆盖发布（`server-api-update`，3 文件）→ 线上校验通过。总耗时 4m31s。
- 包：`ShellStorm2.exe`，**375,780,488 B**（358.4 MiB），SHA256 `24ba5ab61869fbb5abf8e6e03994093bc1d473b86b0454f0159aa9682c14ab33`。
- 线上独立复验：直链 HEAD 200 / Content-Length 375,780,488（＝本地）/ Last-Modified `21 Oct 2026 21:05:38 GMT`；**整包重下载 375,780,488 B（15s @26.3 MB/s），SHA256 逐字节一致**；更新页 200 / 9,885 B（＝本地），4 个 `<h3>`；`/ShellStorm2.exe` 子路径 200 同大小；更新日志 md 200 / 6,475 B。旧 `更新日志_2026-10-21/20.md`、`发布失败报告_2026-10-16.md` 均 **404**。站点列表仍只 `shellstorm2-20261012-190519`（3 files / 375,796,848 B）。
- 更新内容：CHANGELOG 4 条 / 提交 1 条（`72929957` 67 项，另一条自动化 04:03 产生）/ 未提交 4 项（`assets/registry` 的 3 个 `.before_ugstreet02/03/04` 基线备份 + `tools/_tmp_flat_capture.gd.uid`，无害）。
- 四条＝room_08 墙位六口径审计（真因是 L 形凹口朝向：美术帧 40×45 vs 房间 45×40，待业主裁定，未动 production）、支线房间掉落+壳装歪（补 `SecretFloorSupport` + 共享壳配准，断言 26/28）、03 号房暗门南墙→北墙（数据源保持 south 靠 180° 旋转取反）、暗门破板修复（A26 反空过写法）。
- 昨日修好的采集器生效：`# YYYY-MM-DD` 一级标题被正确计入，未再现「0 条」。
- 合规：`project.godot` 第 56 行 `config/name="弹壳风暴2"` 未改；**未执行 commit/push**；冒烟隔离 `APPDATA`；未新建站点；临时下载文件已删。

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
- 大文件临时目录（C 盘满时的外挂）：`I:\工作项目\shellstrom2\ShellStorm2-work\_tmp`
  —— 跑发布前 `export TMP/TEMP/TMPDIR` 指到这里，否则 staging 会撑爆 C 盘
- 部署 API：`http://10.30.40.131:41740`（2026-10-28 起；旧 `10.41.0.2` 已废弃）
- Godot：`I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe`（脚本自动回退定位；与 `config/features=4.7` 不一致，待定）
- 发布 skill 客户端：`C:\Users\zhuangmenghong\.workbuddy\skills\sofunny-resource-sharing\scripts\publish.py`
- 发布耗时约 3.5 分钟（导出占大部分），需后台运行。

## 经验
- **`--skip-build` 前必查源码是否比包新**：`exe` mtime vs `src/` 下最新 `.gd` mtime。源码更新还复用旧包，会发出去一份「页面写了、包里没有」的假更新（10-30 已踩）。
- **免登录直链只归管理员**（服务端 1.9.7）：`--public` 会被 `403 免登录链接由管理员设置`。普通账号发布只能「需登录」，玩家下不到。判断访问状态别再靠 HEAD 猜，`server-sites` 直接有「访问策略」列。
- **`WinError 10054` 别当网络抖**：先查 `/api/v1/health` 的 `version` 与 `/api/v1/me` 的 `user_id`。daemon 1.9.7 起发布要求飞书身份绑定，未绑定会 403 并无视请求体直接关连接；大包上传侧只表现成连接重置。判定法：用 **179 B 小包 POST `site_id=__diag_not_exist__`**（零写入、不建站）即可在 0.03s 内读到真实 403 文本。
- **服务端 1.9.7 的第二个变化**：`/shellstorm2-…exe` 与 `/…/` 都 302 到 `/oauth/feishu?…&src=site`，即公开链接也要求飞书登录。核验线上版本改用 `GET /api/v1/sites`（看 files/bytes 是否与上一版一致）＋站点记录，**不能再靠 HEAD 直链判活**。
- 线上校验不要只靠脚本的 HEAD：本次额外做了「整包下载 + SHA256 比对」才算真正闭环（成功日适用；失败日只需 HEAD 确认线上未被覆盖）。
- 列站点用 `python publish.py server-sites`（没有 `list` 子命令，写错会直接 argparse 报错）。
- `--skip-build` 可复用已有 exe，仅做验证+生成+发布。
- **冒烟的 ERROR 门禁会抓到「退出期资源泄漏」**（`ERROR: N resources still in use at exit`）。它不阻断启动，但按硬约束 1 同样中止发布。排查法：看 `run_headless.log` 里 `Resource still in use:` 指向哪几个 .gd。
- 单跑冒烟（无需重建）约 20 秒：`python scripts/smoke_exported_pack.py <exe> --keep`，适合失败后快速确认是回归还是抖动。
- **改代码前先做源码级快验，比重建省 3 分钟**：`APPDATA=<工程外空白目录> "$GODOT" --headless --path <ROOT> --quit-after 900 --verbose > log 2>&1`，再 grep `^ERROR` 与 `Resource still in use`。泄漏类问题在源码层与导出包上表现一致。
- **RefCounted 成环是这个工程的复发型陷阱**：`A` 持 `B`，又把捕获 `A` 的 lambda `connect` 到 `B` 的信号 ⇒ 环闭合，Godot 纯引用计数不回收，退出报 `N resources still in use at exit`（N = 泄漏文件数）。改法：`WeakRef` + `static` 转发。
- **判断「是不是我改坏的」用临时还原跑基线**：`cp` 备份 → `git stash push -- <文件>` → 跑同一用例 → `git stash pop` → `diff -q` 校验与备份逐字节一致。零风险，别猜。
- **`run_verification_suite.sh` 在本机会被 safe-delete 拦截**：其收尾清理触发「单轮 50 项批量删除需确认」，套件在拷贝工作区阶段即中止。改用直接跑场景：`APPDATA=<隔离> "$GODOT" --headless --path <ROOT> --scene res://tests/verification/<name>.tscn`。
- **「SHA256 与前几日全等」要归因，不能简单当复用旧包、也不能简单当正常**：两步——①看 exe mtime 与线上 Last-Modified 是否今日刷新（证明真跑了导出）；②把 24h 内变更逐项过一遍「是否进 PCK」。已知不进包的类型：`project.godot` 的 `config/features`（编辑器元数据，字节级检索 `<len>4.7<len>Forward Plus` 在 exe 里查不到）、`tools/`+`scripts/`+`docs/`（`export_presets.cfg` 的 `exclude_filter` 排除）、自动化 memory。三者都不变时才允许宣布「对玩家零玩法变更」。
