;(function()
local bus=_G.DD2_OxcartControl
local speed=_G.OJR_UnifiedSpeed
local original_status=status.call
local absent,stale_player=false,false
status.call=function(self,method,...)
    if method=='getCurrentDriver' and absent then return 0 end
    if method=='getCurrentDriver' and stale_player then return human.id end
    return original_status(self,method,...)
end
local original_character=nm.getCharacter
nm.getCharacter=function(self,id) if id==human.id then return human end;return original_character(self,id) end
function driver:get_IsDead() return self.dead==true end
local function request(node,layer,who)
    (who or ox).am:requestActionCore(10,node,layer or 0)
end
local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
driver.pos=body.pos
-- A registered nearby NPC must actually occupy the fully entered driving seat.
for _,case in ipairs({{occupant=false,seated=true},{occupant=driver,seated=false},{occupant=pawns[1],seated=true}}) do
    npc_driver_seat.SitChara=case.occupant or nil;npc_driver_seat.seated=case.seated
    assert(bus.journey.enforce_driver_wait(ox),'Nearby unseated/wrong occupant allowed movement')
    passenger_controller.seated=true
    for _,delta in ipairs({-1,1}) do
        speed.clear();ox.am.CurrentActionList[0].Name='Walk'
        local before=bus.journey.diagnostic_state()
        bus.journey.speed_step(delta)
        local after=bus.journey.diagnostic_state()
        assert(not speed.command and ox.am.CurrentActionList[0].Name=='Walk','Unseated driver speed input accepted')
        assert(before.manual_speed==after.manual_speed and before.manual_resume_at==after.manual_resume_at,'Rejected input changed auto state')
    end
    passenger_controller.seated=false
end
npc_driver_seat.SitChara=driver;npc_driver_seat.seated=true
stale_player=true
assert(bus.journey.enforce_driver_wait(ox),'Stale player driver ID allowed abandoned cart movement')
stale_player=false
for _,node in ipairs({'Walk','Run','Dash'}) do
    ox.am.CurrentActionList[0].Name='Wait';request(node)
    assert(ox.am.CurrentActionList[0].Name==node,'NPC-driven cart blocked: '..node)
end
absent=true
for _,node in ipairs({'Walk','Run','Dash'}) do
    ox.am.CurrentActionList[0].Name=node
    speed.hold(ox,node,360,clock)
    assert(bus.journey.enforce_driver_wait(ox))
    assert(ox.am.CurrentActionList[0].Name=='Wait' and not speed.command,'Driverless moving cart not stopped')
    request(node)
    assert(ox.am.CurrentActionList[0].Name=='Wait','Driverless movement request passed: '..node)
end
local other=object('other ox')
request('Dash',0,other);assert(other.am.CurrentActionList[0].Name=='Dash','Unrelated ox affected')
ox.am.CurrentActionList[0].Name='HighFall'
bus.journey.enforce_driver_wait(ox)
assert(ox.am.CurrentActionList[0].Name=='HighFall','Special native action overwritten')
is_paused=true;ox.am.CurrentActionList[0].Name='Run'
assert(not bus.journey.enforce_driver_wait(ox) and ox.am.CurrentActionList[0].Name=='Run','Paused state mutated')
is_paused=false
bus.journey.begin_manual(cart)
assert(not bus.journey.enforce_driver_wait(ox),'Player driving mistaken for no driver')
for _,node in ipairs({'Walk','Run','Dash'}) do
    request(node);assert(ox.am.CurrentActionList[0].Name==node,'Player driving blocked: '..node)
end
bus.journey.end_manual()
assert(bus.journey.enforce_driver_wait(ox) and ox.am.CurrentActionList[0].Name=='Wait','Driver exit failed to stop abandoned cart')
absent=false;driver.pos=vec(body.pos.x,body.pos.y,body.pos.z-500)
assert(bus.journey.enforce_driver_wait(ox),'Expelled NPC mistaken for available driver')
driver.pos=body.pos;driver.dead=true
assert(bus.journey.enforce_driver_wait(ox),'Dead driver allowed movement')
driver.dead=false
assert(not bus.journey.enforce_driver_wait(ox),'Returning NPC driver not recognized')
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: driverless Walk/Run/Dash -> Wait; NPC/player drivers allowed, remote/dead driver, special actions, pause, other cart and exit')
end)()
