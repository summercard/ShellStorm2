"""删除场景账本中的旧聚落天台条目。

范围（2026-09-19 用户要求删除旧的那套）：
  - 资产主表 ENV-ROOFTOP-SHELTER-50M-3D / ENV-ROOFTOP-SHELTER-90X80
  - 3D-场景通用 ENV-ROOFTOP-SHELTER-90X80
  - 解除参考组件库上指向已删条目的「变体父ID」

派生列公式 / DV / 条件格式 / autofilter / 总览跨度，
一律 import split_asset_ledger（项目约定的唯一公式定义处），不另抄一份。
"""
import sys
from pathlib import Path
from shutil import copyfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
sys.path.insert(0, str(ROOT / "scripts"))

import openpyxl  # noqa: E402
import split_asset_ledger as SAL  # noqa: E402

LEDGER = ROOT / "assets" / "registry" / "ledgers" / "ShellStorm2_场景账本_v001.xlsx"
DROP_IDS = {"ENV-ROOFTOP-SHELTER-50M-3D", "ENV-ROOFTOP-SHELTER-90X80"}
OLD_LAST = 241


def _rows_with(ws, ids):
    return [
        r
        for r in range(SAL.FIRST_DATA_ROW, ws.max_row + 1)
        if str(ws.cell(r, 1).value).strip() in ids
    ]


def main() -> None:
    backup = LEDGER.parent / (LEDGER.name + ".bak_old_rooftop_removal")
    if not backup.exists():
        copyfile(LEDGER, backup)
        print("backup:", backup.name)

    wb = openpyxl.load_workbook(LEDGER)

    # 1) 资产主表：删条目行
    ws = wb[SAL.ASSET_SHEET]
    hits = _rows_with(ws, DROP_IDS)
    print("资产主表 待删行:", hits)
    for r in sorted(hits, reverse=True):
        print("  删除 r%d  %s" % (r, ws.cell(r, 1).value))
        ws.delete_rows(r, 1)

    # 2) 解除悬空的「变体父ID」
    for r in range(SAL.FIRST_DATA_ROW, ws.max_row + 1):
        if str(ws.cell(r, 7).value).strip() in DROP_IDS:
            print("  清空变体父ID r%d  %s" % (r, ws.cell(r, 1).value))
            ws.cell(r, 7).value = None

    last = max(
        r
        for r in range(SAL.FIRST_DATA_ROW, ws.max_row + 1)
        if ws.cell(r, 1).value not in (None, "")
    )
    row_count = last - SAL.HEADER_ROW
    print("资产主表 现为 %d 行 (第6..%d行)" % (row_count, last))
    SAL.rescope_asset_sheet(ws, row_count)

    # 3) 总览：把所有引用旧末行的跨度改到新末行
    ov = wb["总览"]
    token_old = "$%d" % OLD_LAST
    token_new = "$%d" % last
    changed = 0
    for r in range(1, ov.max_row + 1):
        for c in range(1, ov.max_column + 1):
            v = ov.cell(r, c).value
            if isinstance(v, str) and token_old in v:
                ov.cell(r, c).value = v.replace(token_old, token_new)
                changed += 1
    print("总览 跨度改写: %d 处 (%s -> %s)" % (changed, token_old, token_new))

    # 4) 3D-场景通用：删条目行
    page = wb["3D-场景通用"]
    phits = _rows_with(page, DROP_IDS)
    print("3D-场景通用 待删行:", phits)
    for r in sorted(phits, reverse=True):
        print("  删除 r%d  %s" % (r, page.cell(r, 1).value))
        page.delete_rows(r, 1)

    wb.save(LEDGER)
    print("saved:", LEDGER.name)


if __name__ == "__main__":
    main()
