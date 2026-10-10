;(function()
local bus,speed=_G.DD2_OxcartControl,_G.OJR_UnifiedSpeed
local function upvalue(fn,key)
    for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==key then return v end end
end
upvalue(bus.journey.passenger_camera,'options').PLAYER_NEAR_CART_NONCOMBAT=false
function status:get_type_definition()
    return {get_method=function() return {get_num_params=function() return 0 end,
        get_return_type=function() return {get_name=function() return 'Boolean' end} end} end}
end
function passenger_controller:isPlayerSit() return self.seated end
function passenger_controller:get_GameObject() return body end
function ox:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
local old=status.call
local near=false
status.call=function(self,m,...)
    if m=='getFinalStopIndexPosition()' then local p=ox:get_UniversalPosition();return vec(p.x+(near and 1 or 1000),p.y,p.z) end
    return old(self,m,...)
end
local function tick(dt) clock=clock+(dt or 0.1);callbacks.LateUpdateBehavior() end
passenger_controller.seated=true;ox.am.CurrentActionList[0].Name='Walk';tick()
for _,target in ipairs({'Run','Dash'}) do
    bus.journey.speed_step(1);tick()
    assert(speed.command and speed.command.node==target)
    local expiry=speed.command.until_time
    for _=1,10 do
        ox.am:requestActionCore(10,'TurnTarget',0)
        ox.am:requestActionCore(10,'Walk',0)
        assert(ox.am.CurrentActionList[0].Name==target,'Turn request entered a deceleration frame')
        tick(0.01)
    end
    assert(speed.command.until_time==expiry,'Turn hold renewed deadline')
    -- Model a native transition not routed through requestActionCore.
    ox.am.CurrentActionList[0].Name='TurnTarget';tick(0.1)
    assert(ox.am.CurrentActionList[0].Name==target and speed.command.until_time==expiry,'Already-entered turn not recovered')
end
ox.am.CurrentActionList[0].Name='TurnTarget'
npc_driver_seat.seated=false;tick()
assert(not speed.command,'Lost driver retained turn recovery')
npc_driver_seat.seated=true
ox.am.CurrentActionList[0].Name='Run';tick();bus.journey.speed_step(1)
ox.am.CurrentActionList[0].Name='TurnTarget';near=true;tick(0.2)
assert(not speed.command and ox.am.CurrentActionList[0].Name~='Dash','Destination brake overridden by turn repair')
near=false;ox.am.CurrentActionList[0].Name='Run';tick();bus.journey.speed_step(1)
is_paused=true
ox.am:requestActionCore(10,'TurnTarget',0);tick(0.2)
assert(ox.am.CurrentActionList[0].Name=='TurnTarget','Paused native action overwritten')
is_paused=false;tick(1.2);tick(1.2)
-- Driver mode uses the same guard, including already-entered native turns.
local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
bus.journey.begin_manual(cart)
state.native_drive={cart=cart};ox.am.CurrentActionList[0].Name='Dash'
speed.hold(ox,'Dash',1,clock)
ox.am:requestActionCore(10,'TurnTarget',0)
assert(ox.am.CurrentActionList[0].Name=='Dash','Driver mode accepted TurnTarget')
ox.am:requestActionCore(10,'DamageHeavy',0)
assert(ox.am.CurrentActionList[0].Name=='DamageHeavy' and not speed.command,'Driver guard blocked damage')
state.native_drive=nil;bus.journey.end_manual()
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: Run/Dash reject turn/deceleration requests, repair native bypass, unchanged expiry, pause, driver loss, arrival and driver-mode damage')
end)()
