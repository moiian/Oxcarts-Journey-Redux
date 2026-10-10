_G.OJR_EnableRuntimeDiagnostics=true
local writes=0
local paths={}
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
json={dump_file=function(path,data)
    assert(path:match('^OJR_RuntimeTest_.*%.json$') or path:match('^OJR_SeatTrace_.*%.json$'))
    writes=writes+1;paths[path]=copy(data)
    if data.events then assert(#data.events<=400,'Unbounded evidence ring') end
end}
log={error=error}
local diagnostics=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/diagnostics.lua'))()
assert(writes==1,'Session startup did not immediately persist evidence')
local function pos(y) return {x=0,y=y,z=0} end
local hip={get_Name=function() return 'Hip' end,get_Position=function() return pos(0.77) end}
local go={get_address=function() return 1 end,get_Name=function() return 'companion' end}
local tr={get_Position=function() return pos(0.77) end,
    get_Joints=function() return {get_elements=function() return {hip} end} end}
local action_name='Wait'
local reads=0
local list=setmetatable({get_Count=function() return 1 end},{__index=function(_,key)
    assert(key==0,'Out-of-range native action list access')
    reads=reads+1;return {Name=action_name}
end})
local ch={get_GameObject=function() return go end,get_Transform=function() return tr end,
    ['<ActionManager>k__BackingField']={CurrentActionList=list},
    ['<AdjustTerrain>k__BackingField']={MainCharacterController={call=function() return pos(0.77) end}}}
local anchor={get_GameObject=function() return go end,get_Position=function() return pos(0) end,
    get_AxisX=function() return {x=1,y=0,z=0} end,get_AxisY=function() return pos(1) end,
    get_AxisZ=function() return {x=0,y=0,z=1} end}
local enabled=true
local binding={char=ch,slot=1,seat_spec={x=0,y=0.77,z=0},fsm_machine={call=function() return enabled end},fsm_freeze_frame=2}
diagnostics.begin_pose(binding,anchor,'SitOnChairActions',0,1,10)
local trace=diagnostics.traces[binding]
local first_path=trace.path
assert(trace.samples[1].root.y==0.77 and trace.samples[1].physics.y==0.77 and trace.samples[1].hip.y==0.77)
assert(trace.samples[1].actions.layers[1].name=='Wait' and trace.samples[1].fsm_enabled==true)
assert(paths[first_path].trace.actor_pose_number==1 and not paths[first_path].trace.complete)
action_name='SitOnChairActions'
diagnostics.mark_pose(binding,anchor,'requested',1,10)
diagnostics.mark_pose(binding,anchor,'before-freeze',2,10.01)
enabled=false
diagnostics.mark_pose(binding,anchor,'after-freeze',2,10.01)
assert(trace.samples[3].fsm_enabled==true and trace.samples[4].fsm_enabled==false)
local samples,writes_before=#trace.samples,writes
diagnostics.mark_pose(binding,anchor,'before-freeze',3,10.02)
diagnostics.mark_pose(binding,anchor,'after-freeze',3,10.02)
assert(#trace.samples==samples and writes==writes_before,'Repeated per-frame freeze wrote duplicate evidence')
diagnostics.sample_pose(binding,anchor,1,10);assert(#trace.samples==samples,'Sampled before next frame')
for _,time in ipairs({10.01,10.11,10.31,10.61,11.01,12.01}) do diagnostics.sample_pose(binding,anchor,2,time) end
assert(diagnostics.traces[binding] and not paths[first_path].trace.complete,'Trace ended before three seconds')
diagnostics.sample_pose(binding,anchor,3,13.01)
assert(not diagnostics.traces[binding] and #trace.samples==11 and paths[first_path].trace.complete)
assert(trace.samples[11].phase=='after-3' and trace.samples[11].actions.layers[1].name=='SitOnChairActions')
assert(trace.samples[5].callback=='PrepareRendering' and trace.samples[5].fsm_enabled==false)
diagnostics.begin_pose(binding,anchor,'LivSitPose',1,4,14)
local second_path=diagnostics.traces[binding].path
assert(second_path~=first_path and diagnostics.traces[binding].actor_pose_number==2)
diagnostics.cancel_pose(binding);assert(not diagnostics.traces[binding])
assert(paths[second_path].trace.ended_reason=='binding-released')
for i=1,410 do diagnostics.write('test',{i=i},true) end
assert(#diagnostics.events==400)
diagnostics.flush()
assert(paths[first_path].trace.complete and #paths[first_path].trace.samples==11,'First pose lost after ring eviction')
assert(reads>0)
ch['<ActionManager>k__BackingField'].CurrentActionList=setmetatable({get_Count=function() return 0 end},
    {__index=function() error('Empty native list accessed') end})
diagnostics.begin_pose(binding,anchor,'LivSitPose',1,5,15)
assert(diagnostics.traces[binding].samples[1].actions.count==0)
ch['<ActionManager>k__BackingField']=nil
diagnostics.mark_pose(binding,anchor,'requested',5,15)
assert(diagnostics.traces[binding].samples[2].actions.status=='unavailable')
diagnostics.close()
print('PASS: separate retained pose files, safe action bounds, freeze checkpoints, three-second trace and cancellation')
