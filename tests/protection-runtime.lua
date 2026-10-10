;(function()
local bus=_G.DD2_OxcartControl
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
passenger_controller.PartsList={get_Count=function() return 1 end,get_Item=function(_,i) assert(i==0);return part end}
local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
human.pos=vec(0,0,0);ox.pos=vec(0,0,0);body.pos=vec(0,0,0)
bus.journey.begin_manual(cart)
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
print('PASS: real GameObject/Character separation, native controller scope, actual PartsList breakup, range exit/reentry and reset')
end)()
