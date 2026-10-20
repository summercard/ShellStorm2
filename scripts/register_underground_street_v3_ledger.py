"""把「大世界 · 地下街区 编号02」从 v002 升级到 v003（主体楼深化）。

口径：
  · 同一 asset_id 只占**一行**（账本 R 列的 `COUNTIF(...)>1 → 重复` 是硬约束），
    所以 v003 不新增行，而是**升级第 973 行**：版本列 v002→v003，路径、规模、哈希全部换新。
  · v002 的 .blend 保留在磁盘上作可回退阶段文件，但不再作为账本的当前指向。
  · 变更日志新增一行 v0.1.47。
"""
import hashlib
import io
import json
import os

from openpyxl import load_workbook

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
LEDGER = os.path.join(ROOT, "assets", "registry", "ledgers", "ShellStorm2_场景账本_v001.xlsx")
ROW = 973
BLEND = os.path.join(ROOT, "art_source", "environments", "open_world", "source",
                     "underground_street", "v003", "env_underground_street_source_v003.blend")
REL = "art_source/environments/open_world/source/underground_street/v003/env_underground_street_source_v003.blend"
CATALOG = os.path.join(ROOT, "art_source", "environments", "open_world", "source",
                       "underground_street", "v003", "component_catalog.json")

catalog = json.load(io.open(CATALOG, encoding="utf-8"))
n_comp = catalog["unique_component_count"]
n_inst = catalog["total_instance_count"]
n_poly = sum(c["polygon_count"] for c in catalog["components"])
sha = hashlib.sha256(open(BLEND, "rb").read()).hexdigest()

wb = load_workbook(LEDGER)
ws = wb["资产主表"]

assert ws.cell(ROW, 1).value == "ENV-OPENWORLD-UNDERGROUND-STREET-02", ws.cell(ROW, 1).value
old_ver = ws.cell(ROW, 13).value

ws.cell(ROW, 13).value = "v003"
ws.cell(ROW, 15).value = REL
ws.cell(ROW, 14).value = (
    "Blender XYZ 52.0×52.0×30.4m 总包络（含穹顶）；组件 %d 件"
    "（v003 重写主体 5 件：酒店楼 6704 面 / 酒吧楼 3622 面 / 背景楼 2280 面 / HOTEL 与 BAR 招牌改几何笔画 /"
    " 新生产 4 件：路面标线组、人行道细节层、贴墙线束、墙面广告灯箱；其余 38 件复用 v002）"
    "/ 实例 %d 个 / %d 三角面；同族最大 2（≤3）；街区 open_world 地下区"
    % (n_comp, n_inst, n_poly))
ws.cell(ROW, 20).value = sha

# 变更日志（幂等：重跑时先删掉本版已写的那行，避免出现两条 v0.1.47）
log = wb["域变更日志"]
for rr in range(log.max_row, 1, -1):
    if log.cell(rr, 1).value == "v0.1.47":
        log.delete_rows(rr, 1)
r = log.max_row + 1
log.cell(r, 1).value = "v0.1.47"
log.cell(r, 2).value = "2026-10-20"
log.cell(r, 3).value = "地下街区02 主体楼深化"
log.cell(r, 4).value = "关卡场景 / 大世界 地下街区 编号02"
log.cell(r, 5).value = (
    "ENV-OPENWORLD-UNDERGROUND-STREET-02 版本 v002→v003：酒店/酒吧/背景楼三栋主体重写为"
    "带洞外壳真开洞，共 %d 面；两块竖招牌改为几何笔画；新增 4 件街面细节组件。" % n_poly)
log.cell(r, 6).value = (
    "第 973 行原地升级（同 asset_id 仍只占一行）；v002 的 .blend 保留为可回退阶段文件；"
    "组件 %d ≤ 50、同族最大 2 ≤ 3；验证器与源审计全绿；无 GLB / 无 PackedScene / 无碰撞。"
    % n_comp)
log.cell(r, 7).value = "Codex"

wb.save(LEDGER)
print("ROW", ROW, "ver", old_ver, "->", "v003")
print("sha", sha)
print("components", n_comp, "instances", n_inst, "polys", n_poly)
print("log row", r)
