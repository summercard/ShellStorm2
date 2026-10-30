import bpy, json
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=R.parent/'ShellStorm2-work/manor_v017'
# Final comparison pass: charcoal stone and less oblique overview to reveal the bath and entrance.
col=bpy.data.collections['Component_manor_floor_stone']
im=next(i for i in bpy.data.images if i.filepath.endswith('512.png'));px=list(im.pixels)
def cell(rgb):
 return min(((sum((px[(int((y+.5)*51.2)*512+int((x+.5)*51.2))*4+i]-rgb[i])**2 for i in range(3)),x,y) for y in range(10) for x in range(10)))[1:]
old=cell((.23,.24,.24));new=cell((.08,.075,.065))
for o in col.objects:
 if o.type!='MESH':continue
 uv=o.data.uv_layers.active
 for p in o.data.polygons:
  v=uv.data[p.loop_indices[0]].uv
  if (int(v.x*10),int(v.y*10))==old:
   for li in p.loop_indices:uv.data[li].uv.x+=(new[0]-old[0])/10;uv.data[li].uv.y+=(new[1]-old[1])/10
sc=bpy.context.scene;cam=bpy.data.objects['参考顶视相机'];cam.location=(0,-8,38);cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler();sc.camera=cam
sc.render.filepath=str(W/'manor_final.png');bpy.ops.render.render(write_still=True)
# A close view verifies furnishings beyond the full-room thumbnail.
d=bpy.data.cameras.new('会客前台近景');d.type='ORTHO';d.ortho_scale=16;o=bpy.data.objects.new('会客前台近景',d);bpy.data.collections['90_展示与验收_灯光相机'].objects.link(o);o.location=(-5,-12,15);o.rotation_euler=(Vector((-5,2,0))-o.location).to_track_quat('-Z','Y').to_euler();sc.camera=o;sc.render.filepath=str(W/'manor_detail.png');bpy.ops.render.render(write_still=True)
sc.camera=cam;bpy.ops.wm.save_as_mainfile(filepath=str(S/'复古公馆_模块化组件母版_v017.blend'))
print('FINAL_VISUAL_PASS')
