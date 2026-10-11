from pathlib import Path
import json,shutil
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001';V=O/'runtime_probe'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
# Change audited import option to trigger post-import now that shared palette is available.
for p in m['packages']:
    src=Path(p['expected_glb']);f=V/src.relative_to(R);ip=Path(str(f)+'.import');text=ip.read_text(encoding='utf-8');text=text.replace('nodes/root_name=""','nodes/root_name="prp_'+p['package_id']+'"');ip.write_text(text,encoding='utf-8')
# Public palette import must retain lossless + no mipmaps in isolated test.
pal=V/Path(m['palette']).relative_to(R);ip=Path(str(pal)+'.import');text=ip.read_text(encoding='utf-8').replace('compress/mode=3','compress/mode=0').replace('compress/mode=2','compress/mode=0').replace('mipmaps/generate=true','mipmaps/generate=false');ip.write_text(text,encoding='utf-8')
print('PROBE_REIMPORT_PREPARED')
