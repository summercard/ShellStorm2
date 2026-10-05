from pathlib import Path
import traceback
try:
    exec(Path(r'I:/工作项目/shellstrom2/ShellStorm2/_scratch/finalize_radio_evidence_body.py').read_text(encoding='utf-8'), globals())
except BaseException:
    Path(r'I:/工作项目/shellstrom2/ShellStorm2/_scratch/finalize_local_trace.txt').write_text(traceback.format_exc(), encoding='utf-8')
    raise
