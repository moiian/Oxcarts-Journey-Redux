-- Companion-only display correction. No actor Transform, physics or FSM writes.
local M={states={}}
local function valid(o)
    local ok,v=pcall(function() return o and o:get_Valid() end)
    return ok and v==true
end
local function restore(s)
    local item=s and s.applied
    if not item then return end
    s.applied=nil
    pcall(function()
        if not valid(s.hip) then return end
        local p=s.hip:get_Position()
        if math.abs(p.x-item.x)+math.abs(p.y-item.y)+math.abs(p.z-item.z)<0.0001 then
            s.hip:set_Position(Vector3f.new(item.ox,item.oy,item.oz))
        end
    end)
end
function M.invalidate(binding)
    if not binding then return end
    restore(M.states[binding]);M.states[binding]=nil
end
function M.restore()
    for _,s in pairs(M.states) do restore(s) end
end
function M.clear()
    M.restore();M.states={};_G.OJR_PelvisCompensationActive=false
end
function M.tick(bindings,anchor,player,enabled,now)
    now=now or os.clock()
    _G.OJR_PelvisCompensationActive=enabled==true
    if not enabled then M.clear();return end
    local debug_stop=rawget(_G,"OJR_StopDebugPelvisTest")
    if type(debug_stop)=="function" then pcall(debug_stop) end
    if not valid(anchor) then M.clear();return end
    local up=anchor:get_AxisY()
    local length=math.sqrt(up.x*up.x+up.y*up.y+up.z*up.z)
    if length<0.0001 then M.clear();return end
    local ux,uy,uz=up.x/length,up.y/length,up.z/length
    local seen={}
    for _,binding in pairs(bindings) do
        if binding.char~=player and binding.slot and valid(binding.char) then
            seen[binding]=true
            local s=M.states[binding]
            if not s then s={ready_at=now+0.3};M.states[binding]=s end
            if not s.failed then
                local ok,err=pcall(function()
                    if now<s.ready_at then return end
                    if binding.fsm_freeze_frame and binding.fsm_machine and binding.fsm_machine:call("get_Enabled()")~=false then return end
                    local tr=binding.char:get_Transform()
                    if s.hip and not valid(s.hip) then s.searched=false end
                    if not valid(s.hip) then
                        s.hip=nil
                        if s.searched then return end
                        s.searched=true
                        for _,joint in pairs(tr:get_Joints():get_elements() or {}) do
                            if valid(joint) and tostring(joint:get_Name()):lower()=="hip" then s.hip=joint;break end
                        end
                        if not s.hip then return end
                        s.baseline=nil
                    end
                    local p=s.hip:get_Position()
                    -- A second display callback need not undo/reapply the same pose.
                    if s.applied and math.abs(p.x-s.applied.x)+math.abs(p.y-s.applied.y)+math.abs(p.z-s.applied.z)<0.00001 then return end
                    s.applied=nil
                    local actor=tr:get_Position()
                    local offset=(p.x-actor.x)*ux+(p.y-actor.y)*uy+(p.z-actor.z)*uz
                    if s.baseline==nil then s.baseline=offset end
                    local delta=s.baseline-offset
                    if math.abs(delta)>0.0001 then
                        local x,y,z=p.x+ux*delta,p.y+uy*delta,p.z+uz*delta
                        s.hip:set_Position(Vector3f.new(x,y,z))
                        s.applied={x=x,y=y,z=z,ox=p.x,oy=p.y,oz=p.z}
                    end
                end)
                if not ok then
                    restore(s);s.failed=true
                    log.error("[OJR] Companion pelvis compensation unavailable: "..tostring(err))
                end
            end
        end
    end
    for binding,s in pairs(M.states) do
        if not seen[binding] then restore(s);M.states[binding]=nil end
    end
end
return M
