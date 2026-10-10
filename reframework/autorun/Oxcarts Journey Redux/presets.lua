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
function M.init(options, cursor, persist, normalize, passenger_builtins)
    M.options,M.cursor,M.persist,M.normalize=options,cursor,persist,normalize
    M.passenger_builtins=passenger_builtins or {}
    return M
end
local function plain_name(name) return (name or "Unnamed Preset"):gsub("^%[%d+%]%s*","") end
function M.reindex()
    if not M.options then return end
    for _,family in ipairs(families) do
        for i,p in ipairs(M.options.Presets[family]) do
            local name=plain_name(p.name)
            p.name="["..i.."] "..name
            p.enabled=true
            p.skipPassenger=p.skipPassenger==true
        end
    end
end
function M.attach(settings,builtins)
    local options = assert(M.options,"Journey presets must load first")
    local upgrading=(tonumber(options.UnifiedVersion) or 0)<2
    M.factories={}
    M.removed_imports=0
    for _,family in ipairs(families) do
        local legacy_driver,default_driver
        for _,p in ipairs(settings.presets) do if p.family==family then legacy_driver=p;break end end
        for _,p in ipairs(builtins or {}) do if p.family==family then default_driver=p;break end end
        M.factories[family]={}
        for i,source in ipairs(M.passenger_builtins[family] or {}) do
            local p=copy(source)
            p.builtin_id="passenger:"..family..":"..i
            p.driver=p.driver or copy(default_driver and default_driver.slots[1] or driver_slot())
            p.driver_camera=p.driver_camera or copy(default_driver and default_driver.camera or camera())
            p.skipPassenger=p.skipPassenger==true
            M.factories[family][i]=p
        end
        local list=options.Presets[family]
        for i=#list,1,-1 do
            local p=list[i]
            if p.driver_builtin_id~=nil or (p.name or ""):find("(driver import",1,true) then
                table.remove(list,i);M.removed_imports=M.removed_imports+1
            end
        end
        if #list==0 then
            for _,source in ipairs(M.factories[family]) do list[#list+1]=copy(source) end
        end
        for _,p in ipairs(options.Presets[family]) do
            p.enabled=true
            p.driver=p.driver or copy(legacy_driver and legacy_driver.slots[1] or driver_slot())
            p.driver_camera=p.driver_camera or copy(legacy_driver and legacy_driver.camera or camera())
            for _,source in ipairs(M.factories[family]) do
                if p.builtin_id==source.builtin_id or (upgrading and plain_name(p.name)==plain_name(source.name)) then
                    p.builtin_id=source.builtin_id;break
                end
            end
        end
        M.cursor[family]=math.max(1,math.min(M.cursor[family] or 1,#list))
    end
    options.UnifiedVersion=2
    M.normalize({Presets=M.factories})
    M.normalize()
    if type(options.ManualSettings) == "table" then
        for k,v in pairs(options.ManualSettings) do settings[k]=copy(v) end
    end
    settings.freeze_companion_fsm=true
    M.settings=settings
    M.refresh()
    M.save_driver()
end
function M.restore_builtins()
    local changed=false
    for _,family in ipairs(families) do
        local old=M.options.Presets[family]
        local active=old[M.cursor[family] or 1]
        local list,restored={},{}
        for _,source in ipairs(M.factories[family]) do
            local target
            for _,p in ipairs(old) do if p.builtin_id==source.builtin_id then target=p;break end end
            target=target or {}
            for key in pairs(target) do target[key]=nil end
            for key,value in pairs(copy(source)) do target[key]=value end
            list[#list+1]=target;restored[target]=true;changed=true
        end
        for _,p in ipairs(old) do if not restored[p] then list[#list+1]=p end end
        if #list>0 then
            M.options.Presets[family]=list
            M.cursor[family]=1
            for i,p in ipairs(list) do if p==active then M.cursor[family]=i;break end end
        end
    end
    if changed then M.normalize();M.refresh();M.persist() end
    return changed
end
function M.passenger_eligible(preset)
    return preset and preset.enabled~=false and preset.skipPassenger~=true
end
function M.next_passenger(family,start)
    local list=M.options.Presets[family] or {}
    if #list==0 then return nil end
    for n=1,#list do
        local i=((start or 0)+n-1)%#list+1
        if M.passenger_eligible(list[i]) then return i end
    end
    return nil
end
function M.refresh()
    if not M.settings then return end
    M.reindex()
    local selected=M.settings.presets and M.settings.presets[M.settings.preset]
    local family=selected and selected.family or "Normal"
    local flat={}
    local selected_index
    for _,kind in ipairs(families) do
        for i,p in ipairs(M.options.Presets[kind]) do
            M.driver_for(p)
            M.camera_for(p,true)
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
    dst.passenger_camera=copy(src.passenger_camera)
end
function M.camera_for(preset,passenger)
    local _,driver_camera=M.driver_for(preset)
    if not passenger then return driver_camera end
    if type(preset.passenger_camera)~='table' then preset.passenger_camera=copy(driver_camera) end
    local c=preset.passenger_camera
    local function bounded(key,default,lo,hi)
        local n=tonumber(c[key]) or default
        if n~=n or math.abs(n)==math.huge then n=default end
        c[key]=math.max(lo,math.min(hi,n))
    end
    bounded('fov',60,20,120);bounded('distance',1,0,10)
    c.fov_enabled,c.distance_enabled=c.fov_enabled==true,c.distance_enabled==true
    return c
end
return M
