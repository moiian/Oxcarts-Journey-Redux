local actions,seat_bindings={},{}
local player,seating_lock_active,runtime_clock={},false,1
local cart_trip,preset_cursor={pause={}}, {Normal=1}
local movement_control=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/speed.lua'))()
local last_sit_preset,last_sit_request_at={},nil
local ox,anchor={},{}
local function spec(node) return {anim=node,randomIdle=false,x=2,y=3,z=4,lookX=0,lookZ=1} end
local function vec_scale(v,k) return {x=v.x*k,y=v.y*k,z=v.z*k} end
local function vec_add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
function anchor:get_Position() return {x=10,y=20,z=30} end
function anchor:get_AxisX() return {x=1,y=0,z=0} end
function anchor:get_AxisY() return {x=0,y=1,z=0} end
function anchor:get_AxisZ() return {x=0,y=0,z=1} end
local seat_anchor_transform=anchor
local fall_resets,reset_before_request=0,false
local options={FREEZE_COMPANION_FSM=true,Presets={Normal={
    {enabled=true,pawns={spec('SitOnChairActions'),spec('SitOnChairActions'),spec('SitOnChairActions')}},
    {enabled=true,pawns={spec('LivSitChairLean'),spec('LivSitChairLean'),spec('LivSitChairLean')}}}}}
local machine={enabled=true}
function machine:call(method,value)
    if method=='get_Enabled()' then return self.enabled end
    assert(method=='set_Enabled(System.Boolean)');self.enabled=value
end
local function dummy() return {call=function() end} end
local transform={get_UniversalPosition=function() return {} end,set_Parent=function() end}
function transform:set_Position(p) self.position=p end
function transform:lookAt() end
local pawn={get_Valid=function() return true end,get_Transform=function() return transform end,
    ['<Human>k__BackingField']={Fsm=machine},
    ['<PosRotContext>k__BackingField']=dummy(),
    ['<AdjustTerrain>k__BackingField']={MainCharacterController=dummy()},
    ['<FallInfo>k__BackingField']={call=function(_,method)
        assert(machine.enabled,'Fall reset executed while frozen')
        assert(transform.position.x==12 and transform.position.y==23 and transform.position.z==34,'Fall reset used stale seat position')
        if method=='resetFallHeight()' then fall_resets=fall_resets+1;reset_before_request=true end
    end},
    ['<ActionManager>k__BackingField']={requestActionCore=function(_,priority,node)
        assert(machine.enabled,'Pose requested while FSM frozen')
        assert(reset_before_request,'Pose was not preceded by same-call fall reset');reset_before_request=false
        actions[#actions+1]={priority=priority,node=node}
    end}}
local function is_character_valid(ch) return ch==pawn or ch==player end
local function collect_companions() return {pawn},{[pawn]=true},{} end
local function companion_interacting() return false end
local external,paused=false,false
local function external_driver_active() return external end
local function gameplay_is_paused() return paused end
local function find_active_ox() return ox end
local function find_cart_body() return anchor end
local function resolve_seat_anchor() return anchor end
local function classify_cart_model() return 'Normal' end
local function player_is_physically_seated() return true end
local function player_uses_cart_seat_node() return true end
local log={error=function(value) error(value) end}
local re={on_script_reset=function() end}
-- IMPLEMENTATION --
assert(pawn_seat_physics.blocks_pose_action==nil,'Retired action guard remains')
sit_with_next_preset()
assert(#actions==1 and actions[1].node=='SitOnChairActions' and actions[1].priority==0 and machine.enabled,
    'Initial seat must use the same priority as preset changes')
assert(fall_resets==1,'Initial sit did not reset fall exactly once')
runtime_clock=1.2;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(machine.enabled,'Initial pose froze early')
runtime_clock=1.31;pawn_seat_physics.advance_frame();assert(not machine.enabled,'Initial next-frame FSM freeze missing')
start_seated_animation(pawn,seat_bindings[1].seat_spec,'LivSitPose')
assert(fall_resets==2,'Random pose did not reset fall exactly once')
assert(machine.enabled and actions[#actions].node=='LivSitPose' and actions[#actions].priority==1,
    'Random pose priority or thaw behavior changed')
pawn_seat_physics.update_fsm(seat_bindings[1]);assert(machine.enabled,'Random pose froze in the request callback')
pawn_seat_physics.advance_frame();assert(not machine.enabled,'Random pose did not freeze on next callback without time advancing')
assert(runtime_clock==1.31,'Random pose test unexpectedly advanced its timer')
assert(fall_resets==2,'Next-frame freeze unexpectedly reset fall')
options.FREEZE_COMPANION_FSM=false
start_seated_animation(pawn,seat_bindings[1].seat_spec,'LivSitChairBook01')
pawn_seat_physics.advance_frame();assert(machine.enabled,'Random pose ignored global freeze OFF')
options.FREEZE_COMPANION_FSM=true
start_seated_animation(pawn,seat_bindings[1].seat_spec,'LivSitPose')
pawn_seat_physics.advance_frame();assert(not machine.enabled)
actions={};runtime_clock=2;sit_with_next_preset()
assert(#actions==1 and actions[1].node=='LivSitChairLean' and actions[1].priority==0 and machine.enabled,
    'Legacy preset did not directly request sitting with FSM enabled')
runtime_clock=2.2;pawn_seat_physics.update_fsm(seat_bindings[1])
assert(machine.enabled,'Legacy preset froze before the next behavior callback')
last_sit_request_at=runtime_clock;sit_with_next_preset();assert(#actions==1,'Same-frame duplicate switch accepted')
pawn_seat_physics.advance_frame()
assert(not machine.enabled,'Legacy preset did not freeze on next behavior callback')
runtime_clock=2.5;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled,'Preset freeze was lost')
runtime_clock=2.62;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled,'New sitting pose did not freeze')
options.FREEZE_COMPANION_FSM=false;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(machine.enabled,'OFF did not restore FSM')
options.FREEZE_COMPANION_FSM=true;pawn_seat_physics.update_fsm(seat_bindings[1])
runtime_clock=3;pawn_seat_physics.advance_frame();assert(not machine.enabled)
detach_bound_characters();assert(#seat_bindings==0 and machine.enabled,'Detach failed to restore FSM')
-- Preserve an originally-disabled FSM, rather than always enabling on release.
machine.enabled=false;bind_pawns_to_seats();assert(machine.enabled)
runtime_clock=3.31;pawn_seat_physics.advance_frame();assert(not machine.enabled)
detach_bound_characters();assert(not machine.enabled,'Original disabled FSM state lost')
machine.enabled=true;bind_pawns_to_seats()
local binding=seat_bindings[1]
binding.seat_spec.useDirectMotion=true
function pawn:get_Motion() return {getLayer=function() return {call=function() assert(machine.enabled) end} end} end
start_seated_animation(pawn,binding.seat_spec);assert(machine.enabled)
runtime_clock=3.62;pawn_seat_physics.advance_frame();assert(not machine.enabled,'Direct motion failed to freeze next frame')
assert(ox.enabled==nil,'Companion FSM altered ox')
binding.seat_spec.useDirectMotion=false
-- A pending next-frame freeze must not survive release or global OFF.
runtime_clock=4;sit_with_next_preset();assert(machine.enabled)
detach_bound_characters();pawn_seat_physics.advance_frame();assert(machine.enabled,'Released pawn was refrozen')
bind_pawns_to_seats();runtime_clock=5;sit_with_next_preset()
options.FREEZE_COMPANION_FSM=false;pawn_seat_physics.advance_frame();assert(machine.enabled,'Global OFF ignored by pending freeze')
options.FREEZE_COMPANION_FSM=true
-- Direct Bank/Motion also follows reset/request/next-frame freeze.
local direct=seat_bindings[1]
direct.seat_spec.useDirectMotion=true
function pawn:get_Motion() return {getLayer=function() return {call=function() assert(machine.enabled and reset_before_request,'Direct motion missed reset before request');reset_before_request=false end} end} end
start_seated_animation(pawn,direct.seat_spec,nil,direct,true)
assert(machine.enabled and direct.fsm_freeze_frame,'Direct motion did not queue next-frame freeze')
pawn_seat_physics.advance_frame();assert(not machine.enabled)
local cart_action_filters={}
function pawn:get_CharaIDString() return 'pawn' end
local action_hook
local sdk={PreHookResult={SKIP_ORIGINAL='skip'},to_managed_object=function(v) return v end,
    to_int64=function(v) return v end,typeof=function(v) return v end,
    find_type_definition=function() return {get_method=function() return {} end} end,
    hook=function(_,fn) action_hook=fn end}
-- ACTION HOOK --
local function invoke(node)
    local owner={get_Valid=function() return true end,call=function() return pawn end}
    return action_hook({nil,{get_GameObject=function() return owner end},0,{ToString=function() return node end},0})
end
assert(invoke('Run')==nil,'Retired competing-action hook still blocks requests')
assert(invoke('Caught')==nil and #seat_bindings==0 and machine.enabled,'Caught did not restore FSM before release')
options.Presets.Normal[1].pawns[1].useDirectMotion=false
options.Presets.Normal[2].pawns[1].useDirectMotion=false
bind_pawns_to_seats();pawn_seat_physics.advance_frame()
assert(not machine.enabled)
local action_count,fall_count=#actions,fall_resets
pawn_seat_physics.queue_preset('Normal',2)
assert(#actions==action_count and not machine.enabled,'UI queue mutated FSM or animation')
paused=true;pawn_seat_physics.apply_pending_preset()
assert(pawn_seat_physics.pending_preset and #actions==action_count,'Paused menu applied an animation')
paused=false;pawn_seat_physics.advance_frame();pawn_seat_physics.apply_pending_preset()
assert(machine.enabled and #actions==action_count+1 and fall_resets==fall_count+1,'Queued switch skipped full pose/fall/FSM flow')
assert(actions[#actions].node=='LivSitChairLean')
pawn_seat_physics.advance_frame();assert(not machine.enabled,'Queued switch failed to freeze on following behavior')
options.Presets.Normal[1].skipPassenger=true
runtime_clock=runtime_clock+1;sit_with_next_preset()
assert(preset_cursor.Normal==2,'Passenger cycle did not skip marked preset')
options.Presets.Normal[2].skipPassenger=true
action_count=#actions;runtime_clock=runtime_clock+1;sit_with_next_preset()
assert(#actions==action_count,'All-skipped passenger cycle requested a pose')
options.Presets.Normal[1].skipPassenger=false
pawn_seat_physics.queue_preset('Normal',1);detach_bound_characters()
assert(pawn_seat_physics.pending_preset==nil,'Release retained queued reseating')
-- Player remains native and never enters the companion FSM path.
local player_actions=0
player={get_Valid=function() return true end,get_Transform=function() return transform end,
    ['<ActionManager>k__BackingField']={requestActionCore=function() player_actions=player_actions+1 end}}
start_seated_animation(player,{anim='Wait',freezeFsm=true})
assert(player_actions==1,'Legacy player handling changed')
print('PASS: init/preset/random/direct motion use same-frame fall reset before request and next-frame freeze; OFF, restore and native player')
