;(function()
local bus=_G.DD2_OxcartControl
-- Normal release play does not emit protection success/damage diagnostics.
_G.OJR_EnableRuntimeDiagnostics=nil
local previous_info,previous_warn=log.info,log.warn
local noisy_messages={}
log.info=function(message) noisy_messages[#noisy_messages+1]=message end
log.warn=function(message) noisy_messages[#noisy_messages+1]=message end
function ox:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
local function hit(initial)
    local c=object('HitController');c.value=initial
    function c:call(method,value)
        if method=='get_IsInvincible()' then return self.value end
        assert(method=='set_IsInvincible(System.Boolean)',method);self.value=value
    end
    return c
end
local function gameobject(name,tr)
    local g=object(name);g.get_GameObject=nil
    g.hit=hit(false)
    function g:get_Transform() return tr or self end
    function g:call(method,kind)
        assert(method=='getComponent(System.Type)' and kind=='app.HitController')
        return self.hit
    end
    return g
end
local ox_go,cow_go,body_go=gameobject('ch299003',ox),gameobject('cow',cow),gameobject('gm80_042',body)
ox.go,cow.go,body.go=ox_go,cow_go,body_go
local part_go=gameobject('sm80_042_parts',body)
local part=object('part');part.go=part_go
function passenger_controller:get_GameObject() return body_go end
function passenger_controller:get_Valid() return true end
passenger_controller.PartsList={get_Count=function() return 1 end,get_Item=function(_,i) assert(i==0);return part end}
local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
human.pos=vec(0,0,0);ox.pos=vec(0,0,0);body.pos=vec(0,0,0)
bus.journey.begin_manual(cart)
local destroy_hook=assert(hooks['requestDestroy(app.GenerateInfo.GenerateInfoContainer, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean)'])
local old_gui_call,old_manager_call=gui.call,nm.OxcartManager.call
local loading,travel=false,0
gui.call=function(self,method,...)
    if method=='get_IsLoadGui()' then return loading end
    return old_gui_call(self,method,...)
end
nm.OxcartManager.call=function(_,method) assert(method=='getFastTravelState()');return travel end
local ox_container=object('ox container');ox_container._CommonInfo={_ObjectID={_SelectedCharacterID=ox.id}}
local driver_container=object('driver container');driver_container._CommonInfo={_ObjectID={_SelectedCharacterID=driver.id}}
local unrelated_container=object('other cart');unrelated_container._CommonInfo={_ObjectID={_SelectedCharacterID=-9}}
status['<CachedGenerateContainer>k__BackingField']=ox_container
passenger_controller.seated=true
assert(destroy_hook({nil,nil,ox_container})=='skip','Passenger cart destruction not blocked')
assert(destroy_hook({nil,nil,driver_container})=='skip','Actual seated driver destruction not blocked')
assert(destroy_hook({nil,nil,unrelated_container})~='skip','Other cart destruction blocked')
loading=true;assert(destroy_hook({nil,nil,ox_container})~='skip');loading=false
travel=2;assert(destroy_hook({nil,nil,ox_container})~='skip');travel=0
passenger_controller.seated=false
assert(destroy_hook({nil,nil,ox_container})~='skip','Standing trip flag protected cart')
npc_driver_seat.SitChara=human
assert(destroy_hook({nil,nil,ox_container})=='skip','Native player driver not protected')
assert(destroy_hook({nil,nil,driver_container})~='skip','Expelled NPC driver protected')
npc_driver_seat.SitChara=driver
gui.call,nm.OxcartManager.call=old_gui_call,old_manager_call
_G.OJR_EnableRuntimeDiagnostics=nil
callbacks.UpdateBehavior()
assert(ox_go.hit.value and cow_go.hit.value and body_go.hit.value and part_go.hit.value,'Actual target controllers not protected')
local part_hook=hooks['app.Sm80_042_Parts.executeBreak(System.Boolean)']
assert(part_hook({nil,part})=='skip','Current attached frame not protected')
assert(part_hook({nil,object('other part')})~='skip','Unrelated frame protected')
local damage_hook=hooks['damageProc(app.HitController.DamageInfo)']
for _,g in ipairs({ox_go,cow_go,body_go,part_go}) do
    assert(damage_hook({nil,{}, {['<DamageGameObject>k__BackingField']=g}})=='skip','Strict GameObject recognition failed')
end
human.pos=vec(50,0,0)
assert(part_hook({nil,part})~='skip','Part protection exceeded 50-unit boundary')
callbacks.UpdateBehavior()
assert(not ox_go.hit.value and not body_go.hit.value and not part_go.hit.value,'Range exit did not restore native flags')
human.pos=vec(0,0,0);callbacks.UpdateBehavior()
assert(ox_go.hit.value,'Reentry did not reenable protection')
callbacks.reset()
assert(not ox_go.hit.value and not cow_go.hit.value and not body_go.hit.value and not part_go.hit.value,'Script reset leaked invincibility')
assert(#errors==0,table.concat(errors,'\n'))
assert(#noisy_messages==0,'Normal protection emitted test diagnostics: '..table.concat(noisy_messages,'\n'))
local previous_dump=json.dump_file
local native_logs=0
json.dump_file=function(path)
    if path:find('AelinoreNativeSeat_',1,true) then native_logs=native_logs+1 end
end
driver_runtime.native_seat_command('scan');driver_runtime.native_seat_tick()
assert(native_logs==0,'Native driver status wrote diagnostics during normal play')
json.dump_file=previous_dump
log.info,log.warn=previous_info,previous_warn
print('PASS: real GameObject/Character separation, native controller scope, actual PartsList breakup, range exit/reentry and reset')
end)()
