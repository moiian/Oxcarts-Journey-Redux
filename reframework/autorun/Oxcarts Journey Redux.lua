-- Single autorun entry. Modules register their own scoped callbacks.
if rawget(_G, "OJR_UnifiedLoaded") then return end
local function load_module(name)
    local path = "reframework/autorun/Oxcarts Journey Redux/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    assert(chunk, "OJR module unavailable: " .. path .. ": " .. tostring(err))
    return chunk()
end
_G.OJR_UnifiedLoaded = true
re.on_script_reset(function() _G.OJR_UnifiedLoaded = nil end)
local ok, err = pcall(function()
    _G.OJR_RuntimeDiagnostics = load_module("diagnostics")
    _G.OJR_UnifiedPresets = load_module("presets")
    _G.OJR_UnifiedSpeed = load_module("speed")
    _G.OJR_PassengerHud = load_module("hud")
    _G.OJR_CartProtection = load_module("protection")
    _G.OJR_UnifiedPelvis = load_module("pelvis")
    _G.OJR_CompanionDisplay = load_module("display")
    load_module("journey")
    load_module("driver")
    -- Register after the driver display callbacks so native player placement settles first.
    local function restore_companions()
        _G.OJR_UnifiedPelvis.restore()
        _G.OJR_CompanionDisplay.restore()
    end
    re.on_pre_application_entry("UpdateBehavior",restore_companions)
    re.on_pre_application_entry("UpdateJointExpression",_G.OJR_UnifiedPelvis.restore)
    local function correct_companions()
        _G.OJR_UnifiedPelvis.restore()
        local bus=rawget(_G,"DD2_OxcartControl")
        if bus and bus.journey and bus.journey.pelvis_tick then
            _G.OJR_CompanionDisplay.tick(bus.journey.records(),bus.journey.seat_anchor)
            bus.journey.pelvis_tick()
        end
    end
    re.on_application_entry("UpdateJointExpression",correct_companions)
    re.on_application_entry("PrepareRendering",correct_companions)
    re.on_application_entry("PrepareRendering",function()
        local bus=rawget(_G,"DD2_OxcartControl")
        if bus and bus.journey and bus.journey.diagnostics_render then bus.journey.diagnostics_render() end
    end)
    re.on_script_reset(restore_companions)
    re.on_script_reset(_G.OJR_CompanionDisplay.clear)
    re.on_script_reset(_G.OJR_UnifiedPelvis.clear)
    re.on_script_reset(_G.OJR_RuntimeDiagnostics.close)
end)
if not ok then
    local bus = rawget(_G, "DD2_OxcartControl")
    if bus and bus.journey then pcall(bus.journey.release) end
    log.error("[Oxcarts Journey Redux] Unified startup failed: " .. tostring(err))
end
