import bpy,os,json
from pathlib import Path
out={'blend':bpy.data.filepath,'exists':os.path.exists(bpy.data.filepath),'images':[]}
for i in bpy.data.images:
    fp=i.filepath
    ab=bpy.path.abspath(fp) if fp else ''
    out['images'].append({'name':i.name,'filepath':fp,'is_relative':fp.startswith('//'),'abspath_norm':os.path.normpath(ab),'normalized_exists':os.path.exists(os.path.normpath(ab)),'raw_exists':os.path.exists(ab),'packed':bool(i.packed_file)})
out['mats']=[m.name for m in bpy.data.materials]
out['mat_ok']={m.name:[bool(n.image) for n in m.node_tree.nodes if n.type=='TEX_IMAGE'] for m in bpy.data.materials if m.use_nodes}
d=Path(bpy.data.filepath).parent
(d/'path_check.json').write_text(json.dumps(out,ensure_ascii=False,indent=1),encoding='utf-8')
