local runtime_clock,seating_lock_active=1,false
local seat_bindings,frame_jobs={},{}
local cart_trip,preset_cursor={pause={}}, {Normal=1}
local last_sit_preset,last_sit_request_at={},nil
local function actor(id)
    local ch={id=id,actions={},following=true,syncs=0}
    function ch:get_Valid() return not self.invalid end
    function ch:get_address() return self.id end
    local transform={get_UniversalPosition=function() return {} end,
        set_Parent=function() ch.detached=true end}
    function ch:get_Transform() return transform end
    local context={call=function() ch.syncs=ch.syncs+1 end}
    ch['<PosRotContext>k__BackingField']=context
    ch['<AdjustTerrain>k__BackingField']={MainCharacterController={call=function() end}}
    ch['<FallInfo>k__BackingField']={call=function() end}
    ch['<ActionManager>k__BackingField']={requestActionCore=function(_,_,node) ch.actions[#ch.actions+1]=node end}
    return ch
end
local player=actor(100)
local pawns={actor(1),actor(2),actor(3)}
local wrappers={}
for i,ch in ipairs(pawns) do wrappers[i]={get_CachedCharacter=function() return ch end,slot=i-1} end
local pm={get_MainPawn=function() return wrappers[1] end,
    get_PartyPawnList=function() return {get_Count=function() return #wrappers end,get_Item=function(_,i) return wrappers[i+1] end} end,
    getPartyPawnID=function(_,p) return p.slot end}
local npcs,holders={},{}
for i=1,10 do npcs[i]=actor(10+i);holders[i]={CharaID=i} end
npcs[10].following=false
holders[11]={CharaID=1}
local nm={NPCHolderDic=holders,getCharacter=function(_,id) return npcs[id] end}
local manager_missing,query_fail=false,false
local sdk={get_managed_singleton=function(name)
    if name=='app.PawnManager' then return not manager_missing and pm or nil end
    if name=='app.NPCManager' then return nm end
    if name=='app.InteractManager' then return {call=function(_,method,ch)
        assert(method=='isInteracting(app.Character)');return ch.interacting==true end} end
end,find_type_definition=function(name)
    assert(name=='app.NPCUtil')
    return {get_method=function(_,signature)
        assert(signature=='isAccompanyPLParty(app.Character)')
        return {call=function(_,receiver,ch) assert(receiver==nil);if query_fail then error('Query unavailable') end;return ch.following end}
    end}
end}
local function is_character_valid(ch) return ch and ch:get_Valid() end
local external=false
local function external_driver_active() return external end
local function gameplay_is_paused() return false end
local ox,anchor={},{}
local function find_active_ox() return ox end
local function find_cart_body() return anchor end
local function resolve_seat_anchor() return anchor end
local function classify_cart_model() return 'Normal' end
local function player_is_physically_seated() return true end
local function player_uses_cart_seat_node() return true end
local re={on_script_reset=function() end}
local log={error=function(err) error(err) end}
local options={Presets={Normal={{enabled=true,pawns={}}}}}
for i=1,9 do options.Presets.Normal[1].pawns[i]={x=i,y=0.85,z=0,anim='SitOnChairActions',randomIdle=true} end

-- COLLECTOR --
-- IMPLEMENTATION --
-- RELEASE VARIANTS --
-- INTERMEDIATE RELEASE --

local members,roster,guests=collect_companions()
assert(#members==12 and members[1]==pawns[1] and members[4]==npcs[1] and not roster[npcs[10]],'Mixed roster/order/dedup/filter incorrect')
assert(guests[npcs[1]] and not guests[pawns[1]])
bind_pawns_to_seats()
assert(#seat_bindings==9,'Nine companion capacity incorrect')
for i,b in ipairs(seat_bindings) do assert(b.slot==i and b.char==members[i] and b.seat_spec==options.Presets.Normal[1].pawns[i]) end
assert(pawn_seat_physics.blocks_pose_action(npcs[1],'Run',0),'Guest lacks pose lock')
local stable={}
for _,b in ipairs(seat_bindings) do stable[b.char]=b.slot end
local count=#npcs[1].actions
bind_pawns_to_seats(false,true)
assert(#npcs[1].actions==count,'Roster refresh restarted existing pose')
npcs[1].following=false;runtime_clock=3
pawn_seat_physics.prune_party()
assert(#seat_bindings==8 and npcs[1].actions[#npcs[1].actions]=='Wait','Departing guest not released')
bind_pawns_to_seats(false,true)
assert(#seat_bindings==9,'New guest failed to fill vacancy')
for _,b in ipairs(seat_bindings) do if stable[b.char] then assert(b.slot==stable[b.char],'Existing companion changed slot') end end
assert(seat_bindings[9].char==npcs[7] and seat_bindings[9].slot==4,'Vacant slot not reused')
query_fail=true;runtime_clock=5;pawn_seat_physics.prune_party();assert(#seat_bindings==9,'Query failure released valid guests')
query_fail=false;nm.NPCHolderDic=nil;runtime_clock=7;pawn_seat_physics.prune_party();assert(#seat_bindings==9,'Roster failure released valid guests')
nm.NPCHolderDic=holders
manager_missing=true;runtime_clock=9;pawn_seat_physics.prune_party();assert(#seat_bindings==9,'Unavailable PawnManager treated as empty party')
manager_missing=false
npcs[2].interacting=true
assert(not pawn_seat_physics.blocks_pose_action(npcs[2],'QuestInteract',0),'Guest native interaction blocked by pose guard')
local old_syncs,old_actions=npcs[2].syncs,#npcs[2].actions
pawn_seat_physics.prune_party()
assert(#seat_bindings==8 and npcs[2].syncs==old_syncs and #npcs[2].actions==old_actions and not npcs[2].detached,
    'Guest native interaction was overwritten during release')
runtime_clock=11;bind_pawns_to_seats(false,true)
for _,b in ipairs(seat_bindings) do assert(b.char~=npcs[2],'Interacting NPC was rebound') end
local removed=seat_bindings[1].char
pawn_seat_physics.remove(1)
runtime_clock=12;bind_pawns_to_seats(false,true)
for _,b in ipairs(seat_bindings) do assert(b.char~=removed,'Caught/failed companion automatically recaptured') end
-- Preset switching retains slots, waits only on followers, and never touches ox.
npcs[2].interacting=false
runtime_clock=13;bind_pawns_to_seats(true)
for _,b in ipairs(seat_bindings) do if stable[b.char] then assert(b.slot==stable[b.char]) end end
assert(ox.actions==nil and ox.enabled==nil,'Companion operation modified ox driving')
release_pawns_at_intermediate_stop('test')
assert(not pawn_seat_physics.follow_roster,'Stop release did not disable roster reseating')
runtime_clock=15;bind_pawns_to_seats(false,true);assert(#seat_bindings==0,'Stopped passengers immediately reseated')
bind_pawns_to_seats()
release_passengers_from_modifier()
assert(#seat_bindings==0 and not seating_lock_active)
runtime_clock=17;bind_pawns_to_seats(false,true);assert(#seat_bindings==0,'Manual stand automatically reseated companions')
bind_pawns_to_seats();release_passengers_from_skill();assert(#seat_bindings==0)
external=true;assert(not bind_pawns_to_seats(),'OJR ignored external LMD ownership')
print('PASS: nine mixed companion seats, guest membership/interaction release, errors, stable vacancy fill, manual/stop release, preset wait and external ownership')
