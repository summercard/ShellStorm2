# 每日打包发布 · 执行记录

任务：对 ShellStorm2 执行 `python scripts/daily_release.py`，覆盖发布固定站点
`shellstorm2-20261012-190519`（URL 不变）。

## 执行历史

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
