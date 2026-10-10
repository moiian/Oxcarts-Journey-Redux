-- Bounded test evidence, written through REFramework's data-file API.
-- Detailed evidence is opt-in, never collected or written during normal play.
if rawget(_G,'OJR_EnableRuntimeDiagnostics')~=true then
    local idle=function() end
    return {events={},traces={},begin_pose=idle,mark_pose=idle,sample_pose=idle,
        cancel_pose=idle,write=idle,flush=idle,close=idle}
end
local M={events={},traces={},serial=0,started=os.clock(),actor_counts={}}
local session_name=os.date('%Y%m%d_%H%M%S')..'_'..math.floor(M.started*1000)
M.path='OJR_RuntimeTest_'..session_name..'.json'
local function read(fn)
    local ok,value=pcall(fn)
    if ok then return value end
end
local function position(p)
    if not p then return end
    return {x=tonumber(p.x),y=tonumber(p.y),z=tonumber(p.z)}
end
local function identity(o)
    if not o then return end
    return {address=tostring(read(function() return o:get_address() end)),
        name=read(function() return tostring(o:get_Name()) end)}
end
function M.flush()
    local ok,err=pcall(function()
        local saved=json.dump_file(M.path,{version=2,events=M.events,session=M.started})
        assert(saved~=false,'json.dump_file returned false')
    end)
    if not ok and not M.failed then
        M.failed=true
        if log and log.error then log.error('[OJR Diagnostics] Cannot save '..M.path..': '..tostring(err)) end
    end
    return ok
end
function M.write(kind,data,defer)
    M.events[#M.events+1]={t=os.clock()-M.started,kind=kind,data=data}
    if #M.events>400 then table.remove(M.events,1) end
    if not defer then M.flush() end
end
local function save_trace(trace)
    local ok,err=pcall(function()
        assert(json.dump_file(trace.path,{version=2,session=M.started,trace=trace})~=false,
            'json.dump_file returned false')
    end)
    if not ok and not M.trace_failed then
        M.trace_failed=true
        if log and log.error then log.error('[OJR Diagnostics] Cannot save seat trace: '..tostring(err)) end
    end
    return ok
end
local function actions(ch)
    local result={}
    local manager=read(function() return ch['<ActionManager>k__BackingField'] end)
    local list=manager and read(function() return manager.CurrentActionList end)
    local count=list and read(function() return tonumber(list:get_Count()) end)
    if not count then return {status='unavailable'} end
    for layer=0,math.min(count,4)-1 do
        -- Never probe a layer outside the native list, even inside pcall.
        local action=read(function() return list[layer] end)
        result[#result+1]={layer=layer,name=action and read(function() return tostring(action.Name) end) or 'none'}
    end
    return {count=count,layers=result}
end
local function snapshot(binding,anchor,frame,now,phase)
    local ch=binding.char
    local tr=ch:get_Transform()
    local row={phase=phase,callback='PrepareRendering',frame=frame,time=now,slot=binding.slot,
        actor=identity(ch:get_GameObject()),anchor=identity(anchor:get_GameObject()),
        root=position(tr:get_Position()),anchor_position=position(anchor:get_Position()),
        direct_motion=binding.seat_spec.useDirectMotion==true,
        anchor_up=position(anchor:get_AxisY()),spec={x=binding.seat_spec.x,y=binding.seat_spec.y,z=binding.seat_spec.z},
        fsm_enabled=read(function()
            local human=ch['<Human>k__BackingField']
            local manager=ch['<ActionManager>k__BackingField']
            local machine=binding.fsm_machine or human and human.Fsm or manager and manager.Fsm
            return machine and machine:call('get_Enabled()')
        end),
        freeze_frame=binding.fsm_freeze_frame,actions=actions(ch)}
    local pelvis=rawget(_G,'OJR_UnifiedPelvis')
    local correction=pelvis and pelvis.states and pelvis.states[binding]
    if correction then
        row.pelvis={baseline=correction.baseline,ready_at=correction.ready_at,
            applied=correction.applied~=nil,failed=correction.failed==true}
    end
    local spec=binding.seat_spec
    local origin,x,y,z=anchor:get_Position(),anchor:get_AxisX(),anchor:get_AxisY(),anchor:get_AxisZ()
    row.target={x=origin.x+x.x*spec.x+y.x*spec.y+z.x*spec.z,
        y=origin.y+x.y*spec.x+y.y*spec.y+z.y*spec.z,
        z=origin.z+x.z*spec.x+y.z*spec.y+z.z*spec.z}
    row.physics=read(function()
        return position(ch['<AdjustTerrain>k__BackingField'].MainCharacterController:call('get_Position()'))
    end)
    row.hip=read(function()
        for _,joint in pairs(tr:get_Joints():get_elements() or {}) do
            if tostring(joint:get_Name()):lower()=='hip' then return position(joint:get_Position()) end
        end
    end)
    return row
end
local function capture(trace,binding,anchor,frame,now,phase,callback)
    local ok,row=pcall(snapshot,binding,anchor,frame,now,phase)
    row=ok and row or {phase=phase,time=now,frame=frame,error=tostring(row)}
    row.callback=callback
    trace.samples[#trace.samples+1]=row
    return row
end
function M.begin_pose(binding,anchor,node,priority,frame,now,source)
    if not binding then return end
    if M.traces[binding] then M.cancel_pose(binding,'pose-replaced') end
    M.serial=M.serial+1
    local actor=identity(binding.char:get_GameObject())
    local count=(M.actor_counts[actor.address] or 0)+1
    M.actor_counts[actor.address]=count
    local trace={id=M.serial,start=now,frame=frame,node=node,priority=priority,samples={},next=1,
        actor=actor,actor_pose_number=count,source=source or 'unspecified',complete=false,
        path='OJR_SeatTrace_'..session_name..'_'..M.serial..'.json'}
    M.traces[binding]=trace
    local row=capture(trace,binding,anchor,frame,now,'before-request','pose-request')
    save_trace(trace)
    M.write('seat-request',{id=trace.id,node=node,priority=priority,path=trace.path,sample=row})
end
function M.mark_pose(binding,anchor,phase,frame,now)
    local trace=M.traces[binding]
    if not trace or trace.marked and trace.marked[phase] then return end
    trace.marked=trace.marked or {}
    trace.marked[phase]=true
    capture(trace,binding,anchor,frame,now,phase,'pose-lifecycle')
    -- Both freeze snapshots are persisted together, after the native freeze call.
    if phase~='before-freeze' then save_trace(trace) end
end
function M.sample_pose(binding,anchor,frame,now)
    local trace=M.traces[binding]
    if not trace then return end
    local delays={0,0.1,0.3,0.6,1,2,3}
    local delay=delays[trace.next]
    if frame<=trace.frame or now-trace.start<delay then return end
    capture(trace,binding,anchor,frame,now,trace.next==1 and 'next-frame' or ('after-'..delay),'PrepareRendering')
    trace.next=trace.next+1
    if trace.next>#delays then
        trace.complete=true
        M.write('seat-initialization',trace)
        M.traces[binding]=nil
    end
    save_trace(trace)
end
function M.cancel_pose(binding,reason)
    local trace=M.traces[binding]
    if trace then
        trace.ended_reason=reason or 'binding-released'
        save_trace(trace)
        M.write('seat-trace-ended',trace);M.traces[binding]=nil
    end
end
function M.close()
    for binding in pairs(M.traces) do M.cancel_pose(binding) end
    M.write('script-reset',{})
end
M.write('session-start',{purpose='Protection and per-pose three-second evidence; separate seat files survive event-ring eviction'})
return M
