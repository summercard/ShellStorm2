import bpy,json
from pathlib import Path
R=Path('/Users/summercards/ShellStorm2/outputs/verification/base_facility_east_v021')
assert json.loads((R/'scoped_validation.json').read_text())['passed']
for r in json.loads((R/'catalog.json').read_text()):
 c=bpy.data.collections[r['collection']];c['当前状态']='数据验收通过_按用户要求跳过图检';c['视觉验收']='用户要求跳过';c['正面方向']='+Y'
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
