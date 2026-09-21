# -*- coding: utf-8 -*-
"""四次修正收尾：把天台装饰「实例级碰撞策略」写进 MEMORY.md / playbooks，并向 _INDEX.md 追加事务行。

全部 binary-safe（读 bytes、按 \r\n 锚点插、写 bytes）。
"""
import io
import os

BASE = r"I:\工作项目\shellstrom2\.workbuddy\memory"


def patch(path, anchor, insert_after=False, expect=1, label=""):
    raw = open(path, "rb").read()
    a = anchor.encode("utf-8").replace(b"\n", b"\r\n")
    cnt = raw.count(a)
    assert cnt == expect, "%s anchor count=%d expect=%d" % (label, cnt, expect)
    if insert_after:
        raw = raw.replace(a, a + insert_after.encode("utf-8").replace(b"\n", b"\r\n"), 1)
    else:
        raw = raw.replace(a, insert_after.encode("utf-8").replace(b"\n", b"\r\n") + a, 1)
    open(path, "wb").write(raw)
    print("PATCHED %s" % label)


# ---------- 1) MEMORY.md：world3d 段末追加一条 ----------
mem = os.path.join(BASE, "MEMORY.md")
mem_anchor = (
    "- ⚠️ `DungeonRoom3D` 与 `TowerDescent3D` 的 `room.configure(...)` **各有两处**，"
    "少补一处不报错但该房静默退化成生成器白盒。入口安全屋 / 安全房四角 L 件 ⇒ playbooks。\n"
)
mem_add = (
    "- **天台装饰实例级碰撞**：装饰默认 `visual_only`（重放先关组件自带碰撞）；`collision_policy=\"blocking\"` 的件"
    "（白名单 flowerbox/plant_large/plant_small）由 `TowerFloorStage3D._apply_rooftop_collision_policy()` 按 "
    "`TowerGeometry3D.resolve_visual_bounds()` **实测可视包络**挂 `StaticBody3D`(layer=1,mask=0,ALWAYS)+`BoxShape3D`"
    " 代理（尺寸随美术走）；QA 读 `.blend`、运行时探针读 `.json`，两真源别混 ⇒ playbooks。"
)
patch(mem, mem_anchor, insert_after=mem_add, label="MEMORY.md")

# ---------- 2) playbooks：插在「lane 归属摆位模型」之前 ----------
pb = os.path.join(BASE, "MEMORY-playbooks.md")
pb_anchor = "### Blender 布局源摆放 · lane 归属摆位模型\n"
pb_sec = """### 运行时装配 · 天台装饰实例级碰撞策略 `collision_policy`（2026-09-21 四次修正）
- **装饰默认不挡人**：`TowerFloorStage3D` 重放时对每个装饰实例先 `_disable_rooftop_visual_collision()`，而 `flowerbox / plant_large / plant_small` 三件 prefab 本来也是纯可视件（`visual_only=true`、无碰撞节点）⇒ 绿化和所有装饰一样零碰撞（业主报「花盆和花圃没有阻挡」）。
- **只在声明处放行**：布局 JSON 每实例带 `collision_policy`，词表只有 `visual_only`（默认）/ `blocking`；`blocking` 只允许白名单 slug（`flowerbox / plant_large / plant_small`，20 件）。运行时 `_apply_rooftop_collision_policy()` 对 `blocking` 件挂 `StaticBody3D`（名 `BlockingCollision`，`collision_layer=1`、`mask=0`、`PROCESS_MODE_ALWAYS`）+ 子 `CollisionShape3D`（名 `BlockingBox`，`BoxShape3D`）。
- ⛔ **碰撞盒尺寸必须由 `TowerGeometry3D.resolve_visual_bounds(instance)` 量出实测可视包络**，不许写死常量（美术一改自动跟随）；退化包络（size≈0）直接跳过。`mask=0` 是对的：玩家 `collision_layer=1/mask=1` 要能**撞到**代理，代理自身不需要检测别人；`PROCESS_MODE_ALWAYS` 防被流送关闭的父节点连坐。
- 校验口径（两层都反向对照）：绿化必须**恰好 1 个启用形状**且 box 尺寸/中心 == 再算一遍的实测包络（`BLOCKING_BOX_TOL=0.01`）+ body `layer=1 / mask=0 / ALWAYS`；非绿化必须 **0** 个启用形状（防越权挡人）。
- ⚠️ **两个真源别搞混**：布局 QA（`validate_rooftop_decorated_layout_v001.py`）读 **`.blend`** 集合的 `collision_policy` 属性；运行时探针读 **`.json`**。只改一边时另一边的断言不会动 ⇒ 反向对照要分别打 `.json`（运行时红）与 `.blend`（QA 红）。
- ⚠️ 台账 `资产主表` 的 `SHA-256` 列 = **blend** 的 sha256（对应 `文件路径` 列的 `.blend`）；布局 `.blend`/`.json` **git 未跟踪** ⇒ 回滚只能靠字节快照（`_scratch/.../*.before*`），不能靠 `git checkout`。
- 防再犯的断言落点：QA 第 5 层（词表 + 白名单 slug + 计数 + 清单交叉一致）；两份运行时探针（`_check_blocking_proxy()`）；布局源自检（`BLOCKING_SLUGS` == 实际 blocking slug）。

"""
patch(pb, pb_anchor, insert_after=pb_sec, label="playbooks(before lane)")

# ---------- 3) _INDEX.md：追加表行 ----------
idx = os.path.join(BASE, "2026-09-21", "_INDEX.md")
row = (
    "| 16:31 | [天台装饰四次修正（花盆 / 花圃加上物理阻挡）](1631_天台装饰四次修正_花盆花圃碰撞.md) | **实际改动** | "
    "业主报「花盆和花圃没有阻挡」。根因：重放时**所有**装饰被无条件关碰撞，而 `flowerbox/plant_large/plant_small` 是纯可视件 "
    "⇒ 482 件全局零碰撞。修法：布局源 `add(collision=)` 加**实例级策略**（词表 visual_only/blocking，白名单三 slug），绿化 20 件改 `blocking`；"
    "运行时 `_apply_rooftop_collision_policy()` 按 `TowerGeometry3D.resolve_visual_bounds()` **实测可视包络**挂 `StaticBody3D`(layer=1,mask=0,ALWAYS)"
    "+`BoxShape3D` 代理（尺寸随美术走）。QA 新增第 5 层断言、两探针加 `_check_blocking_proxy`。**反向对照**：翻 JSON→两探针 exit 1；"
    "翻 .blend→QA 3 条 FAIL；还原后 .blend(`de1d7ce6…`)/.json(`fcf892d7…`) 逐字节一致。重放仍 120、8/8 验收 0 ERROR、"
    "账本门禁维持 46（row240 状态/规格/SHA + `3D-场景通用` 146 + 域日志 v0.1.8） |\n"
)
raw = open(idx, "rb").read()
if b"1631_" in raw:
    print("INDEX already has 1631")
else:
    if not raw.endswith(b"\n"):
        raw += b"\r\n"
    raw += row.encode("utf-8").replace(b"\n", b"\r\n")
    open(idx, "wb").write(raw)
    print("PATCHED _INDEX.md")

# ---------- 4) 行尾自检 ----------
for p in (mem, pb, idx, os.path.join(BASE, "2026-09-21", "1631_天台装饰四次修正_花盆花圃碰撞.md")):
    raw = open(p, "rb").read()
    print("EOL %-28s crlf=%d lone_lf=%d crcrlf=%d" % (
        os.path.basename(p), raw.count(b"\r\n"), raw.count(b"\n") - raw.count(b"\r\n"), raw.count(b"\r\r\n")))
