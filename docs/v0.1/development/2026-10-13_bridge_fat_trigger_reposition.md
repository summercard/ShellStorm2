# 剧情05 吊桥前触发点改位

日期：2026-10-13；记录ID：`2026-10-13_bridge_fat_trigger_reposition`；功能ID：`NARRATIVE-TRIGGER`；工程版本：0.1.0。
设计依据：[主线剧情剧本 · 剧情05](../design/主线剧情剧本.md#story-05)；[剧情触发08 §13.12](../08_技术施工_剧情触发.md)。
来源：主人 2026-10-13 截图红框，要求「把桥前刷胖子的那个剧情的触发点和范围放到红色框这里，避免太晚和太近触发」。

## 改了什么

只改**触发**，不动刷怪。胖子与 5 只警察仍按剧本刷在桥前（`rooftop_bridge_guard`）。

| 文件 | 改动 |
|---|---|
| `data/narrative/nar_tower_opening_05_bridge_fat.json` | `trigger.radius` 3.0 → **13.5** |
| `src/world3d/TowerDescent3D.gd` | `narrative_anchor()` 的 `rooftop_bridge_approach` 由「桥口正南 10m」改为机房北侧通道定点；新增 `ROOFTOP_BRIDGE_APPROACH_X/Z` 两个常量 |

| 项 | 改前 | 改后 |
|---|---|---|
| 锚点世界坐标（实测） | `(20.0, 0.0, −22.5)` | `(5.4, 0.0, −23.5)` |
| 与桥口 `(20.0, 0.0, −32.5)` 水平距离 | 10.0 m | 17.2 m |
| 与 99F 上行楼梯口 `(−28.0, 0.0, 2.5)` 距离 | 53.5 m，横向偏离必经路线 8.1 m | 42.3 m，几乎落在必经路线上 |
| `trigger.radius` | 3.0 | 13.5 |

刷怪点 `rooftop_bridge_guard = (20.0, 0.0, −28.0)` **未改**。

## 为什么半径要 13.5

触发判定是**圆形**（`NarrativeDirector3D._evaluate_point`：水平距离 + 垂直带），系统当前不支持矩形。主人红框实测为 **7.4 m(x) × 23.8 m(z)** 的窄长条，南北向贯穿机房北侧整条通道。

```text
外接圆（覆盖框的四角）           半径 = sqrt(3.7² + 11.9²) = 12.46 m
玩家可贴机房北墙走到 z ≈ −10.4    到圆心 = 13.10 m       ← 决定半径
取 13.5（覆盖两者 + 0.4 m 余量）
```

玩家从楼梯口到吊桥有两条都合理的走法 —— 贴着机房北墙（z ≈ −10.4）与沿对角线抄近路（z ≈ −23.5）。半径保持 3 时两者**都会漏触发**，症状是「胖子剧情永不触发、日志干净」。

**代价（明说）**：圆比矩形外溢约 10 m(x)，沿对角线抄近路的玩家会在红框西界以西约 6 m 提前触发（离桥口约 26 m 而非 17 m）。位置触发是轮询判定，漏触发是功能失效，提前只是观感，因此按「绝不漏」取值。

## 未做 / 待确认

- **镜头观感未在真机确认**。触发点到刷怪点的距离从 5.5 m 变成 17~26 m，`camera.focus pivot: last_spawn` 的平移距离同比放大，剧本里 `duration: 1.2` 会显得更快。本轮只跑无头验收，**没有在真机上亲眼看过这一段运镜**。
- 未新增矩形触发能力。若日后要严格按框，需要给 `NarrativeScript3D._validate_point_trigger` / `NarrativeDirector3D._evaluate_point` 补可选的 `size` 字段，并配一条会失败的断言。

## 验证与证据

单场景隔离验收，复刻 `scripts/run_verification_suite.sh` 的隔离步骤（工程外 junction 工作区、独立 `project.godot` 用户目录、Autoload 加载前完成隔离）。Godot `4.6.3.stable.official.7d41c59c4`。
日志：`ShellStorm2-work/sessions/2026-10-13_bridge_fat_trigger/`。

| 检查 | 结果 | 证据 |
|---|---|---|
| 前置数据门禁（怪物掉落表 / 运行时设计数据投影） | exit 0 | `MONSTER_DROP_TABLE_CHECK_OK`、`{"files": 39, "issues": []}` |
| 工程导入（全脚本编译） | exit 0，日志门禁干净 | `import.log` |
| 场景预检 `verify_scene_preflight` | exit 0 | `preflight.log` |
| 专项 `verify_narrative_opening_02_05` | **exit 0，156 项全绿** | `scene.log` |
| 日志门禁 `check_verification_log.py` | exit 0 | — |

运行时实测锚点（`scene.log`）：

```text
ANCHOR rooftop_stair_exit      = ( -28.0, 0.0,   2.5)
ANCHOR rooftop_bridge_approach = (   5.4, 0.0, -23.5)   ← 改后值，与常量一致
ANCHOR rooftop_bridge_guard    = (  20.0, 0.0, -28.0)   ← 未变
```

专项首次实机解析出锚点并整段跑通（触发 → 刷 6 只 → 锁输入 → 聚焦胖子 → 回镜 → 解锁 → 写长期历史 → 重播拦截）。
镜头构图判据未因平移距离变大而劣化：

```text
FAT CAMERA samples=48 max_angle_deg=2.70 hold_drift=0.0
```

（改前实测 2.73° / 0.0，同一量级。）该判据只能证明胖子仍在画面中心带内，**不能**证明 1.2 秒平移 17~26 m 的观感是否自然 —— 见上节「未做 / 待确认」。

预期的非通过项（用例自带的故障注入与收口告警，不是缺陷）：`剧情刷怪没有同层安全落点：verification:invalid_roof_point`、`剧情被『skip』收口`、`剧情被『abort:verification_walk』收口`；另有既有 `ObjectDB instances leaked at exit` 警告（改前同样出现，与本次改动无关）。

**未执行**：完整 core / full 套件、长时间游玩、真机镜头观感确认。未新增或替换任何资产，无资产账本哈希变更；未改动存档 schema。

## 回滚

两处改动都是单点：把 `radius` 改回 `3.0`、`narrative_anchor()` 的 `rooftop_bridge_approach` 改回 `Vector3(bridge_x, rooftop.global_position.y, north_z + 10.0)`（并删掉两个常量）。不涉及存档、资产或场景文件。
