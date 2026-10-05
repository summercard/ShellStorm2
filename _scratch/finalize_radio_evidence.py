from pathlib import Path
from collections import Counter
import hashlib,json,shutil,traceback
import openpyxl
root=Path('I:/工作项目/shellstrom2/ShellStorm2'); log=root/'_scratch/finalize_radio_trace.txt'
try:
 exec(Path(root/'_scratch/finalize_radio_evidence_body.py').read_text(encoding='utf-8'),globals())
except Exception: log.write_text(traceback.format_exc(),encoding='utf-8'); raise
