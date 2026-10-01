"""Step 1: functional-reference route graph and planting locations, Z-up/metres.

Reference arrows/circles are annotations, not objects. Existing buildings are
immutable anchors. This is an art-plane reconstruction, not a surveyed CAD plan.
"""
import math
import tower04_plan_v002 as OLD

VERSION='v003'
ROOF=25.0
M=((.101759173,.013891651),(.0420231205,-.105796127),(-98.7739205,27.2159630))
def xy(p):
    return tuple(p[0]*M[0][j]+p[1]*M[1][j]+M[2][j] for j in range(2))
def pixel(p):
    x=p[0]-M[2][0]; y=p[1]-M[2][1]
    det=M[0][0]*M[1][1]-M[0][1]*M[1][0]
    return ((x*M[1][1]-y*M[1][0])/det,(y*M[0][0]-x*M[0][1])/det)

smooth=OLD.smooth
centre=OLD.centre
bounds=OLD.bounds
inside=OLD.inside

# Named endpoints make the two loops and pavilion branch independently testable.
NODES_PX={'west':(146,225),'plaza':(304,153),'head':(357,82),
 'merge':(610,306),'fork':(805,375),'middle':(949,377),
 'pavilion_fork':(1015,389),'lower_merge':(939,461),
 'court_front':(1119,617),'pavilion_entry':(1233,438)}
NODES={k:xy(p) for k,p in NODES_PX.items()}
NODES['west']=(-73.8,5.6)
# Anchor the last metre to the existing sliding door, not the projected roof.
a=OLD.PAVILION_ANGLE; c=OLD.PAVILION_CENTER
w=math.dist(OLD.PAVILION[1],OLD.PAVILION[2])
NODES['pavilion_entry']=(c[0]+math.sin(a)*(w/2+1.45),c[1]-math.cos(a)*(w/2+1.45))
NODES['east_exit']=(73.6,-23.15)
EDGES=[
 ('west','plaza',[(193,188),(240,170)]),
 ('plaza','merge',[(407,173),(498,213),(559,235)]),
 ('plaza','head',[(335,116)]),
 ('head','merge',[(410,100),(475,132),(509,176),(531,219),(570,271)]),
 ('merge','fork',[(655,313),(704,327)]),
 ('fork','middle',[(882,378)]),
 ('middle','pavilion_fork',[(986,382)]),
 ('fork','lower_merge',[(768,386),(735,410),(741,432),(783,454),(853,461),(899,461)]),
 ('middle','lower_merge',[(922,401),(910,430),(923,448)]),
 ('lower_merge','court_front',[(986,469),(1013,515),(1040,568)]),
 ('court_front','east_exit',[]),
 ('pavilion_fork','pavilion_entry',[(1073,351),(1110,351),(1165,390)]),
]
ROUTES=[dict(start=a,end=b,points=smooth([NODES[a]]+[xy(q) for q in mid]+[NODES[b]],8,False)) for a,b,mid in EDGES]

ISLANDS_PX=[
 # The diagram shows two centre islands, not the old four-island arrangement.
 [(747,420),(766,401),(803,395),(842,408),(854,435),(828,453),(791,454),(757,439)],
 [(965,397),(986,397),(1001,417),(985,446),(949,467),(928,451),(935,423),(948,406)],
 # Landscape garden is behind the canopy tip, to the west of the glass box.
 [(927,284),(946,267),(982,257),(1027,260),(1079,276),(1110,297),(1090,319),(1052,315),(1015,293),(975,287),(947,309)],
 [(350,150),(357,136),(375,158),(390,180),(367,174),(355,165)],
]
ISLANDS=[[xy(q) for q in smooth(p,5)] for p in ISLANDS_PX]
LAWN_PX=[(1058,382),(1103,379),(1139,396),(1183,423),(1240,448),
 (1290,479),(1258,523),(1214,546),(1174,543),(1125,526),
 (1078,504),(1042,477),(1039,438),(1041,408)]
LAWN=[xy(q) for q in smooth(LAWN_PX,5)]
# The new photo is cropped: east continuation retains the existing endpoint.
# Only roof overhangs needed for the ref's rear garden/front curve are adjusted;
# the circular building, crescent opening and lower five stories stay unchanged.
REAR_PATCH=[xy(q) for q in smooth([(861,302),(926,279),(968,248),(1042,252),(1130,285),(1092,329),(981,344),(904,339)],5)]
FRONT_PATCH=[xy(q) for q in smooth([(924,463),(1040,477),(1214,541),(1250,610),(1194,655),(1097,634),(1008,575),(937,530)],5)]
PLAZA_PATCH=[xy(q) for q in smooth([(139,223),(172,177),(224,125),(305,67),(358,62),(410,80),(498,115),(544,241),(617,314),(601,326),(495,267),(379,220),(293,181),(217,200),(148,245)],5)]
EAST_PATCH=[(40,-20),(56,-20.7),(74.95,-21.5),(74.95,-24.95),(54,-24.95),(40,-24.6)]
COURT_BEDS_PX=[
 [(1034,401),(1048,381),(1077,383),(1082,398),(1062,420),(1043,421)],
 [(1034,444),(1047,465),(1070,480),(1062,492),(1039,483),(1024,461)],
 [(1100,517),(1142,532),(1162,544),(1135,546),(1103,532)],
 [(1203,530),(1226,523),(1245,510),(1257,514),(1234,539),(1210,548)],
 [(1262,464),(1279,480),(1269,503),(1255,506),(1253,483)],
 [(1113,373),(1150,394),(1185,415),(1180,428),(1143,411),(1110,389)],
]
COURT_BEDS=[[xy(q) for q in smooth(p,4)] for p in COURT_BEDS_PX]
PLAZA_BEDS_PX=[
 [(241,94),(271,77),(310,66),(326,72),(302,83),(262,98)],
 [(363,66),(390,76),(420,92),(414,105),(383,89),(361,79)],
 [(175,147),(209,116),(228,112),(218,129),(183,154)],
 [(144,192),(167,182),(176,192),(159,211),(139,223)],
]
PLAZA_BEDS=[[xy(q) for q in smooth(p,4)] for p in PLAZA_BEDS_PX]
