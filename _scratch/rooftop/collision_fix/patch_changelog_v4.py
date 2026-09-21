"""在 CHANGELOG.md 顶部（标题行之后）插入四次修正条目，保持 CRLF。"""
import sys

P = "docs/v0.1/development/CHANGELOG.md"
b = open(P, "rb").read()

ANCHOR = "# 游戏设计文档 v0.1 变更记录\r\n".encode("utf-8")
if b.count(ANCHOR) != 1:
    print("ANCHOR_FAIL count=%d" % b.count(ANCHOR))
    sys.exit(1)

SECTION = """## 2026-09-21｜四次修正 100F 天台装饰：花盆 / 花圃加上物理阻挡（可挡住玩家）

业主实机反馈：「花盆和花圃没有阻挡」—— 走在天台上可以直接穿过长条花箱与大/小盆栽。根因：装饰布局的**所有**实例都被 `TowerFloorStage3D` 无条件关掉碰撞（原始设计是纯视觉装饰），而 `flowerbox / plant_large / plant_small` 三件 prefab 是**纯可视件**（`visual_only=true`、不带碰撞节点）⇒ 482 件装饰**全局零碰撞**，绿化自然拦不住人。

**修法：给布局源加「实例级碰撞策略」，只让绿化 20 件 `blocking`**（原地修正，AssetID / layout_id / layout_version 不变）：

1. **布局源**（`author_rooftop_decorated_layout_v001.py`）：`add()` 新增 `collision` 参数（默认 `visual_only`），词表 `{visual_only, blocking}` 并硬断言白名单；绿化 6 处调用点（8 花箱 + 6 大盆栽 + 6 小盆栽）传 `blocking`。导出时写 `scene.collision_policy = "per_instance:visual_only(default)+blocking(greenery)"`，`design_intent` / `validation` 记 `blocking_collision_count=20` / `visual_only_collision_count=462`，并自检声明白名单 == 实际 blocking slug。
2. **运行时**（`TowerFloorStage3D.gd`）：新增 `_apply_rooftop_collision_policy(instance, slug, policy)` —— 不论策略**先关**组件自带碰撞（沿用旧行为），`blocking` 时用 **`TowerGeometry3D.resolve_visual_bounds()`** 量出该实例的**实测可视包络**，挂一个 `StaticBody3D`（名 `BlockingCollision`，`collision_layer=1`、`mask=0`、`PROCESS_MODE_ALWAYS`）+ 子 `CollisionShape3D`（`BoxShape3D`，尺寸 = 包络 size、位置 = 包络中心）。**碰撞盒尺寸随美术走、不写死常量**；`mask=0` 是因为玩家（`scenes/Player3D.tscn`，`layer=1/mask=1`）需要「撞得到」它，它自己不需要检测别人。未知策略值 → `push_error` 并跳过。候选根 meta 增 `collision_policy=per_instance` / `blocking_collision_count`。
3. **校验器**（`validate_rooftop_decorated_layout_v001.py`）新增**第 5 层断言**：策略值必须在词表内、`blocking + visual_only == 482`、blocking 的 slug 集合必须 == 白名单、blocking 计数必须 == 8+6+6、`visual_only == 482-20`，且**清单的 `design_intent` / `validation` 与 .blend 实测交叉一致**。
4. **两个运行时探针**（`probe_rooftop_decorated_layout.gd` / `probe_rooftop_decorated_stage_only.gd`）：绿化件必须**恰好 1 个启用碰撞形状**、且其 `BoxShape3D.size` / 中心必须与再算一遍的**实测可视包络**吻合（`BLOCKING_BOX_TOL=0.01`）、body 必须 `layer=1/mask=0/ALWAYS`；非绿化件必须 **0** 启用碰撞形状。

**反向对照（改坏→变红→还原→逐字节一致）**：把 20 件绿化翻回 `visual_only` ⇒ ① 两份运行时探针 `exit 1`（`blocking INST_368_flowerbox enabled shapes=0 expected=1` …）；② 直接在 `.blend` 侧翻坏 ⇒ 布局 QA `ROOFTOP_DECOR_LAYOUT_QA_FAIL` 报 3 条（`blocking slugs=[] / blocking instances=0 / manifest blocking_collision_count=20, actual 0`）。还原后 `.blend`（sha256 `de1d7ce6…`）与 `.json`（sha256 `fcf892d7…`）与快照**逐字节一致**、三类验收全绿。

门禁：`check_asset_registry --ledger scenes --scope full` 维持 **46**（**不新增资产、不新增条目**；布局 .blend 重生成 ⇒ 同步 row 240 的 SHA `09e9a917… → de1d7ce6…`）；场景账本 row 240 状态列 `static / visual_only → static / per_instance(visual_only+blocking)`、规格列 `0启用碰撞 → 20启用碰撞（绿化）`，`3D-场景通用` row 146（碰撞开关 未创建→开、碰撞归属 `引擎（visual_only）→ 引擎（per_instance：默认 visual_only，绿化 blocking）`、碰撞方式 → BoxShape3D 实测包络代理）与域变更日志 **v0.1.8** 同步；运行时清单 `rooftop_100f_decorated_runtime_manifest.json` 的 `collision_policy / enabled_collision_shapes(0→20) / collision_owner` 同步。**8/8 屋顶验收全绿 0 ERROR**：`probe_rooftop_decorated_layout`（`ROOFTOP_DECORATED_LAYOUT_RUNTIME_OK instances=120 groups=6 blocking=20 visual_collisions=0`）/ `probe_rooftop_decorated_stage_only`（`…_OK instances=120 blocking=20 visual_collisions=0`）/ 布局 QA（`…_QA_OK instances=482 … blocking=20 visual_only=462`）/ `verify_rooftop_32x32_contract` / `verify_rooftop_door` / `verify_base_rooftop_transit_door_motion` / `verify_rooftop_railing` / `verify_tower_grid_component_alignment` / `verify_rooftop_floor_facade_components`。

<br>

"""
SEC = SECTION.replace("\n", "\r\n").encode("utf-8")

b = b.replace(ANCHOR, ANCHOR + SEC, 1)
open(P, "wb").write(b)
print("CHANGELOG_V4_OK CR=%d LF=%d CRCRLF=%d" % (b.count(b"\r"), b.count(b"\n"), b.count(b"\r\r\n")))
