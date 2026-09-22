from copy import copy
from datetime import datetime
from pathlib import Path
import shutil
import openpyxl

root = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
ledger = root / "assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx"
backup = ledger.with_name("ShellStorm2_特效账本_v001.xlsx.bak_vfx_shell_pbr2")
shutil.copy2(ledger, backup)

ASSET_ID = "VFX-SHELL-CASING-3D"
MARK = "PBR 定档"

wb = openpyxl.load_workbook(ledger)
fx = wb["3D-特效"]
master = wb["资产主表"]
log = wb["域变更日志"]

fx_row = next(r for r in range(1, fx.max_row + 1) if fx.cell(r, 2).value == ASSET_ID)
m_row = next(r for r in range(1, master.max_row + 1) if master.cell(r, 1).value == ASSET_ID)
print("FX_ROW", fx_row, "MASTER_ROW", m_row)

# --- 3D-特效：功能说明 + 备注 ---
note7 = (
    " PBR 定档（2026-09-22）：金属度 metallic=0.8、反光度（roughness）=0.6，"
    "壳体/底缘/底火三件统一，各件仅以基色区分；常量 SHELL_METALLIC / SHELL_ROUGHNESS。"
)
note17 = (
    " PBR：metallic=0.8 / roughness=0.6（常量 SHELL_METALLIC / SHELL_ROUGHNESS）；"
    "验收读已挂载材质真值（非常量回读）并附反向对照。"
)
if MARK not in str(fx.cell(fx_row, 7).value):
    fx.cell(fx_row, 7).value = str(fx.cell(fx_row, 7).value) + note7
if "metallic=0.8" not in str(fx.cell(fx_row, 17).value):
    fx.cell(fx_row, 17).value = str(fx.cell(fx_row, 17).value) + note17

# --- 资产主表：备注 ---
note25 = (
    " PBR 定档：金属度 metallic=0.8 / 反光度（roughness）=0.6，壳体/底缘/底火三件统一（2026-09-22 指定）。"
)
if "metallic=0.8" not in str(master.cell(m_row, 25).value):
    master.cell(m_row, 25).value = str(master.cell(m_row, 25).value) + note25

# --- 域变更日志：v0.1.4（幂等）---
existing = [str(log.cell(r, 1).value) for r in range(1, log.max_row + 1)]
if "v0.1.4" in existing:
    log_row = existing.index("v0.1.4") + 1
    print("LOG_ROW_EXISTING", log_row)
else:
    log_row = log.max_row + 1
    for c in range(1, 8):
        log.cell(log_row, c)._style = copy(log.cell(log.max_row, c)._style)
        log.cell(log_row, c).number_format = log.cell(log.max_row, c).number_format
    for c, value in enumerate([
        "v0.1.4", "2026-09-22", "条目更新", "特效 · 3D-特效",
        "FX01-07 VFX-SHELL-CASING-3D：PBR 定档为金属度 metallic=0.8、反光度 roughness=0.6，"
        "壳体/底缘/底火三件统一；原先三件各自分散的数值收敛为单一常量组 SHELL_METALLIC / SHELL_ROUGHNESS（各件仅保留基色差异）；"
        "专项验收新增 PBR 真值断言（读已挂载材质，期望值硬编码于验收侧）并附反向对照。",
        "仅材质参数变化，不影响 AssetID / Prefab 路径 / 尺寸契约 / 运动与落地行为；观感为更暗哑统一的黄铜金属弹壳。",
        "摩斯拉",
    ], 1):
        log.cell(log_row, c).value = value

wb.save(ledger)

check = openpyxl.load_workbook(ledger)
cfx, cm, cl = check["3D-特效"], check["资产主表"], check["域变更日志"]
print("FX_NOTE7_PBR", MARK in str(cfx.cell(fx_row, 7).value))
print("FX_NOTE17_PBR", "metallic=0.8" in str(cfx.cell(fx_row, 17).value))
print("MASTER_NOTE_PBR", "metallic=0.8" in str(cm.cell(m_row, 25).value))
print("LOG_ROW", log_row, cl.cell(log_row, 1).value, cl.cell(log_row, 2).value)
print("LOG_MAX_ROW", cl.max_row)
print("SHA_UNCHANGED", cm.cell(m_row, 20).value)
print("MASTER_MAX_ROW", cm.max_row, "FX_MAX_ROW", cfx.max_row)
print("DV_MASTER", len(cm.data_validations.dataValidation), "MERGED_MASTER", len(cm.merged_cells.ranges))
print("DV_FX", len(cfx.data_validations.dataValidation), "MERGED_FX", len(cfx.merged_cells.ranges))
print("BACKUP", backup)
