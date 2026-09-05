bl_info={'name':'Q弹果冻 · 固定切面互动','author':'Codex','version':(1,0,0),'blender':(4,2,0),'location':'3D视图 > N侧栏 > Q弹果冻','description':'拖拉半球果冻、松手弹回；整个底部切面严格固定','category':'3D View'}
import bpy, math, time
import numpy as np
from mathutils import Vector
from bpy_extras import view3d_utils
from bpy.props import FloatProperty
from bpy.app.handlers import persistent
_STATE=None
_MODAL=None

def deform_positions(rest,q,ripple):
    t=np.clip(rest[:,2],0.0,1.0)
    w=t*t*(3-2*t)
    # Height-dependent radial scaling approximates incompressibility;
    # every coordinate at z=0 remains bit-for-bit unchanged.
    stretch=np.maximum(.42,1.0+q[2]*w)
    radial=1.0/np.sqrt(stretch)
    radial+=ripple*w*np.sin(t*math.pi*2.0)*.16
    dst=rest.copy()
    dst[:,0]=rest[:,0]*radial+q[0]*w
    dst[:,1]=rest[:,1]*radial+q[1]*w
    dst[:,2]=rest[:,2]+q[2]*w+ripple*w*np.sin(t*math.pi)*.075
    pinned=t<1e-7
    dst[pinned]=rest[pinned]
    return dst

def new_state(scene):
    entries=[]
    for obj in scene.objects:
        if obj.type!='MESH' or not obj.get('jelly_deform'):continue
        attr=obj.data.attributes.get('jelly_rest')
        if not attr:continue
        rest=np.empty(len(obj.data.vertices)*3,dtype=np.float32)
        attr.data.foreach_get('vector',rest)
        entries.append((obj,rest.reshape((-1,3))))
    return {'scene':scene,'entries':entries,'q':np.zeros(3),'v':np.zeros(3),'r':0.0,'rv':0.0,'target':None,'last':time.perf_counter(),'demo':False,'next_poke':0.0,'alive':True}

def state(scene=None):
    global _STATE
    scene=scene or bpy.context.scene
    if _STATE is None or _STATE['scene']!=scene:
        _STATE=new_state(scene)
    return _STATE

def apply_state(s):
    for obj,rest in s['entries']:
        try:
            dst=deform_positions(rest,s['q'],s['r'])
            obj.data.vertices.foreach_set('co',dst.ravel())
            obj.data.update()
        except ReferenceError:continue
    for window in bpy.context.window_manager.windows:
        for a in window.screen.areas:
            if a.type=='VIEW_3D':a.tag_redraw()

def integrate(s,dt,k,damping):
    # Fixed substeps prevent a stalled viewport from destabilising the spring.
    count=max(1,math.ceil(dt/(1/180)))
    h=dt/count
    for _ in range(count):
        force=-k*s['q']-damping*s['v']
        if s['target'] is not None:
            force=160.0*(s['target']-s['q'])-18.0*s['v']
        s['v']+=force*h;s['q']+=s['v']*h
        # Compression and lean are bounded, while remaining underdamped.
        s['q'][0:2]=np.clip(s['q'][0:2],-.85,.85)
        s['q'][2]=np.clip(s['q'][2],-.48,.58)
        s['rv']+=(-90.0*s['r']-3.3*s['rv'])*h
        s['r']+=s['rv']*h

def tick():
    global _STATE
    s=_STATE
    if not s or not s['alive']:return None
    try:
        scene=s['scene'];now=time.perf_counter();dt=min(.25,max(.001,now-s['last']));s['last']=now
        if s['demo'] and now>s['next_poke']:
            s['v']+=np.array((1.6,-.45,-2.6));s['rv']+=2.6;s['next_poke']=now+3.4
        integrate(s,dt,scene.jelly_k,scene.jelly_damp)
        apply_state(s)
        energy=float(np.linalg.norm(s['v'])+np.linalg.norm(s['q'])+abs(s['r'])+abs(s['rv']))
        if energy<.00025 and s['target'] is None and not s['demo'] and _MODAL is None:
            s['q'][:]=0;s['v'][:]=0;s['r']=0;s['rv']=0;apply_state(s);return None
        return 1/60
    except (ReferenceError,RuntimeError):
        _STATE=None;return None

def wake(scene=None):
    s=state(scene);s['alive']=True;s['last']=time.perf_counter()
    if not bpy.app.timers.is_registered(tick):bpy.app.timers.register(tick,first_interval=.01)
    return s

def reset(scene=None):
    global _STATE
    s=state(scene);s['q'][:]=0;s['v'][:]=0;s['target']=None;s['r']=0;s['rv']=0;s['demo']=False
    apply_state(s)

class JELLY_OT_grab(bpy.types.Operator):
    bl_idname='jelly.grab';bl_label='开始鼠标互动';bl_description='左键抓住果冻拖拉，松手Q弹回位；右键或Esc退出，视角操作仍可用'
    def invoke(self,context,event):
        global _MODAL
        if _MODAL is not None:
            self.report({'INFO'},'互动已开启：左键抓住果冻即可');return {'CANCELLED'}
        if context.window is None or context.area is None or context.area.type!='VIEW_3D':
            self.report({'WARNING'},'请在3D视图的Q弹果冻面板启动互动')
            return {'CANCELLED'}
        self.area=context.area;self.region=next(r for r in context.area.regions if r.type=='WINDOW');self.rv3d=context.space_data.region_3d
        self.dragging=False;self.closed=False;self.s=wake(context.scene);_MODAL=self
        context.window_manager.modal_handler_add(self)
        self.area.header_text_set('Q弹果冻 | 左键按住拉伸 / 松手回弹 | 滚轮缩放，中键旋转 | 右键 / Esc 退出')
        context.window.cursor_modal_set('HAND')
        return {'RUNNING_MODAL'}
    def ray(self,event):
        p=(event.mouse_x-self.region.x,event.mouse_y-self.region.y)
        direction=view3d_utils.region_2d_to_vector_3d(self.region,self.rv3d,p)
        point=view3d_utils.region_2d_to_location_3d(self.region,self.rv3d,p,Vector((0,0,.5)))
        return point-direction*10.0,direction
    def finish(self,context):
        global _MODAL
        self.s['target']=None;self.dragging=False;self.closed=True;_MODAL=None
        try:self.area.header_text_set(None)
        except ReferenceError:pass
        context.window.cursor_modal_restore();return {'FINISHED'}
    def modal(self,context,event):
        if getattr(self,'closed',False):return {'FINISHED'}
        if event.type in {'ESC','RIGHTMOUSE'} and event.value=='PRESS':return self.finish(context)
        if not self.s['alive']:return self.finish(context)
        if event.type=='LEFTMOUSE' and event.value=='PRESS':
            # Do not consume UI clicks outside the viewport WINDOW region.
            if not (self.region.x<=event.mouse_x<=self.region.x+self.region.width and self.region.y<=event.mouse_y<=self.region.y+self.region.height):return {'PASS_THROUGH'}
            origin,direction=self.ray(event)
            hit,location,normal,index,obj,matrix=context.scene.ray_cast(context.evaluated_depsgraph_get(),origin,direction)
            if hit and obj.get('jelly_deform') and location.z>.04:
                self.dragging=True;self.anchor=location.copy();self.normal=self.rv3d.view_rotation@Vector((0,0,1));self.startq=self.s['q'].copy()
                t=max(.04,min(1.0,float(location.z)));self.weight=max(.24,t*t*(3-2*t))
                self.s['target']=self.s['q'].copy();self.s['rv']+=.75
                self.last_target=self.s['q'].copy();self.last_motion=time.perf_counter();self.mouse_velocity=np.zeros(3)
                return {'RUNNING_MODAL'}
            return {'PASS_THROUGH'}
        if event.type in {'MOUSEMOVE','INBETWEEN_MOUSEMOVE'} and self.dragging:
            origin,direction=self.ray(event);denom=direction.dot(self.normal)
            if abs(denom)>1e-6:
                position=origin+direction*((self.anchor-origin).dot(self.normal)/denom)
                d=np.array(position-self.anchor,dtype=float)/self.weight
                target=self.startq+d
                target[:2]=np.clip(target[:2],-.68,.68);target[2]=np.clip(target[2],-.43,.48)
                now=time.perf_counter();delta_t=max(.015,now-self.last_motion)
                velocity=(target-self.last_target)/delta_t
                speed=np.linalg.norm(velocity)
                if speed>5.0:velocity*=5.0/speed
                self.mouse_velocity=.45*self.mouse_velocity+.55*velocity
                self.last_target=target.copy();self.last_motion=now
                self.s['target']=target
                # Update immediately: a fast press-move-release can occur between timers.
                self.s['q']+=.45*(target-self.s['q']);apply_state(self.s)
                self.s['last_drag_target']=target.tolist()
            return {'RUNNING_MODAL'}
        if event.type=='LEFTMOUSE' and event.value=='RELEASE' and self.dragging:
            if self.s['target'] is not None:
                self.s['q']+=.55*(self.s['target']-self.s['q'])
            recent=max(0.0,1.0-(time.perf_counter()-self.last_motion)/.16)
            self.s['v']=.35*self.s['v']+.65*self.mouse_velocity*recent
            self.s['last_release_q']=self.s['q'].tolist();self.s['last_release_velocity']=self.s['v'].tolist()
            self.s['target']=None;self.s['rv']+=1.15;self.dragging=False;apply_state(self.s);return {'RUNNING_MODAL'}
        return {'PASS_THROUGH'}

class JELLY_OT_poke(bpy.types.Operator):
    bl_idname='jelly.poke';bl_label='戳一下';bl_description='施加一次冲量，观察真实时间的弹性回摆'
    def execute(self,context):
        s=wake(context.scene);s['v']+=np.array((1.65,-.38,-2.7));s['rv']+=2.8;return {'FINISHED'}

class JELLY_OT_squash(bpy.types.Operator):
    bl_idname='jelly.squash';bl_label='压扁一下'
    def execute(self,context):
        s=wake(context.scene);s['v']+=np.array((0,0,-3.1));s['rv']+=3;return {'FINISHED'}

class JELLY_OT_demo(bpy.types.Operator):
    bl_idname='jelly.demo';bl_label='自动Q弹演示 / 停止'
    def execute(self,context):
        s=wake(context.scene);s['demo']=not s['demo'];s['next_poke']=0;return {'FINISHED'}

class JELLY_OT_reset(bpy.types.Operator):
    bl_idname='jelly.reset';bl_label='恢复圆滚滚'
    def execute(self,context):reset(context.scene);return {'FINISHED'}

class JELLY_PT_panel(bpy.types.Panel):
    bl_label='Q弹果冻 · 摸摸我';bl_idname='JELLY_PT_panel';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='Q弹果冻'
    @classmethod
    def poll(cls,context):return any(o.get('jelly_body') for o in context.scene.objects)
    def draw(self,context):
        layout=self.layout
        col=layout.column(align=True);col.scale_y=1.4;col.operator('jelly.grab',icon='HAND')
        layout.label(text='左键按住表面拖拉，松手回弹')
        layout.label(text='右键 / Esc 退出互动')
        row=layout.row(align=True);row.operator('jelly.poke');row.operator('jelly.squash')
        layout.operator('jelly.demo',icon='PLAY');layout.operator('jelly.reset',icon='LOOP_BACK')
        layout.separator();layout.prop(context.scene,'jelly_k');layout.prop(context.scene,'jelly_damp')
        box=layout.box();box.label(text='整个底部切面始终固定',icon='LOCKED');box.label(text='表情跟随凝胶一起变形')
        box.label(text='降低阻尼 → 更久的晃动')

@persistent
def before_load(_):
    global _STATE,_MODAL
    if _STATE:_STATE['alive']=False
    if bpy.app.timers.is_registered(tick):bpy.app.timers.unregister(tick)
    _STATE=None;_MODAL=None

@persistent
def after_load(_):
    if any(o.get('jelly_body') for o in bpy.context.scene.objects):reset(bpy.context.scene)

_CLASSES=(JELLY_OT_grab,JELLY_OT_poke,JELLY_OT_squash,JELLY_OT_demo,JELLY_OT_reset,JELLY_PT_panel)
def register():
    for cls in _CLASSES:bpy.utils.register_class(cls)
    if before_load not in bpy.app.handlers.load_pre:bpy.app.handlers.load_pre.append(before_load)
    if after_load not in bpy.app.handlers.load_post:bpy.app.handlers.load_post.append(after_load)
    bpy.types.Scene.jelly_k=FloatProperty(name='弹性',default=48,min=15,max=95,description='越高，回弹越快')
    bpy.types.Scene.jelly_damp=FloatProperty(name='阻尼',default=2.8,min=.8,max=10,description='越低，晃动越持久')
def unregister():
    global _STATE,_MODAL
    if _STATE:
        reset(_STATE['scene']);_STATE['alive']=False
    if bpy.app.timers.is_registered(tick):bpy.app.timers.unregister(tick)
    if before_load in bpy.app.handlers.load_pre:bpy.app.handlers.load_pre.remove(before_load)
    if after_load in bpy.app.handlers.load_post:bpy.app.handlers.load_post.remove(after_load)
    for cls in reversed(_CLASSES):bpy.utils.unregister_class(cls)
    for prop in ['jelly_k','jelly_damp']:
        if hasattr(bpy.types.Scene,prop):delattr(bpy.types.Scene,prop)
    _STATE=None
if __name__=='__main__':register()
