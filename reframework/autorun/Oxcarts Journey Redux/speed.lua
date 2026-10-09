local M={modes={"Wait","Walk","Run","Dash"}}
function M.next(level,delta)
    return math.max(1,math.min(#M.modes,level+delta))
end
function M.level(name)
    for i,node in ipairs(M.modes) do if node:lower()==tostring(name):lower() then return i end end
    return 1
end
return M
