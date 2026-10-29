# 远征03 入口安全屋：补上退出门的地面 EXIT 灯牌

日期：2026-10-29
触发：业主截图红框圈出入口安全屋的退出门，原话「远征关卡03的安全屋的回去的路这里。没有摆放远征01用的退出关卡的功能。帮我摆进去。那个 exit 的物品也要摆进来。」
性质：**补摆一件视觉标识 + 补一条会失败的断言**。不改关卡拓扑、不改门规则、不改结算、不改存档格式。

---

## 1. 先把「功能」和「物品」分开看

业主一句话两个诉求，实测下来一个是已经好的、一个真的缺：

| 诉求 | 状态 | 证据 |
|---|---|---|
| 「退出关卡的功能」 | **已存在** | `PLAYABLE retreat_door side=east has_leaf=true prompt=[E] 退出战局`；`retreat_interact mode=configured_expedition_retreat opened=true` |
| 「那个 exit 的物品」 | **缺失** | 修复前 `EXITSIGN has_sign=false` |

所以本轮**没有**去动 `_append_closed_arrival_door_port()`、
`_get_configured_base_door_bindings()` 的 `expedition_retreat` 绑定、
或 `_open_all_flow_doors()` 的"封闭抵达门必须关"规则 —— 它们逐字未变。

业主产生"没有这个功能"的观感，是因为门外**一点视觉标识都没有**：一扇关着的门 +
门外黑幕，在俯视相机下与普通房门完全一样。

## 2. 根因：第三条建壳路径

`_build_safe_room_exit_sign()` 原先只有两个调用点：

| 路径 | 覆盖谁 | 有牌 |
|---|---|---|
| `_build_safe_room_shell()` | 塔楼模块壳安全屋（v007） | ✅ |
| `_build_shell()` 静态布局分支 | 远征01 / 02（`f00_*_static_layout.tscn`） | ✅（2026-10-12 补过） |
| `_build_shell()` 程序化壳体分支 | **远征03 的 flow 房间** | ❌ |

远征03 走 EGT flow：入口房没有静态美术 TSCN（`static_layout_scene_path` 为空），
墙体由 `_build_wall()` 程序化生成 —— 两条已覆盖的路径**都不会经过这里**。
这正是"功能在、标识不在"的结构原因。

## 3. 改动

### 3.1 `src/world3d/DungeonRoom3D.gd`

**① `_build_shell()` 程序化分支，建门之后补摆一块牌**

```gdscript
if room_type == "STAIR_LOBBY":
    _build_safe_room_exit_sign(dimensions)
```

判据只按**房间类型**，不认关卡 ID —— 任何走程序化壳体的安全房都同样成立，
不会给特定关卡开分支（`check_level_decoupling` 无关卡 id 违规）。

**② `_build_safe_room_exit_sign()` 内部统一写房间 meta**

```gdscript
set_meta("safe_room_exit_sign", true)
set_meta("safe_room_exit_sign_direction", direction)
```

原来这两条只有 v007 那条路径在 `_build_safe_room_shell()` 里写，远征03 的
房间快照里根本看不出有没有牌。收进标牌构造函数后，三条路径口径一致。

幂等仍靠 `SAFE_ROOM_EXIT_SIGN_NODE_NAME`（`get_node_or_null` 先查同名牌），
`_build_safe_room_shell()` 里既有的那次 `set_meta("safe_room_exit_sign", ...)` 与之一致，
不构成第二条真源。

### 3.2 `tests/verification/probe_expedition03_playable.gd`

退出门段落新增 `exit_sign` 断言块，五条判据：

1. 恰好一块（幂等，不多摆）；
2. `visual_only = true`（不挡路）；
3. 子树里没有 `StaticBody3D`（不在走行面造隐形台阶）；
4. 发光面朝上（`facing.y ≈ 1`）、底边贴走行面（`|bottom_y − walk_surface_y_m| ≤ 0.02`）；
5. 切向中心对齐门扇（≤0.35m）、沿门法向比门更靠房内。

第 5 条是关键：**位置错了等于没摆**，只看节点存不存在会被"摆到墙里"混过去。

## 4. 验收

### 4.1 探针（headless）

```
PLAYABLE retreat_door side=east has_leaf=true prompt=[E] 退出战局
PLAYABLE exit_sign count=1
PLAYABLE exit_sign tangential sign=0.00 door=0.00  radial sign=6.67 door=7.50  bottom_y=-0.000
PLAYABLE doors_total=27 open=27 blocked=0 reachable=27/27
PLAYABLE retreat_interact mode=configured_expedition_retreat opened=true overlay=true
PLAYABLE_OK
```

远征01 / 远征02 的依赖静态布局路径未被影响（同一探针，两条都 `PROBE_EXPEDITION_START_EXIT_SIGN_OK`）。

### 4.2 真实渲染

`outputs/expedition03_exit_sign/`：

| 图 | 内容 |
|---|---|
| `expedition03_exit_sign_owner_view.png` | 业主同种子（1590629068）俯视机位，门内侧地面 EXIT 红牌可见 |
| `expedition03_exit_sign_approach.png` / `_closeup.png` | 走近与贴近两档，发光面朝上、牌面平行门洞 |

实测落位：门扇局部 `(7.50, 0.00, 0.00)`，牌中心 `(6.67, 0.045, 0.00)`，
切向偏差 0.00 m，牌底 y = −0.000。

### 4.3 未受影响

| 项 | 结论 |
|---|---|
| 门拓扑 / 封门开锁 / 钥匙 / 命运卡 | 逐字未变（`key_locked=0 fate_gated=0 edges_without_leaf=0/29`） |
| 塔楼安全屋 | `floor_01_entry` 走模块壳分支，不进新代码（该房原本就无牌，非本轮引入） |
| 存档 | 无字段变更 |

## 5. 已知边界

- 本次只补**标识**。若后续要"门口加实体装置"（例如远征02 那种 H4 外部楼梯），
  那是结构件，要走立面/接口设计，不在本轮范围。
- 灯牌是纯视觉件（`visual_only`、零碰撞），转身/贴地都不会顶住角色。
