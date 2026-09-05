import bpy,sys,json,math
import numpy as np
sys.path.insert(0,'/Users/summercards/ShellStorm2/output/kawaii_jelly_v001')
import kawaii_jelly_interaction as j
s=j.new_state(bpy.context.scene)
body=next(o for o in bpy.context.scene.objects if o.get('jelly_body'));rest=next(r for o,r in s['entries'] if o==body);pins=np.abs(rest[:,2])<1e-7
report={'body_vertices':len(rest),'pinned_vertices':int(pins.sum()),'fixed_base_max_error':0.0,'finite':True,'tests':[]}
for q in [np.array((.68,-.6,.48)),np.array((-.65,.4,-.43)),np.array((0,0,0))]:
 d=j.deform_positions(rest,q,.5);err=float(np.max(np.abs(d[pins]-rest[pins])));report['fixed_base_max_error']=max(report['fixed_base_max_error'],err);report['finite'] &= bool(np.all(np.isfinite(d)))
# spring decay, rebound and extreme tuning tests
for k,damp in [(48,2.8),(15,.8),(95,10)]:
 s=j.new_state(bpy.context.scene);s['v']=np.array((1.65,-.38,-2.7));s['rv']=2.8
 xs=[];zs=[]
 for i in range(1800):j.integrate(s,1/120,k,damp);xs.append(float(s['q'][0]));zs.append(float(s['q'][2]))
 report['tests'].append({'k':k,'damping':damp,'x_min':min(xs),'x_max':max(xs),'z_min':min(zs),'z_max':max(zs),'rebounded':min(xs)<0<max(xs) and min(zs)<0<max(zs),'residual_at_15s':float(np.linalg.norm(s['q'])),'finite':bool(np.all(np.isfinite(s['q'])))})
# drag hold followed by release
s=j.new_state(bpy.context.scene);s['target']=np.array((.5,0,.25))
for i in range(120):j.integrate(s,1/120,48,2.8)
held=s['q'].copy();s['target']=None
for i in range(1200):j.integrate(s,1/120,48,2.8)
report['grab_release']={'held_displacement':held.tolist(),'rest_error_10s':float(np.linalg.norm(s['q']))}
# A closed manifold hemisphere is required.
counts={}
for p in body.data.polygons:
 vs=list(p.vertices)
 for a,b in zip(vs,vs[1:]+vs[:1]):key=tuple(sorted((a,b)));counts[key]=counts.get(key,0)+1
report['nonmanifold_edges']=sum(v!=2 for v in counts.values())
report['passed']=report['fixed_base_max_error']==0 and report['finite'] and report['nonmanifold_edges']==0 and all(t['rebounded'] and t['finite'] and t['residual_at_15s']<.01 for t in report['tests']) and report['grab_release']['rest_error_10s']<.00001
json.dump(report,open('/Users/summercards/ShellStorm2/output/kawaii_jelly_v001/弹性与固定底面测试.json','w'),ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False,indent=2))
