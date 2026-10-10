local base='reframework/autorun/Oxcarts Journey Redux/'
local speed=assert(loadfile(base..'speed.lua'))()
local hud=assert(loadfile(base..'hud.lua'))()
local protection=assert(loadfile(base..'protection.lua'))()
local function vec(x,y,z)
    return setmetatable({x=x,y=y,z=z},{__sub=function(a,b) return vec(a.x-b.x,a.y-b.y,a.z-b.z) end,
        __index={length=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}})
end
local count=0
local function actor(name,x)
    count=count+1
    local a={id=count,name=name,pos=vec(x or 0,0,0)}
    function a:get_address() return self.id end
    function a:get_Valid() return not self.invalid end
    function a:get_Name() return self.name end
    function a:get_GameObject() return self end
    function a:get_Transform() return self end
    function a:get_Position() return self.pos end
    function a:get_IsDamage() return self.damaged or false end
    function a:get_IsDead() return self.dead or false end
    a['<ActionManager>k__BackingField']={CurrentActionList={[0]={Name='Wait'}}}
    return a
end
local ox,other=actor('ox'),actor('ox')
speed.hold(ox,'Dash',10,100)
assert(speed.blocks(ox,'Walk',0,101,false),'Competing speed was not blocked')
assert(not speed.blocks(other,'Walk',0,101,false),'Other ox affected')
assert(not speed.blocks(ox,'Walk',1,101,false),'Upper layer affected')
assert(not speed.blocks(ox,'Walk',0,101,true),'Pause blocked native transitions')
speed.issue(function() assert(not speed.blocks(ox,'Wait',0,101,false),'Own brake blocked') end)
assert(not speed.blocks(ox,'DamageHeavy',0,101,false) and not speed.command,'Special action blocked or lease retained')
for _,node in ipairs({'Die','Jump','QuestAction','UnknownAction'}) do
    speed.hold(ox,'Dash',10,100)
    assert(not speed.blocks(ox,node,0,101,false) and not speed.command,node)
end
speed.hold(ox,'Dash',10,100)
assert(not speed.blocks(ox,'Walk',0,110,false),'Expiry boundary')
speed.hold(ox,'Dash',10,100);speed.expire(other,101);assert(not speed.command,'Cart change retained command')
local ok=pcall(function() speed.issue(function() error('injected') end) end)
assert(not ok and speed.issuing==0,'Failed request leaked own-command bypass')
assert(speed.can_command(ox))
ox.damaged=true;assert(not speed.can_command(ox));ox.damaged=false
ox.dead=true;assert(not speed.can_command(ox));ox.dead=false
ox['<ActionManager>k__BackingField'].CurrentActionList[0].Name='HighFall'
assert(not speed.can_command(ox),'Special action would be overwritten by frame repair')
print('PASS: speed ownership, pause, upper layers, own commands, native special actions, expiry and failures')

local ui=hud.new()
local function label_panel(original)
    local text=actor('label');text.message=original;text.writes=0
    function text:get_Message() return self.message end
    function text:set_Message(value) self.message=value;self.writes=self.writes+1 end
    local panel={play='HIDDEN',writes=0}
    function panel:get_Child() return text end
    function panel:get_PlayState() return self.play end
    function panel:set_PlayState(value) self.play=value;self.writes=self.writes+1 end
    return panel,text
end
local panel,text=label_panel('Native action')
local root=actor('root')
local function resolve(_,path) assert(path=='PNL_top/PNL_L03/PNL_txt');return panel end
ui:update(root,{['X (Square)']='Pawns Sit'},resolve)
assert(text.message=='Pawns Sit' and panel.play=='DEFAULT')
ui:update(root,{['X (Square)']='Pawns Sit'},resolve)
assert(text.writes==1 and panel.writes==1,'Unchanged frame repeated UI setters')
ui:update(root,{['X (Square)']='Next layout'},resolve)
assert(text.message=='Next layout' and text.writes==2)
ui:restore();assert(text.message=='Native action' and panel.play=='HIDDEN','UI not restored on mode exit')
ui:update(root,{['X (Square)']='Pawns Sit'},resolve)
text.message='Engine replacement';panel.play='NATIVE_OTHER'
ui:restore();assert(text.message=='Engine replacement' and panel.play=='NATIVE_OTHER','Restore overwrote fresh native state')
ui:update(root,{['X (Square)']='Pawns Sit'},resolve)
ui:update(nil,{},resolve);assert(text.message=='Engine replacement','Missing HUD retained custom labels')
ui:update(root,{['X (Square)']='Pawns Sit'},resolve)
ui:update(root,{},resolve);assert(next(ui.slots)==nil,'Rebound key retained old slot')
ui:update(root,{['X (Square)']='Pawns Sit'},function() return nil end)
assert(next(ui.slots)==nil,'Missing control produced cache')
local second_root=actor('new_root')
ui:update(root,{['X (Square)']='Pawns Sit'},resolve)
ui:update(second_root,{},resolve);assert(text.message=='Engine replacement','Root replacement leaked edits')
print('PASS: passenger labels, native appearance, changed-only writes, rebind, missing HUD and conditional restoration')

local body,cow=actor('gm80_042_00'),actor('cow')
-- Native GameObjects do not have get_GameObject; Characters do.
body.get_GameObject=nil
local guard,driver=actor('ch300802'),actor('ch300795')
local cart2=actor('gm80_042_00',1)
local part=actor('sm80_074_00',12)
assert(protection.cart_receiver(ox,ox,body,cow,true))
assert(protection.cart_receiver(body,ox,body,cow,true))
assert(protection.cart_receiver(cow,ox,body,cow,true))
assert(not protection.cart_receiver(cart2,ox,body,cow,true),'Unrelated body immune')
assert(not protection.cart_receiver(other,ox,body,cow,true),'Unrelated ox immune')
assert(not protection.cart_receiver(driver,ox,body,cow,true),'Driver immune')
assert(not protection.cart_receiver(guard,ox,body,cow,true),'Guard immune')
assert(protection.cart_receiver(part,ox,body,cow,true),'Known nearby part missed')
part.pos=vec(12.01,0,0);assert(not protection.cart_receiver(part,ox,body,cow,true),'Distant part immune')
part.pos=vec(0,0,0);assert(not protection.cart_receiver(part,ox,nil,cow,true),'Part without known body immune')
assert(not protection.cart_receiver(body,ox,body,cow,false),'Out of player range immune')
body.invalid=true;assert(not protection.cart_receiver(body,ox,body,cow,true),'Invalid receiver immune')
print('PASS: active ox/body/cow, known nearby parts, range and exclusion of drivers, guards and other carts')
