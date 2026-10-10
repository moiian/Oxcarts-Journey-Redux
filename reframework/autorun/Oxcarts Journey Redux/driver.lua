-- Native driver interaction and manual steering for the unified OJR runtime.
-- Game type/method names are runtime identifiers, not bundled mod dependencies.
local TITLE = "Let me drive oxcart"
local unified_presets = assert(rawget(_G,"OJR_UnifiedPresets"))
local CONFIG = "LetMeDriveOxcart.json"
local MAX_COMPANIONS = 9 -- Player driver is stored separately in slots[1].
local bus = rawget(_G, "DD2_OxcartControl") or { version = 1 }
_G.DD2_OxcartControl = bus
-- A previous failed reset may have left this script's lease behind.
if bus.owner == TITLE then bus.owner, bus.heartbeat = nil, nil end
local state = { active = false, level = 1, axis = 0, error = nil, seats = {}, protected = {}, behavior_frame = 0 }
-- Private controller functions shared by the native driving paths.
local driver_runtime = {}
local speed_control = assert(rawget(_G,"OJR_UnifiedSpeed"))
local modes = speed_control.modes
local settings = { sensitivity = 45, freeze_companion_fsm = true,
    preset = 1, presets = {
    { name = "Driver and passengers", slots = {
        { x = -0.071, y = 0.920, z = 0.274, yaw = 178, randomIdle = false },
        { x = 0.85, y = 0.23, z = -3.35, yaw = 90 },
        { x = -0.85, y = 0.23, z = -3.35, yaw = -90 },
        { x = 0.85, y = 0.23, z = -4.1, yaw = 90 },
    } },
} }
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function root_offset(value, lo, hi)
    local n = tonumber(value) or 0
    if n ~= n or math.abs(n) == math.huge then n = 0 end
    return clamp(n, lo, hi)
end
local function copy_camera(value,fallback)
    value=type(value)=="table" and value or fallback or {}
    local function bounded(n,default,lo,hi)
        n=tonumber(n) or default
        if n~=n or math.abs(n)==math.huge then n=default end
        return clamp(n,lo,hi)
    end
    return {fov_enabled=value.fov_enabled==true,fov=bounded(value.fov,60,20,120),
        distance_enabled=value.distance_enabled==true,distance=bounded(value.distance,1,0,10)}
end
local function current_camera() return settings.presets[settings.preset].camera end
local front_offset = rawget(_G, "AelinoreCartFrontOffset")
if not front_offset then
    local stored
    local ok, value = pcall(function() return json.load_file("OxcartFrontProbe.json") end)
    if ok and type(value) == "table" then stored = value end
    front_offset = {x=0,y=0,z=1.5}
    for _, key in ipairs({"x","y","z"}) do
        if stored and tonumber(stored[key]) then front_offset[key] = root_offset(stored[key], -10, 10) end
    end
    _G.AelinoreCartFrontOffset = front_offset
end
local families = { "Normal", "Rainy", "Wealthy" }
local family_names = { "Normal oxcart", "Rainproof oxcart", "Luxury oxcart" }
local function expand_companion_slots(layout)
    -- Preserve all existing seats; only supply missing passenger parameters.
    for i=2,MAX_COMPANIONS+1 do
        if not layout.slots[i] then
            for row=0,4 do
                for _,x in ipairs({0.85,-0.85,0}) do
                    local z=-1.1-row*0.8
                    local free=true
                    for _,other in ipairs(layout.slots) do
                        if (other.x-x)^2+(other.z-z)^2<0.65^2 then free=false;break end
                    end
                    if free then
                        layout.slots[i]={x=x,y=0.23,z=z,yaw=x<0 and -90 or 90,
                            anim="SitOnChairActions",randomIdle=true}
                        break
                    end
                end
                if layout.slots[i] then break end
            end
            -- Extreme custom layouts can occupy every candidate; still provide
            -- a valid, editable fallback rather than an incomplete preset.
            if not layout.slots[i] then
                layout.slots[i]={x=0,y=0.23,z=-1.1-(i-2)*0.8,yaw=180,
                    anim="SitOnChairActions",randomIdle=true}
            end
        end
    end
    return layout
end
local function copy_layout(source, name, family)
    local result = { name = name, family = family, enabled = true,
        pawns_customized = source.pawns_customized, slots = {},
        camera=copy_camera(source.camera) }
    for i, slot in ipairs(source.slots) do
        result.slots[i] = {}
        for key, value in pairs(slot) do result.slots[i][key] = value end
    end
    return expand_companion_slots(result)
end
local builtin_presets = {
    {camera={distance=3.9820001125335693,distance_enabled=true,fov=60.84600067138672,fov_enabled=true},enabled=true,family="Normal",name="Normal - Default 1",pawns_customized=true,slots={{randomIdle=false,useOxAnchor=false,x=-0.050999999046325684,y=0.9200000166893005,yaw=178,z=0.33399999141693115},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=0.85,y=0.23,yaw=90.0,z=-2.5999999046325684},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=-0.85,y=0.23,yaw=-90.0,z=-3.35},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=-0.85,y=0.23,yaw=-90.0,z=-2.5}},builtin_id="Normal:1",legacy_name="Layout 3"},
    {camera={distance=4.803999900817871,distance_enabled=true,fov=75.33699798583984,fov_enabled=true},enabled=true,family="Rainy",name="Rainproof - Default 1",pawns_customized=true,slots={{anim="SitOnChairActions",randomIdle=false,x=-0.051,y=0.92,yaw=178,z=0.334},{anim="SitOnChairActions",randomIdle=true,x=0.85,y=0.23,yaw=90,z=-3.35},{anim="SitOnChairActions",randomIdle=true,x=-0.85,y=0.23,yaw=-90,z=-3.35},{anim="SitOnChairActions",randomIdle=true,x=-0.85,y=0.23,yaw=-90,z=-2.5}},builtin_id="Rainy:1",legacy_name="Rainy - Default"},
    {camera={distance=5.704999923706055,distance_enabled=true,fov=75.33699798583984,fov_enabled=true},enabled=true,family="Wealthy",name="Luxury - Default 1",pawns_customized=true,slots={{anim="SitOnChairActions",randomIdle=false,x=0.0,y=0.92,yaw=180,z=0.274},{anim="SitOnChairActions",randomIdle=true,x=0.45,y=0.23,yaw=180,z=-3.15},{anim="SitOnChairActions",randomIdle=true,x=-0.5,y=0.23,yaw=0,z=-1.2},{anim="SitOnChairActions",randomIdle=true,x=0.5,y=0.23,yaw=0,z=-1.25}},builtin_id="Wealthy:1",legacy_name="Wealthy - Default"},
    {camera={distance=3.9820001125335693,distance_enabled=true,fov=60.84600067138672,fov_enabled=true},enabled=true,family="Normal",name="Normal - Default 2",pawns_customized=true,slots={{randomIdle=false,useOxAnchor=false,x=-0.25099998712539673,y=0.9200000166893005,yaw=178,z=0.33399999141693115},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=0.3100000023841858,y=0.9200000166893005,yaw=180.0,z=0.30000001192092896},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=-0.8999999761581421,y=0.23,yaw=-97.0,z=-4.179999828338623},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=0.8799999952316284,y=0.3100000023841858,yaw=90.0,z=-2.5}},builtin_id="Normal:2",legacy_name="Layout 5"},
    {camera={distance=3.9820001125335693,distance_enabled=true,fov=60.84600067138672,fov_enabled=true},enabled=true,family="Normal",name="Normal - Default 3",pawns_customized=true,slots={{randomIdle=false,useOxAnchor=false,x=-0.050999999046325684,y=0.9200000166893005,yaw=178,z=0.33399999141693115},{anim="LivSitChairCrosslegs",bankID=0,freezeFsm=true,motionID=0,randomIdle=false,useDirectMotion=false,useOxAnchor=false,x=1.440000057220459,y=0.7900000214576721,yaw=90.0,z=-1.3200000524520874},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=-1.3300000429153442,y=0.7900000214576721,yaw=-90.0,z=-3.35},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=-0.85,y=0.23,yaw=-90.0,z=-2.5}},builtin_id="Normal:3",legacy_name="Layout 6"},
    {camera={distance=3.9820001125335693,distance_enabled=true,fov=60.84600067138672,fov_enabled=true},enabled=true,family="Normal",name="Normal - Default 4",pawns_customized=true,slots={{randomIdle=false,useOxAnchor=false,x=-0.050999999046325684,y=0.9200000166893005,yaw=178,z=0.33399999141693115},{anim="LivSitChairCrosslegs",bankID=0,freezeFsm=true,motionID=0,randomIdle=false,useDirectMotion=false,useOxAnchor=false,x=1.2200000286102295,y=0.7900000214576721,yaw=-96.0,z=-1.3200000524520874},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=0.7799999713897705,y=0.28999999165534973,yaw=90.0,z=-3.4000000953674316},{anim="SitOnChairActions",bankID=0,freezeFsm=true,motionID=0,randomIdle=true,useDirectMotion=false,useOxAnchor=false,x=-0.85,y=0.23,yaw=-90.0,z=-2.5}},builtin_id="Normal:4",legacy_name="Layout 7"},
    {camera={distance=5.704999923706055,distance_enabled=true,fov=75.33699798583984,fov_enabled=true},enabled=true,family="Wealthy",name="Luxury - Default 2",pawns_customized=true,slots={{anim="SitOnChairActions",randomIdle=false,x=-0.3100000023841858,y=0.92,yaw=180,z=0.274},{anim="SitOnChairActions",randomIdle=true,x=0.28999999165534973,y=0.8600000143051147,yaw=180,z=0.2800000011920929},{anim="SitOnChairActions",randomIdle=true,x=-0.5,y=0.23,yaw=0,z=-1.2},{anim="SitOnChairActions",randomIdle=true,x=0.5,y=0.23,yaw=0,z=-1.25}},builtin_id="Wealthy:2",legacy_name="Layout 8"},
    {camera={distance=5.704999923706055,distance_enabled=true,fov=75.33699798583984,fov_enabled=true},enabled=true,family="Wealthy",name="Luxury - Default 3",pawns_customized=true,slots={{anim="SitOnChairActions",randomIdle=false,x=-0.3100000023841858,y=0.92,yaw=180,z=0.274},{anim="SitOnChairActions",randomIdle=true,x=0.28999999165534973,y=0.8600000143051147,yaw=180,z=0.2800000011920929},{anim="LivSitChairCrosslegs",randomIdle=true,x=-0.5,y=0.33000001311302185,yaw=0,z=-4.510000228881836},{anim="SitOnChairActions",randomIdle=true,x=1.2899999618530273,y=0.75,yaw=-98.0,z=-1.090000033378601}},builtin_id="Wealthy:3",legacy_name="Layout 9"},
    {camera={distance=5.704999923706055,distance_enabled=true,fov=75.33699798583984,fov_enabled=true},enabled=true,family="Wealthy",name="Luxury - Default 4",pawns_customized=true,slots={{anim="SitOnChairActions",randomIdle=false,x=-0.3100000023841858,y=0.92,yaw=180,z=0.274},{anim="LivSitChairCrosslegs",randomIdle=false,x=0.28999999165534973,y=3.0399999618530273,yaw=180,z=0.05000000074505806},{anim="LivSitChairCrosslegs",randomIdle=false,x=0.49000000953674316,y=0.5299999713897705,yaw=0,z=-4.510000228881836},{anim="SitOnChairActions",randomIdle=true,x=0.5,y=0.23,yaw=0,z=-1.25}},builtin_id="Wealthy:4",legacy_name="Layout 10"},
    {camera={distance=4.803999900817871,distance_enabled=true,fov=75.33699798583984,fov_enabled=true},enabled=true,family="Rainy",name="Rainproof - Default 2",pawns_customized=true,slots={{anim="SitOnChairActions",randomIdle=false,x=-0.3310000002384186,y=0.92,yaw=178,z=0.334},{anim="SitOnChairActions",randomIdle=true,x=0.3199999928474426,y=0.9300000071525574,yaw=171.0,z=0.2800000011920929},{anim="SitOnChairActions",randomIdle=true,x=-0.8999999761581421,y=0.23,yaw=-90,z=-4.269999980926514},{anim="SitOnChairActions",randomIdle=true,x=1.0199999809265137,y=0.23,yaw=88.0,z=-2.5}},builtin_id="Rainy:2",legacy_name="Layout 10"},
}
local function clone_builtin(source)
    local layout=copy_layout(source,source.name,source.family)
    layout.builtin_id=source.builtin_id
    return layout
end
local function default_layout(family)
    for _,source in ipairs(builtin_presets) do
        if source.family==family then return clone_builtin(source) end
    end
end
local function attempt(fn) local ok, value = pcall(fn); if ok then return value end end
local function valid(obj) return obj and attempt(function() return obj:get_Valid() end) == true end
local function address(obj) return obj and attempt(function() return obj:get_address() end) end
local function singleton(name) return sdk.get_managed_singleton(name) end
local function save()
    if unified_presets.settings then unified_presets.save_driver() end
end
local saved = attempt(function() return json.load_file(CONFIG) end)
if type(saved) == "table" then
    settings.freeze_companion_fsm=saved.freeze_companion_fsm~=false
    settings.sensitivity = clamp(tonumber(saved.sensitivity) or 45, 5, 180)
    -- Validate persisted layouts before allowing them to write actor transforms.
    if type(saved.presets) == "table" and #saved.presets > 0 then
        local layouts = {}
        for _, layout in ipairs(saved.presets) do
            if type(layout) == "table" and not layout.native_default and type(layout.slots) == "table"
                and #layout.slots >= 4 and #layout.slots <= MAX_COMPANIONS+1 then
                local copy = { name = tostring(layout.name or "Layout"), slots = {}, pawns_customized = layout.pawns_customized == true,
                    camera=layout.camera, family = layout.family, enabled = layout.enabled ~= false,
                    default_family = layout.default_family, builtin_id=layout.builtin_id }
                local complete = true
                for i, slot in ipairs(layout.slots) do
                    if type(slot) ~= "table" then complete = false; break end
                    copy.slots[i] = {}
                    for _, key in ipairs({ "x", "y", "z", "yaw" }) do
                        local n = tonumber(slot[key])
                        if not n or n ~= n or math.abs(n) > 1000 then complete = false; break end
                        copy.slots[i][key] = key=="yaw" and clamp(n,-180,180) or clamp(n,-10,10)
                    end
                    for _, key in ipairs({ "anim", "useOxAnchor", "randomIdle", "useDirectMotion", "freezeFsm", "bankID", "motionID" }) do
                        local value = slot[key]
                        if type(value) == "string" or type(value) == "boolean" or type(value) == "number" then copy.slots[i][key] = value end
                    end
                end
                if complete then layouts[#layouts + 1] = copy end
            end
        end
        if #layouts > 0 then settings.presets = layouts end
    end
    settings.preset = clamp(math.floor(tonumber(saved.preset) or 1), 1, #settings.presets)
end
-- Keep legacy FOV/distance settings; deprecated Camera offset is not imported.
local legacy_camera=type(saved)=="table" and {fov_enabled=saved.camera_fov_enabled,fov=saved.camera_fov,
    distance_enabled=saved.camera_distance_enabled,distance=saved.camera_distance} or nil
for _, layout in ipairs(settings.presets) do
    layout.camera=copy_camera(layout.camera,legacy_camera)
end
-- One-time migration from the old capture-on-takeover seat rule.
if type(saved) ~= "table" or saved.player_seat_rule ~= 1 then
    for _, layout in ipairs(settings.presets) do
        local slot = layout.slots[1]
        slot.x, slot.y, slot.z, slot.yaw = -0.071, 0.920, 0.274, 178
        slot.useOxAnchor = false
    end
end
settings.player_seat_rule = 1
local family_cursor = {}
for _, family in ipairs(families) do
    local value = type(saved) == "table" and type(saved.family_cursor) == "table" and tonumber(saved.family_cursor[family])
    if value and value == value and math.abs(value) ~= math.huge then family_cursor[family] = math.floor(value) end
end
settings.family_cursor = family_cursor
for i, layout in ipairs(settings.presets) do
    if layout.family ~= "Rainy" and layout.family ~= "Wealthy" then layout.family = "Normal" end
    layout.enabled = true -- All layouts of the matching family participate in cycling.
    if type(saved)~="table" or saved.native_pose_rule~=1 then layout.slots[1].randomIdle=false end
    for i=2,4 do if layout.slots[i].randomIdle==nil then layout.slots[i].randomIdle=true end end
    if layout.enabled and not family_cursor[layout.family] then family_cursor[layout.family] = i end
end
if type(saved) ~= "table" or saved.cart_family_rule ~= 1 then
    -- Keep old layouts intact; add the newly supplied measured defaults once.
    for _, family in ipairs(families) do
        settings.presets[#settings.presets + 1] = default_layout(family)
        family_cursor[family] = #settings.presets
    end
    if type(saved) ~= "table" then
        table.remove(settings.presets, 1)
        for _, family in ipairs(families) do family_cursor[family] = family_cursor[family] - 1 end
    end
    settings.preset = family_cursor.Normal
end
settings.cart_family_rule = 1
settings.native_pose_rule = 1
-- Import the approved snapshot once. Only exact old-name/parameter matches
-- become built-ins; unrelated user layouts are never claimed by name alone.
if type(saved)~="table" then
    settings.presets={};family_cursor={};settings.family_cursor=family_cursor
    for _,source in ipairs(builtin_presets) do settings.presets[#settings.presets+1]=clone_builtin(source) end
    settings.preset=1
elseif saved.builtin_presets_rule~=1 then
    local function matches(layout,source)
        if layout.family~=source.family or layout.name~=source.legacy_name then return false end
        for k,v in pairs(source.camera) do if layout.camera[k]~=v then return false end end
        for i,slot in ipairs(source.slots) do
            for k,v in pairs(slot) do if layout.slots[i][k]~=v then return false end end
        end
        return true
    end
    for _,source in ipairs(builtin_presets) do
        local found=false
        for _,layout in ipairs(settings.presets) do
            if not layout.builtin_id and matches(layout,source) then
                layout.builtin_id=source.builtin_id;layout.name=source.name;found=true;break
            elseif layout.builtin_id==source.builtin_id then found=true;break end
        end
        if not found then settings.presets[#settings.presets+1]=clone_builtin(source) end
    end
end
settings.builtin_presets_rule=1
for i,layout in ipairs(settings.presets) do
    expand_companion_slots(layout)
    if not family_cursor[layout.family] then family_cursor[layout.family]=i end
end
family_cursor[settings.presets[settings.preset].family] = settings.preset
local function cart_family(cart)
    local name = attempt(function() return cart.body:get_GameObject():get_Name() end) or ""
    if name:find("gm80_052", 1, true) then return "Wealthy" end
    if name == "gm80_042_00" then return "Normal" end
    if name:find("gm80_042", 1, true) then return "Rainy" end
    return "Normal"
end
local function choose_family(family, cycle, reset_first)
    if reset_first then
        for i, layout in ipairs(settings.presets) do
            if layout.family == family and layout.enabled then
                settings.preset, family_cursor[family], state.family = i, i, family
                return true
            end
        end
    end
    local candidates = {}
    for i, layout in ipairs(settings.presets) do
        if layout.family == family and layout.enabled then candidates[#candidates + 1] = i end
    end
    if #candidates == 0 then
        return false
    end
    local selected = family_cursor[family]
    for n, i in ipairs(candidates) do
        if i == (cycle and settings.preset or selected) then
            selected = cycle and candidates[n % #candidates + 1] or i
            break
        end
    end
    local found = false
    for _, i in ipairs(candidates) do if i == selected then found = true end end
    settings.preset = found and selected or candidates[1]
    family_cursor[family], state.family = settings.preset, family
    return true
end
local function select_family(cart, cycle, reset_first) return choose_family(cart_family(cart), cycle, reset_first) end

local function delete_current_layout(immediate)
    if state.stand_stopped then return end
    if not immediate then
        return driver_runtime.switch_preset(settings.preset,false,function() delete_current_layout(true) end)
    end
    local removed=settings.preset
    local family=settings.presets[removed].family
    local count=0
    for _,layout in ipairs(settings.presets) do if layout.family==family then count=count+1 end end
    -- Deleting the last layout recreates only this cart type's default.
    -- Construct it before removal: the last global layout may be the source.
    local replacement=count==1 and default_layout(family) or nil
    table.remove(settings.presets,removed)
    for _,kind in ipairs(families) do
        local cursor=family_cursor[kind]
        if cursor==removed then family_cursor[kind]=nil
        elseif cursor and cursor>removed then family_cursor[kind]=cursor-1 end
    end
    if replacement then settings.presets[#settings.presets+1]=replacement end
    choose_family(family,false)
    state.layout_changed=true
    save()
end

local function player()
    local cm = singleton("app.CharacterManager")
    return cm and cm["<ManualPlayer>k__BackingField"]
end
local DRIVER_IDS = { 963132753, 2619751808 } -- Nick; ch300680 (user-confirmed driver).
local function find_nearby_driver(manager, registered, body)
    local function distance(actor)
        if not valid(actor) then return math.huge end
        return attempt(function() return (actor:get_Transform():get_Position()-body:get_Position()):length() end) or math.huge
    end
    if distance(registered) <= 12 then return registered end
    local found, nearest = nil, 12.00001
    for _, id in ipairs(DRIVER_IDS) do
        local candidate = attempt(function() return manager:getCharacter(id) end)
        local range = distance(candidate)
        if range <= 12 and range < nearest then found, nearest = candidate, range end
    end
    return found
end
local function discover()
    local nm = singleton("app.NPCManager")
    local om = nm and nm.OxcartManager
    local go = om and om._RaidAttack_CachedGameObject
    if not valid(go) then return nil end
    local ox = go:call("getComponent(System.Type)", sdk.typeof("app.Character"))
    if not valid(ox) then return nil end
    local ch = ox.EnemyCtrl and ox.EnemyCtrl.Ch2
    local parts = ch and ch["<CachedConnectParts>k__BackingField"]
    local cow = parts and parts.CowChara
    if not valid(cow) then return nil end
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
    if not scene then return nil end
    local best, nearest = nil, 12
    for _, model in ipairs({ "gm80_042", "gm80_052", "gm81_004" }) do
        for suffix = -1, 10 do
            local name = suffix == -1 and model or string.format("%s_%02d", model, suffix)
            local body = scene:call("findGameObject(System.String)", name)
            if valid(body) then
                local transform = body:get_Transform()
                local distance = (transform:get_Position() - ox:get_Transform():get_Position()):length()
                if distance < nearest then best, nearest = transform, distance end
            end
        end
    end
    if not best then return nil end
    local anchor, child = best, best:get_Child()
    while child do
        if child:get_GameObject():get_Name():find("MoveFloor", 1, true) then anchor = child; break end
        child = child:get_Next()
    end
    local status = om:getStatus(ox:get_CharaID())
    local driver = status and attempt(function() return nm:getCharacter(status:call("getCurrentDriver")) end)
    driver = find_nearby_driver(nm, driver, best)
    return { ox = ox, cow = cow, body = best, anchor = anchor, driver = driver, status = status }
end
local function paused()
    local gui = singleton("app.GuiManager")
    if not gui then return true end
    return attempt(function() return gui:call("isPausedGUI()") end) == true
        or attempt(function() return gui:call("get_IsLoadGui()") end) == true
        or gui["<IsDispPhotoModeAll>k__BackingField"] == true
end
local function photo_active()
    local gui=singleton("app.GuiManager")
    if not gui or attempt(function() return gui:call("get_IsLoadGui()") end)==true then return false end
    return gui["<IsDispPhotoModeAll>k__BackingField"]==true
        or attempt(function() return gui:call("get_IsDispPhotoModeAll()") end)==true
end
local function action(actor, name, requested_priority)
    local am = actor["<ActionManager>k__BackingField"] or actor:get_ActionManager()
    assert(am, "ActionManager unavailable")
    state.issuing = true
    local priority = requested_priority or (name == "SitOnChairActions" and 1 or 0)
    local ok, err = pcall(function() speed_control.issue(function()
        am:call("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", priority, name, 0)
    end) end)
    state.issuing = false
    if not ok then error(err) end
end
local function native_display_position(anchor,slot)
    local p,x,y,z=anchor:get_Position(),anchor:get_AxisX(),anchor:get_AxisY(),anchor:get_AxisZ()
    -- MoveFloor/seat transforms may have a downward local Y. Keep the
    -- established X/Z layout, but positive height must always move upward.
    local sign=y.y<0 and -1 or 1
    return Vector3f.new(p.x+x.x*slot.x+y.x*slot.y*sign+z.x*slot.z,
        p.y+x.y*slot.x+y.y*slot.y*sign+z.y*slot.z,
        p.z+x.z*slot.x+y.z*slot.y*sign+z.z*slot.z)
end
local function cart_forward(cart)
    local p,ox=cart.body:get_Position(),cart.ox:get_Transform():get_Position()
    local dx,dz=ox.x-p.x,ox.z-p.z
    local length=math.sqrt(dx*dx+dz*dz)
    if length<0.001 then
        local axis=cart.body:get_AxisZ();dx,dz=axis.x,axis.z
        length=math.sqrt(dx*dx+dz*dz)
    end
    assert(length>=0.001,"Cannot determine cart front direction")
    dx,dz=dx/length,dz/length
    return dx,dz
end
local function signed_cart_distances(cart, human)
    local p, center = human:get_Transform():get_Position(), cart.body:get_Position()
    local dx, dz = cart_forward(cart)
    local x, z = p.x-center.x, p.z-center.z
    local forward = x*dx+z*dz
    return forward, forward-front_offset.z, x*dz-z*dx
end
local function passenger_seated(cart, human)
    -- Native controller seat occupancy, independent of ticket ownership or pose.
    -- Optional OJR bindings cover its custom player seating without requiring OJR.
    local bindings = rawget(_G,"OJR_SeatBindings")
    if type(bindings) == "table" then
        for _, seat in pairs(bindings) do
            if type(seat) == "table" and seat.char == human then return true end
        end
    end
    local ok, seated = pcall(function()
        local controller = cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        return controller and controller:call("isPlayerSit()")
    end)
    if ok and type(seated) == "boolean" then return seated end
    return nil -- Unknown is not a verified standing passenger.
end
local function safe_get(object,name)
    return attempt(function()
        local method=object and object:get_type_definition():get_method(name)
        if method and method:get_num_params()==0 then return object:call(name) end
    end)
end
-- Native direction: an isolated driver-seat interaction, not manual seating.
;(function()
    local pending,owned,view=nil,nil,{status="Native driver-seat idle",rows={}}
    local npc_observation
    local entry_wait,entry_resume
    local serial=0
    local function grant_player_access(session)
        local original=tonumber(session.data:get_field("CharacterType"))
        assert(original and original==session.old_mask,"Driver point permissions changed before request")
        session.player_access_added=(original & 1)==0
        if not session.player_access_added then return end
        local granted=original | 1
        session.data:set_field("CharacterType",granted)
        assert(tonumber(session.data:get_field("CharacterType"))==granted,"Player mask write did not take effect")
    end
    local function submit_driver_request(session)
        assert(session.io:call("isInteractEnable(System.UInt32, app.Character)",session.point,session.ch),
            "Native driver point still rejects player after Player flag; no bypass/fallback")
        local result=session.mgr:call("requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)",
            session.io,session.point,session.ch)
        assert(result,"Native request returned no result")
        result:add_ref()
        session.result,session.result_retained=result,true
        session.visual_ready_at=os.clock()+8
    end
    local function release_session_resources(session)
        if session.player_access_added and valid(session.gm) then
            attempt(function()
                -- Undo only the bit this session added. Do not overwrite
                -- non-Player permissions changed by the engine/another mod.
                local current=tonumber(session.data:get_field("CharacterType"))
                if current then session.data:set_field("CharacterType",current & ~1) end
            end)
        end
        session.player_access_added=nil
        if session.result_retained then
            session.result_retained=nil
            attempt(function() session.result:release() end)
        end
        session.result=nil
    end
    local function record(message)
        if view.status==message then return end
        view.status=message
        state.message=message
        if rawget(_G,"OJR_EnableRuntimeDiagnostics")~=true then return end
        view.events=view.events or {}
        view.events[#view.events+1]={t=os.clock(),message=message}
        if #view.events>80 then table.remove(view.events,1) end
        if not view.path then
            serial=serial+1
            view.path="AelinoreNativeSeat_"..os.date("%Y%m%d_%H%M%S").."_"..math.floor(os.clock()*1000).."_"..serial..".log"
        end
        pcall(function() json.dump_file(view.path,{status=view.status,rows=view.rows,events=view.events,npc=view.npc,
            staging=view.staging,staging_requested=view.staging_requested}) end)
    end
    local function clear()
        if owned then
            if owned.bound and (not valid(owned.ch)
                or attempt(function() return owned.mgr:call("isInteracting(app.Character)",owned.ch) end)==false) then
                attempt(driver_runtime.native_pawns_exit)
            end
            if driver_runtime.native_drive_end then attempt(function() driver_runtime.native_drive_end(owned) end) end
            release_session_resources(owned)
        end
        owned=nil
        if driver_runtime.native_boarding_cancel then driver_runtime.native_boarding_cancel() end
        state.native_entry_ready_at=nil
        state.stand_stopped=nil
    end
    local function item(array,index)
        return attempt(function() return array:get_element(index) end)
            or attempt(function() return array:call("get_Item(System.Int32)",index) end)
            or attempt(function() return array._items[index] end)
    end
    local function scan()
        assert(not state.active,"Release manual control before native interaction")
        local cart=discover()
        local ch=player()
        assert(cart and valid(ch),"Approach a loaded oxcart")
        local gm=cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        assert(valid(gm),"Native cart component unavailable")
        local seat=safe_get(gm,"get_DrivingSeat")
        assert(seat,"Native DrivingSeat unavailable")
        assert(not seat.SitChara,"Driver seat occupied or still bound; nothing requested")
        local io=gm.InteractiveObject
        assert(valid(io) and io:call("get_IsRegistered()")
            and io:call("get_IsUpdatedAfterRegisterd()"),"Native cart interaction is not registered/updated")
        local mgr=singleton("app.InteractManager")
        assert(mgr and not mgr:call("isInteracting(app.Character)",ch),"Player is already interacting")
        local candidates={}
        local mapping_readable=true
        view.rows={}
        local n=tonumber(io:call("getNumInteractPoint()"))
        assert(n and n>0 and n<=32,"Unexpected interaction point count")
        for i=0,n-1 do
            local seat_no=attempt(function() return tonumber(gm:call("getSeatNo(System.UInt32)",i)) end)
            local data=item(gm.InteractiveObjectDataList,i)
            local mask=attempt(function() return tonumber(data:get_field("CharacterType")) end)
            local occupant=attempt(function() return gm:call("getInteractChara(System.UInt32)",i) end)
            -- Seat numbers are not interaction point numbers. Driver points may
            -- map to negative seats and may have separate left/right entrances.
            local is_driver=attempt(function() return gm:call("IsDriver(System.UInt32)",i) end)
            if type(is_driver)~="boolean" then mapping_readable=false end
            local enabled=attempt(function() return gm:call("isInteractEnable(System.UInt32)",i) end)
            local candidate=is_driver==true and enabled==true and data~=nil and mask~=nil and not occupant
            view.rows[#view.rows+1]={point=i,seat_no=seat_no,character_mask=mask,
                parent_joint=attempt(function() return tostring(data:get_field("ParentJointName")) end),
                occupant=address(occupant),native_is_driver=is_driver,native_enabled=enabled,driver_candidate=candidate}
            if candidate then candidates[#candidates+1]={point=i,data=data,mask=mask,occupant=occupant} end
        end
        assert(mapping_readable,"Native IsDriver mapping unreadable; no point guessed")
        assert(#candidates>0,"No enabled empty native driver entrance; no passenger point used")
        -- Both sides lead to DrivingSeat; use native point order, never a
        -- passenger point or a seat-number heuristic. Log every alternative.
        local selected=candidates[1]
        assert(selected.data and selected.mask and not selected.occupant,"Driver point unavailable/occupied")
        return {cart=cart,ch=ch,gm=gm,seat=seat,io=io,mgr=mgr,point=selected.point,
            data=selected.data,old_mask=selected.mask,started=os.clock()}
    end
    driver_runtime.native_seat_read=function() return view end
    driver_runtime.native_seat_busy=function() return owned~=nil or pending~=nil or npc_observation~=nil or entry_wait~=nil end
    driver_runtime.native_player_is_driver=function()
        return owned~=nil and owned.bound==true and address(owned.seat.SitChara)==address(owned.ch)
    end
    driver_runtime.native_preset_pause=function(delta)
        if owned and owned.visual_ready_at and os.clock()-delta<owned.visual_ready_at then
            owned.visual_ready_at=owned.visual_ready_at+delta
        end
    end
    driver_runtime.native_seat_command=function(command)
        if command~="scan" and command~="enter" and command~="exit" and command~="npc_exit" then return false end
        if pending then return false end
        if (command=="enter" or command=="scan") and (owned or npc_observation) then return false end
        if entry_wait and command~="exit" then return false end
        pending=command
        return true
    end
    driver_runtime.native_seat_tick=function()
        if paused() then return end
        if entry_wait then
            local q=entry_wait
            if not valid(q.gm) or not valid(q.ch) or os.clock()-q.started>15 then
                entry_wait=nil;clear();record("Driver exit did not complete within 15 seconds or cart unloaded; player entry stopped")
            elseif not q.seat.SitChara and not q.mgr:call("isInteracting(app.Character)",q.ch) then
                entry_wait=nil
                local ok,err=pcall(function()
                    assert(driver_runtime.native_driver_relocate,"Driver relocation unavailable")
                    local target=driver_runtime.native_driver_relocate(q.cart,q.ch)
                    record(string.format("Unbound NPC driver teleported once: 500 behind cart | X %.2f Y %.2f Z %.2f",
                        target.x,target.y,target.z))
                end)
                if ok then
                    entry_resume=true;pending="enter"
                else
                    clear();record("Driver relocation failed; player entry stopped: "..tostring(err))
                end
            end
        end
        if npc_observation and os.clock()>=(npc_observation.next_sample or 0) then
            local q=npc_observation
            q.next_sample=os.clock()+0.25
            local sample={t=os.clock()-q.started,actor=address(q.ch),point=q.point}
            sample.occupant=attempt(function() return address(q.seat.SitChara) end)
            sample.seat_status=attempt(function() return tonumber(q.seat.Status) end)
            sample.interacting=attempt(function() return q.mgr:call("isInteracting(app.Character)",q.ch) end)
            sample.active_point=attempt(function() return tonumber(q.mgr:call("getActiveInteract(app.Character)",q.ch).Point.PointNo) end)
            sample.position=attempt(function() local p=q.ch:get_Transform():get_Position();return {x=p.x,y=p.y,z=p.z} end)
            view.npc.samples[#view.npc.samples+1]=sample
            record("NPC exit observation +"..string.format("%.2fs",sample.t).." | interacting "..tostring(sample.interacting)
                .." | occupant "..tostring(sample.occupant).." | seat status "..tostring(sample.seat_status))
            if sample.t>=20 or not valid(q.ch) or not valid(q.gm) then
                record("NPC exit observation finished; inspect LOG and whether driver stays off cart")
                npc_observation=nil
            end
        end
        if pending then
            local command=pending;pending=nil
            local ok,err=pcall(function()
                if command=="npc_exit" then
                    assert(not state.active and not owned and not npc_observation,"Finish current control/test before NPC exit")
                    view.path=nil;view.events={};view.rows={};view.npc=nil
                    local cart=discover()
                    assert(cart,"Approach a loaded oxcart")
                    local gm=cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
                    assert(valid(gm),"Native cart unavailable")
                    local seat=safe_get(gm,"get_DrivingSeat")
                    local ch=seat and seat.SitChara
                    assert(valid(ch) and address(ch)~=address(player()),"No NPC bound to DrivingSeat; nothing called")
                    local io,mgr=gm.InteractiveObject,singleton("app.InteractManager")
                    assert(valid(io) and mgr,"Native interaction unavailable")
                    local active=mgr:call("getActiveInteract(app.Character)",ch)
                    local point=active and active.Point and tonumber(active.Point.PointNo)
                    assert(active and active.Point and address(active.Point.Object)==address(io)
                        and point and gm:call("IsDriver(System.UInt32)",point)==true
                        and mgr:call("isInteracting(app.Character)",ch)==true,
                        "NPC active interaction does not match native driver entrance; nothing called")
                    view.npc={actor=address(ch),point=point,samples={},before={occupant=address(seat.SitChara),
                        seat_status=tonumber(seat.Status),interacting=true}}
                    record("NPC native exit BEFORE: exact DrivingSeat occupant and active driver point "..point)
                    io:call("endInteractForSystem(System.UInt32, app.Character)",point,ch)
                    npc_observation={ch=ch,gm=gm,seat=seat,mgr=mgr,point=point,started=os.clock()}
                    record("NPC native endInteractForSystem called once; observing 20 seconds; no other changes")
                    return
                end
                if command=="exit" then
                    if entry_wait then entry_wait=nil;clear();record("Pending player entry cancelled");return end
                    assert(owned,"No native test interaction owned")
                    local active=owned.mgr:call("getActiveInteract(app.Character)",owned.ch)
                    assert(active and active.Point and address(active.Point.Object)==address(owned.io)
                        and tonumber(active.Point.PointNo)==owned.point,"Player active point does not match this test")
                    if driver_runtime.native_drive_end then driver_runtime.native_drive_end(owned) end
                    owned.io:call("endInteractForSystem(System.UInt32, app.Character)",owned.point,owned.ch)
                    owned.exiting=true;owned.exit_at=os.clock()
                    record("Native exit requested; waiting for engine completion")
                    return
                end
                assert(not owned and not npc_observation,"Finish the existing native test first")
                local resumed=entry_resume
                local unseated_driver,unseated_gm
                if not resumed then view.path=nil;view.events={};view.rows={} end
                entry_resume=nil
                if command=="enter" then
                    assert(not state.active,"Release non-native control first")
                    local cart=discover();assert(cart,"Approach a loaded oxcart")
                    assert(passenger_seated(cart,player())==false,"Leave the passenger interaction before entering the driver seat")
                    unified_presets.refresh()
                    assert(select_family(cart,false,true),"Enable at least one shared layout for this cart")
                    local gm=cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
                    if not resumed then
                        assert(not bus.owner,"Another controller owns this cart")
                        assert(driver_runtime.native_boarding_wait,"Boarding wait unavailable")
                        driver_runtime.native_boarding_wait(cart)
                    end
                    local seat=safe_get(gm,"get_DrivingSeat")
                    local ch=seat and seat.SitChara
                    if ch then
                        assert(valid(ch) and address(ch)~=address(player()),"Driver seat already belongs to player/stale actor")
                        local io,mgr=gm.InteractiveObject,singleton("app.InteractManager")
                        local active=mgr:call("getActiveInteract(app.Character)",ch)
                        local point=active and active.Point and tonumber(active.Point.PointNo)
                        assert(active and active.Point and address(active.Point.Object)==address(io) and point
                            and gm:call("IsDriver(System.UInt32)",point)==true
                            and mgr:call("isInteracting(app.Character)",ch),"NPC driver active point mismatch; nothing called")
                        io:call("endInteractForSystem(System.UInt32, app.Character)",point,ch)
                        entry_wait={cart=cart,gm=gm,seat=seat,ch=ch,mgr=mgr,started=os.clock()}
                        record("NPC driver exit requested once; waiting before player entry")
                        return
                    end
                    if not resumed and valid(cart.driver) and address(cart.driver)~=address(player()) then
                        local mgr=singleton("app.InteractManager")
                        local active=mgr and mgr:call("getActiveInteract(app.Character)",cart.driver)
                        local point=active and active.Point and tonumber(active.Point.PointNo)
                        if active and active.Point and address(active.Point.Object)==address(gm.InteractiveObject)
                            and point and gm:call("IsDriver(System.UInt32)",point)==true
                            and mgr:call("isInteracting(app.Character)",cart.driver)==true then
                            gm.InteractiveObject:call("endInteractForSystem(System.UInt32, app.Character)",point,cart.driver)
                            entry_wait={cart=cart,gm=gm,seat=seat,ch=cart.driver,mgr=mgr,started=os.clock()}
                            record("Nearby driver boarding request ended; waiting before relocation")
                            return
                        end
                        unseated_driver,unseated_gm=cart.driver,gm
                    else
                        record("No nearby unseated driver to relocate; native driver exit skipped")
                    end
                end
                local q=scan()
                record("Resolved empty driver point "..q.point.." via native IsDriver")
                if command=="scan" then return end
                owned=q
                if unseated_driver then
                    assert(address(unseated_gm)==address(q.gm),"Cart changed before driver relocation")
                    driver_runtime.native_driver_relocate(q.cart,unseated_driver)
                    record("Nearby unseated driver teleported once: 500 behind cart")
                end
                driver_runtime.native_boarding_wait(q.cart)
                q.ready_at=state.native_entry_ready_at or os.clock()+8
                grant_player_access(q)
                submit_driver_request(q)
                record("Native request submitted for driver point "..q.point.."; awaiting acceptance and binding")
            end)
            if not ok then
                record("Native test failed: "..tostring(err))
                -- A failed exit must not discard ownership of an active interaction.
                if command~="exit" and command~="npc_exit" then clear() end
            end
        end
        if not owned then return end
        if not valid(owned.gm) or not valid(owned.ch) then record("Actor/cart unloaded");clear();return end
        if os.clock()<(owned.poll_at or 0) then return end
        owned.poll_at=os.clock()+0.1
        local ok,err=pcall(function()
            local interacting=owned.mgr:call("isInteracting(app.Character)",owned.ch)
            if owned.bound then
                if not interacting then record("Native interaction ended; restoring Player flag");clear();return end
                if owned.exiting and os.clock()-owned.exit_at>10 and not owned.exit_warned then
                    owned.exit_warned=true;record("Native exit still pending; original interaction retained")
                end
                return
            end
            local value=tonumber(owned.result:get_field("ResultType"))
            local enum=sdk.find_type_definition("app.InteractManager.InteractRequestResultType")
            local denied=enum:get_field("Denied"):get_data(nil)
            if value==tonumber(denied) then record("Native request denied; restoring Player flag");clear();return end
            local active=owned.mgr:call("getActiveInteract(app.Character)",owned.ch)
            local seat_matches=address(owned.seat.SitChara)==address(owned.ch)
            if interacting and seat_matches and active and active.Point
                and address(active.Point.Object)==address(owned.io) and tonumber(active.Point.PointNo)==owned.point then
                owned.bound=true
                if driver_runtime.native_drive_begin then driver_runtime.native_drive_begin(owned) end
                record("CONFIRMED: native driver seat; driving enabled; player root/pose/FSM/fall untouched")
            elseif os.clock()-owned.started>15 then
                record("No confirmed driver binding after 15 seconds; requesting cleanup")
                -- If the engine has started an interaction, request its own exit.
                if interacting and active and active.Point and address(active.Point.Object)==address(owned.io)
                    and tonumber(active.Point.PointNo)==owned.point then
                    owned.io:call("endInteractForSystem(System.UInt32, app.Character)",owned.point,owned.ch)
                    owned.bound=true;owned.exiting=true;owned.exit_at=os.clock()
                else clear() end
            end
        end)
        if not ok then record("Native observation failed: "..tostring(err)) end
    end
    driver_runtime.native_seat_close=function()
        pending=nil
        entry_wait=nil;entry_resume=nil
        npc_observation=nil
        if owned and valid(owned.ch) and valid(owned.gm) then
            attempt(function()
                local active=owned.mgr:call("getActiveInteract(app.Character)",owned.ch)
                if active and active.Point and address(active.Point.Object)==address(owned.io)
                    and tonumber(active.Point.PointNo)==owned.point then
                    owned.io:call("endInteractForSystem(System.UInt32, app.Character)",owned.point,owned.ch)
                end
            end)
        end
        clear()
    end
end)()
driver_runtime.native_pawns_command=function(_,cart,freeze_immediately) return driver_runtime.pawn_anchor_command(cart,freeze_immediately) end
driver_runtime.native_pawns_exit=function(skip_wait) return driver_runtime.pawn_anchor_exit(skip_wait) end
driver_runtime.native_pawns_close=function() return driver_runtime.pawn_anchor_exit() end
driver_runtime.native_pawns_tick=function() return driver_runtime.pawn_anchor_tick() end
-- Native follow distance uses CameraManager._DistanceOffset (game option scale,
-- not metres). No FOV or
-- actor-root changes; restore the exact captured setting after ownership ends.
local camera_override = {}
local function native_camera_ready()
    local q=state.native_drive
    return q and not q.exiting and not q.player_preset_disabled
        and os.clock()>=(q.visual_ready_at or math.huge)
end
local function player_camera_settings()
    if state.native_drive then return current_camera(),native_camera_ready(),state.native_drive end
    if bus.journey.passenger_camera then
        local camera,key=bus.journey.passenger_camera()
        if camera then return camera,true,"passenger:"..tostring(key) end
    end
    return current_camera(),false,nil
end
local fov_override = {}
local function restore_camera_fov()
    if fov_override.camera then
        local ok,err=pcall(function() fov_override.camera:call("set_FOV",fov_override.original) end)
        state.fov_status=ok and "FOV restored" or ("FOV restore unavailable: "..tostring(err))
        fov_override.camera,fov_override.original=nil,nil
    end
end
local function update_camera_fov(camera_settings,ready)
    if not camera_settings then camera_settings,ready=player_camera_settings() end
    if not ready or not camera_settings.fov_enabled or paused() or photo_active() then restore_camera_fov(); return end
    if fov_override.suspended then return end
    local camera=sdk.get_primary_camera and sdk.get_primary_camera()
    if not camera then restore_camera_fov(); state.fov_status="Primary camera unavailable"; return end
    if fov_override.camera and fov_override.camera~=camera then
        restore_camera_fov();fov_override.suspended=true
        state.fov_status="Camera changed; FOV suspended until next takeover"; return
    end
    if not fov_override.camera then
        local def=camera:get_type_definition()
        if not def or not def:get_method("get_FOV") or not def:get_method("set_FOV") then
            state.fov_status="FOV getter/setter unavailable"; return
        end
        local original=tonumber(camera:call("get_FOV"))
        if not original or original~=original or original<=5 or original>=180 then
            state.fov_status="Unsupported FOV units/value"; return
        end
        fov_override.camera,fov_override.original=camera,original
    end
    camera:call("set_FOV",camera_settings.fov)
    state.fov_status="FOV override active"
end
local function restore_camera_distance()
    if camera_override.manager then
        local ok,err=pcall(function() camera_override.manager._DistanceOffset=camera_override.original end)
        state.camera_status=ok and "Camera distance restored" or ("Distance restore unavailable: "..tostring(err))
        camera_override.manager,camera_override.original=nil,nil
    end
end
local function update_camera_distance(camera_settings,ready)
    if not camera_settings then camera_settings,ready=player_camera_settings() end
    if not ready or not camera_settings.distance_enabled or paused() or photo_active() then restore_camera_distance(); return end
    if camera_override.suspended then return end
    local manager=singleton("app.CameraManager")
    if not manager then restore_camera_distance(); state.camera_status="CameraManager unavailable"; return end
    if camera_override.manager and camera_override.manager~=manager then
        restore_camera_distance(); camera_override.suspended=true
        state.camera_status="CameraManager changed; distance suspended until next takeover"; return
    end
    if not camera_override.manager then
        local def=manager:get_type_definition()
        if not def or not def:get_field("_DistanceOffset") then
            state.camera_status="Native distance field unavailable"; return
        end
        local original=tonumber(manager._DistanceOffset)
        if not original or original~=original or math.abs(original)==math.huge then
            state.camera_status="Native distance value unavailable"; return
        end
        camera_override.manager,camera_override.original=manager,original
    end
    if manager._DistanceOffset~=camera_settings.distance then manager._DistanceOffset=camera_settings.distance end
    state.camera_status="Camera distance override active"
end
re.on_pre_application_entry("PrepareRendering",function()
    if photo_active() then
        local visual_ok,visual_err=pcall(function() driver_runtime.native_visual_tick() end)
        if not visual_ok then
            attempt(function() driver_runtime.native_visual_restore() end)
            state.visual_status="Photo preset unavailable: "..tostring(visual_err)
        end
    end
end)
local camera_owner
re.on_application_entry("PrepareRendering",function()
    local context_ok,camera_settings,ready,owner=pcall(player_camera_settings)
    if not context_ok then
        restore_camera_fov();restore_camera_distance()
        state.camera_status="Camera context unavailable: "..tostring(camera_settings)
        return
    end
    if owner~=camera_owner then
        restore_camera_fov();restore_camera_distance()
        fov_override.suspended,camera_override.suspended=nil,nil
        camera_owner=owner
    end
    local fov_ok,fov_err=pcall(update_camera_fov,camera_settings,ready)
    if not fov_ok then
        restore_camera_fov(); fov_override.suspended=true
        state.fov_status="FOV unavailable: "..tostring(fov_err)
    end
    local ok,err=pcall(update_camera_distance,camera_settings,ready)
    if not ok then
        restore_camera_distance(); camera_override.suspended=true
        state.camera_status="Camera distance unavailable: "..tostring(err)
    end
end)
driver_runtime.stand_hotkey=function()
    state.preset_switch=nil
    driver_runtime.native_pawns_exit()
    local q=state.native_drive
    if q then
        q.player_preset_disabled=true
        state.stand_stopped=true
        driver_runtime.native_drive_end(q)
    end
end
driver_runtime.switch_preset=function(index,cycle)
    if state.stand_stopped or not state.native_drive then return false end
    unified_presets.refresh()
    if cycle then
        local seated=false
        for _,binding in ipairs(bus.journey.records()) do if binding.char~=player() then seated=true;break end end
        if seated then
            if not choose_family(state.family,true) then return false end
        else
            local current=settings.presets[settings.preset]
            if not current or current.family~=state.family or not current.enabled then
                if not choose_family(state.family,false) then return false end
            end
        end
    else
        local p=settings.presets[index]
        if not p or p.family~=state.family or not p.enabled then return false end
        settings.preset=index
    end
    family_cursor[state.family]=settings.preset
    if not unified_presets.activate(settings.preset) then return false end
    driver_runtime.native_visual_clear()
    state.layout_changed=true
    save()
    return bus.journey.bind_manual(state.native_drive.cart)
end
driver_runtime.switch_preset_tick=function() end
local function synchronize_seat_position(record, transform)
    -- Transform uses scene coordinates. PosRotContext requires via.Position
    -- in universal coordinates; never pass the seat's scene vec3 to setPos.
    local context = record.actor["<PosRotContext>k__BackingField"]
    local terrain = record.actor["<AdjustTerrain>k__BackingField"]
    local controller = terrain and terrain.MainCharacterController
    assert(context and controller, "Seat position sync: context/controller unavailable")
    context:call("setPos(via.Position)", transform:get_UniversalPosition())
    -- CharacterController.warp() has NO parameters. It resynchronizes its
    -- physical position from its owning object's transform, not a Character warp.
    -- Keep capsule geometry/local offset and collision flags unchanged.
    controller:call("warp()")
    local p, physical = transform:get_Position(), controller:call("get_Position()")
    if physical then
        local dx, dy, dz = p.x-physical.x, p.y-physical.y, p.z-physical.z
        record.position_sync_status = string.format("Sync requested | controller/root gap %.3f | Y gap %.3f",
            math.sqrt(dx*dx+dy*dy+dz*dz), dy)
    else
        record.position_sync_status = "Sync requested; controller readback unavailable"
    end
    if record.player then state.position_sync_status = record.position_sync_status end
end
driver_runtime.native_driver_relocate=function(cart,ch)
    assert(valid(ch) and address(ch)~=address(player()),"Driver relocation cannot target player")
    local gm=cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
    local seat=safe_get(gm,"get_DrivingSeat")
    local mgr=singleton("app.InteractManager")
    assert(valid(gm) and seat and not seat.SitChara and mgr
        and not mgr:call("isInteracting(app.Character)",ch),"Driver still bound/interacting; no teleport")
    local terrain=ch["<AdjustTerrain>k__BackingField"]
    assert(ch["<PosRotContext>k__BackingField"] and terrain and terrain.MainCharacterController,
        "Driver position components unavailable")
    local transform=ch:get_Transform()
    local p,origin=transform:get_Position(),cart.body:get_Position()
    local dx,dz=cart_forward(cart)
    local target=Vector3f.new(origin.x-dx*500,p.y,origin.z-dz*500)
    transform:set_Position(target)
    synchronize_seat_position({actor=ch},transform)
    local fall=ch["<FallInfo>k__BackingField"]
    if fall then
        fall:call("resetBaseHeight(via.Position)",transform:get_UniversalPosition())
        fall:call("resetFallHeight()")
    end
    return target
end

local driver_wait_control = {waits={}}
function driver_wait_control.wait_active(ox)
    local record=valid(ox) and driver_wait_control.waits[address(ox:get_GameObject())]
    return record and os.clock()<record.until_time
end
function driver_wait_control.stop_one_second(cart)
    if not cart or not valid(cart.ox) then return end
    driver_wait_control.waits[address(cart.ox:get_GameObject())]={ox=cart.ox,until_time=os.clock()+1}
    action(cart.ox,"Wait")
end
function driver_wait_control.update_waits()
    if paused() then return end
    for key,record in pairs(driver_wait_control.waits) do
        if not valid(record.ox) or os.clock()>=record.until_time then driver_wait_control.waits[key]=nil
        else action(record.ox,"Wait") end
    end
end
local release
-- Companion positions, animations, fall resets and FSM lifetime have one owner.
driver_runtime.pawn_anchor_exit=function()
    bus.journey.release()
    state.seats={}
    return true
end
driver_runtime.pawn_anchor_command=function(cart)
    local q=state.native_drive
    if not q then return bus.journey.sit() end
    cart=cart or q.cart
    unified_presets.refresh()
    unified_presets.activate(settings.preset)
    return bus.journey.bind_manual(cart)
end
driver_runtime.pawn_anchor_pose=function() return bus.journey.manual_pose() end
driver_runtime.pawn_anchor_tick=function()
    state.seats={}
    if not state.native_drive then return end
    for _,r in ipairs(bus.journey.records()) do
        if r.slot then state.seats[#state.seats+1]={actor=r.char,slot=r.slot+1} end
    end
end
-- Player display Transform override. Restore before simulation so the native
-- driver interaction can update its position without a persistent offset.
;(function()
    local transforms={}
    local function vector(v) return Vector3f.new(v.x,v.y,v.z) end
    driver_runtime.native_visual_restore=function()
        for _,entry in ipairs(transforms) do
            if valid(entry.actor) then attempt(function()
                entry.actor:get_Transform():set_Position(entry.position)
            end) end
        end
        transforms={}
    end
    driver_runtime.native_visual_clear=function()
        driver_runtime.native_visual_restore()
    end
    driver_runtime.native_visual_tick=function()
        driver_runtime.native_visual_restore()
        driver_runtime.pawn_anchor_pose()
        local simulation_paused=paused()
        if simulation_paused and not photo_active() then return end
        if state.layout_changed then state.layout_changed=false end
        local function update(ch,cart,index)
            if not valid(ch) then return end
            local slot=settings.presets[settings.preset].slots[index]
            -- Display-position override only. Native interaction, rotation,
            -- physics controllers and animations remain game-owned.
            local transform=ch:get_Transform()
            local anchor=slot.useOxAnchor and cart.ox:get_Transform() or cart.anchor
            local target=native_display_position(anchor,slot)
            transforms[#transforms+1]={actor=ch,position=vector(transform:get_Position())}
            transform:set_Position(target)
        end
        local q=state.native_drive
        local preset=settings.presets[settings.preset]
        if q and native_camera_ready() and preset and preset._canonical.teleportPlayer then update(q.ch,q.cart,1) end
        -- Companions have their own real-position/physics synchronization.
    end
end)()
-- Player physics remain owned by native interaction; pawn anchors are separate.
local function restore_hotbar()
    -- No UI fields were changed: the next native draw resumes automatically.
    state.hotbar_status = "Skill bar: native drawing restored"
end
local function should_draw_hotbar(element)
    if not (state.active or state.native_drive) then return true end
    local go = element and element:call("get_GameObject")
    if go and go:call("get_Name") == "ui010201" then
        state.hotbar_status = "Skill bar: hidden while driving"
        return false
    end
    return true
end
if re.on_pre_gui_draw_element then
    re.on_pre_gui_draw_element(function(element)
        -- Suppress only this HUD draw. No GUIBase/Root/text access or UI mutation.
        local ok, draw = pcall(should_draw_hotbar, element)
        if not ok then
            state.hotbar_status = "Skill bar hide unavailable: " .. tostring(draw)
            return true
        end
        return draw
    end)
else
    state.hotbar_status = "Skill bar hide unavailable: GUI draw callback missing"
end
release = function(reason)
    state.preset_switch=nil;state.stand_stopped=nil
    attempt(driver_runtime.pawn_anchor_exit)
    attempt(driver_runtime.native_visual_clear)
    restore_camera_distance();restore_camera_fov();restore_hotbar()
    state.active=false;state.seats={};state.protected={}
    state.toggle_pending=false;state.layout_changed=false
    state.message=reason or "Native control released"
end

-- Direct keyboard/gamepad HID polling; mouse input is not used for driving.
local function enum(name)
    local result, def = {}, sdk.find_type_definition(name)
    if def then for _, field in ipairs(def:get_fields()) do if field:is_static() then result[field:get_name()] = field:get_data(nil) end end end
    return result
end
local keys, pads = enum("via.hid.KeyboardKey"), enum("via.hid.GamePadButton")
local default_bindings = {
    near_take = { keyboard = "F", gamepad = "Cancel" },
    sit = { keyboard = "E", gamepad = "RLeft" },
    stand = { keyboard = "X", gamepad = "Decide" },
    pawn_stand = { keyboard = "F", gamepad = "Cancel" },
    up = { keyboard = "W", gamepad = "RTrigTop" },
    down = { keyboard = "S", gamepad = "LTrigTop" },
}
settings.bindings = {}
local binding_enums = { keyboard = keys, gamepad = pads }
for name, defaults in pairs(default_bindings) do
    settings.bindings[name] = {}
    for device, key in pairs(defaults) do
        local stored = type(saved) == "table" and type(saved.bindings) == "table" and saved.bindings[name]
        stored = type(stored) == "table" and stored[device]
        settings.bindings[name][device] = (stored == "None" or binding_enums[device][stored]) and stored or key
    end
end
-- Correct the previous release's default shoulder ordering once; user bindings
-- other than that exact old default pair remain untouched.
if type(saved) == "table" and saved.shoulder_binding_rule ~= 1
    and settings.bindings.up.gamepad == "LTrigTop" and settings.bindings.down.gamepad == "RTrigTop" then
    settings.bindings.up.gamepad, settings.bindings.down.gamepad = "RTrigTop", "LTrigTop"
end
settings.shoulder_binding_rule = 1
if type(saved) ~= "table" or saved.entry_hold_binding_rule ~= 1 then
    if settings.bindings.near_take.keyboard == "E" then settings.bindings.near_take.keyboard = "F" end
    if settings.bindings.near_take.gamepad == "RLeft" then settings.bindings.near_take.gamepad = "Cancel" end
end
settings.entry_hold_binding_rule = 1
local shared_builtin_defaults={}
for _,p in ipairs(builtin_presets) do shared_builtin_defaults[#shared_builtin_defaults+1]=clone_builtin(p) end
unified_presets.attach(settings,shared_builtin_defaults)
settings.sensitivity=clamp(tonumber(settings.sensitivity) or 45,5,180)
for name,defaults in pairs(default_bindings) do
    if type(settings.bindings[name])~="table" then settings.bindings[name]={} end
    for device,key in pairs(defaults) do
        local value=settings.bindings[name][device]
        if value~="None" and not binding_enums[device][value] then settings.bindings[name][device]=key end
    end
end
local previous, input = {}, { keyboard = 0, stick = 0 }
local binding_choices = {}
for device, values in pairs(binding_enums) do
    local choices = { "None" }
    for name, value in pairs(values) do
        if value ~= 0 and name ~= "None" and name ~= "All" then choices[#choices + 1] = name end
    end
    table.sort(choices, function(a, b) if a == b then return false elseif a == "None" then return true elseif b == "None" then return false end return a < b end)
    binding_choices[device] = choices
end
local function poll()
    local kb = sdk.call_native_func(sdk.get_native_singleton("via.hid.Keyboard"), sdk.find_type_definition("via.hid.Keyboard"), "get_Device")
    local gp = sdk.call_native_func(sdk.get_native_singleton("via.hid.Gamepad"), sdk.find_type_definition("via.hid.GamePad"), "get_MergedDevice")
    local bits = gp and gp:call("get_Button") or 0
    local function down(name) return kb and keys[name] and kb:call("isDown", keys[name]) == true end
    local function pad(name) local n = pads[name]; return n and n ~= 0 and (bits & n) == n end

    if state.binding_capture then
        state.entry_hold=nil
        local capture, pressed = state.binding_capture, {}
        for _, name in ipairs(binding_choices[capture.device]) do
            local code = binding_enums[capture.device][name]
            if name ~= "None" and code and code ~= 0 then
                if capture.device == "keyboard" then pressed[name] = down(name)
                elseif capture.device == "gamepad" then pressed[name] = pad(name)
                end
            end
        end
        -- Seed from held inputs first; the click opening capture cannot bind itself.
        if capture.previous then
            for _, name in ipairs(binding_choices[capture.device]) do
                if pressed[name] and not capture.previous[name] then
                    settings.bindings[capture.action][capture.device] = name
                    state.binding_capture, state.rebind_block = nil, true
                    save(); break
                end
            end
        end
        capture.previous = pressed
        previous, input = {}, { keyboard = 0, stick = 0 }
        return
    end
    local now = {}
    for name, binding in pairs(settings.bindings) do
        now[name] = down(binding.keyboard) or pad(binding.gamepad)
    end

    if state.rebind_block then
        state.entry_hold=nil
        local held = false
        for _, value in pairs(now) do if value then held = true end end
        previous = now
        input = { keyboard = 0, stick = 0 }
        if not held then state.rebind_block = false end
        return
    end
    for name, value in pairs(now) do input[name] = value and not previous[name] end
    input.near_take_held = now.near_take
    if not now.near_take then state.entry_hold=nil end
    previous = now
    input.keyboard = (down("D") and 1 or 0) - (down("A") and 1 or 0)
    input.stick = gp and tonumber(attempt(function() return gp:call("get_AxisL()").x end)) or 0
    if not input.stick or input.stick ~= input.stick then input.stick = 0 end
    input.stick = clamp(input.stick, -1, 1)
    if attempt(function() return reframework:is_drawing_ui() end) == true then
        state.entry_hold=nil
        input = { keyboard = 0, stick = 0, near_take = not state.active and input.near_take }
    end
end
re.on_application_entry("UpdateHID", function()
    local ok, err = pcall(poll)
    if not ok then
        input = { keyboard = 0, stick = 0 }
        state.error = "Input unavailable: " .. tostring(err)
    end
end)

local last = os.clock()
-- Separate native driving lease: never sets state.active or creates seat
-- records, so the legacy player/pawn constraints and action guards stay off.
;(function()
    local boarding_wait
    driver_runtime.native_boarding_wait=function(cart)
        assert(valid(cart.ox),"Boarding ox unavailable")
        local until_time=os.clock()+8
        state.native_entry_ready_at=until_time
        boarding_wait={ox=cart.ox,until_time=until_time}
        driver_wait_control.waits[address(cart.ox:get_GameObject())]=boarding_wait
        action(cart.ox,"Wait")
    end
    driver_runtime.native_boarding_cancel=function()
        if boarding_wait then
            local key=address(boarding_wait.ox:get_GameObject())
            if driver_wait_control.waits[key]==boarding_wait then driver_wait_control.waits[key]=nil end
            boarding_wait=nil
        end
    end
    driver_runtime.native_boarding_pause=function(delta)
        local q=state.native_drive
        driver_runtime.native_preset_pause(delta)
        if boarding_wait and os.clock()-delta<boarding_wait.until_time then
            boarding_wait.until_time=boarding_wait.until_time+delta
            if state.native_entry_ready_at then state.native_entry_ready_at=state.native_entry_ready_at+delta end
            if q then q.ready_at=q.ready_at+delta end
        end
    end
    driver_runtime.native_drive_begin=function(q)
        state.stand_stopped=nil;state.preset_switch=nil
        assert(not state.active and not bus.owner,"Another controller owns this cart")
        local heading=tonumber(q.cart.cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
        assert(heading,"Native driving cow heading unavailable")
        unified_presets.refresh()
        assert(select_family(q.cart,false,true),"Enable at least one shared layout for this cart")
        assert(unified_presets.activate(settings.preset),"Selected driver layout unavailable")
        q.drive={level=1,axis=0,heading=heading}
        state.native_drive=q
        bus.journey.begin_manual(q.cart)
        bus.owner,bus.heartbeat=TITLE,os.clock()
        camera_override.suspended,fov_override.suspended=nil,nil
        action(q.cart.ox,"Wait")
        driver_runtime.native_seat_read().pawn_anchors_requested=driver_runtime.native_pawns_command(true,q.cart)
        state.message="Native driving: Wait"
    end
    driver_runtime.native_drive_end=function(q)
        if state.native_drive~=q then return end
        speed_control.clear()
        state.native_drive=nil;q.drive=nil
        bus.journey.end_manual()
        state.seats={}
        state.preset_switch=nil
        driver_runtime.native_visual_restore()
        if bus.owner==TITLE then bus.owner,bus.heartbeat=nil,nil end
        if valid(q.cart.ox) then attempt(function() action(q.cart.ox,"Wait") end) end
        restore_camera_distance();restore_camera_fov();restore_hotbar()
        state.message="Native driving stopped; seat exit handled by the game"
    end
    driver_runtime.native_drive_tick=function(dt)
        local q=state.native_drive
        if not q then return end
        local cart,d=q.cart,q.drive
        if input.stand then driver_runtime.stand_hotkey();return end
        if not valid(q.ch) or player()~=q.ch or not valid(cart.ox) or not valid(cart.cow)
            or not valid(cart.body:get_GameObject()) then
            driver_runtime.native_seat_close();return
        end
        local active=q.mgr:call("getActiveInteract(app.Character)",q.ch)
        if address(q.seat.SitChara)~=address(q.ch) or not active or not active.Point
            or address(active.Point.Object)~=address(q.io) or tonumber(active.Point.PointNo)~=q.point then
            -- Native A/exit owns its animation and trajectory. Stop only cow
            -- control; do not insert another endInteract or player Wait.
            driver_runtime.native_drive_end(q)
            q.exiting=true;q.exit_at=os.clock();return
        end
        if cart.status and (cart.status:call("isBroken_OxCart()") or cart.status:call("isDead_Ox()")) then
            driver_runtime.native_drive_end(q)
            driver_runtime.native_seat_command("exit");return
        end
        bus.heartbeat=os.clock()
        if input.sit then driver_runtime.switch_preset(nil,true) end
        driver_runtime.switch_preset_tick()
        if state.layout_changed then
            state.layout_changed=false
            driver_runtime.native_visual_clear()
        end
        -- Stand/A belongs to the game's native interaction, not this loop.
        if os.clock()<(q.ready_at or 0) or driver_wait_control.wait_active(cart.ox) then
            d.level=1;action(cart.ox,"Wait");state.message="Boarding: Wait";return
        end
        if input.up then d.level=speed_control.next(d.level,1)
        elseif input.down then d.level=speed_control.next(d.level,-1) end
        local change=dt/0.15
        d.axis=d.axis+clamp(input.keyboard-d.axis,-change,change)
        local axis=d.axis
        if input.keyboard==0 and math.abs(axis)<0.001 then
            local stick=input.stick
            axis=math.abs(stick)<=0.15 and 0 or (stick<0 and -1 or 1)*(math.abs(stick)-0.15)/0.85
        end
        if math.abs(axis)>0.001 then
            local heading=tonumber(cart.cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
            d.heading=(heading-axis*settings.sensitivity*dt+180)%360-180
        end
        cart.cow:call("set_TargetFrontAngleDeg(System.Single)",d.heading)
        cart.cow:call("set_TargetMoveAngleDeg(System.Single)",d.heading)
        local current=cart.ox["<ActionManager>k__BackingField"].CurrentActionList[0]
        if speed_control.can_command(cart.ox,true) then
            speed_control.hold(cart.ox,modes[d.level],0.5,os.clock())
            if current.Name~=modes[d.level] then action(cart.ox,modes[d.level]) end
        else
            speed_control.clear()
        end
        state.message="Native driving: "..modes[d.level]
    end
end)()
driver_runtime.entry_hold_tick=function(elapsed)
    if not input.near_take_held then state.entry_hold=nil;return end
    local held=state.entry_hold
    if held and held.fired then return end
    if state.active or driver_runtime.native_seat_busy() then state.entry_hold=nil;return end
    local human,cart=player(),discover()
    if not valid(human) or not cart or passenger_seated(cart,human)~=false then state.entry_hold=nil;return end
    local _, driver_forward = signed_cart_distances(cart,human)
    if not (driver_forward>=0 and driver_forward<=3) then state.entry_hold=nil;return end
    if not held or held.cart~=address(cart.body) or held.actor~=address(human) then
        held={cart=address(cart.body),actor=address(human),elapsed=0};state.entry_hold=held
    else held.elapsed=held.elapsed+elapsed end
    if held.elapsed>0.3 and not held.waited then
        driver_wait_control.stop_one_second(cart)
        held.waited=true
    end
    if held.elapsed>=1 then
        held.fired=true
        driver_runtime.native_seat_command("enter")
    end
end
re.on_application_entry("LateUpdateBehavior", function()
    attempt(driver_runtime.native_seat_tick)
    attempt(driver_runtime.native_pawns_tick)
    local now=os.clock()
    local elapsed=math.max(now-last,0)
    local dt=clamp(elapsed,0,0.1);last=now
    if paused() then
        for _,r in ipairs(state.seats) do
            if r.freeze_until and now-elapsed<r.freeze_until then r.freeze_until=r.freeze_until+elapsed end
        end
        state.entry_hold=nil
        driver_runtime.switch_preset_tick()
        driver_runtime.native_boarding_pause(elapsed);input={keyboard=0,stick=0};return
    end
    local ok,err=pcall(function()
        driver_wait_control.update_waits()
        state.behavior_frame=state.behavior_frame+1
        if state.native_drive and input.stand then driver_runtime.stand_hotkey();input.stand=nil end
        if state.native_drive and input.pawn_stand then driver_runtime.native_pawns_exit() end
        driver_runtime.switch_preset_tick()
        if driver_runtime.native_seat_busy() then
            driver_runtime.native_drive_tick(dt)
        end
        if not state.native_drive and bus.journey.passenger_active() then
            if input.stand then bus.journey.stand() end
            if input.up then bus.journey.speed_step(1)
            elseif input.down then bus.journey.speed_step(-1) end
        end
        driver_runtime.entry_hold_tick(elapsed)
    end)
    if not ok then
        state.error="Native driving: "..tostring(err)
        attempt(driver_runtime.native_seat_close)
    end
    input={keyboard=0,stick=0}
end)
re.on_frame(function()
    -- Rendering callback only renews the ownership lease; no actor mutations.
    if state.active or state.native_drive then bus.heartbeat = os.clock() end
end)
-- Undo the display Transform override before gameplay/animation evaluation,
-- then reapply after joint expressions and during Photo Mode rendering.
re.on_pre_application_entry("UpdateBehavior", function()
    driver_runtime.native_visual_restore()
end)
re.on_application_entry("UpdateJointExpression", function()
    local ok, err = pcall(driver_runtime.native_visual_tick)
    if not ok then
        driver_runtime.native_visual_restore()
        state.visual_status = "Unavailable: " .. tostring(err)
    end
end)


local function hook(type_name, signature, before)
    local def = sdk.find_type_definition(type_name)
    local method = def and def:get_method(signature)
    if method then sdk.hook(method, before, function(ret) return ret end)
    else log.warn("[" .. TITLE .. "] Missing optional hook: " .. signature) end
end
hook("app.ActionManager", "requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", function(args)
    -- Cover the AI's short battle-entry Run even with manual control released.
    if not state.native_drive and not next(driver_wait_control.waits) then return end
    local ok,result=pcall(function()
        local request_am=sdk.to_managed_object(args[2])
        if request_am and (sdk.to_int64(args[5]) & 0xffffffff)==0 then
            local owner=request_am:get_GameObject()
            if not valid(owner) then return end
            local waiting=driver_wait_control.waits[address(owner)]
            if waiting and os.clock()<waiting.until_time then
                local node=sdk.to_managed_object(args[4]):ToString()
                if node=="Walk" or node=="Run" or node=="Dash" then return sdk.PreHookResult.SKIP_ORIGINAL end
            end
            local q=state.native_drive
            if q and address(owner)==address(q.cart.ox:get_GameObject()) then
                local node=sdk.to_managed_object(args[4]):ToString()
                if speed_control.blocks(q.cart.ox,node,0,os.clock(),paused()) then return sdk.PreHookResult.SKIP_ORIGINAL end
            end
        end
    end)
    if ok then return result end -- Fail open during object teardown.

end)
re.on_script_reset(function()
    state.entry_hold=nil
    attempt(driver_runtime.native_visual_clear)
    attempt(driver_runtime.native_pawns_close)
    attempt(driver_runtime.native_seat_close)
    driver_wait_control.waits={}
    release("Scripts reset")
    state.return_point, state.return_pending = nil, nil
end)
re.on_config_save(save)
local function draw_driver_ui()
    if imgui.tree_node("General settings") then
        if imgui.button("Let me drive") then driver_runtime.native_seat_command("enter") end
        if imgui.button("Let pawns sit") then driver_runtime.native_pawns_command(true) end
        if imgui.button("Let pawns stand") then driver_runtime.native_pawns_exit() end
        if bus.journey.passenger_active() and imgui.button("Resume passenger auto cruise") then bus.journey.resume_auto() end
        if state.error then imgui.text("Last error: " .. state.error) end
        local changed,value=imgui.slider_float("Steering sensitivity (degrees/s)",settings.sensitivity,5,180)
        if changed then settings.sensitivity=value; save() end
        imgui.tree_pop()
    end
    if imgui.tree_node("Keybind settings") then
        if imgui.begin_table("Driving keybinds",3,1) then
            imgui.table_next_row()
            for _,label in ipairs({"Action","Gamepad","Keyboard"}) do
                imgui.table_next_column(); imgui.table_header(label)
            end
            for _,row in ipairs({{"near_take","Let me drive"},{"sit","Let pawns sit"},
                {"stand","Let me stand"},{"pawn_stand","Let pawns stand"},
                {"up","Accelerate"},{"down","Decelerate"}}) do
                local binding=settings.bindings[row[1]]
                imgui.table_next_row()
                imgui.table_next_column(); imgui.text(row[2])
                for _,device in ipairs({"gamepad","keyboard"}) do
                    imgui.table_next_column()
                    local id=row[1].."_"..device
                    local capture=state.binding_capture
                    if capture and capture.action==row[1] and capture.device==device then
                        imgui.button("Press next input...##"..id)
                    elseif imgui.button(binding[device].."##"..id) then
                        state.binding_capture={action=row[1],device=device}
                        previous,input={},{keyboard=0,stick=0}
                    end
                end

            end
            imgui.end_table()
        end
        local capture = state.binding_capture
        if capture then
            local id = capture.action .. "_" .. capture.device
            imgui.text("Waiting for next " .. capture.device .. " input (release held keys first)")
            if imgui.button("Cancel mapping##" .. id) then state.binding_capture, state.rebind_block = nil, true end
            imgui.same_line()
            if imgui.button("Unbind##" .. id) then
                settings.bindings[capture.action][capture.device] = "None"
                state.binding_capture, state.rebind_block = nil, true; save()
            end
        end
        if imgui.button("Restore default driving keys") then
            for name, defaults in pairs(default_bindings) do
                settings.bindings[name] = {}
                for device, key in pairs(defaults) do settings.bindings[name][device] = key end
            end
            state.binding_capture, state.rebind_block = nil, true
            previous, input = {}, { keyboard = 0, stick = 0 }; save()
        end
        if bus.journey.draw_backup_keybinds then bus.journey.draw_backup_keybinds() end
        imgui.tree_pop()
    end
end

local function draw_player_camera(preset,passenger)
    local camera=unified_presets.camera_for(preset,passenger)
    local c,v=imgui.checkbox("Override FOV",camera.fov_enabled)
    if c then camera.fov_enabled=v;save() end
    c,v=imgui.slider_float("FOV",camera.fov,20,120)
    if c then camera.fov=v;save() end
    c,v=imgui.checkbox("Override camera distance",camera.distance_enabled)
    if c then camera.distance_enabled=v;save() end
    c,v=imgui.slider_float("Camera distance",camera.distance,0,10)
    if c then camera.distance=v;save() end
end
local function draw_driver_player(preset)
    local slot=unified_presets.driver_for(preset)
    for _,key in ipairs({"x","y","z","yaw"}) do
        local changed,value=imgui.drag_float(key.."##driver",slot[key],key=="yaw" and 1 or 0.01,
            key=="yaw" and -180 or -10,key=="yaw" and 180 or 10)
        if changed then slot[key]=value;save() end
    end
    draw_player_camera(preset,false)
end
bus.driver={
    draw_ui=draw_driver_ui,
    draw_player=draw_driver_player,
    draw_camera=draw_player_camera,
    player_adjustment_changed=function(preset)
        local active=settings.presets[settings.preset]
        if active and active._canonical==preset then driver_runtime.native_visual_clear() end
    end,
    get_bindings=function() return settings.bindings end,
    is_busy=function() return driver_runtime.native_seat_busy() end,
    player_is_driver=function() return driver_runtime.native_player_is_driver() end,
    abort=function() return driver_runtime.native_seat_close() end,
    capturing=function() return state.binding_capture~=nil or state.rebind_block==true end,
    layout_selected=function(family,index)
        local q=state.native_drive
        if not q or state.stand_stopped or family~=state.family then return false end
        unified_presets.refresh()
        for i,p in ipairs(settings.presets) do
            if p.family==family and p._index==index then return driver_runtime.switch_preset(i,false) end
        end
        return false
    end,
}
