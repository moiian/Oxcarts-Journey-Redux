local actions,seat_bindings={},{}
local player,seating_lock_active,runtime_clock={},false,1
local cart_trip,preset_cursor={pause={}}, {Normal=1}
local last_sit_preset,last_sit_request_at={},nil
local ox,anchor={},{}
local function spec(node) return {anim=node,randomIdle=false} end
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
local pawn={get_Valid=function() return true end,get_Transform=function() return transform end,
    ['<Human>k__BackingField']={Fsm=machine},
    ['<PosRotContext>k__BackingField']=dummy(),
    ['<AdjustTerrain>k__BackingField']={MainCharacterController=dummy()},
    ['<FallInfo>k__BackingField']=dummy(),
    ['<ActionManager>k__BackingField']={requestActionCore=function(_,priority,node)
        assert(machine.enabled,'Pose requested while FSM frozen')
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
assert(#actions==1 and actions[1].node=='SitOnChairActions' and machine.enabled)
runtime_clock=1.2;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(machine.enabled,'Initial pose froze early')
runtime_clock=1.31;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled,'Initial FSM freeze missing')
start_seated_animation(pawn,seat_bindings[1].seat_spec,'LivSitPose')
assert(machine.enabled and actions[#actions].node=='LivSitPose','Random pose did not thaw')
runtime_clock=1.62;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled,'Random pose failed to refreeze')
actions={};runtime_clock=2;sit_with_next_preset()
assert(actions[1].node=='Wait' and machine.enabled,'Preset Wait not thawed')
runtime_clock=2.2;pawn_seat_physics.step_pose_wait(seat_bindings[1]);pawn_seat_physics.update_fsm(seat_bindings[1])
assert(#actions==1 and machine.enabled,'Preset Wait ended early')
sit_with_next_preset();assert(#actions==1,'Repeated switch restarted pending Wait')
runtime_clock=2.31;pawn_seat_physics.step_pose_wait(seat_bindings[1])
assert(actions[2].node=='LivSitChairLean' and machine.enabled)
runtime_clock=2.5;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(machine.enabled,'New sitting pose froze early')
runtime_clock=2.62;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled,'New sitting pose did not freeze')
options.FREEZE_COMPANION_FSM=false;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(machine.enabled,'OFF did not restore FSM')
options.FREEZE_COMPANION_FSM=true;pawn_seat_physics.update_fsm(seat_bindings[1])
runtime_clock=3;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled)
detach_bound_characters();assert(#seat_bindings==0 and machine.enabled,'Detach failed to restore FSM')
-- Preserve an originally-disabled FSM, rather than always enabling on release.
machine.enabled=false;bind_pawns_to_seats();assert(machine.enabled)
runtime_clock=3.31;pawn_seat_physics.update_fsm(seat_bindings[1]);assert(not machine.enabled)
detach_bound_characters();assert(not machine.enabled,'Original disabled FSM state lost')
machine.enabled=true;bind_pawns_to_seats()
local binding=seat_bindings[1]
binding.seat_spec.useDirectMotion=true
function pawn:get_Motion() return {getLayer=function() return {call=function() assert(machine.enabled) end} end} end
start_seated_animation(pawn,binding.seat_spec);assert(machine.enabled)
runtime_clock=3.62;pawn_seat_physics.update_fsm(binding);assert(not machine.enabled,'Direct motion failed to freeze')
assert(ox.enabled==nil,'Companion FSM altered ox')
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
-- Player remains native and never enters the companion FSM path.
local player_actions=0
player={get_Valid=function() return true end,get_Transform=function() return transform end,
    ['<ActionManager>k__BackingField']={requestActionCore=function() player_actions=player_actions+1 end}}
start_seated_animation(player,{anim='Wait',freezeFsm=true})
assert(player_actions==1,'Legacy player handling changed')
print('PASS: FSM init/random/direct motion, Wait 0.3 + pose 0.3, OFF and exact restore, caught, retired action guard and native player')
