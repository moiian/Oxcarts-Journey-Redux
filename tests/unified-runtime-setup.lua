-- Multiple modules must coexist in the same host callback/hook lists.
local registrations={}
re.on_application_entry=function(name,fn)
    registrations[name]=registrations[name] or {}
    table.insert(registrations[name],fn)
    callbacks[name]=function() for _,f in ipairs(registrations[name]) do f() end end
end
local resets={}
re.on_script_reset=function(fn)
    resets[#resets+1]=fn
    callbacks.reset=function() for _,f in ipairs(resets) do f() end end
end
local errors={}
log.error=function(err) errors[#errors+1]=tostring(err) end
local hook_lists={}
sdk.hook=function(method,pre)
    hook_lists[method]=hook_lists[method] or {}
    if pre then table.insert(hook_lists[method],pre) end
    hooks[method]=function(args)
        local skip
        for _,fn in ipairs(hook_lists[method]) do
            if fn(args)==sdk.PreHookResult.SKIP_ORIGINAL then skip=sdk.PreHookResult.SKIP_ORIGINAL end
        end
        return skip
    end
end
local old_object=object
object=function(...)
    local ch=old_object(...)
    function ch.am:requestActionCore(priority,node,layer)
        return self:call('requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)',priority,node,layer)
    end
    return ch
end
for _,ch in ipairs({human,ox,cow,driver,pawns[1],pawns[2],pawns[3]}) do
    function ch.am:requestActionCore(priority,node,layer)
        return self:call('requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)',priority,node,layer)
    end
end
function status:get_address() return 2222 end
function status:get_isPayMoney() return true end
function pm:getPartyPawnID(pawn)
    if pawn:get_CachedCharacter()==pawns[2] then return 1 end
    return 2
end
function human:get_Input() return {isButtonTrigger=function() return false end} end
function gui:isPausedGUI() return is_paused end
function body:get_UniversalPosition() return vec(self.pos.x+384,self.pos.y,self.pos.z-1024) end
local old_json_load=json.load_file
json.load_file=function(name)
    if name=='LetMeDriveOxcart.json' then return old_json_load(name) end
    if name=='OxcartsJourneyRedux.json' then return rawget(_G,'OJR_TEST_CONFIG') end
end
thread={get_hook_storage=function() return {} end}
_G.OJR_UnifiedPresets=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/presets.lua'))()
_G.OJR_UnifiedSpeed=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/speed.lua'))()
_G.OJR_PassengerHud=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/hud.lua'))()
_G.OJR_CartProtection=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/protection.lua'))()
_G.OJR_RuntimeDiagnostics=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/diagnostics.lua'))()
assert(loadfile('reframework/autorun/Oxcarts Journey Redux/journey.lua'))()
