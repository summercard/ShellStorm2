import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path(__file__).parent
meta=json.loads((P/'animation_meta_v003.json').read_text());s=bpy.data.scenes[meta['clips'][2]['scene']];bpy.context.window.scene=s
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=520;s.render.resolution_y=520;s.render.resolution_percentage=100;s.world=bpy.data.worlds.new('QA');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[1].default_value=.8
for loc in [(3,4,4),(-3,1,3)]:
 d=bpy.data.lights.new('QA','AREA');d.energy=300;d.size=4;o=bpy.data.objects.new('QA',d);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('QA');d.type='ORTHO';d.ortho_scale=2.1;o=bpy.data.objects.new('QA',d);s.collection.objects.link(o);s.camera=o;o.location=(5,0,.9);o.rotation_euler=(Vector((0,.1,.9))-o.location).to_track_quat('-Z','Y').to_euler()
for f in [1,7,13,19]:
 s.frame_set(f);s.render.filepath=str(P/('v003_run_side_%02d.png'%f));bpy.ops.render.render(write_still=True)
