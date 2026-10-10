local M={modes={"Wait","Walk","Run","Dash"}}
function M.next(level,delta)
    return math.max(1,math.min(#M.modes,level+delta))
end
function M.level(name)
    for i,node in ipairs(M.modes) do if node:lower()==tostring(name):lower() then return i end end
    return 1
end
-- One active ox, one bounded movement command. Special actions remain native.
function M.is_move(node)
    return node=="Wait" or node=="Walk" or node=="Run" or node=="Dash"
end
function M.can_command(actor,include_turn)
    if not actor or not actor:get_Valid() then return false end
    local ok,blocked=pcall(function() return actor:get_IsDamage() or actor:get_IsDead() end)
    if ok and blocked then return false end
    local manager=actor["<ActionManager>k__BackingField"]
    local current=manager and manager.CurrentActionList and manager.CurrentActionList[0]
    return current~=nil and (M.is_move(current.Name) or (include_turn and current.Name=="TurnTarget"))
end
function M.clear() M.command=nil end
function M.hold(actor,node,seconds,now)
    assert(M.is_move(node),"Unsupported cart speed")
    M.command={actor=actor,address=actor:get_address(),node=node,until_time=now+seconds}
end
function M.expire(actor,now)
    local q=M.command
    if q and (not actor or not actor:get_Valid() or actor:get_address()~=q.address or now>=q.until_time) then M.clear() end
end
function M.issue(fn)
    M.issuing=(M.issuing or 0)+1
    local result=table.pack(pcall(fn))
    M.issuing=M.issuing-1
    if not result[1] then error(result[2],0) end
    return table.unpack(result,2,result.n)
end
function M.resume_turn(actor,now,suspended,request)
    if suspended then return end
    M.expire(actor,now)
    local q=M.command
    if not q or (q.node~="Run" and q.node~="Dash") or not M.can_command(actor,true) then return end
    local current=actor["<ActionManager>k__BackingField"].CurrentActionList[0].Name
    if not q.turning and current~="TurnTarget" then return end
    -- Recover a turn already entered through another native path, without
    -- renewing the original speed deadline.
    M.issue(function() request(q.node) end)
    q.turning=nil
    return q.node
end
function M.blocks(actor,node,layer,now,suspended)
    if suspended or (M.issuing or 0)>0 or layer~=0 then return false end
    local q=M.command
    if not q or actor:get_address()~=q.address then return false end
    M.expire(actor,now)
    if not M.command then return false end
    if node=="TurnTarget" then
        if q.node~="Run" and q.node~="Dash" then return false end
        if not M.can_command(actor,true) then M.clear();return false end
        return true -- Do not enter the native deceleration action during a speed hold.
    end
    if not M.is_move(node) then M.clear();return false end
    if q.turning then return false end -- Allow the native turn-to-locomotion transition.
    return node~=q.node
end
return M
