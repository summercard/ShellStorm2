"""Check the development/backup boundary without deleting or moving files."""
import json
from pathlib import Path
import sync_runtime_design_data

ROOT=Path(__file__).resolve().parents[1]
TEMP_DIRS=['outputs','output','_scratch','_scratch_logs','build','.codex-tmp','.tmp','.tmp_plan','Godot']

def check():
    issues=[]
    for name in TEMP_DIRS:
        path=ROOT/name
        if path.exists() and any(p.name!='.gdignore' for p in path.iterdir()):
            issues.append('Development output inside project: '+name)
    for source,target in sync_runtime_design_data.mappings():
        if not source.is_file() or not target.is_file() or source.read_bytes()!=target.read_bytes():
            issues.append('Runtime design projection mismatch: '+str(target))
    presets=ROOT/'export_presets.cfg'
    if presets.is_file():
        import re
        for index,filters in enumerate(re.findall(r'^exclude_filter="([^"]*)"',presets.read_text(encoding='utf-8'),re.M)):
            for required in ['tests/*','tools/*','scripts/*','docs/*','assets/registry/*']:
                if required not in filters.split(','):issues.append('Export preset %d missing %s'%(index,required))
    else:issues.append('Missing local export_presets.cfg; restore export configuration before building')
    return issues

if __name__=='__main__':
    issues=check();print(json.dumps({'issues':issues},ensure_ascii=False,indent=2))
    raise SystemExit(bool(issues))
