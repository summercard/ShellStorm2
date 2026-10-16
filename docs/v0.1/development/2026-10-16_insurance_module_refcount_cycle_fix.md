# InsuranceModule ↔ InventoryModule 引用环导致导出包冒烟失败（2026-10-16）

- FeatureID：`INVENTORY-SLOTS` / `RELEASE-PIPELINE`
- 触发：每日发布流水线第 2 步「验证」的第 3 道门禁（隔离冒烟）连续两次失败，发布中止

## 一、症状

`python scripts/daily_release.py` 在冒烟门禁失败，中止发布：

```
SMOKE_FAILED
  ❌ 日志出现 1 行 ERROR

ERROR: 2 resources still in use at exit.
   at: clear (core/io/resource.cpp:805)
Resource still in use: res://src/game/InventoryModule.gd (GDScript)
Resource still in use: res://src/game/InsuranceModule.gd (GDScript)
```

**不是「启动即失败」**：退出码 0、无 `Can't open` / `启动失败` / `Failed loading resource`、隔离目录内正常新建 `base_save.json`（revision=4）。坏在**退出阶段**。

- 05:01 首次执行、08:19 重试执行，源码未变 ⇒ 失败**逐项一致**（同一行号 `run_headless.log:2780`、同 2 个资源、同为 26 个泄漏实例）⇒ **确定性回归，非时序抖动**。
- 10-14、10-15 两次发布均 `SMOKE_OK`（0 行 ERROR）⇒ 本轮新引入。

## 二、根因：RefCounted 引用环

`src/game/InsuranceModule.gd`（修复前）：

```gdscript
func _init(max_slots: int = DEFAULT_INSURANCE_SLOTS) -> void:
	_board = InventoryModule.new(maxi(1, max_slots))
	_board.inventory_changed.connect(func() -> void: insurance_changed.emit())   # ← 环在这里
```

- `InsuranceModule`（`RefCounted`）强引用 `_board`（`InventoryModule`，同为 `RefCounted`）；
- 该 lambda **闭包捕获 `self`**（要调 `insurance_changed.emit()`），而生成的 `Callable` 被存进 **`_board` 的信号表**；
- ⇒ `_board` → lambda → `self` 构成**反向强引用**，环闭合。

Godot 的 `RefCounted` 是纯引用计数、**没有环收集**，环永不归零 ⇒ 两个实例同时泄漏 ⇒ 两个脚本资源在退出时仍被引用 ⇒ 报的正好是 **2 个资源**，与两个文件一一对应。

与外部持有者无关：`Dungeon3D._insurance`（`Dungeon3D.gd:310` / `:1413`）即使被释放也救不了，环在模块内部。

`set_max_slots()`（原第 15–21 行）有**同一处**连接，同样成环。

## 三、修复

保持行为不变，把反向引用改弱（`WeakRef` + 静态转发，`bind` 的绑定参数不构成对被绑定者的强引用）：

```gdscript
func _init(max_slots: int = DEFAULT_INSURANCE_SLOTS) -> void:
	_bind_board(InventoryModule.new(maxi(1, max_slots)))

static func _relay_inventory_changed(owner_ref: WeakRef) -> void:
	var owner: Object = owner_ref.get_ref()
	if owner != null:
		owner.emit_signal("insurance_changed")

func _bind_board(board: InventoryModule) -> void:
	_board = board
	_board.inventory_changed.connect(_relay_inventory_changed.bind(weakref(self)))
```

`set_max_slots()` 同样换成弱转发，**连接时机仍保持在 `restore_slots_snapshot()` 之后**（与原实现一致），避免恢复过程多冒一次 `insurance_changed`。

**否决的方案**：在 `_notification(NOTIFICATION_PREDELETE)` 里手动 `disconnect` —— 环不归零就永远不会走到 `PREDELETE`，改不到根上。改 `InventoryModule` 的基类（脱离 `RefCounted`）影响面远大于收益。

## 四、验收

| 项 | 结果 |
|---|---|
| 源码级 headless 复跑（隔离 `APPDATA`） | `^ERROR` **0 行**、`Resource still in use` **0 条** |
| `check_export_runtime_refs.py` | `EXPORT_RUNTIME_REFS_OK` |
| `check_fixture_shadow_casting.py` | `FIXTURE_SHADOW_CASTING_OK` |
| `smoke_exported_pack.py`（导出包，隔离 `APPDATA`） | **`SMOKE_OK`** |
| 修复前后对照 | 修复前 1 行 ERROR / 2 个资源 / 26 泄漏实例 → 修复后 0 / 0 / 0 |

导出包：`413,202,552 B`，SHA256 `8d348a0c72ce720f85558599412b2ce3733854e123c5c2c9fd0250859f73dbfd`，已发布。
线上独立复验：直链 HTTP 200 / Content-Length 一致 / **整包下载重算 SHA256 逐字节一致**。

功能回归（直接跑测试场景，隔离 `APPDATA`）：

| 用例 | 结果 |
|---|---|
| `verify_grid_inventory_layout` | `GRID_INVENTORY_LAYOUT_OK` rc=0 |
| `verify_runtime_autosave_flow` | `RUNTIME_AUTOSAVE_OK`（含保险格恢复）rc=0 |
| `verify_weapon_instance_fate_ownership_flow` | **失败，但与本修复无关** —— 见第六节（已用「临时还原修复前源码」跑基线证明同样失败） |

> 注：`bash scripts/run_verification_suite.sh batch …` 本轮未跑通 —— 其收尾清理触发本机 safe-delete 的
> 单轮 50 项批量删除确认，套件在拷贝工作区阶段即中止。上述用例改为直接 `--scene` 运行。

## 五、遗留：同类隐患的通用判据

**凡是「A 持 B，且把捕获 A 的 lambda 连到 B 的信号上」，A、B 都是 `RefCounted` 时就成环。**
同一模式需排查其它 `RefCounted` 模块对（含 UI 侧）。当前门禁只在退出时报「`N resources still in use at exit`」，
`N` 与泄漏文件数一一对应 —— 这是目前唯一会失败的断言，**不要为放行放宽「0 行 ERROR」阈值**。

## 六、同轮发现、未处理（如实登记）

`verify_weapon_instance_fate_ownership_flow` 稳定崩溃，**与本轮引用环修复无关**（已用修复前源码跑基线复现同一处）：

```
SCRIPT ERROR: Out of bounds get index '0' (on base: 'Array[Dictionary]')
   at: _ready (res://tests/verification/verify_weapon_instance_fate_ownership_flow.gd:87)
```

**根因：测试夹具的容量写死了「格子化之前」的语义。** 该用例在第 82 / 85 行造小容量容器：

```gdscript
var duplicate_inventory := InventoryModule.new(2)
var insurance := InsuranceModule.new(2)
```

- 旧「独立槽位」语义下，`2` = 「能放 2 件物品」，武器占 1 槽 ⇒ 通过。
- 10-15 棋盘式格子背包上线后，占格按**面积与形状**算：出厂枪是远程武器 `[4, 2]` ⇒ **8 格**（`ItemRegistry.GRID_SIZES`）。
- 而 `InventoryModule.GRID_COLUMNS = 8`，`capacity = 2` 只给 **1 行 × 2 格**，任何高 ≥2 的物品都**放不下**
  ⇒ `find_valid_placement()` 返回空 ⇒ `insure_item_direct()` 返回 `false` ⇒ `get_occupied_slots()` 为空 ⇒ 第 87 行 `[0]` 越界。

**最小可用容量（给公式）**：能容纳 `[4, 2]` 需 `列 ≥ 4` 且 `行 ≥ 2`；在 `GRID_COLUMNS = 8` 下
`capacity ≥ 8 × 2 = 16`。生产默认值 `DEFAULT_INSURANCE_SLOTS = 16`、`DEFAULT_CAPACITY = 24` **都满足**，
⇒ **产品路径不受影响，是本测试夹具的容量过期**（第 86 行的 `_check` 同样会红）。

**未改动**：该用例属 10-15 在改的背包/保险活稿，容量取值应由该轮作者一并裁定；本轮发布门禁不包含它，不影响今日发布。

