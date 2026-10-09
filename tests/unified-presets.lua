local M=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/presets.lua'))()
local function clone(v)
    if type(v)~='table' then return v end
    local out={};for k,x in pairs(v) do out[k]=clone(x) end;return out
end
local function slot(x) return {x=x,y=0.23,z=-2,lookX=1,lookZ=0,anim='SitOnChairActions'} end
local function layout(name)
    local p={name=name,enabled=true,teleportPlayer=true,player=slot(7),pawns={}}
    for i=1,9 do p.pawns[i]=slot(i/10) end
    return p
end
local options={Presets={Normal={layout('User Normal')},Rainy={layout('User Rainy')},Wealthy={layout('User Luxury')}}}
local saved=0
M.init(options,{Normal=1,Rainy=1,Wealthy=1},function() saved=saved+1 end,function() end)
local settings={sensitivity=70,bindings={up={keyboard='W',gamepad='RTrigTop'}},presets={},preset=1}
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    local p={family=family,name=family..' tuned',enabled=true,camera={fov=75},slots={{x=-0.2,y=0.92,z=0.3,yaw=178}}}
    for i=1,9 do p.slots[i+1]={x=i/5,y=0.8,z=-3,yaw=-90,anim='LivSitPose',randomIdle=true} end
    p.builtin_id=family..':1'
    settings.presets[#settings.presets+1]=p
end
local factory=clone(settings.presets)
M.attach(settings,factory)
assert(saved==1 and options.UnifiedVersion==1)
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    local list=options.Presets[family]
    assert(#list==2,'Migration dropped or duplicated a layout')
    assert(list[1].pawns[1].x==0.1 and list[1].player.x==7,'Migration overwrote OJR parameters')
    assert(list[2].pawns[1].x==0.2 and list[2].pawns[1].anim=='LivSitPose','Migration lost LMD parameters')
    assert(math.abs(list[2].pawns[1].lookX+1)<1e-12,'Yaw conversion changed facing')
    assert(list[2].driver.yaw==178 and list[2].driver_camera.fov==75,'Driver parameters lost')
end
assert(not options.ManualSettings.presets,'A second persisted layout store survived')
local p=options.Presets.Normal[2]
assert(M.activate(2) and M.cursor.Normal==2,'Canonical selection did not follow driver')
settings.presets[2].slots[1].x=0.5
assert(p.driver.x==0.5,'Driver editor did not edit shared player data')
p.pawns[1].x=0.66;M.refresh()
assert(settings.presets[2].slots[2].x==0.66,'Companion edits not visible in driver mode')
M.save_driver();M.attach(settings,factory)
assert(#options.Presets.Normal==2,'Reload imported legacy layouts twice')
local custom=layout('Extra custom');M.clone_player_seats(p,custom)
options.Presets.Normal[3]=custom
local customx=custom.pawns[1].x
M.restore_builtins()
assert(custom.pawns[1].x==customx and options.Presets.Normal[1].pawns[1].x==0.1,'Restore modified user layouts')
assert(p.pawns[1].x==0.2 and p.driver.x==-0.2,'Built-in restore failed')
local removed=settings.presets[2]
table.remove(options.Presets.Normal,2)
assert(not M.activate(2),'Deleted preset adapter selected a shifted layout')
print('PASS: lossless categorized migration, shared player seats, nine companion slots, single persistence, idempotence, built-in-only restore and stale deletion')
