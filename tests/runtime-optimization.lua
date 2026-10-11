;(function()
local bus=_G.DD2_OxcartControl
local function upvalue(fn,key)
    for i=1,100 do
        local name,value=debug.getupvalue(fn,i)
        if not name then break end
        if name==key then return value end
    end
    error('Missing test upvalue: '..key)
end
local options=upvalue(bus.journey.passenger_camera,'options')
options.PLAYER_NEAR_CART_NONCOMBAT=false
for _,actor in ipairs({human,ox,pawns[1],pawns[2],pawns[3]}) do
    function actor.am:get_address() return actor.id+10000 end
end
function passenger_controller:isPlayerSit() return self.seated end
function passenger_controller:get_GameObject() return body end
function ox:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
function driver:get_IsDead() return false end
local actors={}
nm.NPCHolderDic={}
for i=1,200 do
    local actor=object('unrelated NPC '..i)
    actors[actor.id]=actor;nm.NPCHolderDic[i]={CharaID=actor.id}
end
local queries,rosters,lookups,strings,components=0,0,0,0,0
local old_get=nm.getCharacter
nm.getCharacter=function(self,id) queries=queries+1;return actors[id] or old_get(self,id) end
local old_main=pm.get_MainPawn
pm.get_MainPawn=function(self) rosters=rosters+1;return old_main(self) end
local old_def=sdk.find_type_definition
sdk.find_type_definition=function(name)
    if name=='app.NPCUtil' then
        return {get_method=function() return {call=function() return false end} end}
    end
    return old_def(name)
end
local old_scene=scene.call
scene.call=function(self,method,name) lookups=lookups+1;return old_scene(self,method,name) end
local function tick() clock=clock+1/60;callbacks.LateUpdateBehavior() end
nm.OxcartManager._RaidAttack_CachedGameObject=nil
for i=1,600 do tick() end
assert(rosters==0 and queries==0,'Idle controller still scans companions/NPCs')
print('PASS: no cart / no bindings: 600 frames, zero party scans and zero NPC queries')
local actor=actors[nm.NPCHolderDic[1].CharaID]
local original_call=actor.call
actor.call=function(self,method,...)
    if method=='getComponent(System.Type)' then components=components+1 end
    return original_call(self,method,...)
end
local node={ToString=function() strings=strings+1;return 'Idle' end}
local action_hook=hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
for i=1,1000 do assert(action_hook({[2]=actor.am,[4]=node,[5]=0})==nil) end
assert(components==0 and strings==0,'Unrelated idle actions still queried components/strings')

nm.OxcartManager._RaidAttack_CachedGameObject=ox
local found=assert(bus.journey.resolve_body(ox))
local discovered=lookups
for i=1,600 do assert(bus.journey.resolve_body(ox)==found) end
assert(lookups==discovered,'Valid body cache repeated scene discovery')
npc_driver_seat.SitChara=nil;npc_driver_seat.seated=false
ox.am.CurrentActionList[0].Name='Walk'
assert(not bus.journey.enforce_driver_wait(ox),'Discovery registered an untouched cart')
ox.am:requestActionCore(10,'Run',0)
assert(ox.am.CurrentActionList[0].Name=='Run','Untouched cart native movement was blocked')
passenger_controller.seated=true
assert(bus.journey.enforce_driver_wait(ox) and ox.am.CurrentActionList[0].Name=='Wait',
    'Actual passenger entry lost no-driver stop')
passenger_controller.seated=false
ox.am:requestActionCore(10,'Walk',0)
assert(ox.am.CurrentActionList[0].Name=='Wait','Previously used cart lost no-driver stop')
-- The active managed-cart case must also reject unrelated actors before string conversion.
for i=1,1000 do assert(action_hook({[2]=actor.am,[4]=node,[5]=0})==nil) end
assert(components==0 and strings==0,'Managed cart caused unrelated NPC action queries')
print('PASS: 2000 unrelated actions, zero component and action-string queries; 600 cache reads, zero repeated scene lookups')

npc_driver_seat.SitChara=driver;npc_driver_seat.seated=true
passenger_controller.seated=true;tick();bus.journey.sit();tick()
assert(#bus.journey.records()>=3,'Companion seating lost')
local target=pawns[1]
local alias={get_address=function() return target.am:get_address() end,
    get_GameObject=function() error('Target filtering queried GameObject') end}
action_hook({[2]=alias,[4]={ToString=function() return 'Caught' end},[5]=0})
for _,binding in ipairs(bus.journey.records()) do assert(binding.char~=target,'Caught did not release cached target') end
assert(target.machine.enabled,'Caught did not restore FSM')
action_hook({[2]=human.am,[4]={ToString=function() return 'Warp' end},[5]=0})
assert(#bus.journey.records()==0,'Player warp did not release bound companions')

-- Invalid bodies are never returned, and misses back off rather than scan every call.
passenger_controller.seated=false;body.invalid=true
clock=clock+1
assert(bus.journey.resolve_body(ox)==nil,'Invalid body cache reused')
local missed=lookups
for i=1,60 do assert(bus.journey.resolve_body(ox)==nil) end
assert(lookups==missed,'Missing body did not back off')
body.invalid=false;clock=clock+0.26
assert(bus.journey.resolve_body(ox)==body,'Recovered body was not rediscovered')
local other=object('replacement ox')
other.EnemyCtrl=ox.EnemyCtrl
nm.OxcartManager._RaidAttack_CachedGameObject=other;tick()
npc_driver_seat.SitChara=nil;npc_driver_seat.seated=false
assert(not bus.journey.enforce_driver_wait(other),'Cart replacement inherited old management permission')
other.am:requestActionCore(10,'Walk',0)
assert(other.am.CurrentActionList[0].Name=='Walk','Replacement native cart inherited old action filter')
print('PASS: target identity aliases, caught/warp cleanup, invalid/missing body recovery, and replacement-cart isolation')
local previous_native=sdk.call_native_func
passenger_controller.seated=true
assert(bus.journey.enforce_driver_wait(other),'Second cart passenger entry did not register')
passenger_controller.seated=false
local replacement_scene={call=function(_,method,name) if name=='gm80_042' then return body end end}
sdk.call_native_func=function(name,...)
    if name=='via.SceneManager' then return replacement_scene end
    return previous_native(name,...)
end
assert(bus.journey.resolve_body(other)==body,'Scene change did not rediscover body')
assert(not bus.journey.enforce_driver_wait(other),'Scene change retained old management permission')
print('PASS: scene identity change invalidates body and management permission')
local scene_lookups=0
sdk.call_native_func=function(name,...)
    if name=='via.SceneManager' then
        return {get_address=function() return 987654 end,call=function(_,method,model)
            scene_lookups=scene_lookups+1
            if model=='gm80_042' then return body end
        end}
    end
    return previous_native(name,...)
end
passenger_controller.seated=true
assert(bus.journey.enforce_driver_wait(other),'Scene alias test did not register passenger')
-- Resolve once to capture the new scene identity, then re-register its passenger.
assert(bus.journey.resolve_body(other)==body)
assert(bus.journey.enforce_driver_wait(other))
passenger_controller.seated=false
local aliases=scene_lookups
for i=1,60 do assert(bus.journey.resolve_body(other)==body) end
assert(scene_lookups==aliases,'Same-address scene wrappers lost body cache')
assert(bus.journey.enforce_driver_wait(other),'Same-address scene wrappers lost management permission')
print('PASS: same-address scene wrappers retain cache and current-cart permission')
end)()
