"""只读：核对门墙行的内容指纹在基线与当前账本之间是否真的变了。

verify_ledger_split.py 报 row_content_mutated 的依据是
`baseline["assets"][id]["v"] != _row_digest(当前行)`。
本次改了 M/N/O/P/T/W/Y 七列，却没报这条 —— 必须查清是「门禁漏检」还是
「指纹本来就只覆盖身份列」，否则「门禁通过」就是假绿。
"""

import json
import sys
from pathlib import Path

PROJECT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
sys.path.insert(0, str(PROJECT / "tools" / "asset_pipeline"))

from openpyxl import load_workbook  # noqa: E402

from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CONTENT_COLUMNS,
    FIRST_DATA_ROW,
    _row_digest,
    _text,
    read_source_rows,
)

ASSET_ID = "ENV-TOWER-WALL-DOOR-5M"
LEDGER = PROJECT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
BASELINE = PROJECT / "assets/registry/ledger_split_baseline.json"

print("CONTENT_COLUMNS = %s" % (CONTENT_COLUMNS,))
print("count           = %d" % len(CONTENT_COLUMNS))

baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
entry = baseline["assets"].get(ASSET_ID)
print("\nbaseline entry  = %s" % json.dumps(entry, ensure_ascii=False)[:400])
baseline_digest = entry["v"] if entry else None
print("baseline digest = %s" % baseline_digest)

wb = load_workbook(LEDGER)
ws = wb[ASSET_SHEET]
rows = read_source_rows(ws)
print("\nread_source_rows: %d rows, first row_number=%s" % (len(rows), rows[0][0]))

target = None
for row_number, values in rows:
    if _text(values[0]) == ASSET_ID:
        target = (row_number, values)
        break
if target is None:
    raise SystemExit("row for %s not found" % ASSET_ID)

row_number, values = target
current_digest = _row_digest(values)
print("ledger row      = %d" % row_number)
print("current digest  = %s" % current_digest)
print("digest changed  = %s" % (current_digest != baseline_digest))

# 逐列打印当前值，确认我改的那几列确实进了 values
for index, value in enumerate(values):
    text = _text(value)
    if text:
        print("  col[%02d] %s" % (index, text[:90]))
