"""独立VFX验收；启动Autoload前隔离用户目录，图片只在最小工程导入。"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import workspace_paths as wp

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--godot', default='I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe')
    args = parser.parse_args()
    mode = 'render' if args.render else 'logic'
    base = wp.work_path('sessions/2026-11-16_exp01_combat/vfx_followup/' + mode + '_' + time.strftime('%Y%m%d_%H%M%S') + '/result.json').parent
    env = os.environ.copy()
    for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME']:
        env[key] = str(wp.work_path(str(base.relative_to(wp.work_root())) + '/' + key.lower() + '/marker').parent)
    env['FAT_BREACH_EVIDENCE'] = str(base)
    # 最小工程仅导入四张专用纹理，不让editor触碰主工程和其他生产资产。
    imp = base / 'texture_import'
    imp.mkdir()
    (imp / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="VfxTextureImport"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    dest = imp / 'assets/art/vfx/textures'
    dest.mkdir(parents=True)
    for path in (ROOT / 'assets/art/vfx/textures').glob('vfx_fat_entry_breach_*.png'):
        shutil.copy2(path, dest / path.name)
    with (base/'import.log').open('w',encoding='utf-8') as log:
        result = subprocess.run([args.godot,'--headless','--path',str(imp),'--editor','--import'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
    if result.returncode:
        raise RuntimeError('专用贴图导入失败：'+str(base/'import.log'))
    for path in dest.glob('*.import'):
        text=path.read_text(encoding='utf-8').replace('mipmaps/generate=false','mipmaps/generate=true').replace('process/size_limit=0','process/size_limit=512')
        path.write_text(text,encoding='utf-8')
    with (base/'import.log').open('a',encoding='utf-8') as log:
        subprocess.run([args.godot,'--headless','--path',str(imp),'--editor','--import'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90,check=True)
    for path in dest.glob('*.import'):
        shutil.copy2(path,ROOT/'assets/art/vfx/textures'/path.name)
    for path in (imp/'.godot/imported').iterdir():
        shutil.copy2(path,ROOT/'.godot/imported'/path.name)
    command=[args.godot,'--path',str(ROOT),'--audio-driver','Dummy','--fixed-fps','60','--quit-after','900','--resolution','1280x720']
    command += ['--rendering-method','forward_plus','--rendering-driver','vulkan'] if args.render else ['--headless']
    command += ['res://tests/verification/verify_fat_entry_breach_vfx.tscn','--','--'+mode]
    with (base/'run.log').open('w',encoding='utf-8') as log:
        result=subprocess.run(command,env=env,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    text=(base/'run.log').read_text(encoding='utf-8',errors='replace')
    errors=[line for line in text.splitlines() if line.startswith(('SCRIPT ERROR:','ERROR:'))]
    report_path=base/'report.json'
    report=json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    passed=result.returncode==0 and not errors and report.get('passed',False) and (not args.render or ('Forward+' in text and 'Vulkan' in text and len(list(base.glob('fat_entry_*.png')))==5))
    summary={'passed':bool(passed),'exit_code':result.returncode,'engine_errors':errors,'checks':report.get('checks',0),'output':str(base),'command':command,'appdata_isolated_before_autoload':True,'renderer_verified':('Forward+' in text and 'Vulkan' in text)}
    (base/'result.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False,indent=2))
    for line in text.splitlines():
        if any(tag in line for tag in ['SCRIPT ERROR','ERROR:','Parse Error','FAT_BREACH_CAPTURE']):
            print(line)
    return 0 if passed else 1
if __name__=='__main__':
    raise SystemExit(main())
