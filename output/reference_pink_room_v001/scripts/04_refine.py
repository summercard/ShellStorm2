# Correct render-observed geometry and color issues.
for o in list(packs['06_床与床品'].objects):
 if o.name.startswith(('粉色垂坠','被面滚边','被头折边')):bpy.data.objects.remove(o,do_unlink=True)
COL=packs['06_床与床品']
verts=[];faces=[];nx=72;ny=76
for j in range(ny+1):
 y=-.555+j*1.015/ny
 for i in range(nx+1):
  u=-1+2*i/nx;x=1.1+u*.412
  side=max(0,(abs(u)*.412-.377)/.035)
  foot=max(0,(-y-.465)/.09)
  z=.483-.132*side**.72-.104*foot**.72
  z+=.0025*sin(i*.49+j*.28)+.002*sin(j*.61)*abs(u)**4
  verts.append((x,y,z))
for j in range(ny):
 for i in range(nx):a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
o=mesh('粉色垂坠被面_已修复床垫穿插',verts,faces,(.77,.07,.31),'fabric',True);sol=o.modifiers.new('被芯厚度','SOLIDIFY');sol.thickness=.009
for sg in [-1,1]:
 pts=[]
 for j in range(36):
  y=-.54+j*.987/35;x=1.1+sg*.393
  z=.485-.132*((.393-.377)/.035)**.72-.104*max(0,(-y-.465)/.09)**.72
  pts.append((x,y,z))
 tube('被边缝线',pts,.0025,(.93,.20,.45),'fabric')
cushion('被头翻折软边',(1.1,.419,.495),(.775,.098,.032),(.94,.21,.48),.36)
# wider lower duvet hem, following the fall
pts=[]
for i in range(51):
 u=-1+2*i/50;xx=1.1+u*.408
 zz=.485-.132*max(0,(abs(u)*.408-.377)/.035)**.72-.104*((.535-.465)/.09)**.72
 pts.append((xx,-.535,zz))
tube('被脚弧形滚边',pts,.003,(.9,.16,.40),'fabric')
# smooth uninterrupted mitered ribbon.
COL=packs['04_折线置物架']
for o in list(COL.objects):
 if o.name.startswith('连续折线搁板'):bpy.data.objects.remove(o,do_unlink=True)
path=[(-.77,1.817),(.28,1.817),(.45,1.45),(.72,1.45),(.97,1.03),(1.64,1.03)]
left=[];right=[]
for i,p in enumerate(path):
 if i==0:dire=Vector(path[1])-Vector(path[0]);dire.normalize();n=Vector((-dire.y,dire.x));d=.028
 elif i==len(path)-1:dire=Vector(path[-1])-Vector(path[-2]);dire.normalize();n=Vector((-dire.y,dire.x));d=.028
 else:
  a=(Vector(path[i])-Vector(path[i-1])).normalized();b=(Vector(path[i+1])-Vector(path[i])).normalized();n1=Vector((-a.y,a.x));n2=Vector((-b.y,b.x));n=(n1+n2).normalized();d=.028/n.dot(n1)
 left.append(tuple(Vector(p)+n*d));right.append(tuple(Vector(p)-n*d))
polyprism('一体连续折线架_斜接转角',left+list(reversed(right)),1.205,1.457,(.019,.014,.024),.003)
# Dense curved broad-leaf foliage.
COL=packs['12_绿植花架']
for o in list(COL.objects):
 if o.name.startswith(('心形绿叶','绿植分枝')):bpy.data.objects.remove(o,do_unlink=True)
def broadleaf(base,tip,width,color):
 b=Vector(base);t=Vector(tip);axis=t-b
 side=axis.cross(Vector((.16,.33,1))).normalized()
 vs=[];fs=[];N=9
 for j in range(N+1):
  u=j/N;mid=b+axis*u+Vector((0,0,.024*sin(pi*u)))
  w=width*sin(pi*u)**.7*(1+.2*sin(pi*u*2))
  vs.extend([mid-side*w,mid+Vector((0,0,.008*sin(pi*u))),mid+side*w])
 for j in range(N):
  a=j*3;fs.extend([(a,a+3,a+4,a+1),(a+1,a+4,a+5,a+2)])
 o=mesh('饱满弧面绿叶',vs,fs,color,'matte',True);s=o.modifiers.new('叶片实体厚度','SOLIDIFY');s.thickness=.001
for k,x in enumerate([-.955,-.563,-.171]):
 for j in range(33):
  sx=x+random.uniform(-.18,.18);sy=random.uniform(1.13,1.36);sz=random.uniform(1.72,1.85)
  tube('茎',(sx,sy,1.69) if False else [(sx,sy,1.69),(sx,sy,sz)],.002,(.065,.13,.007))
  for a in [random.uniform(0,2*pi),random.uniform(0,2*pi)]:
   broadleaf((sx,sy,sz),(sx+cos(a)*random.uniform(.08,.145),sy+sin(a)*.11,sz+random.uniform(-.03,.035)),random.uniform(.035,.052),random.choice([(.055,.12,.004),(.10,.19,.006),(.17,.26,.012),(.035,.077,.003)]))
# Increase characteristic pink saturation without whitening the lighting.
for collname in ['11_粉色电竞椅','09_懒人沙发','07_矮沙发']:
 for o in packs[collname].objects:
  r,g,b,a=o.color
  if r>.65 and g<.5 and b>.3:
   o.color=(r*.9,g*.58,b*.8,1)
# replace the featureless reflected bright stripe in television with dark soft glass.
MATS['gloss'].node_tree.nodes.get('Principled BSDF')
for o in packs['03_电视柜与电视'].objects:
 if o.name.startswith('电视内屏'):o.color=(.009,.006,.016,1)
# Fill the previously sparse basket tops; modest stronger RGB wall pools.
for name in ['粉色背墙洗墙','左侧粉色洗墙','右侧粉色洗墙']:
 bpy.data.objects[name].data.energy*=2.0
bpy.data.objects['主光柔光箱'].data.energy=300
bpy.data.objects['顶部柔光'].data.energy=95
bpy.data.objects['验收_参考轴测'].data.ortho_scale=5.16
scene.camera=bpy.data.objects['验收_参考轴测']
for area_ui in bpy.context.screen.areas:
 if area_ui.type=='VIEW_3D':
  area_ui.spaces.active.overlay.show_overlays=False
  area_ui.spaces.active.region_3d.view_perspective='CAMERA'
  area_ui.spaces.active.region_3d.view_camera_zoom=0
scene.render.filepath=OUT+'/renders/01_参考轴测.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/粉色电竞卧室_高还原_v001.blend')
