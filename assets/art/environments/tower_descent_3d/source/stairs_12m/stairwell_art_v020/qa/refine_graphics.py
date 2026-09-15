import bpy, math
def graphic(name,verts,faces,cells,coll):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    old=bpy.data.objects.get(name)
    if old:bpy.data.objects.remove(old,do_unlink=True)
    o=bpy.data.objects.new(name,me);bpy.data.collections[coll].objects.link(o)
    me.materials.append(bpy.data.materials['02_细腻哑光_青绿大面'])
    uv=me.uv_layers.new(name='PaletteUV')
    for p,cell in zip(me.polygons,cells):
        for j,k in enumerate(p.loop_indices):
            a=2*math.pi*j/len(p.loop_indices);uv.data[k].uv=((cell[0]+.5)/10+.026*math.cos(a),(cell[1]+.5)/10+.026*math.sin(a))
    uv.active_render=True;o['asset_detail_version']='v020';return o
# Reference warning triangle, clear at normal viewing distance.
x=33.92;z=-4.84;y=-1.785
v=[(x-.28,y,z-.22),(x+.28,y,z-.22),(x,y,z+.28),(x-.20,y-.001,z-.18),(x+.20,y-.001,z-.18),(x,y-.001,z+.18)]
graphic('主墙右侧警示箱_三角警告图标',v,[(0,1,4,3),(1,2,5,4),(2,0,3,5)],[(5,5)]*3,'控制盒_装饰组件')
graphic('主墙右侧警示箱_闪电图标',[(x-.01,y+.002,z+.1),(x+.08,y+.002,z-.025),(x+.005,y+.002,z-.025),(x+.05,y+.002,z-.14),(x-.09,y+.002,z+.02),(x-.02,y+.002,z+.02)],[(0,1,2,3,4,5)],[(9,0)],'控制盒_装饰组件')
label=bpy.data.objects['主墙右侧警示箱_铭牌'];label.location.z=-5.35;label.scale*=.62
# Side poster uses the reference orange exploration symbol, distinct from WORK poster.
name='侧墙探索海报_山形印刷';u=13.4;z=-3.;w=2.7;h=4.5
def p(a,b,d=.204):return (47.19-d,u-a*w,z+b*h)
v=[p(-.40,-.12),p(-.23,.31),p(-.05,.06),p(.18,.39),p(.38,-.12),p(.15,-.20),p(-.2,-.20)]
faces=[tuple(range(7))];cells=[(5,6)]
n=len(v);v += [p(-.025+.080*math.cos(i*math.pi/12),-.06+.062*math.sin(i*math.pi/12),.207) for i in range(24)]
faces.append(tuple(range(n,n+24)));cells.append((9,9))
graphic(name,v,faces,cells,'楼层标识与海报_装饰组件')
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
