"""把本轮事务条目插入 2026-09-22 索引顶部（索引文件为 CRLF 约定，必须按 CRLF 写）。"""
from pathlib import Path

P = Path(r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-22\_INDEX.md")

ENTRY = (
    "| 11:15 | [修复「弹壳特效没了」：floor_y 兜底 0 把弹壳瞬移到世界原点]"
    "(1115_弹壳特效消失修复_floor_y兜底0.md) | **Bug 修复（回归 + 验收补强 + 真渲染探针）** | "
    "主人报「弹壳特效没了」。根因是我上一轮改造引入的回归：`_spawn_shell_casing()` 把地面高度**硬编码 `0.0`**，"
    "而塔楼楼层**向下**建（`stage.position.y = -12 × floor_index`，98F ≈ **-1176 m**）⇒ 弹壳出生点即「低于地面」、"
    "**第一帧判定触地**被夹到 `y≈0.046` ⇒ 瞬移到世界原点、掉出玩家视野。"
    "**为什么之前全绿**：验收与探针都把武器摆在 y≈0 —— 恰好是 0 唯一正确的那一层，"
    "⇒「绝对高度」类常量在 y≈0 环境必然假绿，必须专造非零高度用例。"
    "修复：新增 `WeaponModel3D._resolve_shell_floor_y(shooter)` 取**射击者站立面**世界 y"
    "（玩家胶囊底面恰在 y=0、原点即脚底；失效回落枪身 y，**不以 0 兜底**）；`_spawn_shell_casing(world)` → `(shooter: Node3D)`。"
    "验收：`DEEP_FLOOR_Y=-1176` + 非零楼层端到端（枪与射击者同搬 98F，断言弹壳**出生在抛壳挂点**、留该层、精确贴该层地面、"
    "**绝不出现于世界原点附近**）；探针新增**深层楼机位**。RC6a/6b/6c 全红后复原。"
    "⚠️ 新坑：`call()` 类型不匹配（传 Node 给 `shooter: Node3D`）会抛 SCRIPT ERROR **静默截断整个接线用例**，"
    "只表现为 `samples` 没增 + 尾部 `resources still in use` 泄漏，验收仍打印 `_OK`。"
    "另修账本预存漂移（Prefab 08:47 被重存去掉 `load_steps`，三处哈希互不相同）→ 刷成磁盘真值 + 日志 v0.1.5，"
    "门禁回基线 `sha_mismatch=2`。`COMBAT_VFX_TOON_V002_OK samples=14` / `VFX_POOL_LIFECYCLE_OK` / "
    "`SHELL_CASING_VISUAL_OK captured=3`（gap_m=0.0000）+ 3 项武器回归全绿。14.6 补 v002.5。 |"
)

data = P.read_bytes()
assert b"\r" in data, "索引应为 CRLF 约定，实测无 CR —— 先确认口径再写"
text = data.decode("utf-8")
lines = text.split("\r\n")

if any(line.startswith("| 11:15 |") for line in lines):
    print("已存在 11:15 条目，跳过")
else:
    index = next(i for i, line in enumerate(lines) if line.startswith("|---"))
    lines.insert(index + 1, ENTRY)
    P.write_bytes("\r\n".join(lines).encode("utf-8"))
    print("已插入 11:15 条目（位置 %d）" % (index + 1))

check = P.read_bytes().decode("utf-8")
lone = check.replace("\r\n", "").count("\n")
print("复核：loneLF =", lone, "| 含 11:15 =", "| 11:15 |" in check)
for line in check.split("\r\n")[:7]:
    print("  ", line[:52])
