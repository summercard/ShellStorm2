---
name: godot-collision-proxy-segmentation
description: 修 ShellStorm2 房型组件「整块 AABB 碰撞代孕盒」造成的空阻挡——把非矩形件（L 形 / U 形 / 两端分离 / 中间真空 / 带门洞）的碰撞盒按几何手工分段成多个盒。用于「这个组件的阻挡不对」「凹口走不过去」「墙上开口被挡死」「开关开不了灯」等由 safe_box_proxy / structural_box_proxy 单盒代理引起的运行时通行问题；只改组件自身 tscn，不动场景文件。
agent_created: true
---

# Godot 房型组件碰撞代孕盒分段

## 何时用

运行时出现「明明看着是空地却走不过去」「凹口被挡成实心」「门洞被墙封死」，
而组件在 `*_root_top3d.tscn` 里声明 `metadata/collision_policy` 为
`safe_box_proxy` 或 `structural_box_proxy`。

**根因**：生成器 `scripts/generate_expedition_room_type_prefabs.py` 的 `tscn_text()`
对这两个 policy **一律只产一个 `BoxShape3D`**，尺寸 = 整套 `bounds_size_m_godot`（整块 AABB）。
凡是几何 XZ 投影**不是矩形**的件（L 形、U 形、两端分离、中间真空、中间带门洞），
凹口/空段就被整块代理挡成实心。

**不适用**：`optimized_output_bounds_box` 等其它 policy（那是各自功能的占位盒）。

## 三条必须先定死的口径（踩过）

1. **只算「玩家高度带」`PLAYER_TOP = 2.2 m`**。
   只在 2.9 m 高处横跨整面墙的自发光灯带、高处连梁**不需要碰撞**；
   把它们算成「必须覆盖」会永远判 FAIL。
2. **GLB 里读到的是局部 y，不是世界 y**。
   挂在 11 m 高的「墙顶管线收口」局部 y 只有 0..0.7，按局部 y 判会被误报成「玩家可达」。
   必须叠加 `assets/**/room_static_layout.tscn` 里该 slug 的**摆放原点 y**
   （yaw-only 旋转下 `世界 y = 原点 y + 局部 y`）才是世界 y。
3. 🔴 **`slot_role == "solid_wall"` 的墙面件不走「空腔」判据**。
   墙的代孕盒本就是要让墙不可穿越，盒 ⊃ 几何是**预期行为**：
   - 墙底台阶凹口（`wall_t970_5m` 的 0.36 m）无害；
   - 装饰墙皮中央开口（`wall_skin_beveled_5m` 的 2.26 m）**要先实测「开口背后是否有通行空间」**——
     查该实例正对的基础墙是 `wall_solid_5m`（整块实心）还是 `wall_door_5m`
     （三盒门套 = 左右门垛 + 门楣，下方让出 2.2×2.5 净空）。背后实心 ⇒ 超覆盖无害。
   这类件只保留「漏覆盖（穿模）」为真 bug，另设 6 m² 大空腔兜底供人工复核。

> 工程权衡：**碰撞盒略大于几何无害**（顶多蹭到），**留空隙才是 bug**（会穿模）。

## 工作流

```bash
export SS2_ROOT="I:/工作项目/shellstrom2/ShellStorm2"   # 或直接在工程根目录下跑
SK=~/.workbuddy/skills/godot-collision-proxy-segmentation/scripts
```

1. **全量定位**：`python $SK/scan_box_proxy_vs_geometry.py`
   输出「几何候选 / 真正需人工分段」两张表；`slot_role=solid_wall` 与高处放置件会被自动豁免。
2. **摸形状**：`python $SK/band_blocks.py <prefab 相对路径>`
   只取触及高度带的三角面做 XZ 8 连通切块，直接给「建议 N 个盒（`size`/`pos` 按 `bottom_center` 契约）」。
   看不清「同一件里哪些面属横梁、哪些属立柱」时用
   `python $SK/dump_tris.py <prefab 相对路径> tris --in-band=2.2`。
3. **改 tscn**：把单盒换成 N 盒。**只改这一个组件文件**。必须同步：
   - `load_steps = 3 + 盒数`（每多一个 `BoxShape3D` sub_resource 就 +1）
   - `metadata/collision_shape_count = 盒数`
   - 每个 `CollisionShape3D` 的 `position` = 盒中心（契约 `bottom_center`）
   - 注释只用 `;`（Godot tscn 注释符）；文件保持 CRLF
4. **双向复核**：`python $SK/verify_box_segments.py <prefab 相对路径>...`
   四判据全绿才收工：
   - ① 无穿模：相关三角面重心在盒并集外 = 0
   - ② 无空阻挡：盒内、离几何 XZ 投影 > 0.30 m 的成片区域 = 0 m²
   - ③ 无重叠
   - ④ 无漏覆盖（格中心容差半格 `CELL/2`，真漏须 ≥2 格 = 10 cm）
5. **A/B 回归**：直跑 `tests/verification/verify_expedition_room_type_component_replay.tscn`
   （独享 ASCII `APPDATA` + `--headless --path <工程> --scene res://...`，约 30 s），
   把 `^FAIL` 排序后与 HEAD 版逐条 `comm` 比对，必须**条数相同、逐条相同**。

## 🔴 铁律

- **A/B 两边都必须在「热缓存」下跑**。首轮冷缓存会因导入竞态给出不同（更少）的 FAIL 条数，
  同版本连跑两次才稳定 —— 别把冷/热差异当成自己的回归。
- **生成器未改 ⇒ 重跑 `generate_expedition_room_type_prefabs.py` 会把分段全部覆盖回单盒**。
  改完要在台账/事务日志里写明，并提醒主人。
- 做备份循环**必须先 `mkdir -p`**，并给 `cp` 加 `|| exit 1`；
  `git show HEAD:<path> > <path>` 是破坏性操作，只在确认备份成功后执行。
  （WorkBuddy 的 `~/.workbuddy/workspace/sessions/<sid>/modify_backup/` 存有每次写入前的快照，
  可作为误覆盖后的恢复来源。）
- 只改组件自身 tscn；**不动场景文件**（`room_static_layout.tscn` / `f00_*_static_layout.tscn`）、
  不动 `DungeonRoom3D.gd`、不动账本。

## 判据参数速查

| 参数 | 值 | 含义 |
|---|---|---|
| `PLAYER_TOP` / `--band-top` | 2.2 m | 玩家高度带上限 |
| `EMPTY_TOL` | 0.30 m | 「离几何多远算空腔」 |
| `MIN_BLOB_M2` | 0.20 m² | 成片空腔/漏覆盖的报警阈值 |
| `CELL` | 0.05 m | 栅格边长（覆盖判据给半格容差） |
| `SOLID_WALL_CAVITY_LIMIT` | 6.0 m² | `solid_wall` 件的大空腔兜底 |
| `EDGE_EPS` | 1e-4 | 重心-盒边界浮点容差（0.1 mm） |
