# 每日打包发布 · 执行记录

任务：对 ShellStorm2 执行 `python scripts/daily_release.py`，覆盖发布固定站点
`shellstorm2-20261012-190519`（URL 不变）。

## 执行历史

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
- 线上校验不要只靠脚本的 HEAD：本次额外做了「整包下载 + SHA256 比对」才算真正闭环。
- `--skip-build` 可复用已有 exe，仅做验证+生成+发布。
