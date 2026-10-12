# 2026-10-12｜EXIT 霓虹灯标牌组件 + 入口安全房退出门地面实例化

业主原话：

> 「使用 blender 制作一个 出口的英文字样的霓虹灯组件，作为场景组件，记录到账本中。
> 使用红色自发光材质，要按照规范制作。这个东西大约可以挂在门的上方。制作完成后，
> 进行导入，并且放置在安全屋出口的那个门下方的地板上，面朝上，用来提示玩家这个门
> 是用来出去的。同时要更新账本。」

## 一、结论先行

新增**独立通用场景组件** `ENV-BATTLE-EXIT-NEON-SIGN`（EXIT 霓虹灯标牌，红字自发光），
已登记《场景账本》`3D-设施`；并在入口安全房（`STAIR_LOBBY`）的**退出门**
（`door_targets` 该侧为空串的那扇 = 封闭抵达门 /「[E] 退出战局」门）内侧地面
**平铺实例化，发光面朝上、长边平行门洞**。

业主指定的两处口径（本轮提问后确认）：
1. 「出口的门」= **退出战局那扇**（不是通往 `room_01` 的前进门）；
2. 资产归位 = **独立通用场景组件**（不并入安全房房间包，不重建安全房布局源）。

## 二、资产契约（阶段 0 / 1 冻结）

| 项 | 值 |
| --- | --- |
| AssetID | `ENV-BATTLE-EXIT-NEON-SIGN` |
| 大类 / 子类 / block_id | 场景 / `environment_module_3d` / `battle` |
| 制作源 | `art_source/environments/tower_zones/battle/source/exit_neon_sign/exit_neon_sign_source_v001.blend` |
| 视觉 GLB | `assets/art/environments/tower_zones/battle/components/exit_neon_sign/exit_neon_sign_visual_top3d.glb` |
| PackedScene | `assets/art/environments/tower_zones/battle/runtime/exit_neon_sign/exit_neon_sign_root_top3d.tscn` |
| 源 SHA-256（tscn） | `b11891c7fa35fc0ee15e297d092966d6a59b6abe5a7f1fea0d8afafbac81518e` |
| 可视包络 | **1.84 × 0.76 × 0.09 m**（宽 × 高 × 厚） |
| 原点 / 朝向契约 | 底面中心；正面（发光面）= 本地 **+Y** → Godot **-Z** |
| 材质角色 | `01_精工金属`（外框 + 吊耳）/ `02_细腻哑光`（背板）/ `04_柔和自发光`（EXIT 字样） |
| 色盘格（col,row） | 金属 `(9,4)` / 哑光 `(0,0)` / 自发光 **`(4,1)` 红** |
| 面数 / 网格数 | 134 面 / 2 mesh（主体 42 面、字样 92 面） |
| 碰撞 | **无**（`visual_only`，`collision_shape_count = 0`） |

尺寸取向说明：门洞净宽 2.2 m，标牌取 1.84 m 宽正好落在门洞内侧；0.09 m 厚度是
「平铺后不制造隐形台阶」的上限，所以不给碰撞。

## 三、阶段 2 · Blender 制作

脚本 `art_source/environments/tower_zones/battle/source/exit_neon_sign/qa/build_exit_neon_sign.py`
（Blender 4.5 `--background --factory-startup`，可复现）。

- **EXIT 字样**：Blender 内置字体 `Text` 对象 → 转 Mesh → 归一化到 1.20 m 宽、厚 0.05 m；
  绕 X 轴 +90° 立起（字高 → +Z、正面 → +Y）。
- **背板 + 外框 + 吊耳**：6 个 box 合成一个「整合主体」网格，两材质槽
  （槽 0 = 哑光背板、槽 1 = 金属框与吊耳）。吊耳留在顶边，保留「可挂门楣」的结构语义。
- **PaletteUV**：每个面一个小 UV 岛（半径 0.008 UV），完整落在所属材质槽的单一色格
  安全内区；活动编辑层与活动渲染层同为 `PaletteUV`，输出网格无其它 UV 层。
- **材质**：只引用项目级公共色盘 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`
  （外链、不打包），`Closest` 插值；自发光强度 1.5（与既有 `base_camp_neon_sign` 同值）。

**红的来源**：色盘第 1 行为红→灰渐变轴，取 `(col 4, row 1) = #650D20`（最正、饱和度最高的一格）。
自发光材质用 `EMISSION_OP_MULTIPLY`（由公共色盘后处理脚本设置），所以色盘色就是发光色。

Blender 验收（`validate_game_prop.py`）：

```
passed = True   17/17
output_mesh_count = 2    polygon_count = 134    valid_island_polygon_count = 134
palette_uv_on_all_output_meshes / …within_single_cells / active_edit_layer / active_render_layer = True
no_unused_materials = True    palette_images_use_single_external_shared_file = True
```

## 四、阶段 3 · 导入 Godot

- 稳定路径 GLB，`export_image_format="NONE"` ⇒ **GLB 内 0 张图 / 0 个 texture**。
- `.glb.import` 增补 `import_script/path = res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`
  （全仓 759 份既有 GLB 同款；漏配则材质不会绑公共色盘）。重导后实测：
  3 个 surface 角色正确、`albedo_texture == emission_texture == 公共色盘`、
  `emission_operator == MULTIPLY`、`texture_filter == NEAREST`、自发光 surface `strength = 1.50`。
- GLB 内 TEXCOORD_0 落格实测：哑光 `(0,0)` / 金属 `(9,4)` / 自发光 `(4,1)`，与设计逐格一致。
- 探针 `tests/verification/probe_exit_neon_sign.tscn` → `PROBE_EXIT_NEON_SIGN_OK`
  （独立加载 + metadata 契约 + 材质 + AABB `1.84 × 0.76 × 0.09`）。

## 五、摆位 · 入口安全房退出门内侧地面

代码：`src/world3d/DungeonRoom3D.gd` 新增 4 个常量与 4 个函数
（`_build_safe_room_exit_sign` / `_safe_room_retreat_direction` / `_direction_normal` / `_direction_yaw`），
在 `_build_safe_room_shell()` 末尾调用一次。

为什么这样做（而不是塞进房间包）：

- 安全房是**单一方位**布局，运行时按本层门向把整房绕 Y 旋转 0/90/180/270°；
  而「退出门」是哪一扇**要读 `door_targets`**（该侧为空串），在原生局部坐标里并不固定。
- 所以标牌挂**房间根**（与门扇 `_build_door` 同口径），位置/朝向全部按**世界门向**推导；
  挂到会整房旋转的 `art_root` 下反而要反算回原生方位。

姿态与落位：

| 项 | 值 |
| --- | --- |
| 旋转 | `rotation = (PI/2, yaw, 0)`（YXZ）。`Rx(90°)` 把竖立门头姿态放平、发光面朝上；`Ry(yaw)` 把深度方向对准门法向 |
| `yaw` 映射 | south `0` / north `PI` / east `+PI/2` / west `-PI/2` |
| 高度 | 原点在底边 ⇒ 抬 `半个厚度 0.045`，让背面贴走行面 `y=0` |
| 水平退让 | 牌顶边离门洞所在网格线 `0.45 m`（`SAFE_ROOM_EXIT_SIGN_INSET_M`），避免与门垛/门扇穿插 |
| 深度 | 沿门法向占地 `0.76 m`（= 组件包络高度） |

探针 `tests/verification/probe_safe_room_exit_sign.tscn` → `PROBE_SAFE_ROOM_EXIT_SIGN_OK`：

```
AABB min=(6.290, -0.000, -0.920) max=(7.050, 0.090, 0.920) size=(0.760, 0.090, 1.840)
facing(local -Z -> world) = (0.000, 1.000, -0.000)      ← 发光面朝上
牌底面 y=-0.0000 顶面 y=0.0900                          ← 背面贴走行面
牌 X 区间 [6.290, 7.050]（门洞网格线 x=7.5）             ← 落在东门内侧
```

即：世界 Z 向 1.84 m（长边平行门洞）、X 向 0.76 m（门的法向占地）、Y 向 0.09 m（厚度）；
无 `StaticBody3D`。

### 5.1 补：远征01 入口房走的是**另一条**壳体路径（同日追加）

业主追加：

> 「还有这个出口的提示，在远征关卡01的入口安全屋也要放一个」

**这句话点出了首版的一个真漏洞。** 入口安全房有**两条**壳体路径：

| 路径 | 触发 | 是否生成 EXIT 牌 |
| --- | --- | --- |
| 塔楼 / 程序化 | `_build_tower_module_shell()` → `_build_safe_room_shell()` | ✅ 首版已覆盖 |
| **远征01 start 房** | `_build_shell()` 命中 `static_layout_scene_path` 后**提前 `return`** | ❌ **首版漏了** |

关键代码（`DungeonRoom3D._build_shell()`）：

```gdscript
var expedition_static_path := _expedition_static_layout_path()
if not expedition_static_path.is_empty():
    ... 实例化 f00_start_static_layout.tscn，重命名为 SafeRoomArtRoot ...
    _build_runtime_doors_only()
    return                      # ← 这里就返回了，压根不经过 _build_safe_room_shell()
```

`f00_start_static_layout.tscn` 的 `metadata/static_layout_only = true`、13 房之一、
`room_id = "start"`、`room_type = "STAIR_LOBBY"` ⇒ 它就是业主说的「远征关卡01的入口安全屋」。

**改法**（两处，都不改视觉资产）：

1. `_build_shell()` 静态分支的 `_build_runtime_doors_only()` 之后补一次调用，
   条件 `room_type == "STAIR_LOBBY"`；
2. `_build_safe_room_exit_sign()` 开头加**幂等守卫**（按节点名 `SafeRoomExitSign` 去重）
   —— 两条路径将来若同时命中，只会有一块牌。

**为什么不能把牌固化进静态 TSCN**：`_align_static_layout_to_room()` 会把静态布局按本局
门向整体转 Δ（Δ 由几何匹配定序），**门向每局随种子变** ⇒ 牌的位置也必须每局算。
所以它只能运行时按**世界门向**生成（与门扇 `_build_runtime_doors_only()` 同口径）。
这也是它进 `dynamic_runtime_owned` 的原因（见下）。

实测（真实远征01，`run_seed_override = 77001199`，探针 `probe_expedition_start_exit_sign`）：

```
room_id=start  room_type=STAIR_LOBBY
doors=["east", "north"]  door_targets={ "east": "", "north": "room_01" }
static_layout_scene_path=.../expedition_01/f00_start_static_layout.tscn
static_layout_scene_loaded=true
retreat_direction=east                                  ← 退出门（与 2026-10-12 钥匙文档实测一致）
SafeRoomExitSign 节点数=1                                ← 幂等成立
房间局部 AABB x[6.290,7.050] y[-0.000,0.090] z[-0.920,0.920]  半边长=7.50
facing = (0.000, 1.000, -0.000)                          ← 发光面朝上
门法向=(1.000, 0.000, 0.000)  沿门法向占地=0.760  平行门洞长边=1.840
切向：标牌中心=0.000  门扇=0.000（差 0.000）              ← 与门完全同轴
径向：门扇=7.500  标牌中心=6.670（应更靠房内）            ← 落在门内侧
PROBE_EXPEDITION_START_EXIT_SIGN_OK
```

**声明同步（契约诚实）**：静态 TSCN 的 `metadata/dynamic_runtime_owned` 原本是
`["RoomDoor3D", "RoomTrigger", "RuntimeDetail", "NavigationRegion3D"]` —— 漏了 EXIT 牌。
已把 `SafeRoomExitSign` 补进去，并**同步生成器** `scripts/generate_expedition01_room_static_scenes.gd`
（项目纪律：生成器与产物不同步 ⇒ 重跑覆盖）。TSCN 是二进制级外科替换，**CRLF 行尾原样保留**、
只动那 1 行。

**门禁断言**：`verify_expedition_level01_flow._verify_safe_room_exit_sign()` —— 盯
AssetID / 退出门一致性 / `visual_only` / 无 `StaticBody3D` / 发光面朝上 / 贴地 /
不超房界 / 长边平行门洞（尺寸由资产包络推出，不写死）。反向对照：删掉静态分支那次调用，必红。

### 5.2 ⚠️ 过程事故：我用 Python 改 `.gd` 时把行尾从 CRLF 翻成了 LF

做反向对照时，我用 `python -c` 读写 `src/world3d/DungeonRoom3D.gd` 来注入/还原那行调用。
`open(p, encoding="utf8")` 默认走**通用换行**（CRLF→LF），写回时就成了 LF。

**判据**（`git ls-files --eol`）：

| 文件 | 我改之前/后 | 同目录未碰的对照 |
| --- | --- | --- |
| `src/world3d/DungeonRoom3D.gd` | **w/lf** ← 被我翻了 | `Dungeon3D.gd` = w/crlf |
| `scripts/check_runtime_texture_policy.py` | **w/lf** | `check_asset_registry.py` = w/crlf |

`.gitattributes` 对 `.gd` / `.py` **没有规则** ⇒ 按 `core.autocrlf=true`，工作区应为 **CRLF**；
且 `.gitattributes` 自己写着「**不要**给 `*.gd` / `*.tscn` / `*.md` 加 `eol=lf`」。
`git diff --stat` 看不出这件事（autocrlf 会把两侧都规范化成 LF），**只有 `git ls-files --eol` 看得见**。

**已修**：8 个我碰过的 `.gd` / `.py` 全部转回 CRLF（`verify_expedition_level01_flow.gd`、
4 个新探针、`check_runtime_texture_policy.py` 一并按约定落成 CRLF）。修完复核：
`w/crlf`、`git diff --stat` 仍只有预期行数（21 / 72 / 11 行，**不是整文件**）。
`.import` 保持 `w/lf`（`attr/text eol=lf`）、`f00_start_static_layout.tscn` 保持 `w/crlf` 且只改 1 行。

**纪律（新增）**：🔴 **改 `.gd` / `.tscn` / `.md` 这类没有 `.gitattributes` 规则的文件时，
别用 Python 文本模式读写**（`open(..., "r"/"w")` 会做通用换行转换）。
要外科式改就用二进制模式（`"rb"/"wb"`，如本次改 TSCN 那样），或直接用编辑器工具。
事后自查用 `git ls-files --eol <path>`，**别信 `git diff`**。

## 六、🔴 真实渲染暴露并修掉的一个真问题：镜像字

几何探针全绿（朝向 / 贴地 / 区间），但**真实渲染截图一眼看出字是反的** —— 画面里读到的是
「TIX3」。根因在 Blender 侧的立起旋转：

- 文字平面原本躺在 XY、正面（+Z）、厚沿 Z；
- 初版用 `Rx(+90°)` 立起 ⇒ 正面落到 **-Y**，而坐标契约声明「正面（发光面）= 本地 **+Y**」；
- 导出 Y-up 后该面朝 Godot **+Z**；平铺时玩家从 +Y 上方看到的是**背面的镜像字**。

改为绕轴 `(0,1,1)` 转 180°：

```
R = 2nnᵀ - I = [[-1, 0, 0],
                [ 0, 0, 1],
                [ 0, 1, 0]]        det = +1（纯旋转，不镜像）
正面 +Z → +Y    发光面朝外，符合契约
字上 +Y → +Z    字正立
字右 +X → -X    面向 -Z 侧观察者时右手边就是 -X
```

修正后 GLB 实测：自发光面 z ∈ [-0.045, 0.005]（正面落在 -Z 侧），字迹正立。

**为什么几何探针没抓到**：探针断言的是「发光面法向朝上」「长边平行门洞」「贴地」——
这三条在镜像版本里**同样成立**（镜像不改变法向与包络）。字形方向是**只有渲染**才能发现的
那一类缺陷。这条已写进项目记忆：**自发光文字类资产，验收必须带真实渲染截图**。

## 七、账本

《场景账本》`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`：

| 表 | 改动 |
| --- | --- |
| `资产主表` | 追加 r872（867 行）；R/S 派生列由 `split_asset_ledger.rescope_asset_sheet()` 权威重建 |
| `总览` | `A6/C6/E6/G6` + `B10:C13` 共 12 格写死区间 `$871 → $872` |
| `3D-设施` | 追加 r56；`DataValidation`（C/K/L 列）随之覆盖到 872 |
| `域变更日志` | 追加 r64（`v0.1.29 → v0.1.30`；末行按当时实况动态取，共享账本有并发追加） |
| 无损基线 | `assets/registry/ledger_split_baseline.json`：1062 → 1063 条；`column_digests` / `category_counts` / `sheet_digests["3D-设施"]` 重算 |

写入脚本：`ShellStorm2-work/scratch/exit_neon_sign/register_exit_neon_sign.py`（openpyxl 外科式，非编辑器链路）。

门禁：

| 门禁 | 结果 |
| --- | --- |
| `check_asset_registry.py --scope structure` | `ASSET_REGISTRY_CHECK_OK assets=1063 ledgers=9` |
| `check_asset_registry.py --scope full --ledger scenes` | 40 条 `sha_mismatch`，**全部为既有资产**（BASE/BASE99/TOWER/DUNGEON… 行 32–120），新增行 sha 正确 |
| `verify_ledger_split.py` | `LEDGER_SPLIT_VERIFY_OK assets=1063 baseline=2026-10-12` |
| `check_asset_runtime_naming.py` | 14 项**既有**带版本运行资产（角色动画 / 基地椅子），与本次无关；新增文件不带版本号 |
| `check_expedition_room_asset_status.py` | `EXPEDITION_ASSET_STATUS_OK` |

## 八、没有动的东西

- 未改安全房布局源 blend、未改任何既有房间包 / 通用组件；
- 未改 `SAFE_ROOM_PACKAGE_IDS`（标牌不是房间包）；
- 未给标牌加碰撞，也未改任何碰撞层 / 导航；
- 未改门扇、门墙、`RoomDoor3D` 的任何契约；
- 未改其它资产行或其它域账本（基线只补录本行指纹，其余逐位不变）。

## 九、场景专项门禁

`bash scripts/run_verification_suite.sh batch verify_expedition_level01_flow`（`TMPDIR=/d/ssverif/tmp`）：

```
EXPEDITION_LEVEL01_FLOW_OK: … 13 rooms (entry + room_01..10 + boss + extraction …),
15x15 v007 safe room with 2 perpendicular doors, enemy spawn, searchable containers,
door fate 3-choice, free entry gate, STANDARD extraction beacon, abort-return-to-base contract,
default tower unchanged
VERIFICATION_SUITE_OK suite=batch count=1
```

⚠️ 进程退出码是 1，但日志末尾是 `VERIFICATION_SUITE_OK`。原因与项目既有口径一致：
环境批量删除护栏（`[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]`）拦下了套件 EXIT trap
对临时工作区的 `rm -rf`，`assert_workspace_removed` 因此判红。
**判定取「场景自身的 OK 行」，不取这个被环境护栏污染的退出码**。

残留工作区清理状态（**未清干净，属环境护栏限制，非本事务引入**）：

| 环节 | 结果 |
| --- | --- |
| `verification_workspace.py cleanup <ws>` | 310 MB / 18368 文件 → **29 MB / 14250 文件**；剩余批次再次触发每轮 50 文件的批量删除护栏 |
| `purge_stale_verification_workspaces.py --all` | 「没有遗留」—— 该脚本只处理 **>6h** 的陈旧残留，本轮刚生成的不在射程 |
| I: 盘余量 | 226 GB 可用（29 MB 残余无空间风险） |

自动收尾：该目录超过 6h 后会被 `purge_stale_verification_workspaces.py` 清掉。
需立即清可用：`python scripts/verification_workspace.py cleanup <workspace>`（可能需多次）。


## 十、真实渲染证据

探针 `tests/verification/probe_safe_room_exit_sign_visual.tscn`（真渲染器，非 headless）：

```
godot --path . --resolution 1280x720 \
      --scene res://tests/verification/probe_safe_room_exit_sign_visual.tscn
```

产物（工程外）：

| 文件 | 内容 |
| --- | --- |
| `ShellStorm2-work/scratch/exit_neon_sign/visual/safe_room_exit_sign_approach.png` | 房内朝东门斜俯视：EXIT 红字平铺在门内侧地面，字迹朝门外 |
| `ShellStorm2-work/scratch/exit_neon_sign/visual/safe_room_exit_sign_topdown.png` | 更高俯视：看清字样方向与与门的关系 |

两张图同时确认：**字样为正**、红色自发光真的亮、位置在门内侧地面、未穿墙、未挡门洞。

## 十一、未执行项

- 未跑 `verify_battle_wall_floor_facility_kit`（本次未改任何房间包，按规则无需连带）。
- 未跑全量套件（本次只动安全房一条构建分支 + 一个独立组件）。


