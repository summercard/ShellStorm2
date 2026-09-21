"""补齐 3D-场景通用 第146行（ENV-ROOFTOP-DECOR-LAYOUT-100F）的陈旧描述。

- c6：运行时实例数 99 → 120（六组完整列举）
- c16：补 2026-09-21 三次修正口径（立管落地 / 墙挂空调倾倒 / 欧拉序契约）

binary-safe：不改其它 sheet / 单元格；仅原地替换两个字符串。
"""
import shutil
from pathlib import Path

XLSX = Path("assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx")
BAK = XLSX.with_suffix(".xlsx.bak_rooftop_decor_generic_row")

SHEET = "3D-场景通用"
ROW = 146

OLD_C6 = "运行时重放 99 个装饰实例（空调6+绿化20+藤蔓11+水管54+立管支架8）"
NEW_C6 = "运行时重放 120 个装饰实例（空调6+绿化20+藤蔓16+女儿墙挂藤8+水管54+立管16）"

C16_APPEND = (
    "；2026-09-21 三次修正：立管落地 0~9.89m（h=件高4.945、倒装件原点在顶面）、"
    "墙挂空调绕 X 轴 90° 倾倒让风扇朝外（Godot 侧读 basis.y）、"
    "布局源只写 rotation_x_deg + rotation_y_deg（rz=0，规避 Blender XYZ 序 / Godot YXZ 序的次序差）"
)


def main() -> int:
    from openpyxl import load_workbook

    if not BAK.exists():
        shutil.copy2(XLSX, BAK)
        print("backup ->", BAK.name)

    wb = load_workbook(XLSX)  # 非 read_only，需写回
    ws = wb[SHEET]
    aid = ws.cell(ROW, 1).value
    assert aid == "ENV-ROOFTOP-DECOR-LAYOUT-100F", f"row {ROW} A 列不是 rooftop: {aid!r}"

    # --- c6 ---
    c6 = ws.cell(ROW, 6).value
    if c6 and OLD_C6 in c6:
        ws.cell(ROW, 6).value = c6.replace(OLD_C6, NEW_C6)
        print("c6 patched")
    elif c6 and NEW_C6 in c6:
        print("c6 already patched")
    else:
        raise SystemExit(f"c6 未命中旧串，实际为: {c6!r}")

    # --- c16 ---
    c16 = ws.cell(ROW, 16).value
    if c16 and "三次修正" not in c16:
        ws.cell(ROW, 16).value = c16 + C16_APPEND
        print("c16 appended")
    elif c16 and "三次修正" in c16:
        print("c16 already patched")
    else:
        raise SystemExit(f"c16 为空或异常: {c16!r}")

    wb.save(XLSX)
    print("saved", XLSX.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
