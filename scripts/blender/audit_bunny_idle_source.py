"""Read-only anatomy / preview audit for the three weapon standing idles."""
import bpy, json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
source = root / 'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v024/source/animation/chr_bunny01_animation_v024.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
s = next(s for s in bpy.data.scenes if s.get('preview_clip') == 'idle')
bpy.context.window.scene = s
s.frame_set(1)
r = next(o for o in s.objects if o.type == 'ARMATURE')
print('BUNNY_SOURCE_AUDIT', json.dumps({
    'scenes': [{'name':s.name, 'clip':s.get('preview_clip'), 'rigs':[(o.name,o.animation_data.action.name if o.animation_data and o.animation_data.action else '') for o in s.objects if o.type=='ARMATURE']} for s in bpy.data.scenes],
    'libraries':[{'file':l.filepath,'resolved':bpy.path.abspath(l.filepath)} for l in bpy.data.libraries],
    'bones':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'length':b.length,'pose':list(r.pose.bones[b.name].matrix.translation)} for b in r.data.bones},
    'objects':[{'name':o.name,'type':o.type,'hide':o.hide_render,'preview':bool(o.get('preview_only')),'variant':o.get('variant_id'),'parent':o.parent.name if o.parent else None} for o in s.objects],
    'actions':[(a.name,a.get('state_id'),list(a.frame_range)) for a in bpy.data.actions if a.library is None]
},ensure_ascii=False))
