# ShellStorm2 项目长期记忆

> 跨会话硬结论；开发明细见 `.workbuddy/memory/<日期>.md` 与 `docs/v0.1/development/`。

## Git / 工作区
- 默认分支是 `0.1.2`，不是 `main`。先看 `git -c core.quotePath=false status --porcelain -uall`；完成以提交为准。
- 远端已有提交时通常按「提交 → fetch → rebase origin/<分支> → push」；但用户明确要求不合并时，不 fetch/rebase，直接从当前 HEAD 建分支并推送。
- `*.import` 是 Godot 重导入产物，不入库；提交用 `git add -A -- . ':(exclude)**/*.import'`，不要用 checkout 洗掉。
- `.workbuddy/` 除 `tmp/`、`backup/` 外入库；三处技能镜像需逐字一致。修改前备份到 `.workbuddy/backup/<日期>_<主题>/`，备份不入库。
- Windows 推送前动态扫描本机代理端口，用 curl 验证 GitHub 返回 200；不要使用失效的固定代理端口。

## 工具链 / 验收
- Windows Godot：`F:/Godot/4.7.2-stable/...win64_console.exe`；验证一般用 `--headless --path . ... --quit-after 900`，隔离 `APPDATA`/`LOCALAPPDATA`。
- 脚本解析失败可能不退出，必须带 `--quit-after 600`；需要 Autoload 时用场景而非 `--script`。
- 交付前运行 `python3 scripts/check_documentation_contracts.py` 及相关门禁；新增/修改关卡还需读 `docs/v0.1/关卡接入规范.md`、运行 `python3 scripts/check_level_decoupling.py`。
- 运行资产路径不含版本号；版本写在 `art_source/`、清单、台账和 Prefab metadata。交付前运行 `scripts/check_asset_runtime_naming.py`。
- headless 不能验证真实渲染管线；性能结论需真实渲染器。`VfxPool3D.create_unpooled()` 产物必须显式释放。

## 远征03 / 美术
- 墙地砖按本局门位运行时生成；正式 TSCN 负责陈设和作者灯光，禁止运行时删重摆。覆盖测试用 `tools/_exp03_art_coverage_probe`，不要用单个固定 SEED 代替覆盖。
- `SPAWN_GROUND_TOP_MAX_M=0.15` 是公馆地砖覆盖的当前阈值；修改美术后必须连跑 `probe_expedition03_playable`。
- 非 ACTIVE 房间的补充灯不能保留无意义阴影；相关门禁是 `tools/_exp03_shadow_budget_probe.tscn`。

## 运行时经验
- 受击体积应为独立被动 `StaticBody3D`，逐帧跟骨并转发命中，不能挂在敌人 `CharacterBody3D` 上；老碰撞体移出子弹层。层：世界/玩家=1，敌人=3，投射物=4。
- 速度由外推决定的状态直接赋 `velocity.x/z`，不要把当前速度当 steer 目标；朝向用 `move_and_slide()` 后的位置差。
- 动画切段要保留归一化相位并使用 blend；`MANUAL` 下 `play()+seek()` 成对使用，不能每帧重播。
- 材质变体开关只在建材质时设置；灭/淡出优先用能量、颜色、实例透明度。材质缓存需长命持有。

## 已确认结论
- 收租人战败事务（2026-11-08）正式专项已通过；旧性能日志中的 UID 警告不代表当前专项失败。
- 远征03真实渲染修复后稳态约 13 ms GPU，剩余长帧主要来自进房 detail/首波刷怪时的同步构建，不是开火。
