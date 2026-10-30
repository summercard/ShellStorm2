# 烘焙美术复用键：从「每局每房一份」改成「每模板一份」

日期：2026-10-31。功能：WORLD-PLAN。两轮来源：
① 业主「有 cstn 的场景和程式化场景，目前是混用的嘛？」→ 实测不混用，但发现签名机制已静默失效过一次；
② 业主「这个场景工坊的意义就是复用美术进行拼装房间，当然算同一个可复用的」→ 复用键语义重做。

## 零、最终形态（先看结论）

| 项 | 改前 | 改后 |
|---|---|---|
| 复用键 | `size_class + size + type + ports(含 lane) + doors + open_sides + module_shell + safe_corner` | **`size + type + safe_corner`** |
| 文件名 | `runtime_rooms/<room_id>_<键前20>.tscn` | `runtime_rooms/<template_id>_<键前12>.tscn` |
| 一局收敛 | **28 键 / 28 房**（等于每房一份） | **17 键 / 28 房**（种子 77003244）；14 / 29（种子 42） |
| 烘焙场景的角色 | 整房接管（`static_layout_scene_loaded = true`，程序化壳体整个跳过） | **只当美术层**（`art_layer_loaded = true`），几何由运行时重建 |
| 门位敏感 | 差 5m 就判成另一个房间 | 门位不进键，**同模板跨局共用一份美术** |

核心一句：**墙和门是玩法几何，不能进美术资产。** 烘焙场景只提供「这间房长什么样」，
壳体（地板承重 / 墙 / 门 / 角柱）永远由程序化分支按本局端口现算。

## 一、第一轮查出来的三件事

用 `tools/_exp03_shell_source_probe.tscn` 跑 4 个种子共 115 间房，实测：

| 壳体来源 | 房间数 |
|---|---:|
| 程序化壳体 `procedural_shell = true` | 111 |
| 安全房动态壳 `_build_safe_room_shell()`（仅 `start`） | 4 |
| 静态 TSCN 加载 | **0** |

68 份白盒 TSCN（`rt_*` 12 + `egt_*` 56）运行时零加载 —— `expedition_static_layout_path()`
拼的是 `f00_<room_id>_static_layout.tscn`，命名一条都对不上，`src/` 里对这两套目录零引用。

**但真正的问题不是"没接上"，是"接上了也早就坏了"：**

1. **签名含派生字段，已发生过一次漂移。** `RuntimeRoomArtSource.describe()` 的
   geometry 里带了 `size_class`，而它完全由 `size` 推导。2026-10-29 那条
   「flow 房间按真实尺寸取档」的改动把 25×25 从 `tower_cell` 改判成 `medium`，
   签名当场全漂 —— 正式目录里唯一的 `n04_819f1c5888a208ed239e.tscn` 从此
   永远匹配不上，而失配是静默的（退回程序化、不报错）。
2. **失配没有任何可见信号。** `matching_path()` 找不到就 `return ""`，
   日志干净、门禁全绿。
3. **门禁完全不覆盖这一层。** `check_expedition03_room_layouts.py` 只查 `rt_*` / `cr_*` /
   门套件，`runtime_rooms/` 一个字没查。

另外文档 `reference/挺进地牢/EGT房型种类.md` §5 把 `rt_*` 写成「远征03 实际要用的壳」，
与实测相反，会误导后来人以为改它能改到游戏里。

## 二、改了什么

### 1. 签名只放几何事实（`src/world3d/RuntimeRoomArtSource.gd`）

从 geometry 字典里删除 `size_class`。判据写进注释：

> 一个字段如果改推导规则就会变，它不属于签名。`size` 已经表达了同一件事。

保留 `size` / `type` / `ports` / `doors` / `open_sides` / `module_shell` / `safe_corner` ——
这些是"这个房间长什么样"的直接事实。

**副作用（必须知道）**：签名算法变了，**所有已存在的烘焙文件一并失效**。选在此刻改是因为
当时正式目录只剩 1 份死文件、缓存 55 份本来就要重采集 —— 越晚改，损失的已有工作越多。

### 2. 失配时区分"没做过"和"做过但过期"（同文件）

新增 `stale_siblings()`：只看文件名，不 load，扫 `runtime_rooms/<room_id>_*.tscn`，
把前缀相同但签名不同的列出来。

`matching_path()` 命中失败后：**只有**存在过期兄弟文件时才 `push_warning`，
并点名文件与当前签名。理由写在注释里：

- 失配默认正常（这个房间还没人烘焙过）→ 不报警，否则每局 28 个房间各刷一条，
  真问题会被淹掉；
- 同 room_id 的文件存在、只是签名对不上 → 说明美术做过这间，代码改动让它悄悄失效了，
  必须留痕迹。

按 `room_id|signature` 去重，同一房间一局只告一次（实测去掉去重前每房刷 3 条）。

### 3. 门禁补上这一层（`scripts/check_expedition03_room_layouts.py`）

新增 `check_runtime_rooms()`，查四件**文件内部**的事：

1. 文件名 `<room_id>_<20位hex>.tscn` 的后缀 == `runtime_room_signature` 前 20 位；
2. 签名是 64 位十六进制 sha256；
3. `runtime_room_geometry.size` 与 `size_m` 逐值一致；
4. `room_id` 属于本关（六张 flow 节点 / 注入房 `<kind>_inj<n>` / 走廊 `cr<NN>_*`）。

配套修了一个解析缺陷：`runtime_room_geometry` 是多行 JSON，原有逐行
`META_RE` 抓不到，会静默拿空 —— 而"拿空"与"字段真缺失"在检查里看起来一样。
新增 `extract_braced()` 做括号配对提取（带字符串转义处理）。

输出里新增 `runtime_rooms` 计数（证明真的扫到了，不是"扫 0 个所以全绿"）。

**不查**：这份文件在当前代码下还算不算有效 —— 那要运行时几何，文本门禁算不出来。
这条由第 2 项承担。

### 4. 清掉过期文件

`runtime_rooms/n04_819f1c5888a208ed239e.tscn` 删除，备份到
`_scratch/expedition03_stale_runtime_rooms_20261031/`。它同时是"会进包体的死资源"，
留着只占体积。

### 5. 修文档

`reference/挺进地牢/EGT房型种类.md` §5：`rt_*` 用途改为「离线白盒模板 / 美术与布局参考」，
新增「运行时是否加载」一行（否），并补 §5.1 写实测数据与正确通道。

## 三、验证

```
python3 scripts/check_expedition03_room_layouts.py
→ ok: true, runtime_rooms: 1（改动前）, 退出码 0

# 反向对照：造两份坏文件，确认门禁真的会红
cp n04_819f1c….tscn n04_deadbeef0000000000.tscn
→ issues: 文件名后缀 deadbeef0000000000 != 签名前20位 819f1c5888a208ed239e（改名或内容被改过）
   退出码 1，随后删除

godot --headless --path . --scene res://tools/_exp03_shell_source_probe.tscn
→ PROBE_SUMMARY static=0 procedural=111 unknown=4（壳体来源不变）
→ 「房间 n04 有 1 份烘焙场景因签名不符被跳过」× 4（每种子 1 条，去重生效）
   删除死文件后重跑：0 条
```

`n04` 在改动后 4 个种子下的签名：`1ad4cc32` / `f5d23019` / `b81a507b` / `b6920bf8`，
均不等于旧的 `819f1c58` —— 与"永久失效"的判断一致。

### 3.1 工坊单测：改动前红、重新采集后绿

`tools/scene_builder/test_runtime_source.gd` 读 `.godot/editor/scene_builder_runtime/latest.json`
（2026-10-29 的采集索引）与同批快照做端到端验证。它的失败形态是
`runtime failed to resolve saved art` —— 正是签名对不上。

| 时点 | checks | failures |
|---|---:|---:|
| 用 10-29 那批旧签名快照 | 277 | **40** |
| 重新采集后（本次） | 283 | **0** |

旧批次红是**必然的**、与本次改动无关：旧快照签名含 `size_class = tower_cell`，
而 10-29 之后该字段已判成 `medium`，两边永远不等 —— 也就是说这条单测在
本次改动之前就已经红了 40 项，只是没人在跑它（它不在 `run_verification_suite.sh` 里）。

重新采集命令（只写 `ShellStorm2-work/` 与本机 `.godot` 缓存，不碰正式资产）：

```bash
python3 tools/scene_builder/runtime_capture.py \
  --engine "<godot_console.exe>" --seed 77003244 --job verify_sig_20261031
# → {"state":"complete","label":"已读取28个真实房间"}
```

采集后缓存目录有 3 批快照（16:19 / 18:01 / 00:21），`latest.json` 只引用最新一批。
旧两批是可删的开发缓存，未自动清理。

## 四、第二轮：复用键语义重做（业主「当然算同一个可复用的」）

### 4.1 为什么第一轮的修法不够

第一轮只解决了「签名不该含派生字段」，**仍然每局每房一个键**：因为 `ports`
（每个端口的 side/lane/door_width/target）在键里。实测 28 间房 → 28 个键。

而工坊存在的意义就是「美术做一次，套到所有同模板房间」。键里带门位等于把这件事废掉。
更糟的是：每个文件都合法、门禁全绿，**没有任何信号会告诉你"复用从未发生"**。

### 4.2 新键与随之而来的硬约束

键 = `size + type + safe_corner`。门位、门向、模板 id 一律不进键。

**但只换键会立刻出错**：烘焙场景里的墙是按**烘焙那一局**的门位摆的，套到门位不同的
房间 → 门洞在错的位置，表现为「图上有门、走过去撞墙」。两条解法：

| 方案 | 结论 |
|---|---|
| 把墙沿墙平移到新 lane | 弃。只在「同侧门数不变」时成立，EGT 枢纽同侧双门（`N2`/`S2`）一来就破；门墙件长度与 lane 强耦合 |
| **墙不进美术层，壳体由运行时重建** | 选这个 |

所以配套改动是**三件必须一起做**，少一件就坏：

1. `DungeonRoom3D._build_art_layer_only()`：flow 房间加载烘焙场景后**不 return**，
   继续走程序化分支；
2. `_strip_art_layer_geometry()`：剥掉美术层里的
   `prp_room_floor` / `prp_room_wall_segment` / `prp_room_wall_door_segment` /
   `prp_room_door_lintel` / `prp_room_corner_post`；
3. `capture_runtime.gd` 不再往快照写 `ConnectionPorts`（端口是几何层，写进去只会矛盾）。

识别口径用 **prefab 路径**而不是节点名：节点名是运行时生成的（`Wall_north` /
`ShellPart_000`），跨版本会变；prefab 路径是资产契约。

### 4.3 一个必须显式声明的副作用

**在工坊里拖动墙或地砖不会进游戏。** 那是几何层。能让改动跨局生效的只有
装饰、陈设、灯、材质。这条写进了 `_build_art_layer_only()` 的注释、
`check_expedition03_room_layouts.py` 的 `--limit`，以及本文件——因为它违反直觉，
不写明就会变成一个长期的"我改了怎么没变"。

### 4.4 验证（都实跑）

```
godot --headless --path . --scene res://tools/_exp03_reuse_probe.tscn
→ REUSE_KEY 38083aa33b1a
  REUSE_SIBLINGS ["fireplace_room_inj2", "n02", "n05", "n06"]
  REUSE_ROOM n04        art_layer=true static=false stripped=21 wall_north=true
  REUSE_ROOM fireplace_room_inj2 art_layer=true static=false stripped=21 wall_north=true
  REUSE_ROOM n02        art_layer=true static=false stripped=21 wall_north=true
  REUSE_ROOM n05        art_layer=true static=false stripped=21 wall_north=true
  REUSE_ROOM n06        art_layer=true static=false stripped=21 wall_north=true
  REUSE_PROBE_OK failures=0
```

**一份 `combat_25x25_38083aa33b1a.tscn` 被 5 间房同时命中** —— 这就是业主说的
「复用美术进行拼装房间」。每间都是 `art_layer=true` / `static=false`
（没整房接管）/ `stripped=21`（几何件剥干净）/ `wall_north=true`（程序化墙在）。

```
godot --headless --path . --scene res://tools/_exp03_reuse_key_probe.tscn
→ REUSE_SEED 77003244 rooms=28 unique_keys=17
  REUSE_SEED 42       rooms=29 unique_keys=14
  REUSE_PROBE_OK failures=0

python3 scripts/check_expedition03_room_layouts.py
→ ok: true, reuse_budget: {rooms: 55, keys: 2, shared_keys: 2}

godot --headless --path . --script res://tools/scene_builder/test_runtime_source.gd
→ RUNTIME_SOURCE_OK checks=289 failures=0
```

`reuse_budget` 是新加的体检项：六张骨架的 55 间内容房只落成 2 个组合
（NORMAL / HUB），都收敛。**这条断言存在的理由**是——「键没有收敛」是这类失效
唯一可见的形态；文件全合法、门禁全绿，只有这个数字能证明复用真的在发生。

### 4.5 单测断言语义反转（必须记）

`test_runtime_source.gd` 原有一条：

```gdscript
check(CONTRACT.matching_path(test_room, base).is_empty(), "different port geometry incorrectly reused art")
```

**这条断言正是「美术做一次只有一局能用」的制度化表达。** 本轮反转为：

```gdscript
check(CONTRACT.matching_path(test_room, base) == target, "same template with a different door lane must reuse the art")
```

同时把「整房接管」的两条断言（包围盒一致 / 碰撞数一致）换成
「美术层几何被剥离 + 程序化墙存在」，并把 `static_layout_scene_loaded` 判据换成
`art_layer_loaded` —— 前者语义仍是「墙体由该场景接管」，留着会让
`TowerDescent3D._room_walls_owned_by_static_layout()` 等判据误判。

## 五、第三轮：结构件判定改成数据驱动（换正式美术资产不用改代码）

### 5.1 为什么还要改

第二轮把「墙不进美术层」定下来，但**哪一件算墙**还是靠名单。而同一份名单当时
在**三个地方各写了一遍**，且三份不一样：

| 位置 | 判据 |
|---|---|
| `DungeonRoom3D.ART_LAYER_GEOMETRY_PREFIXES` | 5 个**精确文件名**（`prp_room_wall_segment` …） |
| `capture_runtime._wall_height()` | 名字里含 `wall` |
| `test_runtime_source._shell_bounds()` | 4 个 `contains("prp_room_*")` |

换正式美术资产后的实际后果：新墙的 prefab 不在那 5 个名字里 ⇒ 被判成**装饰**留下
⇒ 墙跟着美术走、门位一变就错位 ⇒ 「图上有门、走过去撞墙」。而且三份名单只要漏改一处，
判据还会互相矛盾。

### 5.2 改成什么样

**单点**：`RuntimeRoomArtSource.structure_tag(prefab_path)`，按优先序三条：

1. **程序化壳体自带 prefab**：`props/dungeon_3d/` + `prp_room_*` 名字族。
2. **组件目录的 `slot_role`**（`shell_component_catalog.json`）：
   `solid_wall` / `door_wall` / `door_leaf_preview` / `floor` / `floor_tile` / `corner_l`
   → 结构件。**这是"以后不用改代码"的那条路**：新墙登记进目录（本来就要登记，
   否则工坊里刷不出来）并带正确 role，就自动被剥。
3. **名字族兜底**：目录里有些结构件登记成了 `room_type_component`
   （`floor_base` / `ceiling_deck_5m`），role 抓不到，按名字族补
   （`floor_base` 命中 `floor_base_5m`）。

都不命中 ⇒ **当装饰保留**。默认保留而不是默认剥离：剥错了会缺东西且难查，
留错了最多位置略歪，工坊里一眼能看见。

**匹配必须落在词边界上**，不是裸 `contains`：`wall_t` 这种短族会吃掉
`wall_tapestry`（挂毯），剥掉就是「沙发凭空消失」。允许的续接只有
`family + "_…"` 与 `family + 数字…`，字母续接一律不算。

### 5.3 顺带分成角色标签

只回答"是不是结构"不够：`capture_runtime._wall_height()` 量的是**墙**高，
而角柱（做到 2.9m）和门楣（在墙顶之上）也在结构集合里，混进来量出来的就不是墙高。
所以 `structure_tag()` 还返回 `wall` / `floor` / `corner` / `trim` / `door`，
量墙高走 `is_wall_prefab()`（只认 `wall`）。

实测踩到：第一版直接把 `_wall_height()` 改成「结构集合」，工坊单测立刻红 28 条
（`actual wall height differs from 2.8m`）—— 因为把 2.9m 的角柱算进去了。
这条是分角色的直接原因。

### 5.4 顺手把工坊里的分组名归位

采集器把所有几何实例一律塞进 `WhiteboxShell`（它当时不知道哪件会成为美术）。
剥掉结构后那一组里剩下的全是美术，名字不改的话工坊里打开会看到
「WhiteboxShell 里装着沙发和吊灯」。现在剥完把剩下的一切挪进 `ArtComponents`
并删掉空的 `WhiteboxShell`。

**白盒阶段这一组必然是空的**，但仍要建出来：业主打开房间时应该看到一个空着的
`ArtComponents` 等着摆东西，而不是一个被清空后仍叫「白盒壳体」的组 ——
后者会让人以为「这间房没接上美术」。

### 5.5 验证

新增 `tools/_struct_classify_probe.gd`，两个方向都断言，而且**必须覆盖"以后才加的资产"**：

```
godot --headless --path . --script res://tools/_struct_classify_probe.gd
→ STRUCT_CATALOG loaded=true structure_slugs=33
  STRUCT_DIR_PREFABS 16      # 结构目录里的 16 份资产全判成结构
  STRUCT_DECOR_PREFABS 16    # 装修件目录里的 16 份全判成美术
  STRUCT_OK checks=76 failures=0
```

其中最关键的一条是**纯目录驱动样本**：`tile_upper`（role `floor_tile`）与
`base_corner_l_5m`（role `corner_l`）这两个名字**不在任何名字族里**，
只有 `slot_role` 能认。它们过了，才证明「新资产改目录就行、不用改 .gd」这条真的成立。

另外四条断言专门盯边界：`wall_tapestry` / `wall_xylophone` / `floor_basement_prop` /
`shelf_wall_mount` 必须判成装饰，`wall_t_900` / `wall_x670` / `my_wall_standard_panel` /
`env_manor_wall_standard` 必须判成结构。

回归：

| 检查 | 结果 |
|---|---|
| 工坊单测 `test_runtime_source` | `checks=289 failures=0` |
| 复用实测 `_exp03_reuse_probe` | 五间房命中一份美术，`failures=0`（新增分组名断言） |
| 收敛 `_exp03_reuse_key_probe` | 17/28、14/29，`failures=0` |
| 壳体来源 `_exp03_shell_source_probe` | `static=0 procedural=111 unknown=4`（与改动前逐值相同） |
| 文本门禁 | `ok: true` |

## 六、没做的事

- **美术层目前是空的**。白盒阶段的烘焙场景几乎全是几何件，剥完只剩空壳 ——
  这是**正确状态**，不是 bug：工坊的价值在美术阶段才体现。正式目录
  `runtime_rooms/` 现在是空的，等业主在美术阶段把装饰摆进去再保存。
- **没跑视觉验收**。本轮只动键、加载路径与门禁，不宣称任何观感变化。
- **没清旧批次缓存**。`.godot/editor/scene_builder_runtime/expedition_03/` 里已累积
  5 批快照，`latest.json` 只引用最新一批，旧的都可删，未自动清理。
- **上一轮白盒地砖少一条 5m 带**（`build_whitebox_room_tscn.py` 的 `point_in_poly`
  边界判定）仍然没修，见 `2026-10-30_expedition03_whitebox_topview_capture.md`。
  本次没碰白盒生成器。
