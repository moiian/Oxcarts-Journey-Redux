local calls, errors = {}, {}
local function vec(x,y,z) return {x=x,y=y,z=z} end
local function recorder(name)
    return {call=function(_,method,value) calls[#calls+1]={name,method,value} end}
end
local function character()
    local transform={position=vec(0,0,0),universal={world='universal'}}
    function transform:get_Position() return self.position end
    function transform:get_UniversalPosition() return self.universal end
    function transform:set_Position(value) self.position=value end
    function transform:lookAt(target,up) self.target,self.up=target,up end
    function transform:set_Parent(parent) self.parent=parent end
    return {get_Valid=function() return true end,get_Transform=function() return transform end,
        ['<PosRotContext>k__BackingField']=recorder('context'),
        ['<AdjustTerrain>k__BackingField']={MainCharacterController=recorder('controller')},
        ['<FallInfo>k__BackingField']=recorder('fall')}
end
local player, pawn = character(), character()
local is_character_valid=function(ch) return ch and ch:get_Valid() end
local log={error=function(value) errors[#errors+1]=value end}
local function vec_scale(v,k) return vec(v.x*k,v.y*k,v.z*k) end
local function vec_add(a,b) return vec(a.x+b.x,a.y+b.y,a.z+b.z) end
local axisX,axisY,axisZ=vec(1,0,0),vec(0,0.8,0.6),vec(0,-0.6,0.8)
local seat_anchor_transform={get_Position=function() return vec(10,20,30) end,
    get_AxisX=function() return axisX end,get_AxisY=function() return axisY end,
    get_AxisZ=function() return axisZ end,
    get_GameObject=function() return {get_Valid=function() return true end} end}
local seating_lock_active, runtime_clock = true, 0
local spec={x=2,y=3,z=4,lookX=0,lookZ=1}
local seat_bindings={{char=pawn,seat_spec=spec},{char=player,seat_spec=spec}}
local detached=false
local function detach_bound_characters() detached=true end
local fsm_calls, pending_ai_lock = {}, {}
local allow_enable = true
local function set_fsm_enabled(ch, enabled)
    assert(enabled==true,'Released pawn was frozen again')
    fsm_calls[#fsm_calls+1]=ch
    return allow_enable
end
local function start_seated_animation() error('Unexpected animation mutation') end
local passenger_idle_nodes={}
local roster={[pawn]=true}
local function collect_party_pawns() return {pawn},roster end

-- IMPLEMENTATION --
pawn_seat_physics.step_pose_wait=function() end

enforce_seat_transforms(nil,false)
assert(#calls==4,'Pawn physics synchronization missing or applied to player')
assert(calls[1][2]=='setPos(via.Position)' and calls[1][3]==pawn:get_Transform().universal)
assert(calls[2][2]=='warp()' and calls[2][3]==nil,'Controller warp must have no argument')
assert(calls[3][2]=='resetBaseHeight(via.Position)' and calls[4][2]=='resetFallHeight()')
local p=pawn:get_Transform().position
assert(p.x==12 and math.abs(p.y-20)<0.0001 and p.z==35,'Preset coordinate convention changed')
assert(pawn:get_Transform().up==axisY,'Cart tilt no longer preserved')
calls={};enforce_seat_transforms(nil,true)
assert(#calls==4,'Photo mode lost pawn physics synchronization')
p=pawn:get_Transform().position
calls={};pawn_seat_physics.release(pawn)
assert(#calls==4 and pawn:get_Transform().position==p,'Release teleported pawn or missed fall reset')
calls={};pawn_seat_physics.release(player)
assert(#calls==0,'Release changed native player physics')
pawn['<FallInfo>k__BackingField']=nil
fsm_calls={}
local unchanged=vec(99,99,99);pawn:get_Transform().position=unchanged
pending_ai_lock={pawn,player,pawn}
calls={};enforce_seat_transforms(nil,false);enforce_seat_transforms(nil,false)
assert(#calls==0 and pawn:get_Transform().position==unchanged,'Missing physics moved pawn anyway')
assert(#errors==1,'Identical synchronization errors spammed the log')
assert(#seat_bindings==1 and seat_bindings[1].char==player,'Failed pawn remained bound/protected')
assert(#pending_ai_lock==1 and pending_ai_lock[1]==player,'Failed pawn retained queued freeze')
assert(#fsm_calls==1 and fsm_calls[1]==pawn,'Failed pawn did not regain control')
assert(not detached,'Valid cart was detached')
local departing,extra=character(),character()
seat_bindings={{char=departing,seat_spec=spec},{char=extra,seat_spec=spec},{char=player,seat_spec=spec}}
roster={[extra]=true};pending_ai_lock={departing,extra}
pawn_seat_physics.prune_party()
assert(#seat_bindings==2 and seat_bindings[1].char==extra,'Party pruning removed a valid extra roster member')
assert(#pending_ai_lock==1 and pending_ai_lock[1]==extra,'Departed pawn retained deferred freeze')
roster=nil;pawn_seat_physics.prune_party()
assert(#seat_bindings==2,'Unreadable party roster was treated as departure')
pending_ai_lock={extra};pawn_seat_physics.remove(1)
assert(#pending_ai_lock==0 and #seat_bindings==1,'Caught/single removal did not clear queued freeze')
allow_enable=false;pawn_seat_physics.finish(extra)
assert(pawn_seat_physics.pending_release[extra],'Loading-time release failure was lost')
allow_enable=true;pawn_seat_physics.retry_release()
assert(not pawn_seat_physics.pending_release[extra],'Release retry did not clear recovered FSM')
print('PASS: pawn sync/fall/photo, failed-sync release, queued-freeze cancellation, full roster pruning and release retry')
