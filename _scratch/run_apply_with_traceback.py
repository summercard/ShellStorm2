from pathlib import Path
import traceback
try:
    import runpy
    runpy.run_path('I:/工作项目/shellstrom2/ShellStorm2/_scratch/apply_base99_radio_ledger.py', run_name='__main__')
except Exception:
    Path('I:/工作项目/shellstrom2/ShellStorm2/_scratch/apply_radio_traceback.txt').write_text(traceback.format_exc(), encoding='utf-8')
    raise
