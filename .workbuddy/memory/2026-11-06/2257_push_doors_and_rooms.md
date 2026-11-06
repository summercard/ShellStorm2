# 2257 提交与推送：门/掉落重排 + 远征03 房间重排 + 门资产 v019/v020

## 本轮 9 个提交（从远端 50628623 / 本地 62473955 起）

| 提交 | 内容 |
|---|---|
| `62473955` | 相机贴墙禁止向墙前视（上一轮遗留，本会话首个动作） |
| `daf7ec97` | 远征01 开门免钥匙不弹卡 + 清房 45% 掉箱 + Boss 保底一箱 |
| `2621051e` | 远征02 门策略改「清房即可开」，钥匙经济退役 |
| `9812f1db` | 木门 v019 通顶加厚双面暗红 + Boss 门/门框 v020 + 共享墙去重 |
| `ca817af0` | 远征03 动线重排 + 四个紧凑特殊房 + 工坊六布局 v005 |
| `b1d7b685` | 僵尸死亡液体放大 ×2 + 每块 1.5~2.0 随机 |
| `82031856` | 公共色盘恢复无损无 Mipmap + 禁用 3D 自动转换 |
| `61466eca` | 收招稳态击退放大器 + 死后连发；护栏判据改局部坐标 |
| `76c5692e` | 账本 1437→1440 + 7 个验收登记（scenes 277→281）+ 索引 |

## 🔴 房间挂载门禁第四次救场

`combat_30x40_5fbbae7662fe` / `combat_40x30_18c0881f3934` 的工作区版本
`script = ExtResource` **43/42 → 0**，218 处全变 `script = null`，
`clutter_kind` / `bounds_size` / `ENV-BATTLE-INTERACTIVE-*` 一条不剩；
`event_40x30_24e9d88c229b` 的 `metadata/` 3159 → 358 行。
节点数只掉 2（270→268）⇒ **只比节点数必然全绿**。

处置：备份坏死版到工程外 → `git checkout --` 还原 → 重跑门禁 21 个 tscn 全绿。
备份：`ShellStorm2-work/sessions/2026-11-06_room_script_loss/*__stripped.tscn`

**结论：这条门禁必须进 `run_verification_suite.sh`，不能靠人记。** 四次都是同型。

## 新踩到的两个环境坑

1. **`.git/index.lock` 陈旧残留**：18:59 留下的 0 字节锁，`git add` / `git commit`
   全部报 "File exists"，但 `git status` 正常。判据：`ls -l .git/index.lock` 看时间戳与大小，
   0 字节 + 远超当前时间即可安全 `rm`。
2. **`git commit -F - <<'EOF'` 走 heredoc 在本机会被杀**（SIGTERM，无输出、无提交）。
   改成 `Write` 落成 `.workbuddy/tmp/msg_*.txt` 再 `git commit -F <file>`，
   并用 `run_in_background` 跑 —— 前台 2 分钟超时切后台会拿到空 stdout 误判失败。

## 数值口径（回读数据，不读 commit message）

| 项 | 值 | 位置 |
|---|---|---|
| 远征01 清房掉箱 | **45%**，否则掉一件补给 | `level_plan.clear_drops` |
| 远征01 Boss 箱 | 必掉，品质下限 `rare` | 同上 |
| 远征01 构筑机会 | 期望 **5.5 次**（清房 4.5 + Boss 1） | 同上 |
| 远征02 宝箱 | **刻意不加**（无货币来源，L02-14 待裁决） | `economy` 段注释 |
| 木门 | 高 2.8 m / 门芯 0.32 m / 总厚 0.626967 m | v019 manifest |
| 僵尸液体 | `side = size × 0.72 × 2.0 × roll`，roll∈[1.5,2.0] | `VfxGooDeathBase3D` |
| 台灯总数 | **226**（B 房改 32/32 后） | `verify_lamp_furniture_chain` |

## 已知红项（都非本轮引入，未放宽阈值）

- `check_runtime_texture_policy` 6 条：`npc_palette` size_limit、
  `enm_elite_arms_taker` glb 内嵌图 ×3、`StartupLoadingSplash` 1920×1080 ×2。
- `probe_expedition03_playable` 退出 1：25 扇木门超旧探针 **0.28 m** 门板厚度阈值
  （改前 28 扇）—— 探针阈值与新门 0.32 m 门芯不匹配，**是我该改探针，不是改门**。
- 场景账本 full 2 条 SHA 漂移、文档合同 15 条断链：既有。

## 待办
1. 把房间挂载门禁固化进 `run_verification_suite.sh`（第四次了）。
2. `probe_expedition03_playable` 的门板厚度阈值按新门规格重定口径。
3. 远征02 宝箱要不要加，取决于货币来源怎么定。
4. 近战不看视线、体型缩放放大位移两条仍等业主裁决。
