"""特效账本更新（幂等）：把 FX01-07 弹壳的口径刷到「程序化模拟碰撞 + 尺寸 80% + floor_y 契约」，
并同步 Prefab 的真实 sha256。

背景：Prefab 在 2026-09-22 08:47 被另一会话重存（Godot 去掉了 `load_steps` 提示行），
账本记录的哈希与磁盘实际不符 ⇒ 门禁多出一条 sha_mismatch。本脚本把账本刷成磁盘真值。

幂等判据：备注里是否已含 FIX_MARK；域变更日志 col1 是否已含 v0.1.5。
"""
from copy import copy
import hashlib
import shutil
from pathlib import Path

import openpyxl

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
LEDGER = ROOT / "assets" / "registry" / "ledgers" / "ShellStorm2_特效账本_v001.xlsx"
PREFAB = ROOT / "assets" / "art" / "vfx" / "combat_3d" / "vfx_shell_casing_root_top3d.tscn"
BACKUP = LEDGER.with_suffix(".xlsx.bak_vfx_shell_sim")

FIX_MARK = "【模拟碰撞】"
NEW_VERSION = "v0.1.5"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def set_cell(ws, row: int, col: int, value: str) -> None:
    """写值但保留原样式（openpyxl 的 _style 是 StyleArray，必须用 copy()）。"""
    src = ws.cell(row, col)
    dst = ws.cell(row, col)
    dst.value = value
    dst._style = copy(src._style)


def main() -> None:
    if not LEDGER.exists():
        raise SystemExit("账本不存在：%s" % LEDGER)
    if not BACKUP.exists():
        shutil.copy2(LEDGER, BACKUP)
        print("已备份 ->", BACKUP.name)

    actual_sha = sha256(PREFAB)
    print("Prefab 实际 sha256 =", actual_sha[:16], "...")

    wb = openpyxl.load_workbook(LEDGER)

    # ---------- 资产主表 row 22 ----------
    main_ws = wb["资产主表"]
    recorded = str(main_ws.cell(22, 20).value or "")
    if recorded != actual_sha:
        set_cell(main_ws, 22, 20, actual_sha)
        print("资产主表 row22 col20 哈希：%s -> %s" % (recorded[:16] or "(空)", actual_sha[:16]))
    else:
        print("资产主表 row22 col20 哈希已是最新，跳过")

    note = str(main_ws.cell(22, 25).value or "")
    if FIX_MARK not in note:
        note = note.rstrip() + (
            " " + FIX_MARK + "落地改为**纯程序化模拟碰撞**（解析式越线，不做任何物理射线/空间查询，"
            "Prefab 无碰撞体）：弹壳中心 y 越过「地面高度 + 贴地半径」即视为碰撞；"
            "运动为 飞行(弹跳) → 贴地滚动 → 躺平静止 三阶段；触地带挤压包络。"
            "视觉尺寸缩到原基准 **80%**（WeaponModel3D.SHELL_CASING_SIZE=0.8）。"
            "⚠️ context.floor_y 必须由调用方按真实世界给，禁以 0 兜底 —— 塔楼楼层向下建（98F ≈ -1176m），"
            "兜底 0 会让弹壳出生即判触地、瞬移到世界原点而看不见（2026-09-22 实机缺陷）；"
            "调用方口径 = 射击者站立面 y，见 WeaponModel3D._resolve_shell_floor_y()。"
            "贴地半径取三件最大径向半展 0.058（底缘），非壳体 0.045。"
        )
        set_cell(main_ws, 22, 25, note)
        print("资产主表 row22 col25 备注已补模拟碰撞口径")
    else:
        print("资产主表 row22 col25 已含标记，跳过")

    # ---------- 3D-特效 row 14 ----------
    fx_ws = wb["3D-特效"]
    if str(fx_ws.cell(14, 2).value) != "VFX-SHELL-CASING-3D":
        raise SystemExit("3D-特效 row14 不是弹壳行，实际=%s" % fx_ws.cell(14, 2).value)

    collide = str(fx_ws.cell(14, 11).value or "")
    if "模拟" not in collide:
        set_cell(fx_ws, 14, 11, "程序化模拟碰撞（解析式越线，无物理引擎）")
        print("3D-特效 row14 col11 碰撞方式：%s -> 程序化模拟碰撞" % collide)

    size = str(fx_ws.cell(14, 12).value or "")
    if "80%" not in size:
        set_cell(
            fx_ws,
            14,
            12,
            "视觉尺寸 80%（原基准 ×0.8）：壳体直径 0.046×2×0.8≈0.074m、底缘直径 0.058×2×0.8≈0.093m、"
            "长度 0.24×0.8=0.192m；弹出初速度右向 2.1m/s + 上抛 1.55m/s；lifetime 3.2s",
        )
        print("3D-特效 row14 col12 标准尺寸已按 80% 重写")

    fx_desc = str(fx_ws.cell(14, 7).value or "")
    if FIX_MARK not in fx_desc:
        fx_desc = (
            "枪械开火时从枪械右侧飞出的弹壳：黄铜色圆柱弹壳 + 底缘圆环 + 底火；由 VfxPool3D 按 AssetID 路由。"
            "弹壳脱离武器挂点进入世界空间，程序化重力 9.8m/s² 下落。" + FIX_MARK
            + "落地为纯程序化模拟碰撞（解析式越线判定，不做物理射线/空间查询，Prefab 无碰撞体）："
            "弹壳中心越过「地面高度 + 贴地半径」即触地；运动三阶段 飞行(含弹跳) → 贴地滚动 → 躺平静止；"
            "触地带挤压包络。手感参数：恢复系数 0.32 / 地面摩擦 0.42 / 自旋保留 0.68 / 最多 2 次弹跳 / 滚动衰减 3.4。"
            "视觉尺寸缩到原基准 80%，寿命 3.2s 回收。"
            "PBR 定档（2026-09-22）：金属度 metallic=0.8、反光度（roughness）=0.6，三件统一，"
            "常量 SHELL_METALLIC / SHELL_ROUGHNESS。"
        )
        set_cell(fx_ws, 14, 7, fx_desc)
        print("3D-特效 row14 col7 功能说明已重写")
    else:
        print("3D-特效 row14 col7 已含标记，跳过")

    fx_note = str(fx_ws.cell(14, 17).value or "")
    if FIX_MARK not in fx_note:
        fx_note = fx_note.rstrip() + (
            " " + FIX_MARK
            + "落地已由「物理射线/floor_y 兜底」改为**解析式模拟碰撞**（脚本内无任何物理 API，验收有源码级静态门禁）；"
            "尺寸缩到原基准 80%；贴地半径取三件最大径向半展 0.058（底缘 outer_radius）。"
            "⚠️ floor_y 必须由调用方按真实世界给（塔楼 98F ≈ -1176m），禁以 0 兜底，"
            "调用方=WeaponModel3D._resolve_shell_floor_y(shooter)（取射击者站立面）。"
            "验收 samples=14，含非零楼层端到端与弹壳出生于抛壳挂点断言；真渲染探针 probe_shell_casing_visual（3 机位）。"
        )
        set_cell(fx_ws, 14, 17, fx_note)
        print("3D-特效 row14 col17 备注已补模拟碰撞口径")
    else:
        print("3D-特效 row14 col17 已含标记，跳过")

    # ---------- 域变更日志 ----------
    log_ws = wb["域变更日志"]
    existing = {
        str(log_ws.cell(r, 1).value or "")
        for r in range(1, log_ws.max_row + 1)
    }
    if NEW_VERSION in existing:
        print("域变更日志已含 %s，跳过" % NEW_VERSION)
    else:
        target = log_ws.max_row + 1
        values = [
            NEW_VERSION,
            "2026-09-22",
            "条目更新",
            "特效 · 3D-特效",
            "FX01-07 VFX-SHELL-CASING-3D 弹壳：落地由「物理射线 / floor_y 兜底」改为**纯程序化模拟碰撞**"
            "（解析式越线判定，Prefab 无碰撞体，脚本内无任何物理查询 API）；运动改为 飞行(弹跳) → 贴地滚动 → 躺平静止 "
            "三阶段 + 触地挤压包络，手感常量收敛为一组；视觉尺寸缩到原基准 **80%**；"
            "贴地半径由壳体 0.045 修正为三件最大径向半展 0.058（底缘）；"
            "修复实机缺陷「弹壳特效没了」——floor_y 原硬编码 0，而塔楼楼层向下建（98F ≈ -1176m），"
            "导致弹壳出生即判触地、瞬移到世界原点；现由 WeaponModel3D._resolve_shell_floor_y(shooter) 取射击者站立面。"
            "资产主表 row22 哈希同步刷新为磁盘真值（Prefab 于 08:47 被重存、去掉 load_steps 提示行）。",
            "AssetID / Prefab 路径 / 版本号 v001 / PBR 定档值均不变；仅行为、尺寸常量与落地判据变化；"
            "调用方签名 _spawn_shell_casing(world) → (shooter: Node3D)（内部方法，无外部调用者）。",
            "摩斯拉",
        ]
        for col, value in enumerate(values, start=1):
            set_cell(log_ws, target, col, value)
        print("域变更日志新增 row%d = %s" % (target, NEW_VERSION))

    wb.save(LEDGER)
    print("已保存", LEDGER.name)


if __name__ == "__main__":
    main()
