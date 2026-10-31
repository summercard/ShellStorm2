# 远征静态布局预检查：从「锚点文件存在」改成「锚点文件或复用键美术存在」

日期：2026-10-31。功能：WORLD-PLAN。触发：业主「调试器里 500 多个报错是怎么回事？」

## 零、结论（先看这条）

那 500 多条**不是报错，是一个过时判据刷出来的警告**，美术覆盖本来是满的。

| 项 | 改前 | 改后 |
|---|---|---|
| 单局 `缺静态布局` 警告 | **641 条**（141 个房间名 × 楼层叠加） | **0** |
| 判据 | `ResourceLoader.exists(f00_<room>_static_layout.tscn)` | 同一句 **or** 同目录 `runtime_rooms/` 有烘焙美术 |
| 远征01/02 行为 | 有锚点文件，走第一条件 | 逐字不变（短路在 `or` 前面） |

同批日志里真正的错误只有 1 条 `[BaseManager] Refusing stale save`（正常存档保护），
另有 2 条 `RuntimeRoomArtSource` 过期烘焙文件提示。其余 640 条全出自这一个判据。

## 一、为什么判据本身是错的

`expedition_static_layout_path()` 产出 `f00_<room>_static_layout.tscn`，这个路径有**两种用途**：

1. 远征01/02：它是**真的**房型模板场景，文件存在，按 `static_layout_scene_path` 直接加载。
2. 远征03 起：美术按复用键落到 `<锚点父目录>/runtime_rooms/<template>_<sig12>_<fp6>.tscn`。
   `RuntimeRoomArtSource.art_path()` 只取基准路径的 `get_base_dir()`，**文件名本身不参与**。

所以锚点文件对远征03 只是"目录锚点"，不必存在。预检查只查文件存在，等于对远征03
每一间房必然判假 —— 141 个房间 × 多楼层。

反证：同批日志末行 `COV_OK 缺口=0 未接管=0`，24 种子覆盖探针也是满的，
说明美术**全命中**，所谓"回退到程序化生成"根本没发生。

## 二、改动

`src/world3d/TowerDescent3D.gd`

- 新增 `static func has_runtime_room_art(layout_path: String) -> bool`：
  打开锚点父目录下的 `runtime_rooms/`，有 `.tscn`/`.scn`/`.res`/`.remap` 任一即算有美术。
  放宽扩展名是为了对「导出时转二进制资源」免疫 —— 否则打进包里这条告警还会回来。
- `_append_plan_room_record()` 的预检查改成
  `not ResourceLoader.exists(layout_path) and not has_runtime_room_art(layout_path)`。

**只动告警判据，不动任何加载/回退逻辑。** `DungeonRoom3D._expedition_static_layout_path()`
那条真回退路径一个字没改。

## 三、验收

| 用例 | 结果 |
|---|---|
| `tests/verification/probe_expedition03_playable.tscn` | exit 0，`PLAYABLE_OK`，`缺静态布局` 0 条，SCRIPT ERROR 0 |
| `tests/verification/probe_expedition02_assembly.tscn` | exit 0，`EXP02_ASSEMBLY_DONE`，0 条，SCRIPT ERROR 0 |
| `python3 scripts/check_level_decoupling.py` | `violations: 0` |

探针用 headless 跑（本次改动与渲染无关），`APPDATA`/`LOCALAPPDATA` 指到
`F:/wxgame/ShellStorm2-work/verify_appdata` 隔离存档。

## 四、遗留

- `runtime_rooms/` 里那 2 份签名不符的过期文件仍在包体内（`RuntimeRoomArtSource`
  已按 `stale_siblings` 告警，不再静默）。删或重新烘焙都可，本轮不动。
- 若某个关卡目录将来既无锚点文件、`runtime_rooms/` 也还是空的，告警会照常触发 ——
  这正是这个预检查本来要抓的"无声降级"。
