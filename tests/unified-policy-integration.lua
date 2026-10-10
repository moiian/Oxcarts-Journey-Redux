;(function()
local bus=_G.DD2_OxcartControl
local speed=_G.OJR_UnifiedSpeed
function ox:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
function passenger_controller:get_GameObject() return body end
local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
bus.journey.begin_manual(cart)
local function damage(receiver,value)
    local info={['<DamageGameObject>k__BackingField']=receiver,Damage=value}
    for _,method in ipairs({'damageProc(app.HitController.DamageInfo)',
        'updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)'}) do
        local result=hooks[method]({nil,{},info})
        assert((result=='skip')==(receiver==ox or receiver==body or receiver==cow),'Wrong damage rule: '..receiver.name)
        assert(info.Damage==value,'Damage policy unexpectedly rewrote a multiplier')
    end
end
for _,value in ipairs({0,10,5000}) do
    damage(ox,value);damage(body,value);damage(cow,value);damage(driver,value)
end
local unrelated=object('gm80_042_00');damage(unrelated,5000)
assert(hooks['calcDamageValue(app.HitController.DamageInfo)']==nil,'Multiplier hook retained')
human.pos=vec(21,0,0)
assert(hooks['damageProc(app.HitController.DamageInfo)']({nil,{},
    {['<DamageGameObject>k__BackingField']=body,Damage=5000}})~='skip','Range no longer applies')
human.pos=vec(0,0,0)
state.native_drive={cart=cart}
local hud_element={call=function() return body end}
local hud_go=object('ui010201')
hud_element.call=function() return hud_go end
assert(callbacks.gui_draw(hud_element)==false,'Driver HUD not hidden')
speed.hold(ox,'Dash',10,clock)
ox.am.CurrentActionList[0].Name='Dash'
ox.am:requestActionCore(10,'Walk',0)
assert(ox.am.CurrentActionList[0].Name=='Dash','Manual speed hook failed to block native overwrite')
speed.issue(function() ox.am:requestActionCore(0,'Wait',0) end)
assert(ox.am.CurrentActionList[0].Name=='Wait','Manual braking blocked by speed hook')
ox.am:requestActionCore(10,'Jump',0)
assert(ox.am.CurrentActionList[0].Name=='Jump' and not speed.command,'Manual mode blocked a special action')
state.native_drive=nil
assert(callbacks.gui_draw(hud_element)==true,'Driver HUD not restored')
speed.hold(ox,'Dash',10,0)
ox.am:requestActionCore(10,'Walk',0)
assert(ox.am.CurrentActionList[0].Name=='Walk','Passenger hook affected manual mode')
bus.journey.end_manual()
speed.hold(ox,'Dash',10,0)
ox.am.CurrentActionList[0].Name='Dash'
ox.am:requestActionCore(10,'Walk',0)
assert(ox.am.CurrentActionList[0].Name=='Dash','Passenger speed hook failed to block native overwrite')
ox.am:requestActionCore(10,'DamageHeavy',0)
assert(ox.am.CurrentActionList[0].Name=='DamageHeavy' and not speed.command,'Special action blocked by integration')
speed.issue(function() ox.am:requestActionCore(0,'Wait',0) end)
damage(ox,10);damage(body,10);damage(driver,10)
assert(#errors==0,table.concat(errors,'\n'))
callbacks.reset()
assert(not speed.command,'Script reset leaked speed command')
print('PASS: stacked hooks, both-mode immunity, exact range, no multiplier hook, native special actions and driver HUD restore')
end)()
