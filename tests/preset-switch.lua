local actions, pending_ai_lock, seat_bindings = {}, {}, {}
local player, seating_lock_active, runtime_clock = {}, false, 1
local cart_trip, preset_cursor = {}, {Normal=1}
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
local function external_driver_active() return false end
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
assert(#seat_bindings==1 and #pending_ai_lock==1,'First preset binding/lock missing')
runtime_clock=2;sit_with_next_preset()
assert(#actions==2 and actions[2].node=='LivSitChairLean',
    'Preset switch must directly request the new pose, without generic Wait')
assert(#seat_bindings==1 and #pending_ai_lock==1,'Switch retained old binding/queued lock')
runtime_clock=3;sit_with_next_preset()
assert(#actions==3 and actions[3].node=='SitOnChairActions','Repeated preset cycling failed')
assert(actions[1].priority==1 and actions[2].priority==1 and actions[3].priority==1)
assert(ox.enabled==nil,'Preset switch mutated ox control')
print('PASS: first/second/repeated presets request sitting poses without Wait or ox control changes')
