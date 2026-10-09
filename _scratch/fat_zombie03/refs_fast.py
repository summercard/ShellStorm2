import sys,os,json
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'scripts'))
import check_ledger_refs as c
def fast(root,suffixes):
 for base in c.SCAN_ROOTS:
  for parent,dirs,files in os.walk(root/base):
   dirs[:]=[d for d in dirs if d not in c.PRUNE_DIRS]
   for name in files:
    p=Path(parent)/name
    if p.suffix.lower() in suffixes and '.bak_' not in name:yield p
c.iter_files=fast
code=c.main()
p=root/'outputs/fat_zombie03_reduction/gates.json';d=json.loads(p.read_text());d['refs_original_interrupted']=d['refs'];d['refs']=code;d['refs_traversal']='os.walk prunes same PRUNE_DIRS before descent';d['reopen']=0;d['runtime']=0;d['real_render']=0;d['negative_loop_expected_exit']=1;p.write_text(json.dumps(d,indent=2))
sys.exit(code)
