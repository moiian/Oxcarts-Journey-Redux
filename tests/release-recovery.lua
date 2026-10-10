;(function()
local bus=_G.DD2_OxcartControl
local function upvalue(fn,key)
    for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==key then return v end end
    error('Missing upvalue: '..key)
end
local physics=upvalue(bus.journey.manual_tick,'pawn_seat_physics')
local records=bus.journey.records()
local pending=function() return _G.OJR_PendingFsmRestores or {} end
local function binding(ch,previous)
    ch.machine.enabled=false
    local b={char=ch,fsm_machine=ch.machine,fsm_enabled=previous,fsm_freeze_frame=999}
    records[#records+1]=b
    return b
end
-- Both stacked pre-hooks fail open for nil owners and throwing getters.
local method='requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)'
local bad={get_GameObject=function() error('injected owner failure') end}
local args={nil,bad,10,{ToString=function() return 'Wait' end},0}
assert(pcall(hooks[method],args),'Idle action hook leaked owner exception')
state.native_drive={cart={ox=ox}}
assert(pcall(hooks[method],args),'Active driver hook leaked owner exception')
state.native_drive=nil
assert(pcall(hooks[method],{nil,nil,10,nil,0}),'Nil hook arguments escaped')
bad.get_GameObject=function() return nil end
assert(pcall(hooks[method],args),'Nil owner escaped')

-- One role's Transform failure and another's display failure cannot stop the group.
local first,second=pawns[1],pawns[2]
local first_get=first.get_Transform
first.get_Transform=function() error('injected Transform failure') end
local display_before=rawget(_G,'OJR_CompanionDisplay')
_G.OJR_CompanionDisplay={commit=function() error('injected display commit') end,
    release=function() error('injected display restore') end}
local a,b=binding(first,true),binding(second,true)
assert(pcall(bus.journey.release) and #records==0,'Group release interrupted')
assert(first.machine.enabled and second.machine.enabled,'Later group member stayed frozen')
first.get_Transform=first_get;_G.OJR_CompanionDisplay=display_before

-- Failed FSM restoration survives removal and retries at most once per second.
local machine=first.machine
local native_call=machine.call
local fail,calls=true,0
machine.call=function(self,m,v)
    if m=='set_Enabled(System.Boolean)' then calls=calls+1;if fail then error('injected FSM restore') end end
    return native_call(self,m,v)
end
local held=binding(first,true)
bus.journey.release()
assert(#records==0 and pending()[held] and held.fsm_machine==machine and held.fsm_enabled==true)
assert(not held.fsm_freeze_frame and not machine.enabled,'Failed removal was refrozen or lost its prior state')
local before=calls
physics.advance_frame();physics.advance_frame();assert(calls==before,'Recovery retried every frame')
clock=clock+1;physics.advance_frame();assert(calls==before+1 and pending()[held])
local new_binding={char=first}
assert(not pcall(physics.begin_pose,new_binding),'Unrestored frozen state was recaptured')
fail=false;clock=clock+1;physics.advance_frame()
assert(machine.enabled and not pending()[held] and held.fsm_machine==nil,'Transient failure did not recover')

-- Preserve an originally disabled FSM, rather than forcing enable=true.
fail=true;held=binding(first,false);bus.journey.release()
fail=false;clock=clock+1;physics.advance_frame()
assert(machine.enabled==false and not pending()[held],'Original disabled state not restored')

-- Persistent errors stop native retries after five attempts, but retain recovery state.
fail=true;held=binding(first,true);bus.journey.release()
for _=1,5 do clock=clock+1;physics.advance_frame() end
before=calls
for _=1,10 do clock=clock+1;physics.advance_frame() end
assert(calls==before and pending()[held] and held.fsm_machine==machine,'Exhausted recovery discarded state or kept spamming calls')
first.invalid=true;physics.advance_frame();first.invalid=false
assert(not pending()[held],'Permanently invalid actor retained')

-- A new journey module resumes retained records after hot reload.
held=binding(first,true);bus.journey.release()
for _=1,5 do clock=clock+1;physics.advance_frame() end
assert(pending()[held] and held.restore_attempts==5)
fail=false
-- A temporarily unreadable old binding must survive startup table replacement.
local second_old={char=second,fsm_machine=second.machine,fsm_enabled=true}
records[#records+1]=second_old;second.machine.enabled=false
local second_valid=second.get_Valid
second.get_Valid=function() error('injected reload validity failure') end
assert(loadfile('reframework/autorun/Oxcarts Journey Redux/journey.lua'))()
assert(pending()[second_old],'Unreadable old binding lost during reload')
second.get_Valid=second_valid
physics=upvalue(bus.journey.manual_tick,'pawn_seat_physics')
physics.advance_frame()
assert(machine.enabled and second.machine.enabled and not pending()[held] and not pending()[second_old],'Hot reload lost retained recovery')
machine.call=native_call
print('PASS: stale/nil global action args, isolated group cleanup, retained FSM state, throttled recovery, original false, invalid cleanup and reload recovery')
end)()
