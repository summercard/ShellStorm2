# Run after 01_room.py in the live scene.
# Layout clearance: sofa in front of bed, table ahead of sofa.
for o in packs['07_矮沙发'].objects:o.location.x-=.08;o.location.y+=.25
for o in packs['08_茶几'].objects:o.location.y-=.25

group('11_粉色电竞椅')
chair_start=set(bpy.data.objects)
cx=.08;cy=.39
# Five tapered swept spokes with forks and actual paired wheels.
rod('气压升降杆',(cx,cy,.11),(cx,cy,.374),.022,SIL,'metal')
rod('升降套筒',(cx,cy,.20),(cx,cy,.31),.035,W)
for i in range(5):
 a=2*pi*i/5+.35;ex=cx+.239*cos(a);ey=cy+.239*sin(a)
 tube('五爪流线支脚',[(cx,cy,.13),(cx+.13*cos(a),cy+.13*sin(a),.104),(ex,ey,.075)],.018,WHITE,'metal')
 rod('轮架轴',(ex,ey,.039),(ex,ey,.078),.012,SIL,'metal')
 for offset in [-.018,.018]:
  loc=(ex+offset*cos(a+pi/2),ey+offset*sin(a+pi/2),.044)
  d=(cos(a+pi/2)*.012,sin(a+pi/2)*.012,0)
  rod('独立万向脚轮',tuple(loc[k]-d[k] for k in range(3)),tuple(loc[k]+d[k] for k in range(3)),.034,DK)
  uv('粉色轮毂',tuple(loc[k]+d[k]*1.1 for k in range(3)),(.012,.012,.017),PINK)
box('座椅底盘',(cx,cy,.344),(.248,.213,.044),GREY,.018,'metal')
rod('升降操作杆',(cx+.07,cy,.35),(cx+.19,cy-.04,.35),.007,DK,'metal')
box('操作把手',(cx+.2,cy-.045,.35),(.053,.025,.018),DK,.007)
cushion('椅座粉色包边',(cx,cy-.01,.398),(.373,.359,.099),PINK,.38)
cushion('椅座中心软垫',(cx,cy-.031,.433),(.276,.292,.043),LIGHTP,.45)
# Dedicated tapered racing silhouette, not a rectangular backrest.
outline=[(cx-.137,.448),(cx-.172,.64),(cx-.199,.82),(cx-.155,.943),(cx-.098,.961),(cx-.066,.932),(cx+.066,.932),(cx+.098,.961),(cx+.155,.943),(cx+.199,.82),(cx+.172,.64),(cx+.137,.448)]
polyprism('电竞椅一体侧翼靠背',outline,cy+.112,cy+.19,PINK,.026)
inner=[(cx-.098,.481),(cx-.116,.66),(cx-.143,.805),(cx-.116,.908),(cx+.116,.908),(cx+.143,.805),(cx+.116,.66),(cx+.098,.481)]
polyprism('靠背内嵌软包',inner,cy+.086,cy+.127,LIGHTP,.023)
cushion('腰托',(cx,cy+.066,.536),(.221,.088,.09),PINK,.5)
cushion('头枕',(cx,cy+.072,.864),(.172,.073,.071),LIGHTP,.4)
for sign in (-1,1):
 tube('侧翼白色滚边',[(cx+sign*.136,cy+.092,.492),(cx+sign*.159,cy+.092,.68),(cx+sign*.181,cy+.114,.81),(cx+sign*.148,cy+.119,.925)],.0045,(1,.58,.77),'fabric')
 tube('扶手支架',[(cx+sign*.129,cy,.363),(cx+sign*.213,cy,.442),(cx+sign*.213,cy,.533)],.012,WHITE,'metal')
 cushion('粉色扶手垫',(cx+sign*.213,cy-.026,.541),(.089,.205,.04),LIGHTP,.38)
 tube('座垫拼缝',[(cx+sign*.115,cy-.163,.443),(cx+sign*.119,cy-.03,.458),(cx+sign*.103,cy+.097,.443)],.002,(.71,.1,.32),'fabric')
# Small orientation towards the computer.
from mathutils import Matrix
rot=Matrix.Translation((cx,cy,0))@Matrix.Rotation(-.12,4,'Z')@Matrix.Translation((-cx,-cy,0))
for o in set(bpy.data.objects)-chair_start:o.matrix_world=rot@o.matrix_world

def leaf(name,base,tip,width,color):
 b=Vector(base);t=Vector(tip);axis=t-b;side=axis.cross(Vector((.13,.41,1))).normalized()*width
 mid=b+axis*.5; verts=[b,mid+side,t,mid-side,mid+Vector((0,-.009,.022))]
 o=mesh(name,verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],color,'matte',True)
 sol=o.modifiers.new('叶片厚度','SOLIDIFY');sol.thickness=.0012
 return o

group('12_绿植花架')
# White pierced planter baskets: slatted lattice with visible holes.
for k,x in enumerate([-.955,-.563,-.171]):
 box('花篮底板',(x,1.26,1.515),(.354,.242,.015),W,.005)
 box('花篮上沿',(x,1.118,1.709),(.37,.02,.025),WHITE,.004)
 box('花篮下沿',(x,1.118,1.541),(.37,.018,.017),WHITE,.004)
 for z in [1.575,1.62,1.665]:box('花篮横向编织',(x,1.117,z),(.354,.012,.009),WHITE,.002)
 for i in range(10):
  xx=x-.167+i*.037
  box('花篮纵向编织',(xx,1.116,1.622),(.009,.016,.165),WHITE,.003)
 for yy in [1.15,1.195,1.24,1.285,1.33,1.375]:
  for xx in [x-.173,x+.173]:box('侧壁编织',(xx,yy,1.622),(.012,.012,.165),WHITE,.003)
 box('花篮暗土',(x,1.27,1.696),(.32,.205,.012),(.075,.053,.026),.006)
 for j in range(17):
  sx=x+random.uniform(-.16,.16);sy=random.uniform(1.15,1.36);sz=random.uniform(1.76,1.84)
  tube('绿植分枝',[(sx,sy,1.686),(sx+.02,sy-.015,sz)],.003,(.17,.25,.025))
  for t in range(3):
   a=random.random()*2*pi; tip=(sx+cos(a)*random.uniform(.065,.13),sy+sin(a)*.10,sz+random.uniform(-.02,.035))
   leaf('心形绿叶',(sx,sy,sz-.04),tip,.031,random.choice([(.19,.31,.025),(.28,.4,.035),(.115,.22,.014),(.36,.46,.055)]))
 # cascading tendrils
 for j in range(2):
  xx=x+random.uniform(-.15,.15);yy=1.095
  pts=[(xx,yy,1.76),(xx-.035,yy-.015,1.65),(xx+.015,yy-.012,1.55)]
  tube('垂落藤蔓',pts,.0027,(.18,.27,.018))
  for i in range(5):
   z=1.72-i*.038;sg=(-1)**i
   leaf('垂藤叶',(xx,yy,z),(xx+sg*.06,yy-.02,z-.028),.025,(.23,.33,.03))
# framed photos below the foliage
for x in [-.833,-.648,-.463]:
 box('相框白框',(x,1.067,1.597),(.16,.026,.176),WHITE,.004)
 box('相框深色卡纸',(x,1.049,1.597),(.132,.006,.149),DK,.001)
 box('相纸',(x,1.044,1.597),(.11,.002,.13),(.71,.58,.67),.001)
 # silhouette portrait with hair, face and shirt
 uv('照片人物头发',(x,1.039,1.619),(.033,.003,.045),DK)
 uv('照片人物脸',(x,1.035,1.615),(.024,.003,.03),(.83,.65,.58))
 polyprism('照片人物衣领',[(x-.042,1.536),(x+.042,1.536),(x+.029,1.584),(x,1.568),(x-.029,1.584)],1.037,1.039,(.23,.15,.24),0)

group('13_墙上时钟')
clockx=1.27;clockz=1.52
for i in range(12):
 a=2*pi*i/12;xx=clockx+.264*sin(a);zz=clockz+.264*cos(a)
 o=box('时钟独立刻度',(xx,1.45,zz),(.026,.024,.058),DK,.004);o.rotation_euler.y=a
rod('钟针转轴',(clockx,1.449,clockz),(clockx,1.411,clockz),.018,DK)
tube('分针',[(clockx-.01,1.409,clockz-.026),(clockx,1.409,clockz),(clockx+.043,1.409,clockz+.174)],.009,DK)
tube('时针',[(clockx,1.401,clockz),(clockx+.157,1.401,clockz-.012)],.011,DK)

def pot(x,y,z,s=.07):
 rod('陶瓷小花盆',(x,y,z),(x,y,z+s*1.2),s*.61,WHITE,r2=s*.77)
 rod('花盆口暗土',(x,y,z+s*1.2),(x,y,z+s*1.22),s*.63,(.10,.065,.026))
 for i in range(6):
  a=i*pi/3
  leaf('盆栽尖叶',(x,y,z+s*1.18),(x+cos(a)*s*.7,y+sin(a)*s*.7,z+s*random.uniform(1.9,2.7)),s*.18,random.choice([(.16,.22,.06),(.3,.28,.085),(.26,.37,.10)]))

group('14_搁板盆栽与书籍')
for x in [1.09,1.24,1.405]:pot(x,1.285,1.062,.042)
for j in range(3):
 box('叠放杂志',(1.57,1.275,1.065+j*.014),(.16,.134,.012),[(.68,.04,.32),(.32,.035,.39),(.96,.21,.48)][j],.002)
box('杂志封面白框',(1.57,1.27,1.108),(.114,.09,.002),WHITE,.001)
box('杂志封面插画',(1.57,1.27,1.11),(.09,.066,.002),(.76,.14,.42),.001)

def fuse(parts,name,color,voxel=.006):
 bpy.ops.object.select_all(action='DESELECT')
 for o in parts:o.select_set(True)
 bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
 mod=o.modifiers.new('连续雕塑体','REMESH');mod.mode='VOXEL';mod.voxel_size=voxel
 bpy.ops.object.modifier_apply(modifier=mod.name)
 sm=o.modifiers.new('表面松弛','SMOOTH');sm.factor=.45;sm.iterations=4
 sub=o.modifiers.new('雕塑细分','SUBSURF');sub.levels=1
 o.color=(*color,1)
 for p in o.data.polygons:p.use_smooth=True
 return o

group('15_猫咪摆件')
cat=(.57,1.29,1.48);x,y,z=cat;pinkcat=(.85,.31,.38)
parts=[uv('猫身',(x,y,z+.04),(.105,.036,.045),pinkcat),uv('猫胸',(x-.073,y,z+.071),(.04,.034,.061),pinkcat),uv('猫头',(x-.096,y-.002,z+.123),(.043,.034,.039),pinkcat)]
fuse(parts,'猫咪连续躯干',pinkcat,.004)
for xx in [x-.12,x-.073]:
 polyprism('猫耳',[(xx-.019,z+.143),(xx-.015,z+.184),(xx+.021,z+.148)],y-.023,y+.007,pinkcat,.005)
 polyprism('猫耳内侧',[(xx-.011,z+.15),(xx-.01,z+.176),(xx+.011,z+.151)],y-.026,y-.024,(.54,.105,.2),.002)
for xx in [x-.075,x+.06]:
 tube('猫咪前后足',[(xx,y-.008,z+.045),(xx+.018,y-.021,z+.004),(xx-.019,y-.03,z+.004)],.014,pinkcat)
for xx in [x-.115,x-.082]:uv('猫眼',(xx,y-.033,z+.124),(.004,.003,.005),DK)
uv('猫鼻',(x-.099,y-.038,z+.108),(.004,.003,.003),(.44,.1,.17))
tube('弯曲猫尾',[(x+.075,y+.01,z+.04),(x+.126,y+.007,z+.06),(x+.135,y-.03,z+.017),(x+.105,y-.055,z+.007)],.012,pinkcat)

group('16_床上独角兽玩偶')
x=1.257;y=.34;z=.47
# unified organic body, tapered neck, forehead and elongated equine muzzle
plush=(.75,.74,.80)
parts=[uv('玩偶躯干',(x,y,z+.095),(.065,.044,.095),plush,'fabric'),uv('玩偶颈',(x,y,z+.174),(.041,.038,.079),plush,'fabric'),uv('独角兽头',(x,y-.018,z+.225),(.062,.039,.056),plush,'fabric'),uv('独角兽马吻',(x-.021,y-.052,z+.211),(.052,.047,.036),plush,'fabric')]
fuse(parts,'独角兽连续马头与身体',plush,.004)
for sign in [-1,1]:
 # ears shaped as pointed almond shells
 leaf('独角兽耳',(x+sign*.035,y-.005,z+.25),(x+sign*.057,y-.002,z+.313),.018,plush)
 leaf('独角兽粉色耳心',(x+sign*.036,y-.01,z+.263),(x+sign*.053,y-.008,z+.299),.009,LIGHTP)
 arm=uv('玩偶前腿',(x+sign*.055,y-.028,z+.09),(.027,.027,.069),plush,'fabric');arm.rotation_euler.y=sign*.28
 foot=uv('玩偶坐姿后腿',(x+sign*.054,y-.036,z+.029),(.032,.047,.03),plush,'fabric')
 uv('紫灰蹄底',(x+sign*.054,y-.067,z+.027),(.029,.019,.027),(.53,.49,.63),'fabric')
uv('眼睛左',(x-.052,y-.045,z+.238),(.009,.006,.011),DK,'gloss')
uv('眼睛亮点',(x-.054,y-.051,z+.242),(.0025,.002,.003),WHITE,'gloss')
uv('眼睛右',(x+.039,y-.049,z+.238),(.008,.006,.010),DK,'gloss')
uv('右眼亮点',(x+.037,y-.054,z+.242),(.002,.002,.0025),WHITE,'gloss')
for xx in [x-.04,x-.009]:uv('鼻孔',(xx,y-.096,z+.219),(.0035,.0025,.004),(.28,.24,.34))
purple=(.29,.025,.62)
rod('独角兽锥形角',(x-.009,y-.019,z+.267),(x-.025,y-.03,z+.339),.015,(.68,.25,.88),r2=.001)
for i in range(5):
 zz=z+.269+i*.012;rr=.014*(1-i/6)
 pts=[(x-.009-i*.0025+rr*cos(a),y-.019-i*.0018+rr*sin(a),zz+a/(2*pi)*.005) for a in [j*2*pi/20 for j in range(21)]]
 tube('螺旋角纹',pts,.0018,(.84,.44,.94))
for i in range(5):
 uv('紫色鬃毛',(x+.023,y+.018+i*.004,z+.271-i*.029),(.023,.025,.028),purple,'fabric')
tube('玩偶紫色尾巴',[(x+.02,y+.028,z+.07),(x+.071,y+.063,z+.084),(x+.091,y+.066,z+.035)],.017,purple,'fabric')

group('17_茶几食物和笔筒')
def bowl(x,y,z):
 # lathed dish with rolled lip, concave inner well and base
 profile=[(0,0),(.066,0),(.088,.008),(.103,.035),(.102,.042),(.095,.044),(.088,.022),(.06,.012),(0,.012)]
 vs=[];fs=[];N=48
 for r,h in profile:
  for i in range(N):a=2*pi*i/N;vs.append((x+r*cos(a),y+r*sin(a),z+h))
 for j in range(len(profile)-1):
  for i in range(N):a=j*N+i;b=j*N+(i+1)%N;fs.append((a,b,b+N,a+N))
 mesh('陶瓷碗_真实内壁',vs,fs,WHITE,'gloss',True)
 for i in range(11):
  a=random.random()*2*pi;r=random.random()*.068
  uv('碗内食物',(x+r*cos(a),y+r*sin(a),z+.03),(.019,.016,.01),random.choice([(.87,.24,.018),(.95,.49,.055),(.75,.09,.016)]),seg=16,rings=10)
 for i in range(3):leaf('食物叶片',(x-.03+i*.025,y,z+.04),(x-.024+i*.025,y+.025,z+.047),.007,(.16,.29,.035))
bowl(-.63,-1.27,.285);bowl(-.22,-1.24,.285)
# hollow pencil holder
x=-.42;y=-1.105;z=.285
rod('笔筒外壁',(x,y,z),(x,y,z+.113),.038,(.39,.32,.27),r2=.041)
rod('笔筒内腔',(x,y,z+.11),(x,y,z+.114),.034,(.105,.072,.05))
for i in range(7):
 a=i*2*pi/7;xx=x+cos(a)*.023;yy=y+sin(a)*.023;end=(xx+cos(a)*.018,yy+sin(a)*.015,z+random.uniform(.165,.223))
 rod('独立铅笔',(xx,yy,z+.05),end,.0038,random.choice([(.57,.37,.2),(.82,.72,.56),GREY]))
 rod('铅笔尖',end,(end[0],end[1],end[2]+.014),.0038,(.72,.52,.32),r2=.0005)

group('18_游戏手柄与小饰品')
# custom controller silhouette and face buttons
x=-.73;y=1.016;z=.585
outline=[(x-.118,z),(x-.105,z+.055),(x-.062,z+.071),(x-.031,z+.061),(x+.031,z+.061),(x+.062,z+.071),(x+.105,z+.055),(x+.118,z),(x+.098,z-.012),(x+.061,z+.026),(x-.061,z+.026),(x-.098,z-.012)]
polyprism('游戏手柄双握把',outline,y-.033,y+.034,DK,.013)
for xx in [x-.038,x+.03]:rod('摇杆',(xx,y-.006,z+.058),(xx,y-.006,z+.075),.015,GREY)
for dx,dy in [(-.006,0),(.006,0),(0,-.007),(0,.007)]:uv('彩色手柄按键',(x+.077+dx,y+dy,z+.067),(.004,.004,.003),LIGHTP)
box('十字键横',(x-.076,y,z+.072),(.025,.009,.006),GREY,.002)
box('十字键纵',(x-.076,y,z+.072),(.009,.025,.006),GREY,.002)
for x,y in [(-1.11,.67),(-1.37,.36)]:
 uv('蓝色毛绒球',(x,y,.065),(.042,.042,.042),(.016,.55,.75),'fabric',seg=20,rings=12)
 for i in range(42):
  a=random.uniform(0,pi*2);b=random.uniform(-pi/2,pi/2);v=Vector((cos(a)*cos(b),sin(a)*cos(b),sin(b)))
  base=Vector((x,y,.065))+v*.035;tip=Vector((x,y,.065))+v*.053
  rod('绒球软刺',base,tip,.0025,CYAN,r2=.0008)
# cabinet sticker owls, outlined eyes and ear tufts
for xx,zz,s in [(-1.267,1.282,.038),(-1.15,1.16,.034)]:
 uv('猫头鹰贴纸白底',(xx,.733,zz),(s,.002,s*1.12),(.67,.69,.79))
 for sg in [-1,1]:
  uv('贴纸眼圈',(xx+sg*s*.35,.729,zz+s*.21),(s*.33,.002,s*.38),WHITE)
  uv('贴纸瞳孔',(xx+sg*s*.35,.726,zz+s*.20),(s*.115,.002,s*.19),(.22,.18,.36))
  tube('贴纸耳尖',[(xx+sg*s*.75,.73,zz+s*.37),(xx+sg*s*.69,.73,zz+s*1.17),(xx+sg*s*.2,.73,zz+s*.75)],.0025,(.38,.32,.51))
 polyprism('贴纸小喙',[(xx-s*.12,zz),(xx+s*.12,zz),(xx,zz-s*.22)],.724,.727,(.53,.32,.42),0)
print('stage2 objects',len(bpy.data.objects))
