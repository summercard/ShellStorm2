# 2026-10-21 room_08「有一边墙的位置错位」：六口径审计与图纸朝向缺陷

业主：「然后 08 号房间的装配也有问题。检查一下。」→ 追问后选定「有一边墙的位置错位了」。

## 1. 结论先行

**运行时没有「某一片墙摆错位置」——六项口径全部自洽。** 真正错的是**朝向**：

- 设计图（`02-` / `09-拐角走廊01.svg`，两份归一化顶点逐值相同）与
  `variant_footprints.l_turn` 一致规定：**凹口在东南、竖臂在西南、45 宽 × 40 深**；
- 但 L 走廊**美术帧是 40 宽 × 45 深**（TSCN 实测 x 跨 ±19.89、z 跨 ±22.39）；
- `room_01` 的美术帧凹口在**西北**，声明 40×45、转 −180° ⇒ 运行时**东南** ✓ 与图一致；
- `room_08` 的美术帧凹口在**东南**，声明 **45×40**、必须转 −90° ⇒ 运行时**西南** ✗。

一份 40×45 的美术在 45×40 的房间里**不可能**把凹口留在东南（不转填不满、转了凹口必然换角）。
业主说的「有一边墙的位置错位了」，就是 L 形凹口那条长边落在了**东侧**而不是图纸要求的**西侧**。

改法牵动美术源或模板声明，见 §5.3 —— 需业主先裁定以哪一方为准，本轮不动 production 代码。

## 2. 为什么前面三支探针都答不了这个问题

| 探针 | 口径 | 为什么不够 |
|---|---|---|
| `probe_room_wall_profile` | 从房间内侧朝外打物理射线，量「墙离边界多远」 | 射线**先撞家具/管件就停**（`CollisionBody` / 服务器机柜 / 吊线），偏移 +2/+3/+5 全是噪声 |
| `probe_room_assembly_health` | 美术局部 AABB vs 房间尺寸 | 只答「足迹对不对」，答不了「哪一面墙错」 |
| 逐 TSCN 文本比对 | 烘焙帧坐标 | 运行时 `_align_static_layout_to_room()` 会**整体转壳 + 搬门墙件**，文件帧 ≠ 运行帧 |

新增 `tests/verification/probe_room_wall_audit.gd`，一次给六项口径（见 §4）。

## 3. 七个把结论带偏过的口径坑（都已修）

**① 按 `MeshInstance3D` 逐片量 ⇒ 整屏假红。** 一片 5 m 墙里塞了 `部件00/04/05`
三块子网格（面板 + 两根立柱），逐片量会得到三份「偏 2.5 m 的墙」。必须先按**实例根**聚合。

**② 用「最近的边界」判走向 ⇒ 偏移量算错 20 m。** 转角件离两条边一样近，按最近边界
判会把纵向墙算到横向面上。必须用**薄轴定走向**：Z 向薄 ⇒ 墙沿 X 跑（南/北面）；
X 向薄 ⇒ 墙沿 Z 跑（东/西面）。

**③ 门位读错了 meta。** 运行时真源是 `tower_wall_door_offset_<side>`，
而 `wall_door_lane_<side>` 是**程序化壳**那条路径的 meta，远征静态布局房上是空的
（读到 0 ⇒ 把所有缺口都误判成「不是门位」）。第一版因此得出「west 面 25 m 不是门位、
实墙该在而没有」的错误警报，实际那 25 m 正是西门洞。

**④ 门位读错了 meta。** 运行时真源是 `tower_wall_door_offset_<side>`，
而 `wall_door_lane_<side>` 是**程序化壳**那条路径的 meta，远征静态布局房上是空的
（读到 0 ⇒ 把所有缺口都误判成「不是门位」）。第一版因此得出「west 面 25 m 不是门位、
实墙该在而没有」的错误警报，实际那 25 m 正是 L 形凹口（房间外）。

**⑤ 正交相机 `size` 是纵向跨度，不是「取宽深最大」。** 见 §6，它让我连续三次误读平面图。

**⑥ 非矩形房的凹口被当成缺口。** 探针按**包围盒**四条边统计覆盖，L 形的凹口那两面
本来就没有墙（那里是房间外），于是报出「south −22.5~7.5 不是门位 ⇒ 实墙该在而没有」。
补 `_alcove_rects()`：用**内墙线**（`|offset| > 1` 的那两排墙，正是设计里围出凹口的墙）
反推出凹口矩形，落在其中的缺口归因为「凹口，本来就没有墙」。

**⑦ GDScript 没有反斜杠续行。** 写成 `if a and b \` + 续行会让**整份脚本解析失败**，
而场景根仍是裸 Node，`_ready` 压根不存在 ⇒ 探针不跑也不退出，看起来像「卡死」
（实测白等 6 分钟才发现）。长条件一律用括号跨行。同类：`for sign_x in [1.0, -1.0]`
的迭代变量是 Variant，`var x := sign_x * half_x` 会报「Cannot infer the type」——
必须显式标 `: float`。

## 4. 六项口径的实测结果（room_08 / room_01 对照）

```
room_08  45 宽 × 40 深  template_rotation=0°    美术根 −90.0°  门 south(15.0) / west(−12.5)
room_01  40 宽 × 45 深  template_rotation=90°   美术根 −180.0° 门 south(−12.5) / east(−15.0)
```

| 口径 | room_08 | room_01（业主要求对照） | 判定 |
|---|---|---|---|
| ① 贴边墙逐面覆盖 | north 45/45、east 40/40 满铺；south / west 的缺口**全部归因为「L 形凹口」或「门洞」——零「实墙该在而没有」** | north 40/40、west 45/45 满铺；south/east 缺口同样全部归因为凹口/门洞 | 无凭空缺口 |
| ② 墙段连续性（同线相邻段） | 每段 5.00 m，**无缝无搭接**（唯一「缝 5.00 m」就是门洞） | 同 | 无错台 |
| ③ 立面（底面/顶面/厚度） | 墙 35 件，顶面中位 **11.90 m**、底面中位 **0.00 m**，全部一致；唯二例外是两块 `WALL_LABEL` 标牌（本来就挂在 2.30~2.80 m） | 同 | 无悬空/矮墙 |
| ④ 双帧坐标（美术帧 × 房间帧） | **全部墙件都跟着美术根一起转了**，无未归位件 | 同 | 无「没跟着转的墙」 |
| ⑤ 门墙件归属 | 本房唯一门墙件 `WALL_X_35_SOUTH` 落在 **west** 门（lane −12.5），该门 `owns_door_endpoint=true` **自持** → room_09 | 落在 **east** 门（lane −15.0）自持 → room_02 | 门框在自持侧，正确 |
| ⑥ 与邻房的门位对齐 | south lane +15.0 → 世界 x=137.5；room_07 north lane 0 → 世界 x=137.5 **完全重合**。west lane −12.5 → 世界 z=−237.5；room_09 east lane +2.5 → 世界 z=−237.5 **完全重合** | 同（entry / room_02） | 门与邻房对齐 |

**手性核验**：把 `room_01` 的 22 段贴边墙按 270° 旋转后与 `room_08` 逐段比对 ——
**21/22 段完全重合**（唯一未重合的是 0.2 m 的边界偏置，来自半墙厚），**且镜像候选只有
13/22**。⇒ 两间房是**纯旋转关系，不是镜像**，与 `template_rotation_deg` 之差 270° 一致。

**内墙（L 形凹口内边）**：两间房都是「内缩 15 m」处出 11 件内墙，正是
`component_instances.json` 的 `layout_repairs.l_corridor_l_turn_inner_corner_walls`
记载的那批手工修复件（凹口 X 面 6×`wall_5m_a`、凹口 Z 面 5×`wall_5m_d`），
位置与记载的「层心线 4.8945 / 7.387」逐值吻合。

## 5. 真正的根因：美术源烘焙在 40×45 帧，模板却声明 45×40

### 5.1 三方的朝向逐项摊开

| 对象 | 宽 × 深 | 实体区形状（北在上） | 凹口 |
|---|---|---|---|
| 设计图 `09-拐角走廊01.svg` | 45 × 40 | 北侧全宽带 + **西南**竖臂 | **东南** |
| 设计图 `02-拐角走廊01.svg`（room_01 用） | 45 × 40 | 同上，**归一化顶点逐值相同** | **东南** |
| `corridor_45x40.json` 的 `variant_footprints.l_turn` | 45 × 40 | 同上 | **东南** |
| **运行时 room_01** | 40 × 45 | 北侧全宽带 + **西侧**竖臂 | **东南** ✓ 与图同角 |
| **运行时 room_08** | 45 × 40 | 北侧全宽带 + **东侧**竖臂 | **西南** ✗ |

两份设计图（`02` 与 `09`）的 `polygon` 归一化顶点**逐值相同**：
`(0,0) (1,0) (1,.375) (.333,.375) (.333,1) (0,1)`，都是「北带 + 西南竖臂、缺东南」。

### 5.2 逐份 TSCN 量出来：两间房的**美术帧朝向本身差了 180°**

美术帧 = TSCN 里未经 `_align_static_layout_to_room()` 旋转的原始坐标。两份文件的
x 都跨 ±19.89（40 宽）、z 都跨 ±22.39（45 深），**同一尺寸、不同朝向**：

| | 全宽墙在哪 | 全深墙在哪 | 内转角在哪 | 美术帧凹口 | 美术根 | 运行时凹口 |
|---|---|---|---|---|---|---|
| room_01 | **南**（`Y_*_45` z=+22.39） | **东**（`X_*_REAR` x=+19.89） | x=+4.89 / z=+7.39 | **西北** | −180° | **东南** ✓ 与图一致 |
| room_08 | **北**（`Y_*_45` z=−22.39） | **西**（`X_*_REAR` x=−19.89） | x=−5.00 / z=−7.50 | **东南** | −90° | **西南** ✗ 与图不一致 |

卷起来就是一句话：**room_08 的美术帧已经是「凹口东南」，而它又必须转 −90°
才能塞进 45×40 的房（美术帧是 40×45），于是凹口被转到西南。**
room_01 的美术帧是「凹口西北」，转 −180° 后正好回到东南 —— 所以它看起来是对的。

一份 40×45 的美术，**几何上不可能**在 45×40 的房间里把凹口留在东南：
不转填不满，转了凹口必然换角。这就是「一边墙错位」的来源。

> 口径说明：`room_01` 的房间帧是 40×45（相对模板 45×40 转 90°），严格按「模板转 90°」
> 推它的凹口应在东北或西南，而实测在东南 —— 也就是说**两间房都不是模板的纯旋转**。
> 但业主是在实机里认可 room_01 的，且它与设计图的凹口同角（东南），
> 所以本节以「凹口角与图一致/不一致」为判据，不追「是否严格等于模板旋转」。

### 5.3 为什么不能顺手把 room_08 转回去

- 把美术根从 −90° 改成 0° ⇒ 40×45 的壳塞进 45×40 的房，**四面墙整体偏出 2.5 m**，
  正是上一轮 `2026-10-21_secret_branch_assembly_fix` 修掉的「壳装歪」症状。
- 改成 180° ⇒ 依然 40×45，同样偏出。
- 只挪凹口那 11 件内墙 ⇒ 会把 `layout_repairs.l_corridor_l_turn_inner_corner_walls`
  记载的手工修复件拆散，且外壳边界墙仍是错的朝向。

真正要动的是**美术源**（重出 45×40 帧的 L 走廊源，或把 room_08 的布局重新按 45×40 烘焙）
或**模板声明**（把 `l_turn` 拆成两个朝向变体，承认 room_08 用的是转 90° 的那一支）。
两条路都要业主先裁定「以哪一方为准」，本轮不动 production 代码。

### 5.4 顺带查实的图纸侧缺陷

`scripts/render_expedition01_plan_sheet.py` 的 `OUTLINES` 给 `room_01` 与 `room_08`
写了**逐值相同**的顶点，且该顶点集自身跨 45×40，而 `room_01` 的房间帧是 40×45 ——
`room_01` 的轮廓会画出房间包围盒外 5 m。总平面图（`L470`）与详图共用这份表，
所以两份 `拐角走廊01.svg` 也一样。这一项与 §5.2 是**同一件事的两面**：
设计侧只认一个朝向，运行时却有两个。

## 6. 新增/修改的工具

| 文件 | 作用 |
|---|---|
| `tests/verification/probe_room_wall_audit.gd/.tscn` | **新增**。六口径一次跑完：贴边墙覆盖、墙段连续性、立面高度、双帧坐标、门墙件归属、邻房门位对齐；附俯视 ASCII 覆盖图。`SS2_DUMP=<路径>` 导出 JSON 供绘图脚本；`SS2_FORCE_ROT=<角度>` 强制转美术根做对照实验 |
| `scripts/plot_room_plan_annotated.py` | **新增**。把导出的墙段画成带东南西北方位标注的平面图，多间房并排（黑白=贴边墙、浅蓝=内转角墙、橙圈=门洞+lane 值） |
| `scripts/check_room_wall_against_outline.py` | **新增**。把设计轮廓 `variant_footprints` 映射进房间帧，逐面比对「设计要墙而实测没有 / 实测有而设计不该有」。8 个候选（原样/镜像 × 4 直角）全试，用基准房标定后再套到别的房 |
| `scripts/plot_room_wall_overlay.py` | **新增**。设计轮廓 + 实测墙段叠加图，附交并比 |
| `tests/verification/probe_room_shot.gd` | **修改**。新增 `07_walls_only`（只留墙+地砖、unshaded 红）、`08_neighbours`（本房+邻房一起拍，判「本房的墙与邻房的墙接不接得上」）、`09_walls_oblique`（三维斜视，俯视会把 0.5 m 错位压成一个像素）；**修掉正交相机 `size` 口径 bug**（见下） |

### 正交相机 `size` 口径 bug（值得单独记）

`Camera3D.size` 在正交模式下是**垂直**可视高度，水平方向 = `size × 宽高比`。
原写法 `cam.size = max(宽, 深) + 6` 在 16:9 下纵向只覆盖约 `(max+6) × 9/16` ——
40 m 深的房间只看到 28 m，**南北两面墙被裁在画面外**。

我因此连续三次看图误判成「墙缺了 / 墙错位」。修法：

```gdscript
func _ortho_size_for(width_m: float, depth_m: float, margin_m: float = 3.0) -> float:
	var aspect := 16.0 / 9.0
	var viewport := get_viewport().get_visible_rect().size
	if viewport.y > 1.0:
		aspect = viewport.x / viewport.y
	var need_for_depth := depth_m + margin_m * 2.0
	var need_for_width := (width_m + margin_m * 2.0) / aspect
	return maxf(need_for_depth, need_for_width)
```

**教训**：探针的相机视口本身就是一个容易撒谎的口径。凡「看图判断几何」的探针，
必须先证明「画面装得下整个被测对象」，否则得到的结论是裁切伪影。

## 7. 复现命令

```bash
# 六口径审计（room_08，带 JSON 导出）
SS2_ROOM=room_08 SS2_DUMP=/abs/wall08.json \
  godot --headless --path . res://tests/verification/probe_room_wall_audit.tscn

# 对照房
SS2_ROOM=room_01 SS2_DUMP=/abs/wall01.json \
  godot --headless --path . res://tests/verification/probe_room_wall_audit.tscn

# 带方位标注的平面图
python scripts/plot_room_plan_annotated.py \
  --data wall01.json wall08.json --out outputs/room_wall_overlay/plan_annotated.png

# 设计轮廓 vs 实测墙（逐面差异）
python scripts/check_room_wall_against_outline.py \
  --data wall01.json wall08.json --out outputs/room_wall_overlay/wall_vs_outline.png

# 实拍（必须带窗口，headless 出不了图）
SS2_ROOM=room_08 godot --path . res://tests/verification/probe_room_shot.tscn
```

产出图：`outputs/room_wall_overlay/design_vs_runtime.png`（**设计图 / room_01 / room_08 三方对照，
首选**）、`plan_annotated.png`、`wall_vs_outline.png`、`outputs/room_shot/room_08/*.png`。
导出的墙段数据留在 `outputs/room_wall_overlay/room_01_walls.json` /
`room_08_walls.json`，上面两条绘图命令可直接拿它们复现，不必重跑 Godot。

```bash
# 三方对照（设计图 + 两间实装），带方位标注
python scripts/plot_room_plan_annotated.py \
  --design corridor_45x40:l_turn \
  --data outputs/room_wall_overlay/room_01_walls.json \
         outputs/room_wall_overlay/room_08_walls.json \
  --out outputs/room_wall_overlay/design_vs_runtime.png
```

## 8. 支线验收未退步

本轮只动探针与脚本，不碰 `src/`。回归：

```
SECRET_BRANCH_FLOW_OK 位点=4 槽位固定 门洞不重合 门板可见 落点在房内 门副本=已清 脚下实心 壳已摆正 生成规则=确定 传送=可达 隔离=通过 编成=5强化+2普通 存档=往返一致
```

A27（子图 7 间房脚下全部实心，承重盒 7 块）、A28（7 间房壳足迹全部与本间尺寸吻合）双绿。
