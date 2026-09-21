from pathlib import Path
import openpyxl
p = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_特效账本_v001.xlsx")
wb = openpyxl.load_workbook(p)
ws = wb["资产主表"]
for dv in ws.data_validations.dataValidation:
    ref = str(dv.sqref)
    if ref == "C6:C21":
        dv.sqref = "C6:C22"
    elif ref == "K6:K21":
        dv.sqref = "K6:K22"
    elif ref == "L6:L21":
        dv.sqref = "L6:L22"
wb.save(p)
check = openpyxl.load_workbook(p)
print([(str(x.sqref), x.formula1) for x in check["资产主表"].data_validations.dataValidation])
