#!/usr/bin/env python3
"""Project editable layout JSON into an explicit, exportable runtime directory.

Design files remain authoritative. --check verifies byte-identical projections.
No source file, registry row, or gameplay parameter is changed by this tool.
"""
import argparse,hashlib,json,shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def mappings():
    level_root=ROOT/'source/art/whitebox/tower_zones'
    for level in sorted(level_root.iterdir()):
        if not level.is_dir():continue
        version='v004' if level.name=='battle_level01' else 'v001'
        source=level/version/'data'
        if not (source/'level_plan.json').is_file():continue
        for path in sorted(source.rglob('*.json')):
            yield path,ROOT/'data/level_plans'/level.name/path.relative_to(source)
    yield (ROOT/'source/art/blender/master_office_layout/source/block_00_master_office_layout_v002.layout.json',
           ROOT/'data/layouts/block_00_master_office_layout.json')
    expedition=ROOT/'assets/art/environments/tower_zones/expedition/source'
    yield expedition/'room_types/boss_room/v002/boss_room_50x40_v002.layout.json',ROOT/'data/layouts/expedition/boss_room.json'
    for version in ['v009','v010','v014','v012','v011']:
        yield expedition/'common_components'/version/'component_instances.json',ROOT/'data/layouts/expedition'/version/'component_instances.json'
    for room in ['f00_room_03','f00_room_04']:
        yield expedition/'room_instances'/room/'v001/room_layout.json',ROOT/'data/layouts/expedition'/room/'room_layout.json'
    yield ROOT/'assets/art/environments/tower_zones/rooftop/source/layouts/100f_decorated_v001/rooftop_100f_decorated_layout_v001.json',ROOT/'data/layouts/rooftop_100f_decorated_layout.json'

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    manifest=[];issues=[]
    for source,target in mappings():
        if not source.is_file():issues.append('missing source: '+str(source));continue
        content=source.read_bytes();json.loads(content)
        if args.check:
            if not target.is_file() or target.read_bytes()!=content:issues.append('projection drift: '+str(target))
        else:
            target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
        manifest.append({'source':source.relative_to(ROOT).as_posix(),'runtime':target.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(content).hexdigest()})
    manifest_path=ROOT/'data/runtime_design_data_manifest.json'
    expected={'schema':'shellstorm2.runtime_design_data_projection','files':manifest}
    if args.check:
        if not manifest_path.is_file() or json.loads(manifest_path.read_text(encoding='utf-8'))!=expected:issues.append('projection manifest drift')
    elif not issues:manifest_path.write_text(json.dumps(expected,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'files':len(manifest),'issues':issues},ensure_ascii=False))
    return bool(issues)
if __name__=='__main__':raise SystemExit(main())
