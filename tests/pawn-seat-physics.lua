local calls, errors = {}, {}
local options={FREEZE_COMPANION_FSM=true}
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
    local machine={enabled=true,call=function(self,method,value)
        if method=='get_Enabled()' then return self.enabled end
        assert(method=='set_Enabled(System.Boolean)');self.enabled=value
    end}
    return {get_Valid=function() return true end,get_Transform=function() return transform end,
        ['<Human>k__BackingField']={Fsm=machine},
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
local spec={x=2,y=3,z=4,lookX=0,lookZ=1,useOxAnchor=true,freezeFsm=true}
local seat_bindings={{char=pawn,seat_spec=spec},{char=player,seat_spec=spec}}
local detached=false
local function detach_bound_characters() detached=true end
local function set_fsm_enabled()
    error('Seating must not change FSM state')
end
local function start_seated_animation() error('Unexpected animation mutation') end
local passenger_idle_nodes={}
local roster={[pawn]=true}
local function collect_party_pawns() return {pawn},roster end
local function collect_companions() return {pawn},roster,{} end
local function companion_interacting() return false end

-- IMPLEMENTATION --
pawn_seat_physics.step_pose_wait=function() end

local ox={get_Valid=function() return true end,get_Transform=function()
    error('Removed ox anchor was accessed')
end}
enforce_seat_transforms(ox,false)
assert(#calls==2,'Pawn physics synchronization missing or applied to player')
assert(calls[1][2]=='setPos(via.Position)' and calls[1][3]==pawn:get_Transform().universal)
assert(calls[2][2]=='warp()' and calls[2][3]==nil,'Controller warp must have no argument')
local p=pawn:get_Transform().position
assert(p.x==12 and math.abs(p.y-20)<0.0001 and p.z==35,'Preset coordinate convention changed')
assert(pawn:get_Transform().up==axisY,'Cart tilt no longer preserved')
calls={};enforce_seat_transforms(nil,true)
assert(#calls==2,'Photo mode reset fall or lost position synchronization')
p=pawn:get_Transform().position
calls={};pawn_seat_physics.release(pawn)
assert(#calls==2 and pawn:get_Transform().position==p,'Release teleported pawn or reset fall')
calls={};pawn_seat_physics.reset_fall(pawn)
assert(#calls==2 and calls[1][2]=='resetBaseHeight(via.Position)' and calls[2][2]=='resetFallHeight()','Explicit pose-event reset missing')
calls={};pawn_seat_physics.release(player)
assert(#calls==0,'Release changed native player physics')
pawn['<FallInfo>k__BackingField']=nil
local unchanged=vec(99,99,99);pawn:get_Transform().position=unchanged
calls={};enforce_seat_transforms(nil,false);enforce_seat_transforms(nil,false)
assert(#calls==0 and pawn:get_Transform().position==unchanged,'Missing physics moved pawn anyway')
assert(#errors==1,'Identical synchronization errors spammed the log')
assert(#seat_bindings==1 and seat_bindings[1].char==player,'Failed pawn remained bound/protected')
assert(not detached,'Valid cart was detached')
local departing,extra=character(),character()
seat_bindings={{char=departing,seat_spec=spec},{char=extra,seat_spec=spec},{char=player,seat_spec=spec}}
roster={[extra]=true}
pawn_seat_physics.prune_party()
assert(#seat_bindings==2 and seat_bindings[1].char==extra,'Party pruning removed a valid extra roster member')
roster=nil;pawn_seat_physics.prune_party()
assert(#seat_bindings==2,'Unreadable party roster was treated as departure')
pawn_seat_physics.remove(1)
assert(#seat_bindings==1 and extra:get_Transform().parent==nil,'Single removal left pawn attached')
pawn_seat_physics.finish(extra)
assert(#seat_bindings==1,'Repeated release changed remaining player binding')
print('PASS: pawn sync/fall/photo, failed-sync release, full roster pruning and body-only anchor')
