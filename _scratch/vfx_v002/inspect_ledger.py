## 只读探查特效账本：3D-特效 分页结构 + 域变更日志尾部
import openpyxl

PATH = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_特效账本_v001.xlsx"
wb = openpyxl.load_workbook(PATH)

print("=== sheets ===")
for name in wb.sheetnames:
    ws = wb[name]
    print("  %-16s dims=%s rows=%d cols=%d" % (name, ws.dimensions, ws.max_row, ws.max_column))

ws = wb["3D-特效"]
print("\n=== 3D-特效 表头 + 前 16 行 ===")
for row in ws.iter_rows(min_row=1, max_row=min(16, ws.max_row)):
    vals = []
    for cell in row:
        v = cell.value
        if v is None:
            v = ""
        vals.append(str(v).replace("\n", "\\n")[:38])
    line = " | ".join(vals).rstrip(" |")
    if line.strip():
        print("R%02d: %s" % (row[0].row, line))

print("\n=== 域变更日志 全部 ===")
ws2 = wb["域变更日志"]
for row in ws2.iter_rows(min_row=1, max_row=ws2.max_row):
    vals = [("" if c.value is None else str(c.value).replace("\n", "\\n")[:60]) for c in row]
    line = " | ".join(vals).rstrip(" |")
    if line.strip():
        print("R%02d: %s" % (row[0].row, line))

print("\n=== 合并单元格(3D-特效) ===", list(ws.merged_cells.ranges)[:12])
