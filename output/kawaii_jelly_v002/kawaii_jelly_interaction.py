bl_info={'name':'Q弹果冻 · 重力与固定切面','author':'Codex','version':(2,0,0),'blender':(4,2,0),'location':'3D视图 > N侧栏 > Q弹果冻','description':'固定切面、重力下垂、抓拉快甩、摇晃与硬软调节','category':'3D View'}
import bpy,math,time
import numpy as np
from mathutils import Vector
from bpy_extras import view3d_utils
from bpy.props import FloatProperty,BoolProperty,EnumProperty
from bpy.app.handlers import persistent
_STATE=None
_MODAL=None
_UPDATING=False

def anchor(scene):
    return next((o for o in scene.objects if o.get('jelly_anchor')),None)

def rotation(scene):
    a=anchor(scene)
    return a.matrix_world.to_3x3().normalized() if a else None

def local_vector(scene,vec):
    r=rotation(scene)
    return np.array(r.transposed()@Vector(vec) if r else vec,dtype=float)

def deform_positions(rest,q,ripple=0.0):
    t=np.clip(rest[:,2],0,1);w=t*t*(3-2*t)
    stretch=np.maximum(.43,1.0+q[2]*w)
    radial=1.0/np.sqrt(stretch)
    radial+=ripple*w*np.sin(t*math.pi*2)*.10
    dst=rest.copy()
    dst[:,0]=rest[:,0]*radial+q[0]*w
    dst[:,1]=rest[:,1]*radial+q[1]*w
    dst[:,2]=rest[:,2]+q[2]*w+ripple*w*np.sin(t*math.pi)*.05
    # Bend cross sections towards the centre-line slope: sag is curved, not a rigid tilt.
    bend=.22*w
    dz=-bend*(q[0]*rest[:,0]+q[1]*rest[:,1])
    dst[:,2]+=dz
    dst[t<1e-7]=rest[t<1e-7]
    return dst

def new_state(scene):
    entries=[]
    for obj in scene.objects:
        if obj.type!='MESH' or not obj.get('jelly_deform'):continue
        attr=obj.data.attributes.get('jelly_rest')
        if not attr:continue
        values=np.empty(len(obj.data.vertices)*3,dtype=np.float32);attr.data.foreach_get('vector',values)
        entries.append((obj,values.reshape((-1,3))))
    return {'scene':scene,'entries':entries,'q':np.zeros(3),'v':np.zeros(3),'r':0.0,'rv':0.0,'target':None,'last':time.perf_counter(),'alive':True,'shake_until':0.0,'shake_phase':0.0,'demo':False,'next_poke':0.0,'last_draw':None,'sleeping':False,'peak_drag':0.0,'release_count':0}

def state(scene=None):
    global _STATE
    scene=scene or bpy.context.scene
    if _STATE is None or _STATE['scene']!=scene:_STATE=new_state(scene)
    return _STATE

def gravity_force(scene):
    if not scene.jelly_gravity or not scene.use_gravity:return np.zeros(3)
    return local_vector(scene,scene.gravity)*np.array((1.25,1.25,.85))*scene.jelly_g

def spring_coefficients(scene):
    # A fixed cap is more compliant in bending than normal compression.
    tension=.70 if gravity_force(scene)[2]>0 else 1.0
    return np.array((.60,.60,tension))*scene.jelly_k

def limit_pose(q,v=None):
    old=q.copy();q[:2]=np.clip(q[:2],-1.15,1.15);q[2]=np.clip(q[2],-.47,1.05)
    if v is not None:
        for i in range(3):
            if old[i]!=q[i] and v[i]*(old[i]-q[i])>0:v[i]=0.0
    return q

def equilibrium(scene):
    return limit_pose(gravity_force(scene)/spring_coefficients(scene))

def integrate(s,dt,k=None,damping=None,force=None):
    scene=s['scene'];coeff=spring_coefficients(scene) if k is None else np.asarray(k,dtype=float)
    if coeff.ndim==0:coeff=np.repeat(coeff,3)
    damping=scene.jelly_damp if damping is None else damping
    force=gravity_force(scene) if force is None else np.asarray(force,dtype=float)
    count=max(1,math.ceil(dt*180));h=dt/count
    for _ in range(count):
        accel=force-coeff*s['q']-damping*s['v']
        if s['target'] is not None:accel=200*(s['target']-s['q'])-21*s['v']
        s['v']+=accel*h;s['q']+=s['v']*h;limit_pose(s['q'],s['v'])
        s['rv']+=(-85*s['r']-3.8*s['rv'])*h;s['r']+=s['rv']*h

def apply_state(s,force=False):
    signature=tuple(s['q'])+(s['r'],)
    if not force and s['last_draw'] and max(abs(a-b) for a,b in zip(signature,s['last_draw']))<.000003:return
    for obj,rest in s['entries']:
        try:obj.data.vertices.foreach_set('co',deform_positions(rest,s['q'],s['r']).ravel());obj.data.update()
        except ReferenceError:continue
    s['last_draw']=signature
    for win in bpy.context.window_manager.windows:
        for a in win.screen.areas:
            if a.type=='VIEW_3D':a.tag_redraw()

def tick():
    global _STATE
    s=_STATE
    if not s or not s['alive']:return None
    try:
        scene=s['scene'];now=time.perf_counter();dt=min(.25,max(.001,now-s['last']));s['last']=now
        if not scene.jelly_running:return .08
        if s['demo'] and now>s['next_poke']:
            s['v']+=np.array((1.45,-.35,-1.9));s['rv']+=1.8;s['next_poke']=now+3.4
        external=gravity_force(scene);shaking=scene.jelly_continuous_shake or now<s['shake_until']
        if shaking:
            s['shake_phase']+=dt
            amp=scene.jelly_shake_strength
            envelope=1.0 if scene.jelly_continuous_shake else min(1,max(0,(s['shake_until']-now)/.4))
            wave=(18*sin(s['shake_phase']*8.7),7*cos(s['shake_phase']*7.1),0)
            external+=local_vector(scene,wave)*amp*envelope
        integrate(s,dt,force=external);apply_state(s)
        s['sleeping']=np.linalg.norm(s['v'])<.0002 and np.linalg.norm(s['q']-equilibrium(scene))<.0001 and abs(s['r'])+abs(s['rv'])<.0002 and s['target'] is None and not shaking and not s['demo']
        return .06 if s['sleeping'] and _MODAL is None else 1/60
    except (ReferenceError,RuntimeError):_STATE=None;return None

def wake(scene=None):
    s=state(scene);s['alive']=True;s['last']=time.perf_counter();s['sleeping']=False
    if not bpy.app.timers.is_registered(tick):bpy.app.timers.register(tick,first_interval=.01)
    return s

def settle(scene=None):
    s=state(scene);s['q'][:]=equilibrium(s['scene']);s['v'][:]=0;s['r']=s['rv']=0;s['target']=None;s['demo']=False;s['shake_until']=0
    s['scene'].jelly_continuous_shake=False;apply_state(s,True);return s

def parameter_changed(self,context):
    if not _UPDATING and any(o.get('jelly_body') for o in self.objects):wake(self)

def orientation_changed(self,context):
    if _UPDATING:return
    a=anchor(self)
    if a:
        a.rotation_euler=(0,math.radians(self.jelly_tilt),0)
        if context and context.view_layer:context.view_layer.update()
    s=wake(self);s['target']=None
    if _MODAL:_MODAL.dragging=False

def reset(scene=None):
    return settle(scene)

class JELLY_OT_grab(bpy.types.Operator):
    bl_idname='jelly.grab';bl_label='开始抓拉互动';bl_description='左键慢拉、快甩或轻戳；松手按当前重力回摆；Esc退出'
    def invoke(self,context,event):
        global _MODAL
        if _MODAL is not None:self.report({'INFO'},'抓拉已开启，直接左键拖动果冻');return {'CANCELLED'}
        if context.window is None or context.area is None or context.area.type!='VIEW_3D':return {'CANCELLED'}
        if not context.scene.jelly_running:context.scene.jelly_running=True
        self.area=context.area;self.region=next(r for r in self.area.regions if r.type=='WINDOW');self.rv3d=context.space_data.region_3d
        self.dragging=False;self.closed=False;self.s=wake(context.scene);_MODAL=self
        context.window_manager.modal_handler_add(self);self.area.header_text_set('Q弹果冻 | 左键抓拉 / 快甩 / 轻戳 | 松手重力回弹 | 右键 / Esc退出');context.window.cursor_modal_set('HAND')
        return {'RUNNING_MODAL'}
    def ray(self,event):
        p=(event.mouse_x-self.region.x,event.mouse_y-self.region.y)
        d=view3d_utils.region_2d_to_vector_3d(self.region,self.rv3d,p)
        a=anchor(self.s['scene']);centre=a.matrix_world@Vector((0,0,.5)) if a else Vector((0,0,.5))
        point=view3d_utils.region_2d_to_location_3d(self.region,self.rv3d,p,centre)
        return point-d*15,d
    def finish(self,context):
        global _MODAL
        self.s['target']=None;self.dragging=False;self.closed=True
        if _MODAL is self:_MODAL=None
        try:self.area.header_text_set(None);context.window.cursor_modal_restore()
        except (ReferenceError,AttributeError):pass
        return {'FINISHED'}
    def modal(self,context,event):
        if self.closed:return {'FINISHED'}
        if not self.s['alive'] or (event.type in {'ESC','RIGHTMOUSE'} and event.value=='PRESS'):return self.finish(context)
        if not context.scene.jelly_running:return {'PASS_THROUGH'}
        if event.type=='LEFTMOUSE' and event.value=='PRESS':
            if not(self.region.x<=event.mouse_x<=self.region.x+self.region.width and self.region.y<=event.mouse_y<=self.region.y+self.region.height):return {'PASS_THROUGH'}
            origin,direction=self.ray(event)
            hit,loc,n,idx,obj,mat=context.scene.ray_cast(context.evaluated_depsgraph_get(),origin,direction)
            if not hit or not obj.get('jelly_deform'):return {'PASS_THROUGH'}
            a=anchor(context.scene);local=a.matrix_world.inverted()@loc if a else loc
            # Use the hit polygon's undeformed height: sag can put visible vertices below the cut plane in world space.
            original=obj.original if hasattr(obj,'original') else obj
            attr=original.data.attributes.get('jelly_rest')
            if attr and 0<=idx<len(original.data.polygons):t=sum(attr.data[i].vector.z for i in original.data.polygons[idx].vertices)/len(original.data.polygons[idx].vertices)
            else:t=float(local.z)
            if t<.045:return {'RUNNING_MODAL'}
            self.dragging=True;self.grab_world=loc.copy();self.normal=self.rv3d.view_rotation@Vector((0,0,1));self.startq=self.s['q'].copy()
            t=max(.045,min(1,float(t)));self.weight=max(.22,t*t*(3-2*t))
            self.s['target']=self.s['q'].copy();self.s['rv']+=.3
            self.last_target=self.s['q'].copy();self.last_motion=time.perf_counter();self.mouse_velocity=np.zeros(3);self.moved=0.0
            self.s['grab_count']=self.s.get('grab_count',0)+1
            return {'RUNNING_MODAL'}
        if event.type in {'MOUSEMOVE','INBETWEEN_MOUSEMOVE'} and self.dragging:
            o,d=self.ray(event);denom=d.dot(self.normal)
            if abs(denom)>1e-6:
                pos=o+d*((self.grab_world-o).dot(self.normal)/denom)
                delta=local_vector(context.scene,pos-self.grab_world)/self.weight
                target=limit_pose(self.startq+delta);now=time.perf_counter();dt=max(.012,now-self.last_motion)
                velocity=(target-self.last_target)/dt;speed=np.linalg.norm(velocity)
                if speed>5:velocity*=5/speed
                self.mouse_velocity=.4*self.mouse_velocity+.6*velocity;self.last_target=target.copy();self.last_motion=now;self.moved=max(self.moved,float(np.linalg.norm(delta)))
                self.s['target']=target;self.s['q']+=.5*(target-self.s['q']);apply_state(self.s)
                self.s['last_drag_target']=target.tolist();self.s['peak_drag']=max(self.s['peak_drag'],float(np.linalg.norm(self.s['q']-equilibrium(context.scene))))
            return {'RUNNING_MODAL'}
        if event.type=='LEFTMOUSE' and event.value=='RELEASE' and self.dragging:
            if self.s['target'] is not None:self.s['q']+=.55*(self.s['target']-self.s['q'])
            recent=max(0,1-(time.perf_counter()-self.last_motion)/.16)
            self.s['v']=.35*self.s['v']+.65*self.mouse_velocity*recent
            if self.moved<.025:self.s['v']+=local_vector(context.scene,-self.normal)*1.25
            self.s['last_release_q']=self.s['q'].tolist();self.s['last_release_velocity']=self.s['v'].tolist();self.s['release_count']+=1
            self.s['target']=None;self.s['rv']+=1.0;self.dragging=False;apply_state(self.s)
            return {'RUNNING_MODAL'}
        return {'PASS_THROUGH'}

class JELLY_OT_poke(bpy.types.Operator):
    bl_idname='jelly.poke';bl_label='戳一下'
    def execute(self,context):s=wake(context.scene);s['v']+=np.array((1.4,-.25,-1.8));s['rv']+=1.8;return {'FINISHED'}
class JELLY_OT_squash(bpy.types.Operator):
    bl_idname='jelly.squash';bl_label='压扁一下'
    def execute(self,context):s=wake(context.scene);s['v']+=np.array((0,0,-2.5));s['rv']+=2;return {'FINISHED'}
class JELLY_OT_shake(bpy.types.Operator):
    bl_idname='jelly.shake';bl_label='来回摇晃3秒';bl_description='交替施力，基座位置与朝向不动；结束后保留自然余晃'
    def execute(self,context):s=wake(context.scene);s['shake_until']=time.perf_counter()+3;s['shake_phase']=0;return {'FINISHED'}
class JELLY_OT_settle(bpy.types.Operator):
    bl_idname='jelly.settle';bl_label='停止晃动并归稳'
    def execute(self,context):settle(context.scene);return {'FINISHED'}
class JELLY_OT_pose(bpy.types.Operator):
    bl_idname='jelly.pose';bl_label='设置固定切面朝向'
    pose:EnumProperty(items=[('UP','平放',''),('SIDE','竖放',''),('DOWN','倒挂','')],default='UP')
    def execute(self,context):
        context.scene.jelly_tilt={'UP':0.0,'SIDE':90.0,'DOWN':180.0}[self.pose];wake(context.scene);return {'FINISHED'}
class JELLY_OT_preset(bpy.types.Operator):
    bl_idname='jelly.preset';bl_label='选择硬软预设'
    preset:EnumProperty(items=[('FIRM','偏硬',''),('BOUNCY','Q弹',''),('SOFT','软糯','')],default='BOUNCY')
    def execute(self,context):
        s=context.scene
        s.jelly_k,s.jelly_damp={'FIRM':(75,4.0),'BOUNCY':(30,2.2),'SOFT':(16,1.7)}[self.preset]
        wake(s);return {'FINISHED'}
class JELLY_PT_panel(bpy.types.Panel):
    bl_label='Q弹果冻 · 重力实验台';bl_idname='JELLY_PT_panel';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='Q弹果冻'
    @classmethod
    def poll(cls,context):return any(o.get('jelly_body') for o in context.scene.objects)
    def draw(self,context):
        l=self.layout;s=context.scene
        row=l.row();row.scale_y=1.3;row.operator('jelly.grab',icon='HAND')
        l.label(text='左键抓拉 / 快甩，松手回弹');l.label(text='右键或 Esc 退出抓拉')
        box=l.box();box.label(text='1. 固定切面朝向',icon='LOCKED');r=box.row(align=True)
        for key,label in [('UP','平放'),('SIDE','竖放'),('DOWN','倒挂')]:r.operator('jelly.pose',text=label).pose=key
        box.prop(s,'jelly_tilt',slider=True);box.label(text='只在你调整朝向时转动切面')
        box=l.box();box.label(text='2. 重力与硬软');box.prop(s,'jelly_gravity');box.prop(s,'jelly_g',slider=True)
        r=box.row(align=True)
        for key,label in [('FIRM','偏硬'),('BOUNCY','Q弹'),('SOFT','软糯')]:r.operator('jelly.preset',text=label).preset=key
        box.prop(s,'jelly_k',slider=True);box.prop(s,'jelly_damp',slider=True);box.label(text='硬度越小，下垂越大')
        box=l.box();box.label(text='3. 摇晃与回弹');r=box.row(align=True);r.operator('jelly.poke');r.operator('jelly.squash')
        box.operator('jelly.shake',icon='FORCE_HARMONIC');box.prop(s,'jelly_continuous_shake');box.prop(s,'jelly_shake_strength',slider=True)
        box.operator('jelly.settle',icon='LOOP_BACK');box.prop(s,'jelly_running',toggle=True)
        l.label(text='切面不会因重力或摇晃掉落',icon='PINNED')
        l.label(text='详细操作：同目录《使用说明》')

@persistent
def before_load(_):
    global _STATE,_MODAL
    if _STATE:_STATE['alive']=False
    if bpy.app.timers.is_registered(tick):bpy.app.timers.unregister(tick)
    _STATE=None;_MODAL=None
@persistent
def after_load(_):
    if any(o.get('jelly_body') for o in bpy.context.scene.objects):settle(bpy.context.scene);wake(bpy.context.scene)

_CLASSES=(JELLY_OT_grab,JELLY_OT_poke,JELLY_OT_squash,JELLY_OT_shake,JELLY_OT_settle,JELLY_OT_pose,JELLY_OT_preset,JELLY_PT_panel)
_PROPS=('jelly_k','jelly_damp','jelly_g','jelly_gravity','jelly_tilt','jelly_shake_strength','jelly_continuous_shake','jelly_running')
def register():
    for cls in _CLASSES:bpy.utils.register_class(cls)
    bpy.types.Scene.jelly_k=FloatProperty(name='硬度（越小越软）',default=30,min=12,max=90,update=parameter_changed)
    bpy.types.Scene.jelly_damp=FloatProperty(name='阻尼（越小余晃越久）',default=2.2,min=.6,max=10,update=parameter_changed)
    bpy.types.Scene.jelly_g=FloatProperty(name='重力倍率',default=1,min=0,max=2,update=parameter_changed)
    bpy.types.Scene.jelly_gravity=BoolProperty(name='启用重力下垂',default=True,update=parameter_changed)
    bpy.types.Scene.jelly_tilt=FloatProperty(name='切面倾角 °',default=0,min=0,max=180,update=orientation_changed)
    bpy.types.Scene.jelly_shake_strength=FloatProperty(name='摇晃力度',default=1,min=.1,max=2.5,update=parameter_changed)
    bpy.types.Scene.jelly_continuous_shake=BoolProperty(name='持续来回摇晃',default=False,update=parameter_changed)
    bpy.types.Scene.jelly_running=BoolProperty(name='实时模拟：开 / 暂停',default=True,update=parameter_changed)
    if before_load not in bpy.app.handlers.load_pre:bpy.app.handlers.load_pre.append(before_load)
    if after_load not in bpy.app.handlers.load_post:bpy.app.handlers.load_post.append(after_load)
def unregister():
    global _STATE
    if _STATE:_STATE['alive']=False
    if bpy.app.timers.is_registered(tick):bpy.app.timers.unregister(tick)
    if before_load in bpy.app.handlers.load_pre:bpy.app.handlers.load_pre.remove(before_load)
    if after_load in bpy.app.handlers.load_post:bpy.app.handlers.load_post.remove(after_load)
    for cls in reversed(_CLASSES):bpy.utils.unregister_class(cls)
    for p in _PROPS:
        if hasattr(bpy.types.Scene,p):delattr(bpy.types.Scene,p)
    _STATE=None
if __name__=='__main__':register()
