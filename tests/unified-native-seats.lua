;(function()
local previous_gm=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
local previous_singleton,previous_type=sdk.get_managed_singleton,sdk.find_type_definition
local previous_dump=json.dump_file
local function assert_native_facing(ch,anchor,slot,actor_rotation)
    local expected=actor_rotation or Quaternion.new(0,0,0,1)
    local q=ch.test_joint.rotation
    assert(q.x==expected.x and q.y==expected.y and q.z==expected.z and q.w==expected.w,
        'Position-only diagnostic changed native rotation')
end
-- Isolate earlier seat/drive tests from the automatic pawn staging integration.
local real_stage,real_pawn_command=driver_debug_bridge.native_pawns_stage,driver_debug_bridge.native_pawns_command
driver_debug_bridge.native_pawns_stage=function() return {} end
driver_debug_bridge.native_pawns_command=function() return true end
local interacting,active=false,nil
local requests,exits,refs=0,0,0
local expected_exit_actor=human
local seat={}
local driver_mapping_available,driver_points_enabled=true,true
local left_enabled=false
local passenger_test_state=false
local data={mask=8,get_field=function(self,key) return key=='CharacterType' and self.mask or 'driver_joint' end,
    set_field=function(self,key,value) assert(key=='CharacterType');self.mask=value end}
local io=object('native_io')
function io:call(method,point,ch)
    if method=='get_IsRegistered()' or method=='get_IsUpdatedAfterRegisterd()' then return true end
    if method=='getNumInteractPoint()' then return 6 end
    if method=='isInteractEnable(System.UInt32, app.Character)' then return point==1 and data.mask==9 end
    assert(method=='endInteractForSystem(System.UInt32, app.Character)' and point==1 and ch==expected_exit_actor,method)
    exits=exits+1
end
local result={value=0,get_field=function(self) return self.value end,
    add_ref=function() refs=refs+1 end,release=function() refs=refs-1 end}
local mgr={call=function(_,method,a,point,ch)
    if method=='isInteracting(app.Character)' then return interacting end
    if method=='getActiveInteract(app.Character)' then return active end
    assert(method=='requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)'
        and a==io and point==1 and ch==human,method)
    requests=requests+1;return result
end}
local gm=object('native_cart')
gm.InteractiveObject=io
gm.NonDriverSeatNoList={call=function(_,method) return method=='get_Count()' and 1 or 1 end}
local left_data={mask=10,get_field=function(self,key) return key=='CharacterType' and self.mask or 'driver_joint' end,
    set_field=function(self,key,value) assert(key=='CharacterType');self.mask=value end}
gm.InteractiveObjectDataList={get_element=function(_,i) return i==0 and left_data or i==1 and data or
    {get_field=function(_,key) return key=='CharacterType' and 1 or 'other_joint' end} end}
function gm:get_type_definition() return {get_method=function() return {get_num_params=function() return 0 end} end} end
function gm:call(method,i)
    if method=='isPlayerSit()' then return passenger_test_state end
    if method=='get_DrivingSeat' then return seat end
    if method=='getSeatNo(System.UInt32)' then return i-2 end
    if method=='IsDriver(System.UInt32)' then
        if not driver_mapping_available then error('IsDriver unavailable') end
        return i<2
    end
    if method=='isInteractEnable(System.UInt32)' then return (i~=0 or left_enabled) and (i>=2 or driver_points_enabled) end
    if method=='getInteractChara(System.UInt32)' then return nil end
    error(method)
end
sdk.get_managed_singleton=function(name) return name=='app.InteractManager' and mgr or previous_singleton(name) end
sdk.find_type_definition=function(name)
    if name=='app.InteractManager.InteractRequestResultType' then
        return {get_field=function() return {get_data=function() return 1 end} end}
    end
    return previous_type(name)
end
json.dump_file=function() end
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=gm
state.active=false;is_paused=false
local position,warps,falls,fsm=human.pos,human.test_controller.warps,human.test_fall.reset_calls,human.machine.enabled
local unseated_warps=driver.test_controller.warps
local function command(value)
    assert(driver_debug_bridge.native_seat_command(value));clock=clock+0.2;driver_debug_bridge.native_seat_tick()
end
command('scan')
assert(#driver_debug_bridge.native_seat_read().rows==6 and requests==0 and data.mask==8,driver_debug_bridge.native_seat_read().status)
local rows=driver_debug_bridge.native_seat_read().rows
assert(rows[1].native_is_driver and not rows[1].driver_candidate and rows[2].driver_candidate
    and rows[2].seat_no==-1 and not rows[3].driver_candidate,'Native negative-seat driver mapping failed')
left_enabled=true;command('scan')
rows=driver_debug_bridge.native_seat_read().rows
assert(rows[1].driver_candidate and rows[2].driver_candidate and driver_debug_bridge.native_seat_read().status:find('point 0',1,true),
    'Two native driver entrances were treated as ambiguous')
left_enabled=false
driver_mapping_available=false;command('enter')
assert(requests==0 and data.mask==8 and not driver_debug_bridge.native_seat_busy(),'Unreadable mapping guessed point')
driver_mapping_available=true;driver_points_enabled=false;command('enter')
assert(requests==0 and data.mask==8 and not driver_debug_bridge.native_seat_busy(),'No driver entrance used passenger fallback')
assert(driver.test_controller.warps==unseated_warps,'Invalid driver entrance teleported nearby NPC')
driver_points_enabled=true
seat.SitChara=driver;command('enter')
assert(requests==0 and not driver_debug_bridge.native_seat_busy(),'Occupied seat accepted')
seat.SitChara=nil;command('enter')
assert(requests==1 and data.mask==9 and left_data.mask==10 and refs==1,'Player flag/request missing or other entrance changed')
assert(driver.test_controller.warps==unseated_warps+1 and math.abs(driver.pos.z-body.pos.z)==500,
    'Nearby unseated driver was not physically relocated once behind cart')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and left_data.mask==10 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Denied request leaked mask/lease')
result.value=0;command('enter')
interacting=true;active={Point={Object=io,PointNo=1}};seat.SitChara=human
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(driver_debug_bridge.native_seat_read().status:find('CONFIRMED',1,true),'Native binding not confirmed')
assert(state.native_drive and not state.active and #state.seats==0 and bus.owner==TITLE,
    'Native driving reused legacy seat ownership')
do
    local q,exit_original=state.native_drive,driver_debug_bridge.native_pawns_exit
    local pawn_exits=0
    driver_debug_bridge.native_pawns_exit=function() pawn_exits=pawn_exits+1;return true end
    input={keyboard=0,stick=0,pawn_stand=true}
    callbacks.LateUpdateBehavior()
    assert(pawn_exits==1 and state.native_drive==q and bus.owner==TITLE and not q.player_preset_disabled,
        'Pawn-only stand changed player control or did not call pawn exit')
    driver_debug_bridge.native_pawns_exit=exit_original
end
assert(not driver_debug_bridge.native_seat_command('enter') and state.native_drive,
    'Repeated entry disrupted existing native ownership')
for _,layout in ipairs(settings.presets) do assert(not layout.native_default,'Read-only Default survived migration') end
local original_camera=copy_camera(current_camera())
local previous_primary=sdk.get_primary_camera
local camera_transform=object('camera',vec(7,8,9))
camera_transform.set_Position=function() error('Driving must not write camera position') end
local camera={fov=60,get_GameObject=function() return camera_transform end,
    get_type_definition=function() return {get_method=function() return true end} end,
    call=function(self,name,value) if name=='get_FOV' then return self.fov end;self.fov=value end}
local camera_manager={_DistanceOffset=1,get_type_definition=function() return {get_field=function() return true end} end}
local camera_singleton=sdk.get_managed_singleton
sdk.get_primary_camera=function() return camera end
sdk.get_managed_singleton=function(name) if name=='app.CameraManager' then return camera_manager end;return camera_singleton(name) end
current_camera().fov_enabled=true;current_camera().fov=80
current_camera().distance_enabled=true;current_camera().distance=3
callbacks.PrepareRendering()
assert(camera.fov==60 and camera_manager._DistanceOffset==1 and camera_transform.pos.x==7,
    'Camera overrides applied before boarding delay')
local original_ready=state.native_drive.ready_at
local original_visual_ready=state.native_drive.visual_ready_at
driver_debug_bridge.native_boarding_pause(2)
assert(state.native_drive.ready_at==original_ready+2 and state.native_entry_ready_at==original_ready+2,
    'Pause did not preserve eight seconds of game-time boarding')
assert(state.native_drive.visual_ready_at==original_visual_ready+2,'Pause advanced player preset countdown')
-- Keep the later timing checks relative to the delayed gate.
clock=clock+2
local function drive(keys)
    input={keyboard=0,stick=0}
    for k,v in pairs(keys or {}) do input[k]=v end
    driver_debug_bridge.native_drive_tick(0.1)
end
drive({up=true})
assert(state.native_drive.drive.level==1 and ox.am.CurrentActionList[0].Name=='Wait','Boarding wait accepted acceleration')
clock=clock+5.1
callbacks.PrepareRendering()
drive({up=true})
assert(state.native_drive.drive.level==1 and ox.am.CurrentActionList[0].Name=='Wait',
    'Boarding wait ended before eight seconds')
assert(camera.fov==60 and camera_manager._DistanceOffset==1,
    'Player presets applied at five seconds instead of eight')
local movement_ready=state.native_drive.ready_at
clock=clock+1;driver_debug_bridge.native_boarding_pause(1)
assert(state.native_drive.ready_at==movement_ready+1 and state.native_drive.visual_ready_at==original_visual_ready+3,
    'Pause did not preserve both eight-second delays')
clock=clock+3
callbacks.PrepareRendering()
assert(camera.fov==80 and camera_manager._DistanceOffset==3 and camera_transform.pos.x==7
    and camera_transform.pos.y==8 and camera_transform.pos.z==9,'Delayed FOV/distance overrides missing or camera position changed')
callbacks.PrepareRendering()
assert(camera_transform.pos.x==7,'Rendering changed camera position')
assert(hooks['freeGetOff']==nil,'Unsafe early-departure hook was retained')
assert(native_camera_ready(),'Player presets disabled while still in driver seat')
pre_callbacks.UpdateBehavior()
assert(camera_transform.pos.x==7 and (human.pos-position):length()==0,'Player display Transform was not restored before simulation')
local original_gui_field=gui['<IsDispPhotoModeAll>k__BackingField']
local active_layout=settings.presets[settings.preset]._canonical
active_layout.teleportPlayer=true
gui['<IsDispPhotoModeAll>k__BackingField']=true;is_paused=true
local player_action=human.am.CurrentActionList[0].Name
local photo_warps,photo_falls=human.test_controller.warps,human.test_fall.reset_calls
local old_joint_write=human.test_joint.set_Position
human.test_joint.set_Position=function() error('Player display still writes a skeleton joint') end
clock=clock+50
pre_callbacks.PrepareRendering()
callbacks.PrepareRendering()
local photo_target=native_display_position(state.native_drive.cart.anchor,settings.presets[settings.preset].slots[1])
assert((human.pos-photo_target):length()==0,
    'Photo mode did not apply player Transform preset')
active_layout.teleportPlayer=false
bus.driver.player_adjustment_changed(active_layout)
assert((human.pos-position):length()==0,'Disabling driver adjustment did not restore native display immediately')
pre_callbacks.PrepareRendering()
assert((human.pos-position):length()==0,'Disabled driver adjustment still writes preset position in photo mode')
assert(native_camera_ready(),'Adjust Player incorrectly disabled camera readiness')
active_layout.teleportPlayer=true
pre_callbacks.PrepareRendering()
assert((human.pos-photo_target):length()==0,'Reenabling driver adjustment lost saved coordinates')
assert(human.test_controller.warps==photo_warps and human.test_fall.reset_calls==photo_falls,
    'Player display override performed a physical teleport/fall reset')
assert_native_facing(human,state.native_drive.cart.anchor,settings.presets[settings.preset].slots[1])
assert(camera.fov==60 and camera_manager._DistanceOffset==1 and camera_transform.pos.x==7,
    'Photo mode applied driving camera parameters')
assert(human.am.CurrentActionList[0].Name==player_action,'Photo mode issued a sitting animation')
pre_callbacks.UpdateBehavior();pre_callbacks.PrepareRendering();callbacks.PrepareRendering()
assert((human.pos-photo_target):length()==0,'Photo pre-render fallback lost Transform preset')
pre_callbacks.PrepareRendering()
assert((human.pos-photo_target):length()==0,'Repeated photo rendering accumulated player offset')
driver_debug_bridge.native_visual_restore()
assert((human.pos-position):length()==0,'Photo display restoration lost native position')
pre_callbacks.PrepareRendering()
human.test_joint.set_Position=old_joint_write
gui['<IsDispPhotoModeAll>k__BackingField']=original_gui_field;is_paused=false;last=clock
callbacks.PrepareRendering()
assert(camera.fov==80 and camera_manager._DistanceOffset==3 and camera_transform.pos.x==7,
    'Driving camera did not resume after photo mode')
pre_callbacks.UpdateBehavior()
assert((human.pos-position):length()==0,'Player Transform not restored on gameplay evaluation')
print('PASS: photo-mode player Transform override, no joint/physics/animation/camera writes, restoration and no drift')

-- Reenable the real shared controller and test it under the native driver lease.
drive({up=true});assert(state.native_drive.drive.level==2,'Shared driver acceleration failed')
clock=clock+30;drive({})
assert(state.native_drive.drive.level==2,'Manual mode automatically changed speed')
drive({up=true});assert(state.native_drive.drive.level==3,'Run speed missing')
drive({down=true});assert(state.native_drive.drive.level==2,'Driver deceleration failed')
local player_interact_call=mgr.call
mgr.call=function(self,method,ch,...)
    if ch~=human and method=='isInteracting(app.Character)' then return false end
    return player_interact_call(self,method,ch,...)
end
driver_debug_bridge.native_pawns_command=real_pawn_command
bus.journey.manual_tick()
assert(real_pawn_command(true,state.native_drive.cart))
local bindings=_G.OJR_SeatBindings
assert(#bindings==3,"Shared manual seats did not acquire three companions")
for _,r in ipairs(bindings) do
    assert(r.fsm_machine and r.fsm_machine.enabled==true,"Seat event must unfreeze first")
    assert(r.char.test_fall.reset_calls==1,"One fall reset required on first seat")
    local trace=_G.OJR_RuntimeDiagnostics.traces[r]
    assert(trace and trace.samples[1].phase=='before-request',"Actual initial seating lacks pre-request evidence")
    assert(trace.samples[2].phase=='requested' and trace.samples[2].fsm_enabled==true,"Actual request checkpoint missing")
end
bus.journey.manual_tick()
for _,r in ipairs(bindings) do assert(not r.fsm_machine.enabled,"Shared next-frame FSM freeze missing") end
for _,r in ipairs(bindings) do
    local samples=_G.OJR_RuntimeDiagnostics.traces[r].samples
    assert(samples[3].phase=='before-freeze' and samples[3].fsm_enabled==true,"Pre-freeze checkpoint misplaced")
    assert(samples[4].phase=='after-freeze' and samples[4].fsm_enabled==false,"Post-freeze checkpoint misplaced")
end
local first=settings.preset
assert(driver_debug_bridge.switch_preset(nil,true))
assert(settings.preset~=first and #bindings==3,"Shared layout switch failed")
for _,r in ipairs(bindings) do
    assert(r.fsm_machine.enabled,"Preset switch did not unfreeze")
    assert(r.char.test_fall.reset_calls==2,"Preset switch must reset fall exactly once")
end
bus.journey.manual_tick()
for _,r in ipairs(bindings) do assert(not r.fsm_machine.enabled,"Preset switch did not refreeze next frame") end
-- Exercise the real root UI -> deferred journey selection -> driver switch path.
do
    local original_imgui=imgui
    local stack,depth,backup_seen,skip_seen={},0,false,false
    local current_index=settings.presets[settings.preset]._index
    local menu_target=current_index==1 and 2 or 1
    local last_field,same_line
    local function field(label,value)
        if label=='Skip this preset when player is passenger' then
            assert(last_field=='Adjust Player' and same_line,'Passenger skip is not adjacent to Adjust Player')
            skip_seen=true
        end
        last_field,same_line=label,false
        return false,value
    end
    imgui={}
    function imgui.tree_node(label)
        assert(label~='Passenger backup keybinds' and not label:find('Cross Hotbar Key',1,true),'Obsolete backup section remains')
        if label=='Other Settings' then return false end
        if label=='Backup keybinds' then
            assert(stack[#stack]=='Keybind settings','Backup controls are not inside Keybind settings')
            backup_seen=true
        end
        stack[#stack+1]=label;return true
    end
    function imgui.tree_pop() table.remove(stack) end
    function imgui.push_id() depth=depth+1 end
    function imgui.pop_id() depth=depth-1 end
    function imgui.combo(label,index)
        if label=='Active layout' then return true,menu_target end
        return false,index
    end
    function imgui.begin_table() return true end
    for _,name in ipairs({'end_table','table_next_row','table_next_column','table_header','text','spacing','separator'}) do imgui[name]=function() end end
    function imgui.button() return false end
    function imgui.same_line() same_line=true end
    for _,name in ipairs({'checkbox','input_text','drag_float','drag_int','slider_float'}) do imgui[name]=field end
    local before=pawns[1].test_fall.reset_calls
    callbacks.ui()
    assert(backup_seen and skip_seen and #stack==0 and depth==0,'Unified UI nesting failed')
    assert(settings.presets[settings.preset]._index==current_index and pawns[1].test_fall.reset_calls==before,
        'UI draw immediately applied a pose')
    assert(not pawns[1].machine.enabled,'UI draw changed frozen FSM')
    callbacks.LateUpdateBehavior()
    assert(settings.presets[settings.preset]._index==menu_target and pawns[1].test_fall.reset_calls==before+1,
        'Behavior phase did not apply menu-selected layout exactly once')
    assert(pawns[1].machine.enabled,'Menu switch refroze before a behavior frame could run')
    callbacks.LateUpdateBehavior()
    assert(not pawns[1].machine.enabled and pawns[1].test_fall.reset_calls==before+1,
        'Menu switch missed next-frame freeze or applied twice')
    imgui=original_imgui
end
local reset_count=pawns[1].test_fall.reset_calls
for i=1,4 do bus.journey.manual_tick();bus.journey.manual_pose() end
assert(pawns[1].test_fall.reset_calls==reset_count,"Routine follow/render reset fall")
human.pos=vec(5,0,0);bus.journey.manual_tick()
assert(#bindings==3,'Manual seats released at exactly five')
human.pos=vec(5.001,0,0);bus.journey.manual_tick()
assert(#bindings==0,'Manual seats did not release beyond five')
for _,ch in ipairs(pawns) do assert(ch.machine.enabled,'Distance release leaked FSM') end
human.pos=position
assert(real_pawn_command(true,state.native_drive.cart));bus.journey.manual_tick()
-- Pawn-only stand leaves native driver control intact.
driver_debug_bridge.native_pawns_exit()
assert(#bindings==0 and state.native_drive,"Pawn-only stand stopped player driving")
for _,ch in ipairs(pawns) do assert(ch.machine.enabled,"Stand leaked FSM freeze") end
bus.journey.manual_tick();assert(#bindings==0,"Stand immediately reseated party")
assert(real_pawn_command(true,state.native_drive.cart))
bus.journey.manual_tick()
-- Native completion, rather than a speculative A-button hook, releases all.
interacting=false;active=nil;seat.SitChara=nil
driver_debug_bridge.native_drive_tick(0.1)
assert(not state.native_drive and #bindings==0 and not bus.unified_manual_active,"Native exit leaked shared companions/ownership")
for _,ch in ipairs(pawns) do assert(ch.machine.enabled,"Native exit leaked FSM") end
driver_debug_bridge.native_seat_close()
-- No NPC restoration is performed.
assert(math.abs(driver.pos.z-body.pos.z)==500,"Exiting restored NPC driver")
assert(data.mask==8 and refs==0,"Native exit leaked flag/result lease")
-- Every new manual trip starts from the first enabled preset.
command("enter")
interacting=true;active={Point={Object=io,PointNo=1}};seat.SitChara=human
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(state.native_drive and settings.presets[settings.preset]._index==1,"Reentry remembered old preset")
driver_debug_bridge.stand_hotkey()
assert(not state.native_drive and #bindings==0 and state.stand_stopped,"Let me stand did not stop all scripted driving")
assert(not driver_debug_bridge.switch_preset(nil,true),"Preset cycling survived Let me stand")
driver_debug_bridge.native_seat_close()
assert(not bus.owner and not bus.unified_manual_active,"Final release leaked manual owner")
function gm:isPlayerSit() return passenger_test_state end
passenger_test_state=true
assert(bus.journey.passenger_active(),'Passenger speed service did not recognize passenger interaction')
ox.am.CurrentActionList[0].Name='Wait'
bus.journey.manual_tick();bus.journey.speed_step(1)
assert(ox.am.CurrentActionList[0].Name=='Walk','Passenger accelerate is not shared Wait/Walk/Run/Dash')
bus.journey.speed_step(1)
assert(ox.am.CurrentActionList[0].Name=='Walk','Duplicate bindings accelerated twice in one frame')
bus.journey.manual_tick();bus.journey.speed_step(1)
assert(ox.am.CurrentActionList[0].Name=='Run','Passenger Run step missing')
bus.journey.manual_tick();bus.journey.speed_step(-1)
assert(ox.am.CurrentActionList[0].Name=='Walk','Passenger deceleration failed')
passenger_test_state=false
print("PASS: unified startup, native driver entry/8s/photo, shared companion seats/presets/fall/FSM, stand, native exit and first-preset reentry")
end)()
