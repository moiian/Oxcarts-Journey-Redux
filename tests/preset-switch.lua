local actions, pending_ai_lock, seat_bindings = {}, {}, {}
local player, seating_lock_active, runtime_clock = {}, false, 1
local cart_trip, preset_cursor = {pause={}}, {Normal=1}
local last_sit_preset, last_sit_request_at = {}, nil
local ox, anchor = {}, {}
local function spec(node) return {anim=node,freezeFsm=true,randomIdle=false} end
local options={Presets={Normal={
    {enabled=true,pawns={spec('SitOnChairActions'),spec('SitOnChairActions'),spec('SitOnChairActions')}},
    {enabled=true,pawns={spec('LivSitChairLean'),spec('LivSitChairLean'),spec('LivSitChairLean')}}}}}
local function dummy() return {call=function() end} end
local transform={get_UniversalPosition=function() return {} end,set_Parent=function() end}
local pawn={get_Valid=function() return true end,get_Transform=function() return transform end,
    ['<PosRotContext>k__BackingField']=dummy(),
    ['<AdjustTerrain>k__BackingField']={MainCharacterController=dummy()},
    ['<FallInfo>k__BackingField']=dummy(),
    ['<ActionManager>k__BackingField']={requestActionCore=function(_,priority,node)
        actions[#actions+1]={priority=priority,node=node}
    end}}
local function is_character_valid(ch) return ch==pawn end
local function set_fsm_enabled(ch,enabled) ch.enabled=enabled;return true end
local function collect_party_pawns() return {pawn}, {[pawn]=true} end
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

sit_with_next_preset()
assert(#actions==1 and actions[1].node=='SitOnChairActions','First preset pose missing')
assert(#seat_bindings==1 and #pending_ai_lock==0 and pawn.enabled==true,'Pawn FSM should remain enabled')
assert(pawn_seat_physics.blocks_pose_action(pawn,'Run',0),'Competing action not blocked')
assert(not pawn_seat_physics.blocks_pose_action(pawn,'SitOnChairActions',0),'Expected pose blocked')
assert(not pawn_seat_physics.blocks_pose_action(player,'Run',0),'Player action blocked')
assert(not pawn_seat_physics.blocks_pose_action(pawn,'Run',1),'Upper layer blocked')
assert(not pawn_seat_physics.blocks_pose_action({},'Run',0),'Unbound NPC action blocked')
external=true;assert(not pawn_seat_physics.blocks_pose_action(pawn,'Run',0));external=false
paused=true;assert(not pawn_seat_physics.blocks_pose_action(pawn,'Run',0));paused=false
start_seated_animation(pawn,seat_bindings[1].seat_spec,'LivSitPose')
assert(seat_bindings[1].pose_node=='LivSitPose','Random pose did not update lock')
assert(pawn_seat_physics.blocks_pose_action(pawn,'SitOnChairActions',0),'Old pose still allowed after random pose')
actions={}
runtime_clock=2;sit_with_next_preset()
assert(#actions==1 and actions[1].node=='Wait' and pawn.enabled==true,'Switch did not request Wait with FSM enabled')
assert(#pending_ai_lock==0 and seat_bindings[1].pose_node=='Wait')
assert(pawn_seat_physics.blocks_pose_action(pawn,'Run',0),'Wait phase can be interrupted')
runtime_clock=2.2;pawn_seat_physics.step_pose_wait(seat_bindings[1])
assert(#actions==1,'Wait ended too early')
sit_with_next_preset();assert(#actions==1,'Repeated switch restarted timer')
runtime_clock=2.31;pawn_seat_physics.step_pose_wait(seat_bindings[1])
assert(#actions==2 and actions[2].node=='LivSitChairLean' and pawn.enabled==true)
assert(seat_bindings[1].pose_wait_until==nil and #pending_ai_lock==0)
runtime_clock=3;sit_with_next_preset();assert(actions[3].node=='Wait')
detach_bound_characters()
assert(#seat_bindings==0 and pawn.enabled==true and #pending_ai_lock==0)
assert(not pawn_seat_physics.blocks_pose_action(pawn,'Run',0),'Released pawn still locked')
runtime_clock=4;sit_with_next_preset()
assert(actions[4].node=='LivSitChairLean','Fresh seating should not inherit cancelled Wait')
local original=pawn['<ActionManager>k__BackingField'].requestActionCore
pawn['<ActionManager>k__BackingField'].requestActionCore=function()
    assert(not pawn_seat_physics.blocks_pose_action(pawn,'OwnPose',0),'Own pose blocked')
    error('request failed')
end
assert(not pcall(pawn_seat_physics.request_pose_action,pawn,'OwnPose',1))
assert(not pawn_seat_physics.issuing[pawn],'Failed request left bypass enabled')
pawn['<ActionManager>k__BackingField'].requestActionCore=original
seat_bindings[1].seat_spec.useDirectMotion=true
function pawn:get_Motion() return {getLayer=function() return {call=function() end} end} end
start_seated_animation(pawn,seat_bindings[1].seat_spec)
assert(seat_bindings[1].pose_node==nil and pawn.enabled==true,'Direct motion restored old action lock or froze FSM')
assert(pawn_seat_physics.blocks_pose_action(pawn,'Run',0),'Direct motion can be interrupted by action request')
assert(ox.enabled==nil,'Preset switch mutated ox control')
print('PASS: FSM-enabled pose guard, random pose, Wait 0.3s switching, repeated input, cancellation, direct motion and bypass cleanup')

local cart_action_filters={}
function pawn:get_CharaIDString() return 'pawn' end
local action_hook
local sdk={PreHookResult={SKIP_ORIGINAL='skip'},
    to_managed_object=function(value) return value end,to_int64=function(value) return value end,
    typeof=function(value) return value end,
    find_type_definition=function() return {get_method=function() return {} end} end,
    hook=function(_,callback) action_hook=callback end}
-- ACTION HOOK --
local function invoke(ch,node,layer)
    local owner={get_Valid=function() return true end,call=function() return ch end}
    local manager={get_GameObject=function() return owner end}
    return action_hook({nil,manager,0,{ToString=function() return node end},layer or 0})
end
assert(invoke(pawn,'Run',0)=='skip','Actual hook allowed competing action')
assert(invoke(pawn,'Run',1)==nil,'Actual hook blocked upper layer')
pawn_seat_physics.issuing[pawn]=true
assert(invoke(pawn,'NewPose',0)==nil,'Actual hook blocked mod pose request')
pawn_seat_physics.issuing[pawn]=nil
assert(invoke(pawn,'Caught',0)==nil and #seat_bindings==0 and pawn.enabled==true,
    'Caught should release binding before action guard and preserve native handling')
assert(invoke(pawn,'Run',0)==nil,'Actual hook kept released pawn locked')
print('PASS: actual ActionManager hook, internal request bypass, upper-layer pass-through and caught release')
