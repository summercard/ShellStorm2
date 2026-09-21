from copy import copy
from datetime import datetime
from pathlib import Path
import hashlib
import shutil
import openpyxl

root = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
ledger = root / "assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx"
backup = ledger.with_name("ShellStorm2_特效账本_v001.xlsx.bak_vfx_shell_casing")
shutil.copy2(ledger, backup)

prefab_rel = "assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn"
script_rel = "src/vfx/VfxShellCasing3D.gd"
prefab = root / prefab_rel
script = root / script_rel
sha = hashlib.sha256(prefab.read_bytes()).hexdigest()
now = datetime(2026, 9, 22)

wb = openpyxl.load_workbook(ledger)
master = wb["资产主表"]
# AssetMasterTable already reserves rows through 115. Append to the first empty row, preserving table range.
master_row = next(r for r in range(6, master.max_row + 2) if master.cell(r, 1).value is None)
master_values = {
    1: "VFX-SHELL-CASING-3D",
    2: "抛壳落地特效",
    3: "特效",
    4: "战斗反馈",
    5: "FX01-07",
    8: "俯视3D",
    9: "开火抛壳/落地",
    10: "玩家/敌人远程枪械",
    11: "已完成",
    12: "P1",
    13: "v001",
    14: "PackedScene/程序运动",
    15: prefab_rel,
    16: script_rel,
    17: "弹壳,抛壳,落地,枪械反馈",
    18: f'=LOWER(TRIM(C{master_row})&"|"&TRIM(D{master_row})&"|"&TRIM(E{master_row})&"|"&TRIM(F{master_row})&"|"&TRIM(H{master_row})&"|"&TRIM(I{master_row}))',
    19: f'=IF(COUNTIF($R$6:$R$115,R{master_row})>1,"重复","唯一")',
    20: sha,
    21: "摩斯拉",
    22: now,
    23: "原创程序几何",
    24: "—",
    25: "独立纯视觉 Prefab，无碰撞体；每次成功开火生成 1 枚；从枪械右侧抛出，重力 9.8m/s²，命中地板最多 2 次小弹跳后静止，3.2s 回收；验收 verify_combat_vfx_toon_v002。",
}
for c in range(1, 26):
    master.cell(master_row, c)._style = copy(master.cell(21, c)._style)
    master.cell(master_row, c).number_format = master.cell(21, c).number_format
for c, value in master_values.items():
    master.cell(master_row, c).value = value

fx = wb["3D-特效"]
# Insert a row before the next section header, keeping group layout and existing entries intact.
fx.insert_rows(14, 1)
for c in range(1, 18):
    fx.cell(14, c)._style = copy(fx.cell(13, c)._style)
    fx.cell(14, c).number_format = fx.cell(13, c).number_format
fx_values = {
    1: "FX01-07",
    2: "VFX-SHELL-CASING-3D",
    3: "抛壳落地特效",
    4: prefab_rel,
    7: "枪械开火时从枪械右侧飞出的弹壳：黄铜色圆柱弹壳 + 底缘圆环 + 底火；由 VfxPool3D 按 AssetID 路由。弹壳脱离武器挂点进入世界空间，程序化重力 9.8m/s² 下落，命中地板最多 2 次小弹跳后静止，寿命 3.2s 回收。",
    8: script_rel,
    9: "无",
    10: "无",
    11: "程序射线落地",
    12: "直径约 0.09m；长度 0.24m；弹出初速度右向 2.1m/s + 上抛 1.55m/s；lifetime 3.2s",
    13: "原点=弹壳中心；朝向=圆柱 local Y 为壳体长轴；出生点取 EjectionSocket/TacticalSocket",
    14: "玩家/敌人远程枪械开火反馈",
    15: "已完成",
    16: "v001",
    17: "已实装；Prefab=assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn；脚本=src/vfx/VfxShellCasing3D.gd；根节点=VfxShellCasing3D(Node3D)；FX编号 FX01-07；调用方=WeaponModel3D._fire_now → _spawn_shell_casing；纯视觉无碰撞体，落地由现有物理射线或 floor_y 兜底；验收=verify_combat_vfx_toon_v002，含端到端右侧抛壳与反向对照。",
}
for c, value in fx_values.items():
    fx.cell(14, c).value = value
fx[2][0].value = str(fx[2][0].value).replace("共 11 条", "共 12 条")
fx[2][0].value += "【2026-09-22 进度】新增 FX01-07 VFX-SHELL-CASING-3D：开火抛壳、重力落地、最多两次小弹跳后静止，接入 WeaponModel3D 与 VfxPool3D。"

log = wb["域变更日志"]
log_row = log.max_row + 1
for c in range(1, 8):
    log.cell(log_row, c)._style = copy(log.cell(log.max_row, c)._style)
log_values = [
    "v0.1.3", "2026-09-22", "新增条目", "特效 · 3D-特效",
    "新增 FX01-07 VFX-SHELL-CASING-3D 抛壳落地特效：独立 Prefab + 脚本，接入 WeaponModel3D 开火链路与 VfxPool3D；弹壳从枪械右侧抛出，按重力下落，最多两次小弹跳后静止并回收；补专项验收与反向对照。",
    "新增一个 AssetID；不改既有 AssetID；纯视觉无碰撞体；开火调用向后兼容。", "摩斯拉"
]
for c, value in enumerate(log_values, 1):
    log.cell(log_row, c).value = value

wb.save(ledger)
check = openpyxl.load_workbook(ledger)
assert check["资产主表"].cell(master_row, 1).value == "VFX-SHELL-CASING-3D"
assert check["3D-特效"].cell(14, 2).value == "VFX-SHELL-CASING-3D"
assert check["域变更日志"].cell(log_row, 1).value == "v0.1.3"
print("UPDATED", ledger)
print("BACKUP", backup)
print("MASTER_ROW", master_row)
print("FX_ROW", 14)
print("LOG_ROW", log_row)
print("PREFAB_SHA", sha)
print("DV_MASTER", len(check["资产主表"].data_validations.dataValidation))
print("MERGED_MASTER", len(check["资产主表"].merged_cells.ranges))
print("DV_FX", len(check["3D-特效"].data_validations.dataValidation))
print("MERGED_FX", len(check["3D-特效"].merged_cells.ranges))
