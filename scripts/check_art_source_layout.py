"""Check the editable-art boundary; never mutate assets."""
import json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    issues=[]
    if not (ROOT/'art_source/.gdignore').is_file():issues.append('Missing art_source/.gdignore')
    for folder in ['assets/art','source','tools/3Dgame-design/save']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and p.suffix.lower() in {'.blend','.psd','.kra','.xcf'}:
                issues.append('Authoring source outside art_source: '+p.relative_to(ROOT).as_posix())
    index=json.loads((ROOT/'assets/registry/current_source_index.json').read_text(encoding='utf8'))
    for source in index['sources']:
        if not source['path'].startswith('art_source/') or not (ROOT/source['path']).is_file():
            issues.append('Missing/misplaced current source: '+source['path'])
    files=[p.relative_to(ROOT).as_posix() for p in (ROOT/'art_source').rglob('*') if p.is_file()]
    result=subprocess.run(['git','-c','core.quotepath=false','check-ignore','--no-index','-z','--stdin'],cwd=ROOT,input=('\0'.join(files)+'\0').encode('utf8'),capture_output=True)
    if result.returncode not in (0,1):issues.append('git check-ignore failed: '+result.stderr)
    elif result.stdout:issues.extend('Source ignored by Git: '+s for s in result.stdout.decode('utf8').rstrip('\0').split('\0'))
    print(json.dumps({'source_files':len(files),'current_blends':len(index['sources']),'issues':issues},ensure_ascii=True))
    return bool(issues)

if __name__=='__main__':raise SystemExit(main())
