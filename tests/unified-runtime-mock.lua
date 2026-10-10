_G.OJR_EnableRuntimeDiagnostics=true
local clock = 100
os.clock = function() return clock end
local callbacks, hooks, pre_callbacks = {}, {}, {}
local kb_down, gp_bits, stick_x, mouse_bits = {}, 0, 0, 0
local is_paused, missing, force_fail = false, false, false
local function vec(x,y,z)
    local v = {x=x,y=y,z=z}
    return setmetatable(v, {__sub=function(a,b) return vec(a.x-b.x,a.y-b.y,a.z-b.z) end,
        __index={length=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}})
end
Vector3f = {new=vec}
local function quaternion(x,y,z,w)
    return setmetatable({x=x,y=y,z=z,w=w},{__mul=function(a,b)
        return quaternion(a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
            a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
            a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z)
    end})
end
Quaternion={new=quaternion}
local counter = 0
local function object(name, p)
    counter = counter + 1
    local obj = {name=name,id=counter,pos=p or vec(0,0,0)}
    function obj:get_address() return self.id end
    function obj:get_Valid() return not self.invalid end
    function obj:get_Name() return self.name end
    function obj:get_Position() return self.pos end
    function obj:set_Position(p) self.pos=p end
    function obj:get_Rotation() return self.rotation or quaternion(0,0,0,1) end
    function obj:set_Rotation(q) self.rotation=q end
    function obj:get_Transform() return self end
    function obj:get_GameObject() return self.go or self end
    function obj:get_AxisX() return vec(1,0,0) end
    function obj:get_AxisY() return vec(0,1,0) end
    function obj:get_AxisZ() return vec(0,0,1) end
    function obj:lookAt(target,up) self.looked=true;self.look_target=target;self.look_up=up end
    function obj:get_Child() return nil end
    function obj:get_CharaID() return self.id end
    function obj:get_ActionManager() return self.am end
    function obj:call(method,p)
        if method=='get_GameObject' then return self:get_GameObject() end
        if method=='get_Name' then return self:get_Name() end
        if method=='getComponent(System.Type)' and p=='app.Character' then return self end
        assert(method=='warp(via.vec3, app.CharacterWarpOption)', method)
        self.pos, self.physics_pos, self.warps = p, p, (self.warps or 0)+1
    end
    obj.machine = {enabled=true, call=function(self, method, value)
        if method=='get_Enabled()' then return self.enabled end
        self.enabled=value
    end}
    obj.am = {Fsm=obj.machine, CurrentActionList={[0]={Name='Wait'}}}
    function obj.am:get_GameObject() return obj end
    function obj.am:call(method, priority, node, layer)
        if force_fail and node~='Wait' and (priority==0 or priority==1) then error('Injected seat failure') end
        local str = {ToString=function() return node end}
        local hook = hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
        if hook and hook({nil,self,priority,str,layer})=='skip' then return end
        self.CurrentActionList[0].Name=node
    end
    obj['<ActionManager>k__BackingField']=obj.am
    obj['<Human>k__BackingField']={Fsm=obj.machine}
    return obj
end
local human, ox, cow, body, driver = object('player'),object('ox'),object('cow'),object('gm80_042_00'),object('driver')
local pawns = {object('pawn1'),object('pawn2'),object('pawn3')}
local function add_skeleton(actor)
    local joint=object(actor.name..'_root')
    joint.local_pos=vec(0,0,0);joint.rotation=quaternion(0,0,0,1)
    function joint:get_Parent() return nil end
    function joint:get_Position() return self.world_pos or actor.pos end
    function joint:set_Position(p) self.world_pos=p end
    function joint:get_LocalPosition() return self.local_pos end
    function joint:set_LocalPosition(p) self.local_pos=p;self.world_pos=nil end
    function joint:get_LocalRotation() return self.rotation end
    function joint:get_Rotation() return self.rotation end
    function joint:set_LocalRotation(q) self.rotation=q end
    function joint:set_Rotation(q) self.rotation=q end
    actor.test_joint=joint
    function actor:get_Joints() return {get_elements=function() return {joint} end} end
end
add_skeleton(human)
for _,ch in ipairs(pawns) do add_skeleton(ch) end
local heading=20
-- Distinct scene/universal coordinates expose accidental coordinate-space mixing.
local function add_position_components(actor)
    function actor:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
    function actor:set_UniversalPosition(value) self.pos=vec(value.x-384,value.y,value.z+1024) end
    local context={Position=actor:get_UniversalPosition()}
    function context:call(method,value)
        assert(method=='setPos(via.Position)',method)
        self.Position=value;self.writes=(self.writes or 0)+1
    end
    local controller={position=actor.pos,warps=0}
    function controller:call(method,...)
        if method=='warp()' then
            assert(select('#',...)==0,'Controller warp unexpectedly received a position')
            self.position=vec(actor.pos.x,actor.pos.y,actor.pos.z);self.warps=self.warps+1
        elseif method=='get_Position()' then return self.position
        else error('Unexpected controller call: '..method) end
    end
    actor['<PosRotContext>k__BackingField']=context
    actor['<AdjustTerrain>k__BackingField']={MainCharacterController=controller}
    actor.test_position_context,actor.test_controller=context,controller
    local fall={base_calls=0,reset_calls=0,['<FallHeight>k__BackingField']=5}
    function fall:call(method,value)
        if method=='resetBaseHeight(via.Position)' then self.BaseFallHeight=value;self.base_calls=self.base_calls+1
        elseif method=='resetFallHeight()' then self['<FallHeight>k__BackingField']=0;self.reset_calls=self.reset_calls+1
        else error('Unexpected fall method: '..method) end
    end
    actor['<FallInfo>k__BackingField']=fall
    actor.test_fall=fall
end
add_position_components(human)
add_position_components(driver)
for _,actor in ipairs(pawns) do add_position_components(actor) end
cow['<PosRotContext>k__BackingField']={call=function() return heading end}
function cow:call(method,value) self[method]=value end
local passenger_controller={seated=false}
local npc_driver_seat={SitChara=driver,seated=true,call=function(self,method) assert(method=='isSit()');return self.seated end}
function passenger_controller:call(method)
    if method=='get_DrivingSeat' then return npc_driver_seat end
    assert(method=='isPlayerSit()');return self.seated
end
ox.EnemyCtrl={Ch2={['<CachedConnectParts>k__BackingField']={CowChara=cow},
    ['<CachedOxcart>k__BackingField']=passenger_controller}}
function ox:call() return self end
local status={broken=false,call=function(self,m)
    if m=='getCurrentDriver' then return driver.id end
    if m=='clrDriver()' then self.clear_calls=(self.clear_calls or 0)+1; return end
    if m=='isBroken_OxCart()' then return self.broken end
    return false
end}
function status:get_type_definition()
    return {get_method=function(_,name)
        if name=='clrDriver' then return {get_num_params=function() return 0 end} end
    end}
end
local cm={['<ManualPlayer>k__BackingField']=human}
local nm={OxcartManager={_RaidAttack_CachedGameObject=ox,getStatus=function() return status end},getCharacter=function() return driver end}
local gui={call=function(_,m) if m=='isPausedGUI()' then return is_paused end return false end}
local function pawn_wrap(actor) return {get_CachedCharacter=function() return actor end} end
local members={_items={[0]=pawn_wrap(pawns[2]),[1]=pawn_wrap(pawns[3])},get_Count=function() return 2 end}
local pm={get_MainPawn=function() return pawn_wrap(pawns[1]) end,get_PartyPawnList=function() return members end}
local keyboard_names={A=1,D=2,G=3,E=4,F=5,W=6,S=7,LShift=8,Alpha1=9,Alpha2=10,Alpha3=11,Alpha4=12,Space=13,X=14}
local gamepad_names={RTrigBottom=1,RLeft=2,Cancel=4,Decide=1024,RTrigTop=8,LTrigTop=16,LTrigBottom=32,LUp=64,LLeft=128,LRight=256,LDown=512}
local function definition(name)
    return {get_fields=function()
        local values = name=='via.hid.KeyboardKey' and keyboard_names or name=='via.hid.GamePadButton' and gamepad_names or name=='via.hid.MouseButton' and {L=1,R=2} or {}
        local fields={}
        for key,value in pairs(values) do fields[#fields+1]={is_static=function() return true end,get_name=function() return key end,get_data=function() return value end} end
        return fields
    end,get_method=function(_,sig)
        if name=='app.Sm80_042_Parts' then return name..'.'..sig end
        return sig
    end}
end
local kb={call=function(_,_,key) return kb_down[key] or false end}
local gp={call=function(_,m) if m=='get_AxisL()' then return {x=stick_x} end return gp_bits end}
local mouse={call=function(_,_,flag) return flag and (mouse_bits & flag)==flag or false end}
local scene={call=function(_,_,name) if name=='gm80_042' then return body end end}
sdk={find_type_definition=definition,typeof=function(x) return x end,get_native_singleton=function(x) return x end,
    get_managed_singleton=function(name)
        if name=='app.CharacterManager' then return cm elseif name=='app.NPCManager' then return missing and nil or nm
        elseif name=='app.GuiManager' then return gui elseif name=='app.PawnManager' then return pm end
    end,
    call_native_func=function(name,_,method)
        if name=='via.hid.Keyboard' then return kb elseif name=='via.hid.Gamepad' then return gp
        elseif name=='via.hid.Mouse' then return mouse elseif name=='via.SceneManager' then return scene end
    end,
    hook=function(method,pre) hooks[method]=pre end,to_managed_object=function(x) return x end,to_int64=function(x) return x end,
    PreHookResult={SKIP_ORIGINAL='skip'}}
json={load_file=function() return rawget(_G,'LMD_TEST_CONFIG') end,dump_file=function() end}
log={error=function() end,warn=function() end}
re={on_application_entry=function(name,fn) callbacks[name]=fn end,on_frame=function(fn) callbacks.frame=fn end,
    on_pre_application_entry=function(name,fn) pre_callbacks[name]=fn end,
    on_draw_ui=function(fn) callbacks.ui=fn end,on_script_reset=function(fn) callbacks.reset=fn end,on_config_save=function() end,
    on_pre_gui_draw_element=function(fn) callbacks.gui_draw=fn end}
imgui={}
