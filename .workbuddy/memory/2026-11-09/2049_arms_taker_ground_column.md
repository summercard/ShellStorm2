# 收租人躯干贴地补底柱（受击盒 16 → 17）

功能：ELITE-ROSTER / ENEMY-AI。设计契约 r13 → **r14**。

## 业主诉求

「身体上的盒子往下穿到跟地面齐平，让子弹打到身体中间也能受到伤害，不然有时候打不中他。」

## 结论/数据

- **1 级体型系数 = 1.0**（旧 2.5 已废，见 2026-11-04_arms_taker_scale_250）；模型 3.5 m 预制体 × 全局 0.70 = 2.45 m bind 身高；idle 姿态头顶判定盒顶 1.95 m。每级 +6%，12 级上限 1.66 倍 ≈ 4.07 m。
- 移动圆柱：半径 0.816 × 0.70 = **0.571 m**，高 1.30 × 0.70 = **0.91 m**（子弹完全无视它，`collision_layer = 0`）。
- 旧 16 个跟骨盒在 idle 下**两腿之间未覆盖宽度 0.448 m**（世界）；弹体半径 0.12 ⇒ 直径 0.24 < 0.448，中心线子弹整条穿过。玩家枪口高度正好压在腰盒底 1.04 m 下方。
- 新增 `Volume_TorsoColumn`：横截面沿用腰盒 `0.111 × 0.119` 骨骼单位、顶边接腰盒顶边（局部 y=0.072）、底边每帧取最低靴底、世界轴竖直。补后剩两条侧缝 0.063 / 0.112 m，均 < 弹径 ⇒ 无直通通道。

## 技术要点（可复用）

- **`BoxShape3D` 吃非均匀 basis**：实测 `diag(2,4,2)` 时 x=0.9 命中 /1.1 不中、y=1.9 命中 /2.1 不中（Godot 4.6.3）。所以长柱高度可以写成变换的 Y 缩放，`size.y` 保持 1.0，不必每帧改 shape.size。
- `Enemy3D._build_animated_hit_volumes()` 现已支持可选 `label` 键：同一根骨骼挂两个盒时只靠 `bone` 会撞节点名。
- 兜底：靴底采样为空时把柱子沉到 y=-1000，别返回 `Transform3D()` —— 那会在世界原点留一个能打中空气的幽灵盒。

## 验收

`SECOND_ELITE_STATE_FLOW_OK checks=1428`（原 1390，新增 38），退出 0。三条旧断言（「打两腿之间不掉血」）随设计改向翻转，新增几何三条（底贴靴底 ≤0.01 m、顶接腰盒 ≤0.06 m、横截面 >0.15×0.15 m）+ 子弹/真实手枪两条。

## 环境坑（这次踩到的）

- **Bash 工具会把 env 剥掉再 spawn 子 bash**：`export FOO=bar; bash -c 'echo $FOO'` 输出空，PATH 也被重置成 `/usr/bin`。要在子 bash 里生效必须把 export 写进 `bash -c '...'` 内部（对 python3 这类非 bash 子进程则正常继承）。
- 因此 `scripts/run_verification_suite.sh` preflight 的 `check_expedition03_room_layouts.py` 在本机必挂（stdout 落 GBK，`↔` 抛 `UnicodeEncodeError`），`PYTHONIOENCODING=utf-8` 传不进去 ⇒ 本轮改用同一 Godot 参数 + 隔离 `APPDATA`/`LOCALAPPDATA` 直接跑场景，再用同一个 `check_verification_log.py` 复核。
- 该场景日志恒有 180 行 `ERROR: Basis ... must be normalized`，全部来自 `src/vfx/VfxShellCasing3D.gd:264`（弹壳落定 slerp 用了带缩放的 basis）。文件最后改动 2026-10-09 `dd2a0aec`，工作区未改 ⇒ **既有问题**，日志门禁因此红，本轮未修。
- `data/runtime_design_data_manifest.json` 有 3 条陈旧哈希（内容与源一致，只是没重跑），顺手 `sync_runtime_design_data.py` 重建；台账里 `enm_elite_arms_taker_root_top3d.tscn` 记 830 B/92dfd166，实物 1138 B/5b63de8d（2026-11-08 快照提交时没同步）—— **未动，已报**。
- 资产包 JSON 原本是 **CRLF**：用 Python 重写时务必 `newline=''` 再手动转 CRLF，否则台账哈希口径（按 CRLF 字节算）会整体漂移。
