# -*- coding: utf-8 -*-
import os

BASE = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-21"

# 1) 事务文件追加「收尾补记」
t = os.path.join(BASE, "1631_天台装饰四次修正_花盆花圃碰撞.md")
d = open(t, "rb").read().decode("utf-8")
add = (
    "\r\n## 收尾补记（验收实跑时发现，同一日）\r\n\r\n"
    "跑 8 个屋顶验收时，每条日志都带 **15 条 `ERROR:`**，全部是\r\n"
    "`Failed to load script \"res://src/vfx/VfxImpact3D.gd\" / \"VfxMuzzleFlash3D.gd\" with error \"Parse error\"`。\r\n"
    "排查：`git status` 显示 `src/vfx/VfxImpact3D.gd` / `VfxMuzzleFlash3D.gd` 为 **M（工作区已改）**，另有未跟踪新文件\r\n"
    "`src/vfx/ToonVfxGeometry.gd`(+`.uid`)；报错是「Cannot infer the type of … / Variant 类型推断警告当成错误」。\r\n"
    "⇒ 这是**另一个并发会话在改 VFX** 留下的中间态，**与本批无关**（本会话对 `src/vfx/**` 零写操作）。\r\n"
    "判读：8/8 场景 **non-VFX ERROR = 0**、各自判定行照常打印、`rc=0`；账本门禁仍 46"
    "（5 invalid_status / 18 path_not_found / 23 sha_mismatch，逐类与基线一致，`ROOFTOP-DECOR-LAYOUT-100F` **0 命中**）。\r\n"
    "未去动那两份 VFX 脚本（避免与并发会话互相覆盖）。\r\n"
)
if "收尾补记" not in d:
    d = d.rstrip() + "\r\n" + add
    raw = d.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
    open(t, "wb").write(raw)
    print("transaction note: appended")
else:
    print("transaction note: already has 补记")

# 2) 索引行加限定
idx = os.path.join(BASE, "_INDEX.md")
raw = open(idx, "rb").read()
old = "账本门禁维持 46（row240 状态/规格/SHA + `3D-场景通用` 146 + 域日志 v0.1.8） |".encode("utf-8")
if raw.count(old) == 1:
    new = ("账本门禁维持 46（row240 状态/规格/SHA + `3D-场景通用` 146 + 域日志 v0.1.8）；"
           "⚠️ 同日另有并发会话在改 VFX，验收日志含 VfxImpact/VfxMuzzleFlash 解析错误（本批 non-VFX ERROR=0） |").encode("utf-8")
    raw = raw.replace(old, new, 1)
    open(idx, "wb").write(raw)
    print("index: qualified")
else:
    print("index: anchor count", raw.count(old))
