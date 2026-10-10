;(function()
local bus=_G.DD2_OxcartControl
local function upvalue(fn,key)
    for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==key then return v end end
    error('Missing upvalue '..key)
end
local options=upvalue(bus.journey.passenger_camera,'options')
options.PLAYER_NEAR_CART_NONCOMBAT=false
function status:get_type_definition()
    return {get_method=function() return {get_num_params=function() return 0 end,
        get_return_type=function() return {get_name=function() return 'Boolean' end} end} end}
end
function passenger_controller:isPlayerSit() return self.seated end
function passenger_controller:get_GameObject() return body end
function human:get_Motion()
    return {getLayer=function() return {get_MotionBankID=function() return 0 end,
        get_MotionID=function() return passenger_controller.seated and 2010 or 0 end} end}
end
local function tick(dt) clock=clock+(dt or 0.1);callbacks.LateUpdateBehavior() end
local function count() local n=0;for _,b in ipairs(bus.journey.records()) do if b.char~=human then n=n+1 end end;return n end
local function exit() passenger_controller.seated=false;tick() end
for _,node in ipairs({'Wait','Walk'}) do
    exit();bus.journey.release();ox.am.CurrentActionList[0].Name=node
    local before=bus.journey.passenger_layout()
    passenger_controller.seated=true;tick()
    assert(count()==3,'Passenger entry failed to seat companions during '..node)
    local after=bus.journey.passenger_layout()
    assert(before[1].x==after[1].x and before[1].z==after[1].z,'Automatic entry cycled preset')
    tick();local fall=pawns[1].test_fall.reset_calls
    tick();assert(pawns[1].test_fall.reset_calls==fall,'Automatic entry repeatedly restarted pose')
    bus.journey.release();tick();assert(count()==0,'Explicit stand retriggered automatic seating without reentry')
end
for _,node in ipairs({'Run','Dash'}) do
    exit();bus.journey.release();ox.am.CurrentActionList[0].Name=node
    passenger_controller.seated=true;tick();assert(count()==0,'Fast-speed entry auto-seated companions')
end
exit();bus.journey.release();ox.am.CurrentActionList[0].Name='Wait'
bus.journey.sit();tick();local fall=pawns[1].test_fall.reset_calls
passenger_controller.seated=true;tick()
assert(count()==3 and pawns[1].test_fall.reset_calls==fall,'Already seated companions restarted on passenger entry')
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: Wait/Walk passenger entry seats once without cycling; Run/Dash, existing seats and explicit stand remain untouched')
end)()
