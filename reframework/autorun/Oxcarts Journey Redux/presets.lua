-- One persisted layout owns both player seats and all companion positions.
local M = {}
local families = {"Normal", "Rainy", "Wealthy"}
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k,v in pairs(t) do if k ~= "_canonical" then out[k] = copy(v) end end
    return out
end
local function camera()
    return {fov_enabled=false,fov=60,distance_enabled=false,distance=1}
end
local function driver_slot()
    return {x=-0.071,y=0.920,z=0.274,yaw=178,randomIdle=false}
end
function M.init(options, cursor, persist, normalize)
    M.options,M.cursor,M.persist,M.normalize=options,cursor,persist,normalize
    return M
end
function M.attach(settings,builtins)
    local options = assert(M.options,"Journey presets must load first")
    if options.UnifiedVersion ~= 1 then
        -- Preserve every existing OJR layout. Import LMD layouts as additional
        -- variants rather than guessing which conflicting companion layout wins.
        for _,family in ipairs(families) do
            local fallback
            for _,p in ipairs(settings.presets) do if p.family==family then fallback=p;break end end
            for _,p in ipairs(options.Presets[family]) do
                p.driver=copy(fallback and fallback.slots[1] or driver_slot())
                p.driver_camera=copy(fallback and fallback.camera or camera())
            end
        end
        for _,old in ipairs(settings.presets) do
            local list=options.Presets[old.family]
            local p=copy(list[1])
            p.name=old.name .. " (driver import)"
            p.enabled=old.enabled~=false
            p.driver,p.driver_camera=copy(old.slots[1]),copy(old.camera)
            p.driver_builtin_id=old.builtin_id
            for i=1,9 do
                local slot=copy(old.slots[i+1])
                if slot then
                    local a=math.rad(slot.yaw or 0)
                    slot.lookX,slot.lookZ=math.sin(a),math.cos(a)
                    slot.yaw,slot.freezeFsm,slot.useOxAnchor=nil,nil,nil
                    p.pawns[i]=slot
                end
            end
            list[#list+1]=p
        end
        options.ManualSettings={}
        options.UnifiedVersion=1
    end
    for _,family in ipairs(families) do
        for _,p in ipairs(options.Presets[family]) do
            p.driver=p.driver or driver_slot()
            p.driver_camera=p.driver_camera or camera()
        end
    end
    if type(options.ManualSettings) == "table" then
        for k,v in pairs(options.ManualSettings) do settings[k]=copy(v) end
    end
    settings.freeze_companion_fsm=true
    M.settings=settings
    M.builtins=builtins or {}
    M.refresh()
    M.save_driver()
end
function M.restore_builtins()
    local changed=false
    for _,family in ipairs(families) do
        for _,p in ipairs(M.options.Presets[family]) do
            for _,source in ipairs(M.builtins or {}) do
                if p.driver_builtin_id==source.builtin_id then
                    p.driver,p.driver_camera=copy(source.slots[1]),copy(source.camera)
                    for i,slot in ipairs(source.slots) do
                        if i>1 then
                            local s=copy(slot)
                            local a=math.rad(s.yaw or 0)
                            s.lookX,s.lookZ=math.sin(a),math.cos(a)
                            s.yaw,s.freezeFsm,s.useOxAnchor=nil,nil,nil
                            p.pawns[i-1]=s
                        end
                    end
                    changed=true
                    break
                end
            end
        end
    end
    if changed then M.normalize();M.persist();M.refresh() end
    return changed
end
function M.refresh()
    if not M.settings then return end
    local selected=M.settings.presets and M.settings.presets[M.settings.preset]
    local family=selected and selected.family or "Normal"
    local flat={}
    local selected_index
    for _,kind in ipairs(families) do
        for i,p in ipairs(M.options.Presets[kind]) do
            M.driver_for(p)
            local slots={p.driver}
            for n=1,9 do
                local slot=copy(p.pawns[n])
                slot.yaw=math.deg(math.atan(slot.lookX or 0,slot.lookZ or 1))
                slots[n+1]=slot
            end
            flat[#flat+1]={name=p.name,family=kind,enabled=p.enabled~=false,
                camera=p.driver_camera,slots=slots,_canonical=p,_index=i}
            if kind==family and i==(M.cursor[kind] or 1) then selected_index=#flat end
        end
    end
    M.settings.presets=flat
    M.settings.preset=selected_index or 1
end
function M.activate(index)
    local p=M.settings and M.settings.presets[index]
    if not p or p.enabled==false then return false end
    -- Resolve by identity; a UI deletion must not apply a shifted old index.
    for i,canonical in ipairs(M.options.Presets[p.family]) do
        if canonical==p._canonical then
            M.cursor[p.family]=i
            M.settings.preset=index
            return true
        end
    end
    return false
end
function M.save_driver()
    local target={}
    for _,key in ipairs({"sensitivity","bindings","shoulder_binding_rule","entry_hold_binding_rule"}) do
        if M.settings[key]~=nil then target[key]=copy(M.settings[key]) end
    end
    M.options.ManualSettings=target
    M.persist()
end
function M.driver_for(preset)
    preset.driver=preset.driver or driver_slot()
    preset.driver_camera=preset.driver_camera or camera()
    local function bounded(t,key,default,lo,hi)
        local n=tonumber(t[key]) or default
        if n~=n or math.abs(n)==math.huge then n=default end
        t[key]=math.max(lo,math.min(hi,n))
    end
    local d,c=preset.driver,preset.driver_camera
    for _,key in ipairs({"x","y","z"}) do bounded(d,key,driver_slot()[key],-10,10) end
    bounded(d,"yaw",178,-180,180)
    d.randomIdle,d.useOxAnchor=false,nil
    bounded(c,"fov",60,20,120);bounded(c,"distance",1,0,10)
    c.fov_enabled,c.distance_enabled=c.fov_enabled==true,c.distance_enabled==true
    return preset.driver,preset.driver_camera
end
function M.clone_player_seats(src,dst)
    dst.driver,dst.driver_camera=copy(src.driver),copy(src.driver_camera)
end
return M
