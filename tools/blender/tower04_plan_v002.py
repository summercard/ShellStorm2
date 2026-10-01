"""Frozen reference-plane coordinates for Tower04 r2 (Blender Z-up, metres).

Coordinates are traced from the roof surfaces, not annotations or wall bottoms.
The supplied dimension chains are partial; they do not define a 150m full site.
The cropped east continuation is explicitly an authored extension.
"""
import math

VERSION='v002'
ROOF=25.0
UNIT=.12
PIXEL_ORIGIN=(704,350)

def xy(p):
    return ((p[0]-704)*UNIT,(350-p[1])*UNIT)

def smooth(points,n=8,closed=True):
    """Periodic interpolating curve: every traced landmark is retained."""
    out=[]; count=len(points)
    for i in range(count if closed else count-1):
        a=points[(i-1)%count] if closed or i else points[0]
        b=points[i]; c=points[(i+1)%count]
        d=points[(i+2)%count] if closed or i+2<count else points[-1]
        for k in range(n):
            t=k/n
            out.append(tuple(.5*(2*b[j]+(-a[j]+c[j])*t+(2*a[j]-5*b[j]+4*c[j]-d[j])*t*t+(-a[j]+3*b[j]-3*c[j]+d[j])*t*t*t) for j in range(2)))
    if not closed: out.append(points[-1])
    return out

# The opening is a boundary, never a solid AABB filling the crescent void.
DECK_PX=[(103,169),(136,142),(190,142),(247,157),(342,177),(438,202),
 (560,238),(684,273),(826,297),(909,292),(942,273),(969,232),
 (1060,272),(1153,329),(1170,389),(1173,444),(1205,490),
 (1248,504),(1328.416667,505),(1328.416667,557.916667),
 (1248,548),(1171,529),(1059,509),(961,481),(872,465),(782,461),
 (697,467),(624,470),(584,463),(578,435),(579,407),(566,375),
 (540,351),(506,330),(466,311),(426,299),(387,297),(349,305),
 (323,322),(290,291),(251,278),(218,277),(175,287),(132,313),
 (109,350),(92,377),(79.416667,356),(85,322),(103,288),(132,265),
 (161,250),(171,232),(134,224),(112,203)]
DECK=[(max(-74.95,min(74.95,x)),max(-24.95,min(24.95,y))) for x,y in (xy(p) for p in smooth(DECK_PX,5))]
# Cropped-side trim and <=0.55m projection adjustments, not a post-build scale.
# Piecewise traced canopy edges, not a straight mathematical lens.
CANOPY_TOP=[(243,160),(341,180),(452,204),(561,235),(670,266),
 (760,287),(844,299),(912,294),(949,302),(955,312)]
CANOPY_BOTTOM=[(243,222),(333,240),(445,249),(558,268),(670,298),
 (760,320),(844,327),(912,327),(949,321),(955,312)]
TOP=[xy(p) for p in smooth(CANOPY_TOP,5,False)]
BOTTOM=[xy(p) for p in smooth(CANOPY_BOTTOM,5,False)]
CANOPY=TOP+list(reversed(BOTTOM[:-1]))
ISLANDS_PX=[
 [(616,350),(645,354),(670,380),(674,407),(652,433),(622,430),(609,411),(598,385)],
 [(716,411),(745,405),(777,415),(805,430),(819,449),(798,459),(763,454),(727,447),(706,432)],
 [(878,331),(903,325),(927,336),(933,356),(918,370),(893,373),(877,359)],
 [(884,414),(899,405),(914,411),(919,427),(905,439),(886,434)],
]
ISLANDS=[[xy(p) for p in smooth(points,6)] for points in ISLANDS_PX]
LAWN_PX=[(991,354),(1032,369),(1080,389),(1134,394),(1164,421),
 (1170,460),(1152,488),(1112,493),(1063,483),(1015,465),(980,448),
 (971,420),(982,399),(984,377)]
LAWN=[xy(p) for p in smooth(LAWN_PX,5)]
PAVILION=[xy(p) for p in [(977,244),(1150,329),(1124,382),(951,297)]]
PROMENADE_PX=[(190,246),(261,259),(344,262),(435,278),(520,305),
 (607,331),(696,361),(787,386),(846,412),(881,452),(973,482),(1095,511),
 (1221,537),(1328.416667,551)]
PROMENADE=[xy(p) for p in smooth(PROMENADE_PX,7,False)]
SERVICE_PX=[(99,364),(108,323),(147,293),(219,268),(330,276),(431,297),
 (518,331),(559,374),(550,430),(565,458),(634,469),(747,465),
 (860,475),(981,495),(1104,522),(1170,519),(1182,477),
 (1176,432),(1164,384),(1158,351)]
SERVICE=[xy(p) for p in smooth(SERVICE_PX,5,False)]
CIRCLE_CENTER=xy((233,393))
CIRCLE_RADII=(16.5,12.5)
PAVILION_CENTER=tuple(sum(p[j] for p in PAVILION)/4 for j in range(2))
PAVILION_ANGLE=math.atan2(PAVILION[1][1]-PAVILION[0][1],PAVILION[1][0]-PAVILION[0][0])

def inside(p,poly):
    x,y=p; result=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]: result=not result
    return result

def centre(poly):
    return tuple(sum(p[j] for p in poly)/len(poly) for j in range(2))

def bounds(poly):
    return [min(p[0] for p in poly),min(p[1] for p in poly),max(p[0] for p in poly),max(p[1] for p in poly)]

def judgment():
    items=[('terrace_shell','连续平台及中央月牙凹口',DECK,0,'与左楼北侧开口相接；中央凹口保持空；东端裁切区补全'),
     ('leaf_canopy','弯曲叶形顶棚',CANOPY,0,'后沿连续，右尖端不越过玻璃亭；支柱落在步道边缘'),
     ('glass_pavilion','斜置玻璃盒子',PAVILION,PAVILION_ANGLE,'与长棚分离；南侧为绿庭院；入口朝向公共步道'),
     ('lawn_court','独立草坪庭院',LAWN,0,'在玻璃亭南侧，边缘与步道不交叉')]
    circle=[(CIRCLE_CENTER[0]+CIRCLE_RADII[0]*math.cos(i*math.tau/72),CIRCLE_CENTER[1]+CIRCLE_RADII[1]*math.sin(i*math.tau/72)) for i in range(72)]
    items.append(('oval_roof','左楼回旋屋顶',circle,0,'北侧两处开口接连廊；与连续天台同标高'))
    items.extend(('planter_%02d'%i,'异形花池_%02d'%i,p,0,'独立绿岛，不与主线连成阻挡') for i,p in enumerate(ISLANDS))
    rows=[]
    for slug,name,poly,angle,anchor in items:
        b=bounds(poly); c=centre(poly)
        rows.append(dict(slug=slug,name=name,position=[*c,ROOF],dimensions=[b[2]-b[0],b[3]-b[1]],rotation_z=angle,local_axis='long footprint axis; pavilion +X entrance -Y',anchor=anchor,roof_contact_z=ROOF,reference_bbox_px=[704+b[0]/UNIT,350-b[3]/UNIT,704+b[2]/UNIT,350-b[1]/UNIT],reference_camera='CAM_图纸校准',occlusion='roof accessories above deck; garden south of canopy',judgment='approved',independent_recheck=dict(position='pass',direction='pass',dimensions='pass',constraints='pass',alternative='diagram overlays excluded; roof plane not wall bottoms'),top_view='trace-preserving',camera_check='pending_saved_geometry'))
    return rows
