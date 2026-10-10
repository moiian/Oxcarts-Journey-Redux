-- Display-only actor Transform placement. No skeleton, context or controller writes.
local M={states={}}
local function valid(o)
    local ok,v=pcall(function() return o and o:get_Valid() end)
    return ok and v==true
end
local function vec(p) return Vector3f.new(p.x,p.y,p.z) end
local function quat(q) return Quaternion.new(q.x,q.y,q.z,q.w) end
local function restore(s,force)
    if not s or not s.applied then return end
    s.applied=false
    if not valid(s.char) then return end
    local tr=s.char:get_Transform()
    local p,q=tr:get_Position(),tr:get_Rotation()
    local matches=s.target and s.turn
        and math.abs(p.x-s.target.x)+math.abs(p.y-s.target.y)+math.abs(p.z-s.target.z)<0.0001
        and math.abs(q.x-s.turn.x)+math.abs(q.y-s.turn.y)+math.abs(q.z-s.turn.z)+math.abs(q.w-s.turn.w)<0.0001
    if force or matches then tr:set_Position(s.position);tr:set_Rotation(s.rotation) end
end
function M.restore()
    for _,s in pairs(M.states) do pcall(restore,s) end
end
function M.restore_binding(binding) pcall(restore,M.states[binding]) end
function M.release(binding)
    if not binding then return end
    pcall(restore,M.states[binding]);M.states[binding]=nil
end
function M.clear() M.restore();M.states={} end
function M.apply(binding,anchor)
    if not binding.root_spec or not valid(binding.char) then return end
    local s=M.states[binding]
    if not s then s={char=binding.char};M.states[binding]=s end
    if s.failed then return end
    local ok,err=pcall(function()
        restore(s)
        assert(valid(anchor),'Companion display anchor unavailable')
        local tr=binding.char:get_Transform()
        local spec=binding.seat_spec
        local p,x,y,z=anchor:get_Position(),anchor:get_AxisX(),anchor:get_AxisY(),anchor:get_AxisZ()
        local target=Vector3f.new(p.x+x.x*spec.x+y.x*spec.y+z.x*spec.z,
            p.y+x.y*spec.x+y.y*spec.y+z.y*spec.z,p.z+x.z*spec.x+y.z*spec.y+z.z*spec.z)
        local lx,lz=spec.lookX,spec.lookZ
        if lx==0 and lz==0 then lx=1 end
        local facing=Vector3f.new(target.x+x.x*lx+z.x*lz,
            target.y+x.y*lx+z.y*lz,target.z+x.z*lx+z.z*lz)
        s.position,s.rotation=vec(tr:get_Position()),quat(tr:get_Rotation())
        s.applied=true
        tr:set_Position(target)
        tr:lookAt(facing,y)
        s.target,s.turn=vec(tr:get_Position()),quat(tr:get_Rotation())
    end)
    if not ok then
        pcall(restore,s,true);s.failed=true
        log.error('[OJR] Companion Transform display unavailable: '..tostring(err))
    end
end
function M.commit(binding,anchor)
    if not binding or not binding.root_spec or not valid(binding.char) then M.release(binding);return end
    -- Keep the current display destination for the caller's physical exit sync.
    if valid(anchor) then M.apply(binding,anchor) end
    M.states[binding]=nil
end
function M.tick(bindings,anchor_for)
    local seen={}
    for _,binding in ipairs(bindings) do
        if binding.root_spec and valid(binding.char) then
            seen[binding]=true;M.apply(binding,anchor_for(binding.char))
        end
    end
    for binding in pairs(M.states) do if not seen[binding] then M.release(binding) end end
end
return M
