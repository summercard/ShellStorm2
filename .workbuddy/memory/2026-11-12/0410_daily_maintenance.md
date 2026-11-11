# 04:10 每日维护：git 提交 18 项 + 回收站三盘全清（回收约 745 MB）

## git（分支 `0.2`）

- 开工 21 项待处理，`_s2_mtime_check_1112.py`（START=03:55）核出 6 项 mtime 晚于 START
  （03:57–04:01，均早于实开机时刻 04:05）→ 逐个验内容完整性：3 个 json `json.loads` 通过，
  `Dungeon3D.gd` 尾部落在完整函数 `_can_use_special_item`（555 个 func）→ 判定为已落地的快照，照收。
- `git add -A` 后 `git reset` 踢出 3 项过程文件（磁盘保留）：`_probe_loop.txt`（0 B）、
  `override.cfg.disabled_20261109`（151 B 本机配置备份）、
  `tests/verification/verify_main_story_boss_gate.report.json`（354 B 探针报告）。
  实收 **18 项**（18 files / +326 / −16），提交 `98feb2c5`「2026-11-12 每日自动提交：18 项变更」，
  中文走 `-c i18n.commitEncoding=utf-8 commit -F %TEMP%`，字节核验 `\xe6\xaf\x8f` = 「每」。
- **push 一次成功**：`5fb7d891..98feb2c5`（0.2 -> 0.2），秒级，无 LFS 大件、无 non-ff、无重试。推后 0/0。

## 本轮改动主线

1. **出生/入场朝向改用几何真源** —— `Dungeon3D.forward_door_point_from(from_room_id)`：
   取「主路下一间房那扇门」的世界坐标；环状图无 `parent` 时退开放邻边，门节点优先于房间中心，
   无从判断返回 null（调用方保持原朝向）。配套 `_main_path_next_room_id` + `get_door_links_snapshot`
   （不再让外部直摸私有 `_door_nodes`，避免改名后静默拿空字典）。`DungeonRoom3D` +10、`TowerDescent3D` +26 接入。
   **起因**：`aim_yaw=0`（世界 −Z）与关卡朝向无关 —— 远征01 起始房入口在东侧，角色出生就背对第一间房、拍到出口。
2. **入场近景遮挡** —— `ExpeditionEntryPresentation3D.suppress_occluders/restore_occluders`：
   只改 `visible`（不改材质），阈值 `MAX_OCCLUDER_EXTENT_M=3.0`（排除地板/墙/碎屑群）、
   `CHARACTER_RADIUS_M=0.45`（擦线判定），线段命中 + 体量近似双判据；
   调用点在 `prepare()` 内、黑幕仍全覆盖时。**实测 `GeometryInstance3D.transparency=0.12` 对 GLB 不透明材质完全无效**（诊断打印 faded=2 但画面不变）。
3. **远征01 room03 遭遇时序改判** —— `preparation_sec` 3→60、`start_delay_sec` 3→0：
   先停顿 60 秒再进刷怪，60 秒是准备倒计时不是刷怪截止；设计 §11.1 追加 11-12 裁定。
4. 文档/账本：新开发记录《远征01 入场全息仪式》+69、`远征关卡01设计` 改判、CHANGELOG/feature_registry、
   道具账本 xlsx 刷新，`verify_expedition_entry_hologram_ceremonies.gd` +18 断言。

## 回收站

- 清空前 **8021 条 / 逻辑 772.2 MB / 实际 745.4 MB**（C: 216/63.0MB/47.1MB、D: 23/13.8MB/146.8KB、
  I: 7782/695.4MB/698.1MB）；7896 条 24h 内，**全部当前用户 SID（-1279），无其他 SID**。
- 大头：NVIDIA GLCache 39.9 MB（11-12 02:20）+ `ShellStorm2-work\verification\shellstorm-verification.ihJiTe`
  整套 `.godot/imported` 副本（`.scn`/`.ctex` 各 6.6–32.7 MB，695 MB 几乎全在这里）。
- **`purge` 结局：C:\、D:\、I:\ 全部 0x0（OK）**；E/G/H OSError(22) 属预期。$I 条目 8079 → 135。
- `verify` 残余 **125 条 / 逻辑 17.05 MB**（C: 58/15.90MB、D: 2/0.90MB、I: 65/0.25MB）。
  按盘条目数判清空：C 216→58、D 23→2、I 7782→65 三盘均已清。
  类型：~RF 导入临时件 54、Godot/HILLHOUSE 日志 38（4.36MB）、存档 `.bak` 11、其他 10（12.12MB，GLCache 为主）、
  系统 Temp/npm 9、Rokoko 3；全部当前用户 SID。
  **0 条日期 ≥ 2026-11-12**，最新 2026-11-09 02:57（GLCache .bin/.toc，仍被 NVIDIA 占用）→ 无清空后新写入。
- 实测 $R 实际占用 **0.003 MB（C 3 个文件，D/I 各 0）** → 17.05 MB 逻辑体积几乎全是孤儿 `$I` 元数据。
  真实回收约 **745 MB 磁盘 / 772 MB 逻辑**。D 盘 2 条 / 0.90 MB 仍是已知长期钉子。
