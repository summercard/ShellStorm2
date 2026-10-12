# 自动化记忆：ShellStorm2 定期 git 提交（只提交，不 push）

## 执行记录

### 2026-10-12 06:20（首次执行）
- 仓库 `I:\工作项目\shellstrom2\ShellStorm2`，分支 `0.1.2`，起始 HEAD `6c4abb83`。
- 工作区 85 项改动（34 组受版本控制文件 + CJK 文件名若干），按主题拆成 3 个提交：
  1. `46c7fb4a` 主线剧情02—05接入与主线剧本档，镜头/刷怪落点修复、新档09:00起始（34 文件）
  2. `2a76676a` 塔3检修平台与远征入口：来源返航、双梯碰撞，远征关关闭背景音乐（26 文件）
  3. `dfc205d2` 鸟群v003缩放减速、基地提示标签放大，房间布局源路径与文档索引同步（25 文件）
- 提交后 `git status --porcelain` 空，无残留。未 push。

### 2026-10-12 08:43（主人手动要求 push）
- 推 `0.1.2`，含 `6c4abb83`（美术资产存放调整）起共 5 个提交。**耗时 3 小时 12 分**，成功：`e157449f..500fff61`，LFS 1093 对象 / 2.7 GB。
- **关键教训：`6c4abb83` 那批 2.54 GiB `.blend` LFS 对象一直没上传**，首次 `git push` 卡 26 分钟后被远端切断（3 条连接 CloseWait）。以后看到待推提交含 `art_source/` 大批 .blend，先预判这是数小时级长传。
- **抗断连参数（写在 `.git/config`，本地、不进版本控制）**：`lfs.concurrenttransfers=2`、`lfs.activitytimeout=300`、`lfs.tlstimeout=300`、`lfs.transfer.maxretries=10`、`http.version=HTTP/1.1`、`http.postBuffer=524288000`。另**拆成「先 `git lfs push` 再 `git push`」串行**，进度可见、失败可单独续传。
- 实测该链路跨境到 GitHub LFS 后端（AWS S3）吞吐 0.17 MB/s 起步，后半程提速到 353 KB/s。**判断「是否真在传」用 `Get-NetAdapterStatistics` 的 SentBytes 增量**（`Get-Counter` 中文系统取值为空）。
- 全程后台跑（`run_in_background`），**不要用 `sleep` 轮询**，靠 task-notification 唤醒。
- **注意**：这 3 小时里另一会话继续产出新改动（224 项：exit_neon_sign 资产、远征关卡02设计、LoadingResourceWarmup、安全屋/太阳遮挡探针等），push 完成时工作区已非干净 —— 这属下一批，未处理。

## 操作要点（下次复用）
- **归类靠 `docs/v0.1/development/CHANGELOG.md` 的当日小节**：主人自己按主题分组，直接照它归类最贴合意图。
- **提交信息风格**：单行中文短句，用「、」和「，」串并列项，不加 body、不加前缀（如 feat:）。参考近提交「美术资产存放调整，2.5剧本链路修复」。
- **中文路径可用**：Git Bash 下 `git add -- "docs/v0.1/07_技术施工_基地设施.md"` 直接生效，无需转义；`git status` 会显示八进制转义，加 `-c core.quotepath=false` 可读。
- **跨主题文件只能整体归入一个提交**（如 `CHANGELOG.md`/`MODULE_INDEX.md`/`feature_registry.json` 覆盖全部主题）→ 放进最后一个提交，并让提交信息体现「索引同步」。
- **依赖顺序**：新档时间起点（A）先提交，塔3返航依赖其 `BaseManager` 改动（B），`run_verification_suite.sh` 跟随 B 以便注册的测试已存在。
- 无需跑验证套件/文档门禁（本任务只做提交，改动由前序会话产出并已记录）。
- `.gitignore` 忽略项（`.godot/`、`*.glb.import`、`.workbuddy/*.log`、`__pycache__` 等）属正常预期，不提交、不算残留。
- **push 是外部动作**：本自动化只提交。主人明确说 push 才推；推前用 `git log --oneline origin/<branch>..HEAD` 看范围，若含大批 `art_source/` 则预告长传时间。
