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
    _G.OJR_UnifiedPresets = load_module("presets")
    _G.OJR_UnifiedSpeed = load_module("speed")
    load_module("journey")
    load_module("driver")
end)
if not ok then
    local bus = rawget(_G, "DD2_OxcartControl")
    if bus and bus.journey then pcall(bus.journey.release) end
    log.error("[Oxcarts Journey Redux] Unified startup failed: " .. tostring(err))
end
