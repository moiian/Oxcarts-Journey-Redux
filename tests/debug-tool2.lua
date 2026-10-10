local clock,reads,saves=100,0,0
os.clock=function() return clock end
local callbacks,hooks,stores={},{},{}
local function copy(t)
    if type(t)~='table' then assert(t==nil or type(t)=='string' or type(t)=='number' or type(t)=='boolean');return t end
    assert(not t.get_address,'Managed object leaked into JSON')
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local next_id=0
local function obj(name)
    next_id=next_id+1
    local o={id=next_id,name=name,pos={x=0,y=0,z=0},draw=true}
    function o:get_Valid() return not self.invalid end
    function o:get_address() return self.id end
    function o:get_Transform() return self end
    function o:get_UniversalPosition() return self.pos end
    function o:get_GameObject() return self.go or self end
    function o:get_CharaID() return self.character_id or self.id end
    function o:call(m,...)
        local f=self[m:gsub('%(%s*%)$','')];if f then return f(self,...) end
        if m=='getComponent(System.Type)' then return self.char or self end
        if m=='get_DrawSelf' then return self.draw end
        error('Unavailable: '..m)
    end
    o.am={CurrentActionList={[0]={Name='Walk'},get_Count=function() return 1 end}}
    function o:get_ActionManager() return self.am end
    return o
end
local ox,body,driver,gm,status,manager,ai=obj('ox'),obj('body'),obj('driver'),obj('gm'),obj('status'),obj('manager'),obj('ai')
gm.go=body
local seated=true
local seat={SitChara=driver,call=function(_,m) if m=='isSit' then return seated end end}
function gm:get_DrivingSeat() return seat end
function ox:get_EnemyCtrl() return {get_Ch2=function() return {get_field=function() return gm end} end} end
local function container(id)
    local c,d=obj('container'),obj('common')
    d._ObjectID={_SelectedCharacterID=id};d._RequestID={_GenID={_TableID=7,_ExtraID=id},_UniqID={_RowID=2,_Index=3}}
    d._CustomGeneratorID={_TableID=7,_ExtraID=id};d._ContextPosition={x=1,y=2,z=3};d._ContextAngle={x=0,y=0,z=0,w=1}
    d._Category=8;d._LayerType=2;d._Option=123;d._IsRegisterDisableDestroyContent=false
    c._CommonInfo=d;return c
end
local c=container(ox.id);status['<CachedGenerateContainer>k__BackingField']=c
status['<oxcartAI>k__BackingField']=ai
ai['<CachedCharacter>k__BackingField']=ox
ai['<destroy_radius>k__BackingField']=50
function status:getCurrentDriver() return driver.id end
function manager:getStatus(id) assert(id==ox:get_CharaID());return status end
function manager:getFastTravelState() return 2 end
manager._RaidAttack_CachedGameObject=ox
local nm={OxcartManager=manager,call=function(_,m,id) assert(m=='getCharacter' and id==driver.id);return driver end}
sdk={typeof=function(x) return x end,to_managed_object=function(x) assert(type(x)~='number','Primitive miscast');return x end,
    to_int64=function(x) return x end,to_float=function(x) return x end,to_valuetype=function(x) return x end,
    get_managed_singleton=function(name) reads=reads+1;if name=='app.NPCManager' then return nm end end,
    find_type_definition=function(name) return {get_method=function(_,sig)
        if sig=='unregistDummyNPC(app.CharacterID)' then return end
        return name..'.'..sig
    end} end,
    hook=function(method,pre,post) hooks[method]={pre=pre,post=post} end}
thread={get_hook_storage=function() return stores[#stores] end,get_id=function() return 1 end}
re={on_application_entry=function(name,fn) callbacks[name]=fn end,on_draw_ui=function(fn) callbacks.ui=fn end,
    on_script_reset=function(fn) callbacks.reset=fn end}
json={dump_file=function(path,data) saves=saves+1;json.last_path=path;json.last=copy(data) end}
imgui={}
local previous=function() end;_G.AelinoreOxcartTrace2=previous
local m=assert(loadfile('debug/Aelinore DEBUG tool2.lua'))()
local function tick(dt) clock=clock+(dt or 0.21);callbacks.LateUpdateBehavior() end
local function event(kind)
    for i=#m.events,1,-1 do if m.events[i].kind==kind then return m.events[i] end end
end
local function invoke(key,args,ret,inner)
    local h=assert(hooks[key],key);stores[#stores+1]={}
    assert(h.pre(args)==nil,'Read-only hook blocked original')
    if inner then inner() end
    assert(h.post(ret)==ret,'Native return was changed');stores[#stores]=nil
end
for _=1,10 do tick() end
assert(reads==0 and saves==0,'OFF probe read live objects or wrote files')
m.start()
assert(m.active and saves==1 and m.last.body.address==tostring(body.id) and m.last.driver.seated==true)
assert(m.last.status.container.options==123 and m.last.manager.fast_travel==2 and m.last.ai.destroy_radius==50)
local missing=false;for _,h in ipairs(m.hooks) do if not h.available then missing=true end end;assert(missing)
local root='app.OxcartManager.onUpdate()'
local destroy='app.OxcartAI.requestAllDestroy(System.Boolean, System.Boolean, System.Boolean)'
local gd='app.GenerateManager.requestDestroy(app.GenerateInfo.GenerateInfoContainer, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean)'
invoke(root,{nil,manager},nil,function()
    invoke(destroy,{nil,ai,0,1,0},nil,function()
        invoke(gd,{nil,manager,c,0,1,0,1,0},0,function()
            invoke('via.GameObject.destroy(via.GameObject)',{nil,body},nil)
        end)
    end)
end)
local chain
for _,e in ipairs(m.events) do
    if e.kind=='native_enter' and e.data.method=='via.GameObject.destroy(via.GameObject)' then chain=e.data.parent_chain end
    if e.kind=='native_return' and e.data.method==gd then assert(e.data.value==false,'False result lost') end
end
assert(chain and #chain==3 and chain[1]==root and chain[2]==destroy and chain[3]==gd,'Nested context lost')
local decision='app.GenerateManager.isReGenerateDitanceCheck(app.GenerateInfo.CommonInfoData, System.Single)'
local before_decision=#m.events
for _=1,7200 do invoke(decision,{nil,manager,c._CommonInfo,20},0) end
assert(#m.events==before_decision and #m.decisions==1 and m.decisions[1].result==false,'Decision polling leaked events or lost false')
local auto='app.AutoDestroyDistributorUnit.update()'
invoke(auto,{nil,manager},nil,function()
    invoke(gd,{nil,manager,c,1,0,0,0,0},1,function()
        local e=event('native_enter')
        assert(e.data.upstream_context[1].method==auto,'Destroy upstream missing')
        assert(e.data.current_state.status.container.character_id==ox.id,'Destroy-time target state missing')
        assert(#e.data.recent_decisions==1 and e.data.recent_decisions[1].result==false,'Range decision evidence missing')
        assert(e.data.lua_bridge_stack:find('not a native stack',1,true),'Lua stack mislabeled')
    end)
end)
local registration='app.OxcartStatus.registerOxcart(app.CharacterID, app.OxcartAI, System.Boolean)'
local before_flood=#m.events
for i=1,7200 do
    invoke(root,{nil,manager},nil,function()
        invoke('app.OxcartManager.updateConvWarp()',{nil,manager},nil)
        invoke('app.OxcartManager.onFastTravel()',{nil,manager},nil)
    end)
    invoke(registration,{nil,status,ox.id,ai,1},status)
end
assert(m.active and #m.events==before_flood+2,'Actual 120-second polling pattern filled event budget')
assert(event('native_enter').count==7200 and event('native_return').count==7200,'Registration repeats not counted')
invoke('app.OxcartManager.onFastTravel()',{nil,manager},nil,function()
    invoke(destroy,{nil,ai,0,1,0},nil,function()
        local e=event('native_enter');assert(e.data.parent_chain[1]=='app.OxcartManager.onFastTravel()','Polling context removed from real event')
    end)
end)
local count=#m.events
invoke(gd,{nil,manager,container(999),0,0,0,0,0},1)
invoke('app.OxcartManager.destroyGenerateRequest(app.CharacterID)',{nil,manager,999},nil)
assert(#m.events==count,'Unrelated NPC included')
invoke('app.OxcartManager.destroyGenerateRequest(app.CharacterID)',{nil,manager,ox.id},nil)
assert(#m.events==count+2)
for _=1,10000 do _G.AelinoreOxcartTrace2('ojr_stop',{reason='no driver'}) end
assert(event('ojr_stop').data.count==10000 and #m.events==count+3,'Stop flood not coalesced')
_G.AelinoreOxcartTrace2('ojr_request_blocked',{node='Walk'});assert(#m.events==count+3)
body.draw=false;tick();assert(#m.incidents==1 and #m.incidents[1].samples>0)
manager._RaidAttack_CachedGameObject=nil;tick()
assert(m.last.ox.address==nil and m.last.status.address==tostring(status.id),'Logical record lost during unload')
local ox2=obj('replacement');ox2.character_id=ox.id
function ox2:get_EnemyCtrl() return ox:get_EnemyCtrl() end
manager._RaidAttack_CachedGameObject=ox2;body.draw=true;tick()
assert(m.last.ox.address==tostring(ox2.id) and m.cart_id==tostring(ox.id))
ox2.am.CurrentActionList=setmetatable({get_Count=function() return 0 end},{__index=function() error('Empty list indexed') end})
tick();assert(m.active and m.last.ox.action==nil and #m.errors==0)
local cb1='System.Action`2<app.PrefabInstantiateResults,app.DummyArg_2_0_0_13>'
local cb2='System.Action`2<app.PrefabInstantiateResults,app.DummyArg_2_0_0_14>'
invoke('app.GenerateManager.forceRequestCreateInstance(app.GenerateInfo.GenerateInfoContainer, '..cb1..', '..cb2..')',{nil,manager,c,nil,nil},17)
assert(event('native_return').data.value==17)
-- Separate invocation storage under recursion; threads never share a call chain.
invoke(destroy,{nil,ai,1,0,0},nil,function() invoke(destroy,{nil,ai,0,0,0},nil) end)
m.mark();assert(json.last.reason=='visual mark' and json.last.read_only)
tick(6);assert(json.last.reason=='checkpoint')
tick(121);assert(not m.active and json.last.reason=='120-second recording completed')
local saved_reads=reads;tick();assert(reads==saved_reads)
m.start();for i=1,1100 do _G.AelinoreOxcartTrace2('ojr_speed_requested',{node=tostring(i)}) end
assert(m.active and m.page==2 and m.total_events==1101 and #m.events==101,'Page rollover stopped monitoring or lost events')
assert(json.last.reason=='event page completed; recording continues' and #json.last.events==1000)
body.draw=false;tick();assert(m.active and #m.incidents>0,'Later disappearance after rollover missed')
invoke('via.GameObject.destroy(via.GameObject)',{nil,body},nil)
assert(event('native_enter').data.method=='via.GameObject.destroy(via.GameObject)','Later destroy after rollover missed')
m.stop('manual stop');assert(json.last.page==2 and json.last.active==false and json.last_path:match('_part002%.json$'))
local ended=m.ended;tick(60);assert(m.ended==ended and m.ended-m.started==json.last.elapsed,'Stopped elapsed timer advanced')
-- Main-menu recording can identify a newly generated cart without a cached ox.
manager._RaidAttack_CachedGameObject=nil
m.start()
assert(m.cart_id==nil)
local generated=container(987654)
local prefab=obj('prefab');function prefab:get_ResourcePath() return 'AppSystem/ch/ch299/Prefab/ch299003_A_10.pfb' end
invoke('app.GenerateManager.requestCreateInstance(app.PrefabController, app.GenerateInfo.GenerateInfoContainer, System.Int32, app.InstanceInfo, '..cb1..', '..cb2..')',
    {nil,manager,prefab,generated,0,nil,nil,nil},12)
assert(m.scene_cart_ids['987654'] and event('native_return').data.value==12,'Scene generation before nearest cart discovery missed')
invoke(gd,{nil,manager,generated,1,0,0,0,0},1)
assert(event('native_enter').data.arguments[1].value.character_id==987654)
callbacks.reset()
assert(not m.active and _G.AelinoreOxcartTrace2==previous and not _G.AelinoreDebugTool2)
assert(json.last_path:match('^AelinoreOxcartLifecycle_'))
print('PASS: lifecycle probe OFF idle, filtering, native returns, 7200-frame real polling regression, nested context, continued event pages/later disappearance, save/reset')
