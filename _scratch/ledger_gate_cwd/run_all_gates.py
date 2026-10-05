from pathlib import Path
import json, subprocess
root=Path(r'I:/工作项目/shellstrom2/ShellStorm2')
out=root/'outputs/base99_radio_v001'
gate=root/'_scratch/ledger_gate_cwd'
py=r'C:/Users/zhuangmenghong/.workbuddy/binaries/python/envs/default/Scripts/python.exe'
commands={
 'structure':[py,str(root/'scripts/check_asset_registry.py'),'--project-root',str(root),'--scope','structure'],
 'full_props':[py,str(root/'scripts/check_asset_registry.py'),'--project-root',str(root),'--scope','full','--ledger','props'],
 'split':[py,str(root/'tools/asset_pipeline/verify_ledger_split.py'),'--project-root',str(root)],
 'naming':[py,str(root/'scripts/check_asset_runtime_naming.py'),'--json'],
}
results={}
for name,cmd in commands.items():
 p=subprocess.run(cmd,cwd=gate,capture_output=True)
 stdout=p.stdout.decode('utf-8','replace')
 stderr=p.stderr.decode('utf-8','replace')
 (out/f'gate_{name}_stdout.txt').write_text(stdout,encoding='utf-8')
 (out/f'gate_{name}_stderr.txt').write_text(stderr,encoding='utf-8')
 results[name]={'exit_code':p.returncode,'stdout':stdout,'stderr':stderr}
(out/'gate_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
lines=['ShellStorm2 收音机账本登记门禁结果','日期：2026-10-05','']
for name,r in results.items():
 lines += [f'[{name}] exit={r["exit_code"]}',r['stderr'].strip() or r['stdout'].splitlines()[-1] if r['stdout'].splitlines() else '无输出','']
lines += ['分类结论：structure 与 split 为本次登记后全量结构/无损结果；full_props 的 sha_mismatch 只落在登记前已有行（r10-r25），新增收音机 r27 未出现；naming 为既有运行时命名欠账，不归因于本次收音机登记。','模型状态：StatusLight 命名误报保留，模型门禁不宣称全过。']
(out/'gate_results.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
