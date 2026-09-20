# Executed inside the authoring context before Action creation.
legacy_solve=solve

def aim(n,d):
 return (tails[n]-heads[n]).normalized().rotation_difference(Vector(d).normalized())
def apply_q(Q,hip):
 for pb in a.pose.bones:
  n=pb.name;par=pb.parent.name if pb.parent else None
  pb.rotation_mode='QUATERNION';pb.rotation_quaternion=rest[n].to_quaternion().inverted()@(Q[par].inverted() if par else Quaternion())@Q[n]@rest[n].to_quaternion();pb.location=(0,0,0);pb.scale=(1,1,1)
 a.pose.bones['Hip'].location=rest['Hip'].to_3x3().inverted()@(hip-heads['Hip']);bpy.context.view_layer.update()
def solve(clip,t):
 if clip=='dead':
  legacy_solve(clip,t);return
 phase=2*math.pi*t;Q={n:Quaternion() for n in rest};hip=heads['Hip'].copy();hip.z-=.032
 chest=-13;roll=2;turn=0;nod=5;wrist=18
 arm={'L':[(-.35,.2,-.92),(-.18,.97,-.15)],'R':[(.30,.25,-.92),(.12,.96,-.24)]}
 targets={side:heads[side+'_Foot'].copy() for side in ['L','R']};footrot={'L':0,'R':0}
 if clip=='idle':
  hip.x+=.017+.009*math.sin(phase);chest+=1.7*math.sin(phase);roll=3+1.5*math.sin(phase);turn=2*math.sin(phase-.5);nod+=2.5*math.sin(phase-.8)
  arm['L'][1]=(-.18,.96,-.15+.07*math.sin(phase-.7));arm['R'][1]=(.12,.96,-.24+.06*math.sin(phase-1.1))
 elif clip in ['walking','running']:
  run=clip=='running';chest=-21 if run else -14;stride=.25 if run else .15;hip.z-=.01*(1-math.cos(phase*2));hip.x+=.017*math.cos(phase);roll=4*math.cos(phase);turn=5*math.sin(phase);nod+=3*math.sin(phase-.8)
  for side,offset in [('L',0),('R',.5)]:
   u=(t+offset)%1;stance=.53 if run else (.65 if side=='L' else .58)
   if u<stance:
    targets[side].y+=stride*(.5-u/stance);footrot[side]=track(u/stance,[(0,-9),(.18,0),(.75,0),(1,12)])
   else:
    v=(u-stance)/(1-stance);targets[side].y+=stride*(-.5+smooth(v));targets[side].z+=(.07 if run else (.04 if side=='L' else .014))*math.sin(math.pi*v);footrot[side]=-12*math.sin(math.pi*v)
  lag=math.sin(phase-.55);arm['L'][0]=(-.3,.12+.3*lag,-.9);arm['R'][0]=(.3,.12-.24*lag,-.9);arm['L'][1]=(-.15,.92,-.2+.24*lag);arm['R'][1]=(.15,.92,-.25-.19*lag)
 elif clip=='attack':
  drive=track(t,[(0,0),(.23,-1),(.34,-1),(.45,1),(.57,.85),(.78,.3),(1,0)]);turn=-32*drive;chest=-13-15*max(0,drive);hip.y+=.028*drive;hip.x-=.024*drive;hip.z-=.014*max(0,drive);nod=-7*drive
  # Explicit elbow/forearm silhouettes: open claw, across-body sweep, heavy drop.
  arm['R'][0]=(track(t,[(0,.3),(.25,.95),(.35,.95),(.46,-.2),(.62,.25),(1,.3)]),track(t,[(0,.25),(.25,-.2),(.45,.9),(.62,.5),(1,.25)]),track(t,[(0,-.92),(.25,.05),(.45,-.3),(.7,-.92),(1,-.92)]))
  arm['R'][1]=(track(t,[(0,.12),(.25,.3),(.45,-.8),(.62,-.3),(1,.12)]),.9,track(t,[(0,-.24),(.25,.8),(.45,-.4),(.65,-.85),(1,-.24)]));arm['L'][0]=(-.45,.2,-.75);arm['L'][1]=(-.25,.9,.05-.3*drive);wrist=12+18*max(0,drive)
 elif clip=='hurt':
  impulse=track(t,[(0,0),(.10,1),(.24,.8),(.48,-.3),(.68,.15),(1,0)]);chest=-13+30*impulse;roll=-12*impulse;turn=9*impulse;nod=-20*impulse;hip.y-=.028*impulse;hip.x+=.022*impulse
  targets['R'].z+=track(t,[(0,0),(.15,.065),(.3,.055),(.52,0),(1,0)]);targets['R'].y+=track(t,[(0,0),(.18,.05),(.52,-.055),(.8,-.055),(1,0)])
  arm['L'][0]=(-.35-.35*impulse,.2,-.92+.5*impulse);arm['R'][0]=(.3+.3*impulse,.25,-.92+.5*impulse);arm['L'][1]=(-.18,.97,.35*impulse-.15);arm['R'][1]=(.12,.96,.5*impulse-.24)
 Q['Hip']=rz(turn*.2);Q['Waist']=rx(chest*.5)@ry(roll*.5)@rz(turn*.45);Q['Spine02']=rx(chest)@ry(roll)@rz(turn);Q['Neck']=Q['Spine02']@rx(4);Q['Head']=Q['Neck']@rx(nod)@ry(-roll*.35)
 for side in ['L','R']:
  Q[side+'_Clavicle']=Q['Spine02'];Q[side+'_Upperarm']=Q['Spine02']@aim(side+'_Upperarm',arm[side][0]);Q[side+'_Forearm']=Q['Spine02']@aim(side+'_Forearm',arm[side][1]);Q[side+'_Hand']=Q[side+'_Forearm']@rx(wrist)
  for fi,finger in enumerate(['Thumb','Index','Middle','Pinky']):
   for j in [1,2]:Q[side+'_'+finger+str(j)]=Q[side+'_Hand']@rx((1 if side=='R' else -1)*(14+fi*3+j*9))
 apply_q(Q,hip)
 # Analytical two-link IK, positive-Y knee pole, no bone stretching.
 for side in ['L','R']:
  n=side+'_Thigh';k=side+'_Calf';h=a.pose.bones[n].head.copy();target=targets[side];delta=target-h;distance=delta.length;L1=(tails[n]-heads[n]).length;L2=(tails[k]-heads[k]).length;distance=min(distance,L1+L2-.0005);axis=delta.normalized();pole=Vector((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized();along=(L1*L1-L2*L2+distance*distance)/(2*distance);height=math.sqrt(max(0,L1*L1-along*along));knee=h+axis*along+pole*height
  Q[n]=aim(n,knee-h);Q[k]=aim(k,target-knee);Q[side+'_Foot']=rx(footrot[side])
 apply_q(Q,hip)
 # Contact correction is per leg, never globally bob the entire actor to the lowest vertex.
 ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
 low=min((m.matrix_world@v.co).z for v in me.vertices);ev.to_mesh_clear()
 if low<.001:
  hip.z+=.001-low;apply_q(Q,hip)
