# 远征01 Boss房专属件摆位源（Task #40）＋ 门位/旋转判定

提交 `d231517e`（分支 `0.1.2`，本地 ahead 2；**push 被凭据阻塞**，见末节）。
产物：`scripts/build_expedition01_boss_room_layout.py` ＋
`assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002/boss_room_50x40_v002.layout.json`（6 件，9598 B，CRLF 纯，`--check` 绿）。

## 钉死的契约

- **房间局部换算（Boss 房）**：`Godot_local = (bx - cbx, bz, -(by - cby))`。
  `bx/by/bz` = `position_m`（源房间世界系，X=东 Y=北 Z=上；本房中心在源世界原点 ⇒ `cbx=cby=0`）。
  ⚠️ **y 必须取 bz**：区块00 loader 把 y 写成常量 `0.0`（它那 90 个实例 `position_m[2]` 全为 0），
  照抄会把主屏（底 3.805）、墙面标识（底 7.4461）压到地面。区块00 若真去泛化 y，行为等价（实测 z 全 0）。
- **6 件 GLB 已归一化到「XY 居中、底面 z=0」**（导出只做平移、不改朝向）⇒ **旋转恒 0**。
  脚本用「导出包络 XY 居中 / 底面 z=0」反证并断言 `allowed_rotations_y_deg` 含 0。
- **6 件全 `visual_only=true` / 包内 `collision_shape_count=0`** ⇒ 装配无需补碰撞；
  `base_floor_base` 承重归 `TowerFloorStage3D._build_support()`。
- **摆位源只登记专属件**：壳体 5 类（墙/门墙/门扇/L拐角/地砖）**不能写死** —— 门位随每局 constrained 版图变。
  故 `scope="exclusive_only"`。
- `rooms[].{bounds_x_m,bounds_y_m,...}` 的字段形**就是** `RoomShellLayoutBuilder3D.build_block()` 的输入形
  （区块00 摆位源的 `rooms[]` 同形，另含 `doors/exits/use_corner_l`）。
- 记了一个事实差异未裁决：`base_floor_base` 厚 0.26m vs 房间 manifest `floor_top_m=0.3m`，差 0.04m。

## 判定（业主授权「按规则判断」）

- **(a) 门墙走注册表**：统一走 `shell_component_catalog.json`（区块00 `_spawn_authored_layout_wall` 的
  硬编码 `SAFE_ROOM_WALL_DOOR_PREFAB` 正是该注册表里的 `ENV-SHARED-GENERIC-WALL-DOOR-5M` 同路径）。
  改后须跑区块00 回归守 `checks=230`。
- **(b) Boss 房门位**：**不约束**，按生成结果（设计页 §4.4「门位由 RoomDoorLane 算、不手填」
  ＋「以生成结果为准再裁决」）。manifest `ports` 的「南进西出」是来源竞技场语义，不是本关版图口径。
- **(c) 通道桥坑深/桥宽/下层动线**：仍待定，**不阻塞** —— 本轮内部件不摆设，壳体只由外轮廓决定。
- **(d) 通道桥「短边可开门」**：业主已拍板。
  🔴 **不能靠改 `template_rotation_deg` 落地**：`FloorPlanGenerator.room_from_source()` 白名单**不含 rotation**，
  旋转只进 `_data_driven_layout_id` 的 canonical 哈希、不参与几何；constrained 侧房间 rot 恒 0。
  ⇒ 必须在生成器层把「桥房只能从**短边**接邻居」做成**放置约束**（放置候选按房间模板的
  「长/短轴」过滤，父子两向都必须落在长轴上，搜索回退能力会下降 ⇒ 需盯 `used_fallback`）。

## 接线路径（#42 已定）

远征房间 `tower_module_shell=true`（`TowerDescent3D._append_tower_record` 写死）；
`authored_layout_*` 只在 `spec.authored_layout_shell` 为真时透传
（`_append_plan_room_record` L1881）⇒ **13 间房统一置 `authored_layout_shell=true`**，
`authored_layout_instances` = 区块级组合器逐房产出；Boss 房再把 6 件专属
（`slot_role="exclusive_component"`）追加进**同一个** `instances` 数组 ⇒ 单机制、单透传、不新增开关。
`DungeonRoom3D._build_authored_layout_shell` 需新增 `exclusive_component` 分支。
⚠️ 投影到 Blender 世界系（组合器输入）时：`bx = center_m.x`、**`by = -center_m.y`**（平面 +y=南 ↔ Blender +Y=北），
**东/西墙的门槽偏移在此镜像下符号翻转**（南北墙不翻）。

## 阻塞

`git push origin 0.1.2` → `fatal: could not read Username ... terminal prompts disabled`。
穷尽排查：无 `~/.git-credentials`、GCM 无条目、`cmdkey` 无 github、无 `gh`、无 `_netrc`；
SSH 两把密钥均未注册（`ssh -T` → `Permission denied (publickey)`）。
⇒ 需业主给 PAT 或注册公钥 / 改 SSH 远程；本地提交已就绪（不会丢）。

## 下一步

1. #42-A 接线：白名单 4 处 ＋ 生成器调 `RoomShellLayoutBuilder3D`（区块级）＋ `exclusive_component` 分支 ＋ (a) 裁决。
2. #42-B 通道桥短边约束（生成器放置层）＋ 盯 `used_fallback`。
3. #43 账本/设计页 §3.1.1 同步 ＋ 全门禁。
