;(function()
local bus=_G.DD2_OxcartControl
local speed=_G.OJR_UnifiedSpeed
local function upvalue(fn,key)
    for i=1,100 do
        local name,value=debug.getupvalue(fn,i)
        if not name then break end
        if name==key then return value end
    end
    error('Missing test upvalue: '..key)
end
local trip=upvalue(bus.journey.speed_step,'cart_trip')
upvalue(bus.journey.passenger_camera,'options').PLAYER_NEAR_CART_NONCOMBAT=false
function status:get_type_definition()
    return {get_method=function() return {get_num_params=function() return 0 end,
        get_return_type=function() return {get_name=function() return 'Boolean' end} end} end}
end
local function tick(dt)
    clock=clock+(dt or 0.1);callbacks.LateUpdateBehavior()
end
function ox:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
function passenger_controller:isPlayerSit() return self.seated end
function passenger_controller:get_GameObject() return body end
function human:get_Motion()
    return {getLayer=function() return {get_MotionBankID=function() return 0 end,
        get_MotionID=function() return passenger_controller.seated and 2010 or 0 end} end}
end
local original_status=status.call
local near_destination=false
status.call=function(self,method,...)
    if method=='get_isPayMoney' then return true end
    if method=='getFinalStopIndexPosition()' then
        local p=ox:get_UniversalPosition();return vec(p.x+(near_destination and 1 or 100),p.y,p.z)
    end
    return original_status(self,method,...)
end
passenger_controller.seated=true;ox.am.CurrentActionList[0].Name='Walk'
tick();bus.journey.sit();tick()
assert(#bus.journey.records()>=3,'Initial seating failed')
bus.journey.speed_step(1)
assert(speed.command.node=='Run','Run speed step failed')
local run_duration=speed.command.until_time-upvalue(bus.journey.speed_step,'runtime_clock')
assert(run_duration==360,'Run did not receive Dash-equivalent duration')
tick(3);ox.am:requestActionCore(10,'Walk',0)
assert(ox.am.CurrentActionList[0].Name=='Run','Run overwritten after two seconds')
passenger_controller.seated=false;tick()
assert(#bus.journey.records()>=3 and trip.keep_standing_companions,'Standing during Run released companions')
speed.issue(function() ox.am:requestActionCore(0,'Walk',0) end);tick()
assert(#bus.journey.records()>=3,'Later Walk discarded standing retention')
human.pos=vec(15,0,0);tick();assert(#bus.journey.records()>=3,'Exactly 15 released companions')
human.pos=vec(15.01,0,0);tick();assert(#bus.journey.records()==0,'Beyond 15 did not release companions')
human.pos=vec(0,0,0);passenger_controller.seated=true;tick()
ox.am.CurrentActionList[0].Name='Run';bus.journey.speed_step(1)
assert(trip.manual_speed and trip.manual_resume_at,'Manual Dash did not schedule auto resume')
tick(4.9);assert(trip.manual_speed,'Auto resumed before five seconds')
is_paused=true;tick(10);assert(trip.manual_speed,'Pause consumed auto resume timer')
is_paused=false;tick(0);tick(0.31) -- Existing post-menu settling window remains in effect.
assert(not trip.manual_speed and not trip.manual_resume_at and not trip.auto_paused,'Dash did not restore auto after five gameplay seconds')
assert(ox.am.CurrentActionList[0].Name=='Dash','Auto handoff interrupted Dash')
tick();bus.journey.speed_step(-1)
assert(ox.am.CurrentActionList[0].Name=='Run' and trip.manual_speed and not trip.manual_resume_at)
tick();bus.journey.speed_step(1);tick(1);bus.journey.speed_step(-1);tick(6)
assert(trip.manual_speed and not trip.manual_resume_at,'Later manual Run did not cancel Dash auto timer')
near_destination=true;tick(0.2)
assert(ox.am.CurrentActionList[0].Name=='Walk' and not speed.command,'Persistent Run blocked destination braking: '..ox.am.CurrentActionList[0].Name..' / '..tostring(trip.destination and trip.destination.reason)..' / '..tostring(speed.command and speed.command.node))
near_destination=false;tick();ox.am.CurrentActionList[0].Name='Run';bus.journey.speed_step(1)
tick();bus.journey.speed_step(1);local reset_at=trip.manual_resume_at
tick(4.9);assert(trip.manual_speed and trip.manual_resume_at==reset_at,'Repeated Dash input failed to restart timer')
tick(0.11);assert(not trip.manual_speed)
-- Native special actions retain precedence over both persistent speeds.
ox.am:requestActionCore(10,'Jump',0);assert(not speed.command and ox.am.CurrentActionList[0].Name=='Jump')
ox.am.CurrentActionList[0].Name='Walk'
local camera_settings=assert(bus.journey.passenger_camera())
camera_settings.fov_enabled=true;camera_settings.fov=88
camera_settings.distance_enabled=true;camera_settings.distance=4.5
local camera={fov=60,get_type_definition=function() return {get_method=function() return true end} end,
    call=function(self,name,value) if name=='get_FOV' then return self.fov end;self.fov=value end}
local manager={_DistanceOffset=1,get_type_definition=function() return {get_field=function() return true end} end}
local previous_singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name) if name=='app.CameraManager' then return manager end;return previous_singleton(name) end
sdk.get_primary_camera=function() return camera end
callbacks.PrepareRendering();assert(camera.fov==88 and manager._DistanceOffset==4.5,'Passenger camera override missing')
is_paused=true;gui['<IsDispPhotoModeAll>k__BackingField']=true
callbacks.PrepareRendering();assert(camera.fov==60 and manager._DistanceOffset==1,'Photo mode inherited passenger camera settings')
is_paused=false;gui['<IsDispPhotoModeAll>k__BackingField']=false
callbacks.PrepareRendering();assert(camera.fov==88 and manager._DistanceOffset==4.5)
passenger_controller.seated=false;callbacks.PrepareRendering()
assert(camera.fov==60 and manager._DistanceOffset==1,'Passenger exit did not restore camera')
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: Run duration, standing retention/15 distance, Dash auto handoff/pause/reinput, Run arrival braking, native actions and passenger camera/photo/exit')
end)()
