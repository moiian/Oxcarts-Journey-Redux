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
local options={UnifiedVersion=1,Presets={}}
local factories,driver_factory={},{}
local settings={sensitivity=70,bindings={up={keyboard='W',gamepad='RTrigTop'}},presets={},preset=1}
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    factories[family]={layout(family..' Facing Each Other')}
    local builtin=clone(factories[family][1]);builtin.player.x=8;builtin.pawns[1].x=8
    local custom=layout(family..' custom')
    options.Presets[family]={builtin,custom}
    local imported=layout('renamed driver layout');imported.driver_builtin_id=family..':1'
    options.Presets[family][3]=imported
    local d={family=family,name='Old driver',camera={fov=75},slots={{x=-0.2,y=0.92,z=0.3,yaw=178}}}
    settings.presets[#settings.presets+1]=d;driver_factory[#driver_factory+1]=clone(d)
end
options.Presets.Normal[4]=layout('Custom old LMD (driver import)')
local saved=0
M.init(options,{Normal=1,Rainy=1,Wealthy=1},function() saved=saved+1 end,function() end,factories)
M.attach(settings,driver_factory)
assert(saved==1 and options.UnifiedVersion==2 and M.removed_imports==4)
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    local list=options.Presets[family]
    assert(#list==2,'Removed user layout or retained driver import')
    assert(list[1].name=='[1] '..family..' Facing Each Other' and list[1].builtin_id,'Builtin name/identity missing')
    assert(list[1].player.x==8 and list[1].pawns[1].x==8,'Migration reset tuned passenger parameters')
    assert(list[1].driver.x==-0.2 and list[1].driver_camera.fov==75,'Missing player driver fallback')
    assert(list[2].builtin_id==nil,'Custom layout mistaken for built-in')
end
assert(not options.ManualSettings.presets,'A second persisted layout store survived')
local camera_preset=options.Presets.Normal[1]
local passenger_camera=M.camera_for(camera_preset,true)
assert(passenger_camera~=camera_preset.driver_camera and passenger_camera.fov==75,'Passenger camera fallback is missing or shared')
passenger_camera.fov=85;M.refresh()
assert(camera_preset.driver_camera.fov==75 and camera_preset.passenger_camera.fov==85,'Passenger camera overwrote driver camera')
local custom=options.Presets.Normal[2]
assert(M.activate(2) and M.cursor.Normal==2)
settings.presets[2].slots[1].x=0.5
assert(custom.driver.x==0.5,'Driver parameters are not canonical')
custom.pawns[1].x=0.66;M.refresh()
assert(settings.presets[2].slots[2].x==0.66,'Shared companion update lost')
M.attach(settings,driver_factory)
assert(#options.Presets.Normal==2 and M.removed_imports==0,'Reload changed preset inventory')
local extra=layout('Extra custom');M.clone_player_seats(custom,extra)
options.Presets.Normal[3]=extra
assert(extra.driver~=custom.driver and extra.driver_camera~=custom.driver_camera and extra.builtin_id==nil)
assert(extra.passenger_camera~=custom.passenger_camera and extra.passenger_camera.fov==custom.passenger_camera.fov)
M.restore_builtins()
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    local p=options.Presets[family][1]
    assert(p.player.x==7 and p.pawns[1].x==0.1 and p.driver.x==-0.2 and p.driver_camera.fov==75,
        'Restore did not reset both player modes and shared companions')
end
assert(custom.pawns[1].x==0.66 and custom.driver.x==0.5,'Restore modified custom layout')
table.remove(options.Presets.Normal,1);M.cursor.Normal=1
M.restore_builtins()
assert(#options.Presets.Normal==3 and options.Presets.Normal[2]==custom and M.cursor.Normal==2,
    'Restore did not recreate deleted builtin while preserving selected custom identity')
options.Presets.Normal[1].skipPassenger=true
assert(M.next_passenger('Normal',0)==2,'Passenger cycle did not skip flagged first layout')
for _,p in ipairs(options.Presets.Normal) do p.skipPassenger=true end
assert(M.next_passenger('Normal',1)==nil,'All-skipped cycle must be a no-op')
M.refresh();assert(M.activate(1),'Passenger skip blocked manual driver selection')
table.remove(options.Presets.Normal,2)
assert(not M.activate(2),'Deleted preset adapter selected a shifted layout')
print('PASS: import removal, indexed passenger names, tuned value preservation, full builtin restore/recreation, custom preservation, skip/all-skip and stale identity')
