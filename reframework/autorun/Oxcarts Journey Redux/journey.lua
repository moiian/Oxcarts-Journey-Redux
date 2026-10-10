-- Oxcarts Journey Redux
-- Runtime input, passenger seating, cart control, and protection services.

-- Optional ownership handshake. No dependency when manual driving is absent.
local manual_cart
local unified_presets = assert(rawget(_G, "OJR_UnifiedPresets"))
local driving_bus = rawget(_G, "DD2_OxcartControl") or { version = 1 }
_G.DD2_OxcartControl = driving_bus
local function external_driver_active()
    if driving_bus.unified_manual_active then return true end
    if driving_bus.driver and driving_bus.driver.is_busy() then return true end
    return driving_bus.owner ~= nil and driving_bus.heartbeat ~= nil
        and os.clock() - driving_bus.heartbeat < 2.0
end

local input_bindings = (function()
    local function read_enum_values(typename)
        local t = sdk.find_type_definition(typename)
        if not t then return {} end
        local fields = t:get_fields()
        local enum = {}
        for _, field in ipairs(fields) do
            if field:is_static() then
                local name = field:get_name()
                if not string.match(name, 'All') then enum[name] = field:get_data(nil) end
            end
        end
        return enum
    end

    local function invert_enum_map(enum)
        local l = {}
        for k,v in pairs(enum) do l[v] = k end
        return l
    end

    local keyboard_codes = read_enum_values("via.hid.KeyboardKey")
    local gamepad_codes = read_enum_values("via.hid.GamePadButton")
    local keyboard_singleton = sdk.get_native_singleton("via.hid.Keyboard")
    -- DD2's September 2026 title update renamed the native gamepad singleton
    -- and replaced getMergedDevice(0) with get_MergedDevice().
    local gamepad_singleton = sdk.get_native_singleton("via.hid.Gamepad") or sdk.get_native_singleton("via.hid.GamePad")
    local keyboard_type = sdk.find_type_definition("via.hid.Keyboard")
    local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
    local key_state = { down = { keyboard = {}, gamepad = {} }, trigger = { keyboard = {}, gamepad = {} } }
    local keyboard_name_by_code = invert_enum_map(keyboard_codes)
    local binding_capture_id = nil

    -- Enum members such as None have value 0. A bitmask test with 0 is always
    -- true, so they must never participate in polling or key rebinding.
    local function is_bindable_enum_member(name, value)
        if name == nil or value == nil or tonumber(value) == 0 then return false end
        local normalized = tostring(name):lower():gsub("[%s_%-%[%]]", "")
        return normalized ~= "none" and normalized ~= "notbound" and normalized ~= "unbound"
    end

    local function poll_inputs(selected_bindings)
        local kb = sdk.call_native_func(keyboard_singleton, keyboard_type, 'get_Device')
        local gp = sdk.call_native_func(gamepad_singleton, gamepad_type, "get_MergedDevice")
        local gp_down = gp and (gp:call("get_Button") or 0) or 0
        local gp_trigger = gp and (gp:call("get_ButtonDown") or 0) or 0

        if binding_capture_id == nil and selected_bindings ~= nil then
            for _, binding in ipairs(selected_bindings) do
                if binding.type == 'keyboard' then
                    local code = keyboard_codes[binding.key]
                    if kb ~= nil and is_bindable_enum_member(binding.key, code) then
                        key_state.down.keyboard[binding.key] = kb:call('isDown', code)
                        key_state.trigger.keyboard[binding.key] = kb:call('isTrigger', code)
                    else
                        key_state.down.keyboard[binding.key] = false
                        key_state.trigger.keyboard[binding.key] = false
                    end
                elseif binding.type == 'gamepad' then
                    local code = gamepad_codes[binding.key]
                    if gp ~= nil and is_bindable_enum_member(binding.key, code) then
                        key_state.down.gamepad[binding.key] = (gp_down | code) == gp_down
                        key_state.trigger.gamepad[binding.key] = (gp_trigger | code) == gp_trigger
                    else
                        key_state.down.gamepad[binding.key] = false
                        key_state.trigger.gamepad[binding.key] = false
                    end
                end
            end
            return
        end

        if kb then
            for k,v in pairs(keyboard_codes) do
                if is_bindable_enum_member(k, v) then
                    key_state.down.keyboard[k] = kb:call('isDown', v)
                    key_state.trigger.keyboard[k] = kb:call('isTrigger', v)
                else
                    key_state.down.keyboard[k] = false
                    key_state.trigger.keyboard[k] = false
                end
            end
        end
        if gp then
            for k,v in pairs(gamepad_codes) do
                if is_bindable_enum_member(k, v) then
                    key_state.down.gamepad[k] = (gp_down | v) == gp_down
                    key_state.trigger.gamepad[k] = (gp_trigger | v) == gp_trigger
                else
                    key_state.down.gamepad[k] = false
                    key_state.trigger.gamepad[k] = false
                end
            end
        end
    end

    local function capture_triggered_binding()
        for k, v in pairs(key_state.trigger.keyboard) do
            if v and is_bindable_enum_member(k, keyboard_codes[k]) then return {type = 'keyboard', key = k} end
        end
        for k, v in pairs(key_state.trigger.gamepad) do
            if v and is_bindable_enum_member(k, gamepad_codes[k]) then return {type = 'gamepad', key = k} end
        end
        return nil
    end

    local function binding_is_down(binding)
        if type(binding) ~= 'table' or binding.key == nil then return false end
        local enum = binding.type == 'keyboard' and keyboard_codes or binding.type == 'gamepad' and gamepad_codes or nil
        if not enum or not is_bindable_enum_member(binding.key, enum[binding.key]) then return false end
        return key_state.down[binding.type][binding.key] or false
    end

    local function binding_was_triggered(binding)
        if type(binding) ~= 'table' or binding.key == nil then return false end
        local enum = binding.type == 'keyboard' and keyboard_codes or binding.type == 'gamepad' and gamepad_codes or nil
        if not enum or not is_bindable_enum_member(binding.key, enum[binding.key]) then return false end
        return key_state.trigger[binding.type][binding.key] or false
    end

    local function encode_binding(binding)
        if binding == 0 or binding == nil then return nil end
        local enum = binding.type == 'keyboard' and keyboard_codes or binding.type == 'gamepad' and gamepad_codes or nil
        if not enum or not is_bindable_enum_member(binding.key, enum[binding.key]) then return nil end
        if binding.type == 'keyboard' then return string.format('0x%x', enum[binding.key]) end
        return binding.key
    end

    local function decode_binding(str)
        if str == 'null' or str == nil or type(str) ~= 'string' then return nil end
        if string.sub(str, 1, 2) == '0x' then
            local key = keyboard_name_by_code[tonumber(str)]
            if not is_bindable_enum_member(key, key and keyboard_codes[key] or nil) then return nil end
            return {type = 'keyboard', key = key}
        else
            if not is_bindable_enum_member(str, gamepad_codes[str]) then return nil end
            return {type = 'gamepad', key = str}
        end
    end

    local function binding_label(binding) return binding and binding.key or 'Unbound' end

    local function imgui_rebind_button(id, current_binding)
        if binding_capture_id == id then
            imgui.text('Rebinding from ' .. binding_label(current_binding) .. ' (Esc to unbind)')
            imgui.same_line()
            imgui.push_id(id)
            if imgui.button('Keep current') then
                binding_capture_id = nil
                return false, nil
            end
            imgui.pop_id(id)

            local captured_binding = capture_triggered_binding()
            if captured_binding ~= nil then
                binding_capture_id = nil
                if captured_binding.key == 'Escape' then return true, nil
                else return true, captured_binding end
            end
        else
            imgui.push_id(id)
            if imgui.button(current_binding and current_binding.key or 'Unset') then binding_capture_id = id end
            imgui.pop_id(id)
        end
        return false, nil
    end

    return {
        update = poll_inputs,
        is_pressed = binding_is_down,
        was_triggered = binding_was_triggered,
        serialize_key = encode_binding,
        deserialize_key = decode_binding,
        imgui_rebind_button = imgui_rebind_button,
        cancel_capture = function() binding_capture_id = nil end,
    }
end)()
local character_manager = sdk.get_managed_singleton("app.CharacterManager")
local gui_manager = sdk.get_managed_singleton("app.GuiManager")
local npc_manager = sdk.get_managed_singleton("app.NPCManager")
local scene_manager = sdk.get_native_singleton("via.SceneManager")
local scene_manager_type = sdk.find_type_definition("via.SceneManager")
local gui_get_object = sdk.find_type_definition("via.gui.Control"):get_method("getObject(System.String)")
local gui_base_type = sdk.typeof("app.GUIBase")

local movement_control = assert(rawget(_G,"OJR_UnifiedSpeed"))
local passenger_hud = assert(rawget(_G,"OJR_PassengerHud")).new()
local runtime_clock = 0
local player, input

-- Native Input action flags, not keyboard enum values. Legacy mouse controls
-- remain available when this passenger module is exercised on its own.
local MOUSE_DASH_FLAG = 16777218
local MOUSE_WALK_FLAG = 1946159104

-- Each cart family keeps an independent preset cursor.
local preset_cursor = { Normal = 1, Rainy = 1, Wealthy = 1 }
local last_sit_preset = {}
local last_sit_request_at = nil

math.randomseed(os.time())

-- Optional passenger idle variations.
local passenger_idle_nodes = {
    "SitOnChairActions",
    "LivSitChairCrosslegs",
    "LivSitChairLean",
    "SitOnChairCrossArmStart",
    "LivSitPose",
    "LivSitChairBook01",
    "LivSitChairLoseieus"
}

local function is_character_valid(character)
    if not character then return false end
    local success, valid = pcall(function() return character:get_Valid() end)
    return success and valid or false
end

-- Release bindings left by a previous hot reload. The legacy key is read once
-- so upgrading an active session cannot leave pawns parented to the cart.
local legacy_seat_bindings = _G.BetterOxcarts_BoundPawns
local previous_seat_bindings = _G.OJR_SeatBindings or legacy_seat_bindings
_G.OJR_PendingFsmRestores = rawget(_G,"OJR_PendingFsmRestores") or {}
for binding in pairs(_G.OJR_PendingFsmRestores) do binding.restore_attempts,binding.restore_next_at=0,0 end
if previous_seat_bindings then
    for _, item in ipairs(previous_seat_bindings) do
        local char = item
        if type(item) == "table" and item.char then char = item.char end
        local readable,valid=pcall(function() return char and char:get_Valid() end)
        if type(item)=="table" and item.fsm_machine then
            local restored=readable and valid==true and pcall(function()
                item.fsm_machine:call("set_Enabled(System.Boolean)",item.fsm_enabled)
            end)
            if restored or (readable and valid==false) then
                _G.OJR_PendingFsmRestores[item]=nil
                item.fsm_machine,item.fsm_enabled=nil,nil
            else
                item.fsm_freeze_frame,item.fsm_freeze_at=nil,nil
                _G.OJR_PendingFsmRestores[item]=true
            end
        end
        if readable and valid==true then pcall(function() char:get_Transform():set_Parent(nil) end) end
    end
end
_G.BetterOxcarts_BoundPawns = nil
_G.OJR_PendingSeatRelease = nil
_G.OJR_SeatBindings = {}

local seating_lock_active = false
local seat_bindings = _G.OJR_SeatBindings
local seat_anchor_transform = nil 

-- Session state shared by the frame updater and damage hooks.
local prior_cart_seat_state = false
local prior_player_seat_state = false
local previous_fast_travel_state = 0
local reseat_requested_at = nil
local photo_mode_was_active = false

local CART_START_GRACE = 10.0
local RUSH_STOP_CONFIRM = 2.0
local RUSH_STOP_SPEED = 0.5
local cart_trip = {
    manual_standing_seats = false,
    seat_changed_at = nil,
    rush_requested_at = nil,
    last_position = nil,
    last_position_at = nil,
    has_moved_in_rush = false,
    stopped_since = nil,
    braked_for_destination = false,
    arrival_was_false = false,
    last_check_at = nil,
    paid_status_address = nil,
    paid_seen = false,
    paid_current = nil,
    ticket_loss_handled = false,
    intermediate_arrival_seen = false,
    intermediate_arrival_checked = false,
    stopover_wait_armed = false,
    intermediate_arrival_result = nil,
    walk_since = nil, walk_angle = nil, walk_turn = 0,
    departure_pending = false, auto_paused = false,
    destination = nil, auto_reason = nil,
    pause = { active = false, resume_pending = false },
    stop_reason = nil,
}

if _G.OJR_ReseatPending == nil then
    _G.OJR_ReseatPending = _G.BetterOxcarts_PendingReseat or false
end
_G.BetterOxcarts_PendingReseat = nil

local function vec_add(v1, v2) return Vector3f.new(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z) end
local function vec_scale(v, s) return Vector3f.new(v.x * s, v.y * s, v.z * s) end

local options = {
    DASH_DURATION = 360,
    AUTO_RUSH = true,
    RECOVERY_WALK_SECONDS = 4.0,
    RECOVERY_MAX_TURN = 60.0,
    DESTINATION_BRAKE_DISTANCE = 15.0,
    DRIVER_NONCOMBAT = true,
    CART_NONCOMBAT = true,
    PLAYER_NEAR_CART_NONCOMBAT = true,
    DISABLE_CAMERA = true,
    STATUS_IMMUNITY = true,
    FREEZE_COMPANION_FSM = true,
    PREVENT_CART_BREAKUP = true,
    
    Key_PadModifyKey = {type = 'gamepad', key = 'LTrigBottom'},
    Key_MouseModifyKey = {type = 'keyboard', key = 'LShift'},

    Key_PadModifyDash = {type = 'gamepad', key = 'LUp'},
    Key_MouseModifyDash = {type = 'keyboard', key = 'Alpha1'},
    Key_PadModifyWalk = {type = 'gamepad', key = 'LLeft'},
    Key_MouseModifyWalk = {type = 'keyboard', key = 'Alpha2'},
    Key_PadModifyTeleport = {type = 'gamepad', key = 'LRight'},
    Key_MouseModifyTeleport = {type = 'keyboard', key = 'Alpha3'},
    Key_PadModifyStand = {type = 'gamepad', key = 'LDown'},
    Key_MouseModifyStand = {type = 'keyboard', key = 'Alpha4'},
    
    Key_PadSkillTeleport = {type = 'gamepad', key = 'RLeft'},
    Key_MouseSkillTeleport = {type = 'keyboard', key = 'E'},
    Key_PadSkillStand = {type = 'gamepad', key = 'Cancel'},
    Key_MouseSkillStand = {type = 'keyboard', key = 'F'},
    
    Key_PadSkillDash = {type = 'gamepad', key = 'RTrigTop'},
    Key_MouseSkillDash = {type = 'keyboard', key = 'None'},--已硬编码鼠标左右键
    Key_PadSkillWalk = {type = 'gamepad', key = 'LTrigTop'},
    Key_MouseSkillWalk = {type = 'keyboard', key = 'None'},--已硬编码鼠标左右键

    UnifiedVersion = 0,
    ManualSettings = {},
    Presets = {}
}

local default_key_bindings = {}
for name, binding in pairs(options) do
    if name:find("^Key_") then
        default_key_bindings[name] = { type = binding.type, key = binding.key }
    end
end

local watched_inputs = {}

local function is_key_valid(k)
    return type(k) == "table" and k.type ~= nil and k.key ~= nil
end

local function rebuild_input_watchlist()
    watched_inputs = {}
    for k, v in pairs(options) do
        if type(v) == "table" and k:find("Key_") and is_key_valid(v) then
            table.insert(watched_inputs, v)
        end
    end
end

-- Built-in seat layouts are grouped by cart body type.
local function get_default_normal_presets()
    -- aelinore layouts imported from the local OJR configuration.
    return {
        {
            ["builtin_id"] = "passenger:Normal:1",
            ["driver"] = {["randomIdle"]=false,["x"]=-0.050999999046325684,["y"]=0.9200000166893005,["yaw"]=178,["z"]=0.33399999141693115},
            ["driver_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[1] Facing Each Other",
            ["passenger_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            pawns = {
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-3.35},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.23,["z"]=-3.35},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.23,["z"]=-2.5},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.25,["z"]=-4.050000190734863},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-2.7},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = false,
        },
        {
            ["builtin_id"] = "passenger:Normal:2",
            ["driver"] = {["randomIdle"]=false,["x"]=-0.050999999046325684,["y"]=0.9200000166893005,["yaw"]=178,["z"]=0.33399999141693115},
            ["driver_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[2] Side by Side",
            ["passenger_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            pawns = {
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-3.35},
                {["anim"]="SitOnChairCrossArmStart",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.23,["z"]=-3.35},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-4.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.8999999761581421,["y"]=0.25,["z"]=-4.050000190734863},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = false,
        },
        {
            ["builtin_id"] = "passenger:Normal:3",
            ["driver"] = {["randomIdle"]=false,["x"]=-0.050999999046325684,["y"]=0.9200000166893005,["yaw"]=178,["z"]=0.33399999141693115},
            ["driver_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[3] Look Around",
            ["passenger_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            pawns = {
                {["anim"]="LivSitChairCrosslegs",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=1.35,["y"]=0.77,["z"]=-2},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.23,["z"]=-3.35},
                {["anim"]="SitOnChairCrossArmStart",["bankID"]=0,["lookX"]=1,["lookZ"]=1,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-4.6},
                {["anim"]="LivSitChairCrosslegs",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=-1.350000023841858,["y"]=0.7699999809265137,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-2.7},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = false,
        },
        {
            ["builtin_id"] = "passenger:Normal:4",
            ["driver"] = {["randomIdle"]=false,["x"]=-0.050999999046325684,["y"]=0.9200000166893005,["yaw"]=178,["z"]=0.33399999141693115},
            ["driver_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[4] Sit on the Edge",
            ["passenger_camera"] = {["distance"]=3.9820001125335693,["distance_enabled"]=true,["fov"]=60.84600067138672,["fov_enabled"]=true},
            pawns = {
                {["anim"]="LivSitChairCrosslegs",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=1.25,["y"]=0.77,["z"]=-2},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-1.25,["y"]=0.8,["z"]=-3.35},
                {["anim"]="SitOnChairCrossArmStart",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.25,["z"]=-4.2},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.25,["z"]=-3.450000047683716},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-2.7},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=1.25,["y"]=0.77,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = true,
        },
    }
end

local function get_default_rainy_presets()
    -- aelinore layouts imported from the local OJR configuration.
    return {
        {
            ["builtin_id"] = "passenger:Rainy:1",
            ["driver"] = {["anim"]="SitOnChairActions",["randomIdle"]=false,["x"]=-0.051,["y"]=0.92,["yaw"]=178,["z"]=0.334},
            ["driver_camera"] = {["distance"]=4.803999900817871,["distance_enabled"]=true,["fov"]=75.33699798583984,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[1] Rainy - Side by Side",
            ["passenger_camera"] = {["distance"]=1.2000000476837158,["distance_enabled"]=true,["fov"]=75.33699798583984,["fov_enabled"]=true},
            pawns = {
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-3.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.23,["z"]=-3.35},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-4.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1.0,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.8500000238418579,["y"]=0.23000000417232513,["z"]=-4.349999904632568},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = false,
        },
        {
            ["builtin_id"] = "passenger:Rainy:2",
            ["driver"] = {["anim"]="SitOnChairActions",["randomIdle"]=false,["x"]=-0.051,["y"]=0.92,["yaw"]=178,["z"]=0.334},
            ["driver_camera"] = {["distance"]=4.803999900817871,["distance_enabled"]=true,["fov"]=75.33699798583984,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[2] Rainy - Facing Each Other",
            ["passenger_camera"] = {["distance"]=1.2000000476837158,["distance_enabled"]=true,["fov"]=75.33699798583984,["fov_enabled"]=true},
            pawns = {
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-1,["y"]=0.23,["z"]=-2.35},
                {["anim"]="SitOnChairCrossArmStart",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.95,["y"]=0.23,["z"]=-4.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-4.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1.0,["lookZ"]=0.0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.949999988079071,["y"]=0.23000000417232513,["z"]=-3.1500000953674316},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.1},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-2.7},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = false,
        },
    }
end

local function get_default_wealthy_presets()
    -- aelinore layouts imported from the local OJR configuration.
    return {
        {
            ["builtin_id"] = "passenger:Wealthy:1",
            ["driver"] = {["anim"]="SitOnChairActions",["randomIdle"]=false,["x"]=0,["y"]=0.92,["yaw"]=180,["z"]=0.274},
            ["driver_camera"] = {["distance"]=5.704999923706055,["distance_enabled"]=true,["fov"]=75.33699798583984,["fov_enabled"]=true},
            ["enabled"] = true,
            ["name"] = "[1] Luxury - Facing Each Other",
            ["passenger_camera"] = {["distance"]=5.704999923706055,["distance_enabled"]=true,["fov"]=75.33699798583984,["fov_enabled"]=true},
            pawns = {
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=0,["lookZ"]=-1,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.45,["y"]=0.23,["z"]=-3.15},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=0,["lookZ"]=1,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.5,["y"]=0.23,["z"]=-1.2},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=0,["lookZ"]=1,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.5,["y"]=0.23,["z"]=-1.25},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0,["y"]=0.85,["z"]=-1.9000000000000001},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-2.7},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=-1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=-0.85,["y"]=0.85,["z"]=-3.5000000000000004},
                {["anim"]="SitOnChairActions",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["pelvisCompensation"]=false,["randomIdle"]=true,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.85,["z"]=-4.300000000000001},
            },
            ["player"] = {["anim"]="Wait",["bankID"]=0,["lookX"]=1,["lookZ"]=0,["motionID"]=0,["randomIdle"]=false,["useDirectMotion"]=false,["x"]=0.85,["y"]=0.23,["z"]=-2.55},
            ["skipPassenger"] = false,
            ["teleportPlayer"] = false,
        },
    }
end

local function normalize_presets(target)
    local options=target or options
    if type(options.Presets) ~= "table" then
        options.Presets = {}
    end
    
    -- A flat preset list belongs to the original Normal category.
    if #options.Presets > 0 and not options.Presets.Normal then
        local old_presets = {}
        for i, p in ipairs(options.Presets) do old_presets[i] = p end
        options.Presets = {
            Normal = old_presets,
            Rainy = get_default_rainy_presets(),
            Wealthy = get_default_wealthy_presets()
        }
    end
    
    -- Supply any category that is absent or empty.
    if not options.Presets.Normal or #options.Presets.Normal == 0 then options.Presets.Normal = get_default_normal_presets() end
    if not options.Presets.Rainy or #options.Presets.Rainy == 0 then options.Presets.Rainy = get_default_rainy_presets() end
    if not options.Presets.Wealthy or #options.Presets.Wealthy == 0 then options.Presets.Wealthy = get_default_wealthy_presets() end
    
    for cat_name, cat_presets in pairs(options.Presets) do
        for _, preset in ipairs(cat_presets) do
            preset.enabled = true -- All layouts participate in cycling, including legacy disabled ones.
            if type(preset.teleportPlayer) ~= "boolean" then preset.teleportPlayer = false end
            preset.skipPassenger=preset.skipPassenger==true
            preset.name = preset.name or "Unnamed Preset"
            
            preset.player = preset.player or {}
            preset.player.x = preset.player.x or 0.0
            preset.player.z = preset.player.z or 0.0
            preset.player.y = preset.player.y or 0.85
            preset.player.lookX = preset.player.lookX or 0.0
            preset.player.lookZ = preset.player.lookZ or 0.0
            preset.player.anim = preset.player.anim or "SitOnChairActions"
            -- Obsolete seat flags are discarded without changing saved coordinates.
            preset.player.useOxAnchor, preset.player.freezeFsm = nil, nil
            if type(preset.player.randomIdle) ~= "boolean" then preset.player.randomIdle = false end
            if type(preset.player.useDirectMotion) ~= "boolean" then preset.player.useDirectMotion = false end
            preset.player.bankID = preset.player.bankID or 0
            preset.player.motionID = preset.player.motionID or 0

            preset.pawns = preset.pawns or {}
            for i = 1, 9 do
                if i>3 and not preset.pawns[i] then
                    local chosen
                    for row=0,4 do
                        for _,x in ipairs({0.85,-0.85,0}) do
                            local z=-1.1-row*0.8
                            local free=true
                            for _,slot in ipairs(preset.pawns) do
                                if (x-(slot.x or 0))^2+(z-(slot.z or 0))^2<0.65^2 then free=false;break end
                            end
                            if free then chosen={x=x,y=0.85,z=z,lookX=x>=0 and 1 or -1,lookZ=0,randomIdle=true};break end
                        end
                        if chosen then break end
                    end
                    preset.pawns[i]=chosen or {x=0,y=0.85,z=-1.1-(i-1)*0.8,lookX=1,lookZ=0,randomIdle=true}
                end
                if not preset.pawns[i] then preset.pawns[i] = {} end
                preset.pawns[i].x = preset.pawns[i].x or 0.0
                preset.pawns[i].z = preset.pawns[i].z or 0.0
                preset.pawns[i].y = preset.pawns[i].y or 0.85
                preset.pawns[i].lookX = preset.pawns[i].lookX or 0.0
                preset.pawns[i].lookZ = preset.pawns[i].lookZ or 0.0
                preset.pawns[i].anim = preset.pawns[i].anim or "SitOnChairActions"
                preset.pawns[i].useOxAnchor, preset.pawns[i].freezeFsm = nil, nil
                preset.pawns[i].pelvisCompensation=preset.pawns[i].pelvisCompensation==true
                if type(preset.pawns[i].randomIdle) ~= "boolean" then preset.pawns[i].randomIdle = false end
                if type(preset.pawns[i].useDirectMotion) ~= "boolean" then preset.pawns[i].useDirectMotion = false end
                preset.pawns[i].bankID = preset.pawns[i].bankID or 0
                preset.pawns[i].motionID = preset.pawns[i].motionID or 0
            end
        end
    end
end

local fixed_cart_parameters = {
    DASH_DURATION = true, RECOVERY_WALK_SECONDS = true,
    RECOVERY_MAX_TURN = true, DESTINATION_BRAKE_DISTANCE = true,
    AUTO_RUSH = true, DRIVER_NONCOMBAT = true,
    CART_NONCOMBAT = true, PLAYER_NEAR_CART_NONCOMBAT = true,
}

local function load_options()
    local loaded = json.load_file("OxcartsJourneyRedux.json")
    if loaded then
        for k, v in pairs(loaded) do
            if options[k] ~= nil and not fixed_cart_parameters[k] then
                if k == "Presets" then
                    -- Accept both the original flat array and categorized data.
                    if #v > 0 and not v.Normal then
                        options.Presets.Normal = v
                    else
                        options.Presets = v
                    end
                elseif k:find("Key_") then
                    local success, parsed = pcall(input_bindings.deserialize_key, v)
                    if success and is_key_valid(parsed) then
                        if parsed.type == "mouse" then parsed.type = "keyboard" end
                        options[k] = parsed
                    end
                else
                    options[k] = v
                end
            end
        end
    end
    normalize_presets()
    options.FREEZE_COMPANION_FSM=true
    options.COMPANION_PELVIS_COMPENSATION=nil
    options.PREVENT_CART_BREAKUP=true
    rebuild_input_watchlist()
end

local function persist_options()
    if unified_presets and unified_presets.reindex then unified_presets.reindex() end
    local save_data = {}
    for k, v in pairs(options) do
        if type(v) == "table" and is_key_valid(v) and k:find("Key_") then
            save_data[k] = input_bindings.serialize_key(v)
        else
            save_data[k] = v
        end
    end
    json.dump_file("OxcartsJourneyRedux.json", save_data)
    rebuild_input_watchlist()
end

local function restore_default_key_bindings()
    input_bindings.cancel_capture()
    for name, binding in pairs(default_key_bindings) do
        options[name] = { type = binding.type, key = binding.key }
    end
    persist_options()
end

load_options()
unified_presets.init(options,preset_cursor,persist_options,normalize_presets,{
    Normal=get_default_normal_presets(),Rainy=get_default_rainy_presets(),Wealthy=get_default_wealthy_presets()
})

local function gameplay_is_paused()
    local paused = false
    pcall(function() paused = gui_manager:isPausedGUI() == true end)
    pcall(function() paused = paused or gui_manager:call("get_IsPausedGUINoLock()") == true end)
    pcall(function() paused = paused or gui_manager["<IsDispPhotoModeAll>k__BackingField"] == true end)
    return paused
end

local last_clock_sample = 0
local function update_runtime_clock()
    local deltaTime = os.clock() - last_clock_sample
    last_clock_sample = os.clock()
    if gameplay_is_paused() then deltaTime = 0 return end
    runtime_clock = runtime_clock + deltaTime
end

local function find_active_ox()
    if manual_cart then return manual_cart.ox end
    local oxObject = npc_manager.OxcartManager._RaidAttack_CachedGameObject
    if not oxObject then return nil end
    local is_valid = false
    pcall(function() is_valid = oxObject:get_Valid() end)
    if not is_valid then return nil end
    
    local char = nil
    pcall(function() char = oxObject:call("getComponent(System.Type)", sdk.typeof("app.Character")) end)
    return char
end

local function find_cart_body(ox)
    if manual_cart and ox==manual_cart.ox then return manual_cart.body end
    if not ox then return nil end
    local ox_pos = nil
    pcall(function() ox_pos = ox:get_Transform():get_Position() end)
    if not ox_pos then return nil end

    local scene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene()")
    if not scene then return nil end
    
    -- Candidate names cover the known cart-body variants.
    local possible_names = {
        "gm80_042", -- 雨天顶棚车厢 / 动态生成的普通车
        "gm80_052", -- 富人车厢
        "gm81_004"  -- 幽灵牛车 (备用)
    }
    -- Standard bodies can carry a numbered suffix.
    for i = 0, 10 do
        table.insert(possible_names, string.format("gm80_042_%02d", i))
        table.insert(possible_names, string.format("gm80_052_%02d", i))
    end

    -- Resolve the first valid body object without retaining stale wrappers.
    for _, cart_name in ipairs(possible_names) do
        local cart_go = scene:call("findGameObject(System.String)", cart_name)
        if cart_go then
            local is_valid = false
            pcall(function() is_valid = cart_go:get_Valid() end)
            if is_valid then
                local cart_transform = cart_go:get_Transform()
                if (ox_pos - cart_transform:get_Position()):length() < 12.0 then
                    return cart_transform 
                end
            end
        end
    end
    return nil
end

-- Select the preset family from stable model hints on the active cart body.
local function classify_cart_model(cart_transform)
    if not cart_transform then return "Normal" end
    local go = cart_transform:get_GameObject()
    if not go then return "Normal" end
    local name = go:get_Name()
    if not name then return "Normal" end
    
    if string.find(name, "gm80_052") then 
        return "Wealthy" 
    elseif name == "gm80_042_00" then 
        return "Normal" 
    elseif string.find(name, "gm80_042") then 
        return "Rainy" 
    end
    
    return "Normal"
end

local function resolve_seat_anchor(cart_transform)
    if not cart_transform then return nil end
    local child = cart_transform:get_Child()
    local backup_anchor = cart_transform
    while child do
        local name = nil
        pcall(function() name = child:get_GameObject():get_Name() end)
        -- MoveFloor owns the coordinate space used by the seat offsets.
        if name and name:find("MoveFloor") then
            return child 
        end
        child = child:get_Next()
    end
    return backup_anchor
end

local function player_cart_distance(ox)
    local ok, distance = pcall(function()
        if not is_character_valid(ox) or not is_character_valid(player) then return nil end
        local a = ox:get_Transform():get_UniversalPosition()
        local b = player:get_Transform():get_UniversalPosition()
        local dx, dy, dz = tonumber(a.x) - tonumber(b.x), tonumber(a.y) - tonumber(b.y), tonumber(a.z) - tonumber(b.z)
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return ok and distance or nil
end

local function player_is_near_cart(ox)
    local distance = player_cart_distance(ox)
    return distance ~= nil and distance <= 20.0
end

local function player_is_cart_passenger(ox)
    if not ox then return false end
    local is_sitting = false
    pcall(function()
        if not ox:get_Valid() then return end
        -- Read the live cart controller first. Motion IDs remain a fallback
        -- for moments when the controller has not finished initializing.
        local enemy_controller = ox.EnemyCtrl
        local ch2 = enemy_controller and enemy_controller.Ch2
        local cart_controller = ch2 and ch2["<CachedOxcart>k__BackingField"]
        local sitting = cart_controller and cart_controller:isPlayerSit() or false
        if not cart_controller then
            local action_manager = player["<ActionManager>k__BackingField"]
            local current_action = action_manager and action_manager.CurrentActionList and action_manager.CurrentActionList[0]
            local action_name = current_action and current_action.Name or ""
            local layer = player:get_Motion():getLayer(0)
            local motion_bank = layer and layer:get_MotionBankID() or -1
            local motion_id = layer and layer:get_MotionID() or -1
            sitting = (motion_bank == 60 or (action_name ~= "UseSealBottle" and motion_bank == 0)) and motion_id == 2010
        end
        if not sitting then return end
        
        local oxID = ox:get_CharaID()
        local status = npc_manager.OxcartManager:getStatus(oxID)
        if status and status:get_isPayMoney() then 
            is_sitting = true 
        end
    end)
    return is_sitting
end

-- Motion-only seat detection is used while entering or leaving the cart.
local function player_uses_cart_seat_node()
    if not player or not player:get_Valid() then return false end
    local is_sit = false
    pcall(function()
        local action_manager = player["<ActionManager>k__BackingField"]
        local current_action = action_manager and action_manager.CurrentActionList and action_manager.CurrentActionList[0]
        local action_name = current_action and current_action.Name or ""
        
        local layer = player:get_Motion():getLayer(0)
        if layer then
            local motion_bank = layer:get_MotionBankID()
            local motion_id = layer:get_MotionID()
            is_sit = (motion_bank == 60 or (action_name ~= "UseSealBottle" and motion_bank == 0)) and motion_id == 2010
        end
    end)
    return is_sit
end

-- Ticket ownership is deliberately separate from the controller's seat state.
local function player_is_physically_seated(ox)
    local ok, sitting = pcall(function()
        local cart = ox and ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        return cart and cart:call("isPlayerSit()")
    end)
    if ok and type(sitting) == "boolean" then return sitting end
    return player_uses_cart_seat_node()
end

local function install_cart_interaction_overrides()
    local ox_mgr_def = sdk.find_type_definition("app.OxcartManager")
    if ox_mgr_def then
        for _, method in ipairs(ox_mgr_def:get_methods()) do
            local name = method:get_name():lower()
            local ret = method:get_return_type()
            if ret and ret:get_name() == "Boolean" then
                if name:find("israid") or name:find("isattack") or name:find("isbattle") then
                    sdk.hook(method, function(args) end, function(retval) return sdk.to_ptr(0) end)
                end
                if name:find("isenable") or name:find("iscan") or name:find("allow") then
                    if name:find("ride") or name:find("board") or name:find("interact") or name:find("sit") then
                        sdk.hook(method, function(args) end, function(retval) return sdk.to_ptr(1) end)
                    end
                end
            end
        end
    end
end
pcall(install_cart_interaction_overrides)

local function modifier_is_down()
    local pad_mod = false
    local mouse_mod = false
    if is_key_valid(options.Key_PadModifyKey) then
        local s, v = pcall(input_bindings.is_pressed, options.Key_PadModifyKey)
        pad_mod = s and v
    end
    if is_key_valid(options.Key_MouseModifyKey) then
        local s, v = pcall(input_bindings.is_pressed, options.Key_MouseModifyKey)
        mouse_mod = s and v
    end
    return pad_mod or mouse_mod
end

local function collect_party_pawns()
    local pawn_manager = sdk.get_managed_singleton("app.PawnManager")
    if not pawn_manager then return nil end -- Unavailable is not an empty party.
    local party_members, roster = {}, {}
    local main_pawn = pawn_manager:get_MainPawn()
    if main_pawn then
        local main_character = main_pawn:get_CachedCharacter()
        if main_character and main_character:get_Valid() then
            party_members[1] = main_character
            roster[main_character] = true
        end
    end
    local partyList = pawn_manager:get_PartyPawnList()
    if partyList then
        local count = partyList:get_Count()
        for i = 0, count - 1 do
            -- The backing array survives API wrapper changes; get_Item remains
            -- a compatibility fallback for builds that do not expose it.
            local pawn = partyList._items and partyList._items[i] or nil
            if not pawn then
                local success, item = pcall(function() return partyList:get_Item(i) end)
                if success then pawn = item end
            end
            if pawn then
                local pawn_character = pawn:get_CachedCharacter()
                if pawn_character and pawn_character:get_Valid() then
                    roster[pawn_character] = true
                    local party_slot = tonumber(pawn_manager:getPartyPawnID(pawn))
                    if pawn_character == party_members[1] then
                        -- Main Pawn may also appear in the party list; never duplicate it.
                    elseif party_slot == 1 then party_members[2] = pawn_character
                    elseif party_slot == 2 then party_members[3] = pawn_character
                    else
                        local exists=false
                        for _,ch in pairs(party_members) do if ch==pawn_character then exists=true;break end end
                        if not exists then
                            local index=4
                            while party_members[index] do index=index+1 end
                            party_members[index]=pawn_character
                        end
                    end
                end
            end
        end
    end
    local ordered={}
    local last=3
    for index in pairs(party_members) do last=math.max(last,index) end
    for i=1,last do if party_members[i] then ordered[#ordered+1]=party_members[i] end end
    return ordered, roster
end

local escort_roster={actors={},next_scan=0}
local function companion_interacting(ch)
    local ok,value=pcall(function()
        local manager=sdk.get_managed_singleton("app.InteractManager")
        return manager and manager:call("isInteracting(app.Character)",ch)
    end)
    return ok and value==true
end
local function collect_companions()
    local party_ok,members,roster=pcall(collect_party_pawns)
    if not party_ok or not members or not roster then return nil end
    local guests={}
    if runtime_clock>=escort_roster.next_scan then
        escort_roster.next_scan=runtime_clock+1
        local prior={}
        for _,ch in ipairs(escort_roster.actors) do prior[ch]=true end
        local ok,found=pcall(function()
            local nm=sdk.get_managed_singleton("app.NPCManager")
            assert(nm and nm.NPCHolderDic,"NPC roster unavailable")
            local td=sdk.find_type_definition("app.NPCUtil")
            local method=td and td:get_method("isAccompanyPLParty(app.Character)")
            assert(method,"NPC membership unavailable")
            local list,seen={},{}
            for _,holder in pairs(nm.NPCHolderDic) do
                local ch
                pcall(function() ch=holder and nm:getCharacter(holder.CharaID) end)
                if is_character_valid(ch) and ch~=player and not roster[ch] and not seen[ch] then
                    seen[ch]=true
                    local read_ok,following=pcall(function() return method:call(nil,ch) end)
                    if (read_ok and following==true) or ((not read_ok or type(following)~="boolean") and prior[ch]) then list[#list+1]=ch end
                end
            end
            table.sort(list,function(a,b) return a:get_address()<b:get_address() end)
            return list
        end)
        if ok then escort_roster.actors=found end
    end
    for _,ch in ipairs(escort_roster.actors) do
        if is_character_valid(ch) and ch~=player and not roster[ch] then
            guests[ch]=true;roster[ch]=true;members[#members+1]=ch
        end
    end
    return members,roster,guests
end

-- Pawn root transforms, universal position and physical controller must agree.
-- Player positions remain owned by the existing native passenger interaction.
local pawn_seat_physics = {}
function pawn_seat_physics.request_pose_action(character, node, priority)
    local manager = character["<ActionManager>k__BackingField"]
    assert(manager, "Pawn ActionManager unavailable")
    manager:requestActionCore(priority, node, 0)
end
function pawn_seat_physics.restore_fsm(binding, retry)
    if not binding then return true end
    binding.fsm_freeze_frame,binding.fsm_freeze_at=nil,nil
    for _,entry in ipairs({{"OJR_CompanionDisplay","release"},{"OJR_RuntimeDiagnostics","cancel_pose"},
        {"OJR_UnifiedPelvis","invalidate"}}) do
        local service=rawget(_G,entry[1])
        if service then pcall(service[entry[2]],binding) end
    end
    local pending=rawget(_G,"OJR_PendingFsmRestores") or {}
    _G.OJR_PendingFsmRestores=pending
    if binding.fsm_machine then
        local ok,err=pcall(function()
            local valid=binding.char and binding.char:get_Valid()
            assert(type(valid)=="boolean","Companion validity unreadable")
            if valid then
                binding.fsm_machine:call("set_Enabled(System.Boolean)",binding.fsm_enabled)
            end
        end)
        if not ok then
            if not pending[binding] then log.error("Companion FSM restore failed; recovery queued: "..tostring(err)) end
            pending[binding]=true
            binding.restore_attempts=(binding.restore_attempts or 0)+(retry and 1 or 0)
            binding.restore_next_at=os.clock()+1
            return false
        end
        binding.fsm_machine,binding.fsm_enabled=nil,nil
    end
    pending[binding]=nil
    binding.restore_attempts,binding.restore_next_at=nil,nil
    return true
end
function pawn_seat_physics.retry_fsm_restores()
    local pending=rawget(_G,"OJR_PendingFsmRestores")
    if not pending or not next(pending) then return end
    local now=os.clock()
    for binding in pairs(pending) do
        -- Exhausted records survive reset/reload; never recapture their frozen state.
        local ok,valid=pcall(function() return binding.char and binding.char:get_Valid() end)
        if ok and valid==false then
            pending[binding]=nil;binding.fsm_machine,binding.fsm_enabled=nil,nil
        elseif (binding.restore_attempts or 0)<5 and now>=(binding.restore_next_at or 0) then
            pawn_seat_physics.restore_fsm(binding,true)
        end
    end
end
function pawn_seat_physics.begin_pose(binding)
    if not binding or binding.char==player then return end
    for prior in pairs(rawget(_G,"OJR_PendingFsmRestores") or {}) do
        assert(prior.char~=binding.char,"Companion FSM recovery pending")
    end
    if rawget(_G,"OJR_UnifiedPelvis") then _G.OJR_UnifiedPelvis.invalidate(binding) end
    if options.FREEZE_COMPANION_FSM==false then pawn_seat_physics.restore_fsm(binding);return end
    if not binding.fsm_machine then
        local human=binding.char["<Human>k__BackingField"]
        local machine=human and human.Fsm
        if not machine then
            local manager=binding.char["<ActionManager>k__BackingField"] or binding.char:get_ActionManager()
            machine=manager and manager.Fsm
        end
        assert(machine,"Companion FSM unavailable")
        local enabled=machine:call("get_Enabled()")
        assert(type(enabled)=="boolean","Cannot capture companion FSM state")
        binding.fsm_machine,binding.fsm_enabled=machine,enabled
    end
    binding.fsm_machine:call("set_Enabled(System.Boolean)",true)
    binding.fsm_freeze_frame=(pawn_seat_physics.frame or 0)+1
    binding.fsm_freeze_at=nil
end
function pawn_seat_physics.update_fsm(binding)
    if binding.char==player then return end
    if options.FREEZE_COMPANION_FSM==false then pawn_seat_physics.restore_fsm(binding);return end
    if not binding.fsm_machine then pawn_seat_physics.begin_pose(binding) end
    local due=binding.fsm_freeze_frame and (pawn_seat_physics.frame or 0)>=binding.fsm_freeze_frame
        or (not binding.fsm_freeze_frame and runtime_clock>=(binding.fsm_freeze_at or math.huge))
    if due then
        local diagnostics=rawget(_G,"OJR_RuntimeDiagnostics")
        if diagnostics then pcall(diagnostics.mark_pose,binding,seat_anchor_transform,'before-freeze',pawn_seat_physics.frame or 0,runtime_clock) end
        binding.fsm_machine:call("set_Enabled(System.Boolean)",false)
        binding.fsm_freeze_frame=nil
        if diagnostics then pcall(diagnostics.mark_pose,binding,seat_anchor_transform,'after-freeze',pawn_seat_physics.frame or 0,runtime_clock) end
    end
end
function pawn_seat_physics.advance_frame()
    pawn_seat_physics.retry_fsm_restores()
    pawn_seat_physics.frame=(pawn_seat_physics.frame or 0)+1
    for i=#seat_bindings,1,-1 do
        local binding=seat_bindings[i]
        if binding.fsm_freeze_frame then
            local ok,err=pcall(pawn_seat_physics.update_fsm,binding)
            if not ok then pawn_seat_physics.remove(i);log.error("Companion next-frame freeze failed: "..tostring(err)) end
        end
    end
end
function pawn_seat_physics.prepare(character)
    local context = character["<PosRotContext>k__BackingField"]
    local terrain = character["<AdjustTerrain>k__BackingField"]
    local controller = terrain and terrain.MainCharacterController
    local fall = character["<FallInfo>k__BackingField"]
    assert(context and controller and fall, "Pawn seat physics unavailable")
    return context, controller, fall
end
function pawn_seat_physics.synchronize(character, transform)
    local context, controller = pawn_seat_physics.prepare(character)
    local universal_position = transform:get_UniversalPosition()
    context:call("setPos(via.Position)", universal_position)
    -- No-argument warp reads the owning transform; never pass scene vec3 to setPos.
    controller:call("warp()")
end
function pawn_seat_physics.reset_fall(character)
    local _,_,fall=pawn_seat_physics.prepare(character)
    local universal_position=character:get_Transform():get_UniversalPosition()
    fall:call("resetBaseHeight(via.Position)", universal_position)
    fall:call("resetFallHeight()")
end
function pawn_seat_physics.place(character,seat_spec)
    if character~=player then pawn_seat_physics.prepare(character) end
    local anchor=assert(seat_anchor_transform,"Seat anchor unavailable")
    local origin=anchor:get_Position()
    local x,y,z=anchor:get_AxisX(),anchor:get_AxisY(),anchor:get_AxisZ()
    local pos=vec_add(vec_add(vec_add(origin,vec_scale(x,seat_spec.x)),vec_scale(z,seat_spec.z)),vec_scale(y,seat_spec.y))
    local target=vec_add(pos,vec_add(vec_scale(x,seat_spec.lookX),vec_scale(z,seat_spec.lookZ)))
    if seat_spec.lookX==0 and seat_spec.lookZ==0 then target=vec_add(pos,x) end
    local transform=character:get_Transform()
    local observer=rawget(_G,"OJR_HeightObserver")
    if type(observer)=="function" then pcall(observer,"BeforeSeatWrite",character,anchor,seat_spec,pawn_seat_physics.frame) end
    if character==player then
        pawn_seat_physics.restore_player_display()
        local p=transform:get_Position()
        local ok,rotation=pcall(function() return transform:get_Rotation() end)
        pawn_seat_physics.player_display={char=character,position=Vector3f.new(p.x,p.y,p.z),rotation=ok and rotation or nil}
    end
    transform:set_Position(pos)
    transform:lookAt(target,y)
    if character~=player then pawn_seat_physics.synchronize(character,transform) end
    if type(observer)=="function" then pcall(observer,"AfterSeatWrite",character,anchor,seat_spec,pawn_seat_physics.frame) end
end
function pawn_seat_physics.restore_player_display()
    local display=pawn_seat_physics.player_display
    pawn_seat_physics.player_display=nil
    if display and is_character_valid(display.char) then
        pcall(function()
            local transform=display.char:get_Transform()
            transform:set_Position(display.position)
            if display.rotation then transform:set_Rotation(display.rotation) end
        end)
    end
end
function pawn_seat_physics.sync_player_adjustment(preset)
    -- Update only the player binding; do not restart any companion pose/FSM.
    for i=#seat_bindings,1,-1 do
        if seat_bindings[i].char==player then table.remove(seat_bindings,i) end
    end
    pawn_seat_physics.restore_player_display()
    if not manual_cart and preset.teleportPlayer
        and is_character_valid(player) and player_uses_cart_seat_node() then
        if not seating_lock_active then
            local ox=find_active_ox()
            local body=ox and find_cart_body(ox)
            if not body or not player_is_physically_seated(ox) then return end
            seat_anchor_transform=resolve_seat_anchor(body)
        end
        if seat_anchor_transform then
            table.insert(seat_bindings,{char=player,seat_spec=preset.player})
            seating_lock_active=true
        end
    end
end
function pawn_seat_physics.release(character)
    if character ~= player and is_character_valid(character) then
        pcall(function() pawn_seat_physics.synchronize(character,character:get_Transform()) end)
    end
end
function pawn_seat_physics.finish(character)
    if not is_character_valid(character) then return end
    pawn_seat_physics.release(character)
    pcall(function() character:get_Transform():set_Parent(nil) end)
end
function pawn_seat_physics.remove(index, native_interaction)
    local binding=seat_bindings[index]
    if not binding then return end
    local display=rawget(_G,"OJR_CompanionDisplay")
    if display and not native_interaction then pcall(display.commit,binding,seat_anchor_transform) end
    pawn_seat_physics.restore_fsm(binding)
    table.remove(seat_bindings, index)
    if binding and binding.char~=player then
        pawn_seat_physics.excluded=pawn_seat_physics.excluded or {}
        pawn_seat_physics.excluded[binding.char]=true
    end
    if binding and not native_interaction then pawn_seat_physics.finish(binding.char) end
    if #seat_bindings == 0 then seating_lock_active = false end
end
function pawn_seat_physics.prune_party()
    local ok, _, roster = pcall(collect_companions)
    if not ok or not roster then return end -- Unreadable does not prove departure.
    for i = #seat_bindings, 1, -1 do
        local char = seat_bindings[i].char
        local interacting=seat_bindings[i].guest and companion_interacting(char)
        if not is_character_valid(char) or (char ~= player and not roster[char]) or interacting then
            pawn_seat_physics.remove(i,interacting)
            if not interacting and char~=player and is_character_valid(char) then
                pcall(pawn_seat_physics.request_pose_action,char,"Wait",0)
            end
        end
    end
    for ch in pairs(pawn_seat_physics.excluded or {}) do
        if not roster[ch] then pawn_seat_physics.excluded[ch]=nil end
    end
end


-- Detach every bound character and resume normal pawn control.
local function detach_bound_characters()
    pawn_seat_physics.pending_preset=nil
    pawn_seat_physics.restore_player_display()
    pawn_seat_physics.follow_roster=false
    cart_trip.manual_standing_seats = false
    for i=#seat_bindings,1,-1 do
        local binding=seat_bindings[i]
        local interacting=binding.guest and companion_interacting(binding.char)
        pawn_seat_physics.remove(i,interacting)
    end
    seating_lock_active=false
end

re.on_script_reset(function()
    seating_lock_active = false
    detach_bound_characters()
end)

-- Let the requested animation initialize, then freeze the captured NPC FSM.
local function start_seated_animation(char, seat_spec, force_anim_node, pending_binding, legacy_switch)
    if not char or not char:get_Valid() then return end
    local is_pawn = char ~= player
    local diagnostics=rawget(_G,"OJR_RuntimeDiagnostics")
    if is_pawn and diagnostics then
        local observed_binding=pending_binding
        for _,binding in ipairs(seat_bindings) do
            if binding.char==char then observed_binding=binding;break end
        end
        if observed_binding then
            pcall(diagnostics.begin_pose,observed_binding,seat_anchor_transform,force_anim_node or seat_spec.anim,
                legacy_switch and 0 or 1,pawn_seat_physics.frame or 0,runtime_clock,
                force_anim_node and 'random-idle' or (legacy_switch and 'preset-switch' or 'initial-or-reseat'))
        end
    end
    if is_pawn then
        if pending_binding then pawn_seat_physics.begin_pose(pending_binding) end
        for _, binding in ipairs(seat_bindings) do
            if binding.char == char then
                if binding~=pending_binding then pawn_seat_physics.begin_pose(binding) end
                pending_binding=binding
            end
        end
    end
    
    if is_pawn then
        local display=rawget(_G,"OJR_CompanionDisplay")
        if display and pending_binding then display.restore_binding(pending_binding) end
        if not pending_binding or not pending_binding.root_placed then
            pawn_seat_physics.place(char,pending_binding and pending_binding.root_spec or seat_spec)
            if pending_binding then pending_binding.root_placed=true end
        end
        pawn_seat_physics.reset_fall(char)
    end
    if seat_spec.useDirectMotion and not force_anim_node then
        local ok, err = pcall(function()
            local motion = char:get_Motion()
            if is_pawn then assert(motion, "Pawn Motion unavailable") end
            if motion then
                local layer = motion:getLayer(0)
                if is_pawn then assert(layer, "Pawn base motion layer unavailable") end
                if layer then
                    layer:call("changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)", seat_spec.bankID or 0, seat_spec.motionID or 0, 0.0, 12.0, 1, 1)
                end
            end
        end)
        if not ok and is_pawn then error(err) end
    else
        local action_manager = nil
        pcall(function() action_manager = char["<ActionManager>k__BackingField"] end)
        
        if action_manager then
            local ok, err = pcall(function()
                -- The companion FSM is temporarily enabled for this request.
                if is_pawn then
                    pawn_seat_physics.request_pose_action(char, force_anim_node or seat_spec.anim, legacy_switch and 0 or 1)
                else action_manager:requestActionCore(1, force_anim_node or seat_spec.anim, 0) end
            end)
            if not ok then error(err) end
            
        elseif is_pawn then error("Pawn ActionManager unavailable") end
    end
    if is_pawn and pending_binding and diagnostics then
        pcall(diagnostics.mark_pose,pending_binding,seat_anchor_transform,'requested',pawn_seat_physics.frame or 0,runtime_clock)
    end
    if is_pawn and pending_binding then
        local display=rawget(_G,"OJR_CompanionDisplay")
        if display then display.apply(pending_binding,seat_anchor_transform) end
    end
end

-- Release variants use different exit animations for the two hotbars.
local function release_passengers_from_skill()
    if not seating_lock_active then return end
    if not player or not player:get_Valid() then return end
    
    local passengers={}
    for _,binding in ipairs(seat_bindings) do if binding.char~=player then passengers[#passengers+1]=binding.char end end
    seating_lock_active = false
    detach_bound_characters()

    for _,pawn_character in ipairs(passengers) do
        if pawn_character and pawn_character ~= player and not companion_interacting(pawn_character) then
            local action_manager = pawn_character["<ActionManager>k__BackingField"]
            if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
        end
    end
end

local function release_passengers_from_modifier()
    if not player or not player:get_Valid() then return end
    if not seating_lock_active then return end
    
    local passengers={}
    for _,binding in ipairs(seat_bindings) do if binding.char~=player then passengers[#passengers+1]=binding.char end end
    seating_lock_active = false
    detach_bound_characters()

    for _,pawn_character in ipairs(passengers) do
        if pawn_character and pawn_character:get_Valid() and pawn_character ~= player and not companion_interacting(pawn_character) then
            local action_manager = pawn_character["<ActionManager>k__BackingField"]
            if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
        end
    end
end

-- Build the active bindings from the selected cart-specific layout.
local function bind_pawns_to_seats(legacy_switch, add_missing_only)
    if external_driver_active() and not manual_cart then return false end
    if add_missing_only and (not seating_lock_active or not pawn_seat_physics.follow_roster) then return false end
    if add_missing_only then
        if runtime_clock<(pawn_seat_physics.next_roster_refresh or 0) then return false end
        pawn_seat_physics.next_roster_refresh=runtime_clock+1
    else pawn_seat_physics.next_roster_refresh=0;pawn_seat_physics.excluded={} end
    local ox = find_active_ox()
    if not ox then return end
    
    local cart_transform = find_cart_body(ox)
    if not cart_transform then 
        return
    end
    
    seat_anchor_transform = resolve_seat_anchor(cart_transform)
    
    local cat = classify_cart_model(cart_transform)
    local idx = preset_cursor[cat] or 1
    local preset = options.Presets[cat] and options.Presets[cat][idx]
    
    if not preset then preset = options.Presets[cat] and options.Presets[cat][1] end
    if not preset then return end

    if not add_missing_only then
    cart_trip.seat_changed_at = runtime_clock
    cart_trip.stopped_since = nil
    cart_trip.arrival_was_false = false
    cart_trip.last_check_at = nil
    end

    local party_members,_,guests=collect_companions()
    if not party_members then return end
    for _,binding in ipairs(seat_bindings) do
        if binding.root_cart and binding.root_cart~=cart_transform then
            detach_bound_characters();add_missing_only=false;break
        end
    end
    local previous_slots,bound,previous = {},{},{}
    for _,binding in ipairs(seat_bindings) do
        bound[binding.char]=true
        previous[binding.char]=binding
        if binding.char~=player then previous_slots[binding.char]=binding.slot end
    end
    if not add_missing_only then
        pawn_seat_physics.restore_player_display()
        for i=#seat_bindings,1,-1 do if seat_bindings[i].char==player then table.remove(seat_bindings,i) end end
    end

    if not manual_cart and not add_missing_only and preset.teleportPlayer and player and player:get_Valid() and player_uses_cart_seat_node() then
        table.insert(seat_bindings, {char = player, seat_spec = preset.player})
    end

    local occupied,assigned,eligible={},{},{}
    for _,ch in ipairs(party_members) do
        eligible[ch]=ch~=player and not companion_interacting(ch)
            and not (add_missing_only and (pawn_seat_physics.excluded or {})[ch])
    end
    for i=#seat_bindings,1,-1 do
        if seat_bindings[i].char~=player and not eligible[seat_bindings[i].char] then pawn_seat_physics.remove(i) end
    end
    for _,ch in ipairs(party_members) do
        local slot=previous_slots[ch]
        if eligible[ch] and slot and slot<=9 and not occupied[slot] then assigned[ch]=slot;occupied[slot]=true end
    end
    for _,ch in ipairs(party_members) do
        if eligible[ch] and not assigned[ch] then for slot=1,9 do if not occupied[slot] then assigned[ch]=slot;occupied[slot]=true;break end end end
    end
    for _,pawn_character in ipairs(party_members) do
        local i=assigned[pawn_character]
        if i and pawn_character and pawn_character:get_Valid() and pawn_character ~= player
            and not (add_missing_only and bound[pawn_character])
            and not companion_interacting(pawn_character) then
            local physics_ready, physics_error = pcall(pawn_seat_physics.prepare, pawn_character)
            if physics_ready then
                local binding=previous[pawn_character]
                if not binding then
                    local base=options.Presets[cat][1].pawns[i]
                    binding={char=pawn_character,slot=i,root_cart=cart_transform,
                        root_spec={x=base.x,y=base.y,z=base.z,lookX=base.lookX,lookZ=base.lookZ}}
                end
                binding.seat_spec,binding.guest=preset.pawns[i],guests[pawn_character]==true
                binding.pose_failed=nil
                local ok, err = pcall(function()
                    start_seated_animation(pawn_character, preset.pawns[i],nil,binding,legacy_switch and previous_slots[pawn_character]~=nil)
                end)
                local next_idle = preset.pawns[i].randomIdle and (runtime_clock + math.random() * 25 + 5) or nil
                binding.next_idle_time = next_idle
                if ok then
                    if not previous[pawn_character] then table.insert(seat_bindings, binding) end
                else
                    if previous[pawn_character] then
                        for index=#seat_bindings,1,-1 do if seat_bindings[index]==binding then table.remove(seat_bindings,index) end end
                    end
                    pawn_seat_physics.restore_fsm(binding)
                    pawn_seat_physics.excluded=pawn_seat_physics.excluded or {}
                    pawn_seat_physics.excluded[pawn_character]=true
                    pawn_seat_physics.finish(pawn_character)
                    log.error("[Oxcarts Journey Redux] Pawn pose request failed: " .. tostring(err))
                end
            else
                local old=previous[pawn_character]
                if old then
                    for index=#seat_bindings,1,-1 do
                        if seat_bindings[index]==old then pawn_seat_physics.remove(index);break end
                    end
                end
                pawn_seat_physics.excluded=pawn_seat_physics.excluded or {}
                pawn_seat_physics.excluded[pawn_character]=true
                log.error("[Oxcarts Journey Redux] Pawn seat skipped: " .. tostring(physics_error))
            end
        end
    end
    
    seating_lock_active = #seat_bindings > 0
    if not add_missing_only then pawn_seat_physics.follow_roster=seating_lock_active end
    return seating_lock_active
end

local function sit_with_next_preset()
    -- Coalesce overlapping modifier/skill bindings within one gameplay frame.
    if last_sit_request_at == runtime_clock then return end
    local ox = find_active_ox()
    if not ox then return end
    local cart_transform = find_cart_body(ox)
    if not cart_transform then return end
    local cat = classify_cart_model(cart_transform)
    local presets = options.Presets[cat]
    if not presets or #presets == 0 then return end
    local companions_seated=false
    for _,binding in ipairs(seat_bindings) do if binding.char~=player then companions_seated=true;break end end
    local next_idx = (preset_cursor[cat] or 1)-(companions_seated and 0 or 1)
    for i = 1, #presets do
        next_idx = next_idx % #presets + 1
        if presets[next_idx].enabled and not (player_is_physically_seated(ox) and presets[next_idx].skipPassenger) then
            preset_cursor[cat] = next_idx
            if pawn_seat_physics.menu then pawn_seat_physics.menu.indices[cat]=next_idx end
            if bind_pawns_to_seats(true) then
                -- A deliberate modifier Sit while standing must survive the
                -- automatic Walk/Wait release check on subsequent frames.
                cart_trip.manual_standing_seats = not player_is_physically_seated(ox)
                last_sit_preset[cat] = next_idx
                last_sit_request_at = runtime_clock
            end
            return
        end
    end
end

function pawn_seat_physics.queue_preset(family,index)
    local preset=options.Presets[family] and options.Presets[family][index]
    if preset then pawn_seat_physics.pending_preset={family=family,preset=preset} end
end
function pawn_seat_physics.apply_pending_preset()
    local pending=pawn_seat_physics.pending_preset
    if not pending or gameplay_is_paused() then return end
    pawn_seat_physics.pending_preset=nil
    local ox=find_active_ox()
    local body=ox and find_cart_body(ox)
    if not body or classify_cart_model(body)~=pending.family then return end
    local index
    for i,p in ipairs(options.Presets[pending.family]) do if p==pending.preset then index=i;break end end
    if not index then return end -- Deleted or replaced while waiting for gameplay.
    if manual_cart then
        if driving_bus.driver then driving_bus.driver.layout_selected(pending.family,index) end
        return
    end
    if external_driver_active() then return end
    preset_cursor[pending.family]=index
    if seating_lock_active and bind_pawns_to_seats(true) then
        cart_trip.manual_standing_seats=not player_is_physically_seated(ox)
        last_sit_preset[pending.family]=index
        last_sit_request_at=runtime_clock
    end
end

local action_bindings = {
    Walk = {
        skillUiKey = "LB", modifyUiKey = "D-Pad Left",  
        name = "Oxcart Walk",
        padSkillKey = "Key_PadSkillWalk", mouseSkillKey = "Key_MouseSkillWalk",
        padModifyKey = "Key_PadModifyWalk", mouseModifyKey = "Key_MouseModifyWalk",
        nodeName = "Wait", isDash = false, isUI = true
    },
    Dash = {
        skillUiKey = "RB", modifyUiKey = "D-Pad Up",    
        name = "Oxcart Dash",
        padSkillKey = "Key_PadSkillDash", mouseSkillKey = "Key_MouseSkillDash",
        padModifyKey = "Key_PadModifyDash", mouseModifyKey = "Key_MouseModifyDash",
        nodeName = "Dash", isDash = true, isUI = true
    },
    Teleport = {
        skillUiKey = "X (Square)", modifyUiKey = "D-Pad Right",  
        name = "Pawns Sit",      
        padSkillKey = "Key_PadSkillTeleport", mouseSkillKey = "Key_MouseSkillTeleport",
        padModifyKey = "Key_PadModifyTeleport", mouseModifyKey = "Key_MouseModifyTeleport",
        skillAction = sit_with_next_preset,
        modifyAction = sit_with_next_preset,
        isUI = true
    },
    Stand = {
        skillUiKey = "B (Circle)", modifyUiKey = "D-Pad Down", 
        name = "Pawns Stand",
        padSkillKey = "Key_PadSkillStand", mouseSkillKey = "Key_MouseSkillStand",
        padModifyKey = "Key_PadModifyStand", mouseModifyKey = "Key_MouseModifyStand",
        skillAction = function()
            if driving_bus.driver then driving_bus.journey.release() else release_passengers_from_skill() end
        end,
        modifyAction = function()
            if driving_bus.driver then driving_bus.journey.release() else release_passengers_from_modifier() end
        end,
        isUI = true
    }
}

-- StopIndex advances along the road; StopoverIndex retains the purchased stop.
-- Use that ticket index, not the route's final stop, on intermediate journeys.
local function cart_destination_probe(ox, status)
    local result = {}
    local ok, err = pcall(function()
        status = status or npc_manager.OxcartManager:getStatus(ox:get_CharaID())
        if not status then error("Cart status unavailable") end
        local is_stopover, stopover_index, waiting
        pcall(function()
            local base = sdk.find_type_definition("app.OxcartStatusSaveData")
            is_stopover = base:get_field("IsStopover"):get_data(status)
            stopover_index = base:get_field("StopoverIndex"):get_data(status)
            waiting = base:get_field("IsWaitStopoverTimer"):get_data(status)
        end)
        result.waiting = waiting == true
        if result.waiting then result.reason = "intermediate stop waiting timer active" end
        local position = ox:get_Transform():get_UniversalPosition()
        local function distance(destination)
            if not destination then return nil end
            local dx, dz = tonumber(position.x) - tonumber(destination.x), tonumber(position.z) - tonumber(destination.z)
            return math.sqrt(dx * dx + dz * dz)
        end
        local final_ok, final = pcall(function() return status:call("getFinalStopIndexPosition()") end)
        if final_ok and final then
            result.final_distance = distance(final)
            result.final_position = { x = tonumber(final.x), y = tonumber(final.y), z = tonumber(final.z) }
        end
        if is_stopover == true and type(stopover_index) == "number" and stopover_index >= 0 then
            local destination_ok, destination = pcall(function()
                return status:call("getStopIndexPosition(System.Int32)", stopover_index)
            end)
            result.kind, result.index = "intermediate", stopover_index
            if destination_ok then result.distance = distance(destination)
            else result.note = "Intermediate position unavailable: " .. tostring(destination) end
        else
            result.kind, result.distance = "final", result.final_distance
            if is_stopover == true then result.note = "Invalid StopoverIndex; using final destination" end
        end
        local limit = options.DESTINATION_BRAKE_DISTANCE
        if result.waiting then result.reason = "intermediate stop waiting timer active"
        elseif result.distance and result.distance <= limit then result.reason = "near " .. result.kind .. " destination"
        -- A lingering stopover ticket must not prevent braking at the final stop.
        elseif result.final_distance and result.final_distance <= limit then result.reason = "near final destination" end
    end)
    if not ok then result.error = tostring(err) end
    cart_trip.destination = result
    return result
end

local function cart_destination_brake_reason(ox, status)
    return cart_destination_probe(ox, status).reason
end

function pawn_seat_physics.driver_wait_reason(ox)
    if not is_character_valid(ox) then return nil end
    if manual_cart or (driving_bus.driver and driving_bus.driver.player_is_driver()) then return nil end
    local ok,reason=pcall(function()
        local status=npc_manager.OxcartManager:getStatus(ox:get_CharaID())
        if not status then return "no NPC driver" end
        local id=status:call("getCurrentDriver")
        if not id or tonumber(id)==0 then return "no NPC driver" end
        local driver=npc_manager:getCharacter(id)
        if not is_character_valid(driver) then return "no NPC driver" end
        if driver==player then return "player is not driving" end
        local death_ok,dead=pcall(function() return driver:get_IsDead() end)
        if death_ok and dead then return "NPC driver is dead" end
        local controller=ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        local seat=controller and controller:call("get_DrivingSeat")
        local occupant=seat and seat.SitChara
        if not is_character_valid(occupant) or occupant:get_address()~=driver:get_address() then
            return "NPC driver is not in driver seat"
        end
        if seat:call("isSit()")~=true then return "NPC driver is not fully seated" end
        local body=find_cart_body(ox)
        if not body then return nil end
        local a,b=driver:get_Transform():get_Position(),body:get_Position()
        if (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>144 then return "NPC driver is away from cart" end
    end)
    if not ok then return "NPC driver seat state unavailable" end
    return reason
end

local function trace_cart_event(kind,detail)
    local observer=rawget(_G,"AelinoreOxcartTrace2")
    if type(observer)=="function" then pcall(observer,kind,detail) end
end
local function request_cart_locomotion(ox, nodeName, isDash, automatic)
    if not ox then return end
    local driver_wait=nodeName~="Wait" and pawn_seat_physics.driver_wait_reason(ox)
    if driver_wait then
        cart_trip.stop_reason="movement blocked: "..driver_wait
        trace_cart_event("ojr_speed_rejected",{node=nodeName,reason=driver_wait})
        return
    end
    -- Do not immediately restart Dash inside the braking zone or during a stop.
    if isDash then
        local reason = cart_destination_brake_reason(ox)
        if reason then
            local message = "dash request blocked: " .. reason
            cart_trip.stop_reason = message
            return
        end
    end
    local action_manager = ox["<ActionManager>k__BackingField"]
    if not action_manager or not action_manager.CurrentActionList then return end
    local success, current_action = pcall(function() return action_manager.CurrentActionList[0] end)
    if not success or not current_action then return end
    
    if not movement_control.can_command(ox) then return end
    movement_control.issue(function() action_manager:requestActionCore(0, nodeName, 0) end)
    if not automatic then cart_trip.auto_paused = not isDash end
    movement_control.hold(ox,nodeName,(isDash or nodeName=="Run") and options.DASH_DURATION or 2,runtime_clock)
    trace_cart_event("ojr_speed_requested",{node=nodeName,automatic=automatic==true,t=runtime_clock})
    if isDash then
        cart_trip.departure_pending = false
        cart_trip.walk_since, cart_trip.walk_angle, cart_trip.walk_turn = nil, nil, 0
        cart_trip.rush_requested_at = runtime_clock
        cart_trip.rush_ack_until = runtime_clock + 0.5
        cart_trip.has_moved_in_rush = false
        cart_trip.stopped_since = nil
        cart_trip.last_position = nil
        cart_trip.last_position_at = nil
        cart_trip.braked_for_destination = false
    else
        cart_trip.rush_requested_at = nil
        cart_trip.stopped_since = nil
    end
    return true
end

local cart_battle_overrides = {
    address = nil, hooks = {},
    option_for_method = { isDriverBattleMode = "DRIVER_NONCOMBAT", isAnyoneBattleMode = "CART_NONCOMBAT" },
}

local function install_cart_battle_overrides_hooks(status)
    local definition = status:get_type_definition()
    for _, name in ipairs({ "isDriverBattleMode", "isAnyoneBattleMode" }) do
        if not cart_battle_overrides.hooks[name] then
            local method_name = name
            local ok, err = pcall(function()
                local method = definition:get_method(method_name)
                assert(method and method:get_num_params() == 0, "missing zero-argument method")
                assert(method:get_return_type():get_name() == "Boolean", "not a Boolean method")
                sdk.hook(method, function(args)
                    local storage = thread.get_hook_storage()
                    storage["ojr_" .. method_name] = false
                    local object = sdk.to_managed_object(args[2])
                    if object and object:get_address() == cart_battle_overrides.address then
                        storage["ojr_" .. method_name] = true
                    end
                end, function(retval)
                    if thread.get_hook_storage()["ojr_" .. method_name] then
                        if options[cart_battle_overrides.option_for_method[method_name]] then return sdk.to_ptr(0) end
                    end
                    return retval
                end)
                cart_battle_overrides.hooks[method_name] = true
            end)
            if not ok then
                log.error("[Oxcarts Journey Redux] Battle override unavailable: " .. method_name .. ": " .. tostring(err))
                -- Avoid retrying a failed native hook every frame.
                cart_battle_overrides.hooks[method_name] = "failed"
            end
        end
    end
end

local function read_cart_status(ox)
    if not ox then
        cart_battle_overrides.address = nil
        return nil
    end
    local status = nil
    pcall(function()
        status = npc_manager.OxcartManager:getStatus(ox:get_CharaID())
    end)
    local address = status and status:get_address() or nil
    cart_battle_overrides.address = address
    if status then install_cart_battle_overrides_hooks(status) end
    return status
end

local function status_is_true(status, method_name)
    if not status then return false end
    local ok, value = pcall(function() return status:call(method_name) end)
    return ok and value == true
end

local function get_cart_action(character)
    if not is_character_valid(character) then return "unavailable (character not loaded)" end
    local ok, action_name = pcall(function()
        local manager = character["<ActionManager>k__BackingField"] or character:get_ActionManager()
        local actions = manager and manager.CurrentActionList
        local action = actions and actions[0]
        return action and action.Name
    end)
    if not ok then return "call failed: " .. tostring(action_name) end
    return action_name and tostring(action_name) or "unavailable (no layer 0 action)"
end

local cart_normal_guard = { radius = 2.5, next_at = nil }

local function player_cart_body_distance(ox)
    local ok, distance = pcall(function()
        if not is_character_valid(ox) or not is_character_valid(player) then return nil end
        local body = find_cart_body(ox)
        if not body then return nil end
        local a = body:get_UniversalPosition()
        local b = player:get_Transform():get_UniversalPosition()
        local dx, dy, dz = tonumber(a.x) - tonumber(b.x), tonumber(a.y) - tonumber(b.y), tonumber(a.z) - tonumber(b.z)
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return ok and distance or nil
end

local function update_cart_normal_guard(ox)
    if not options.PLAYER_NEAR_CART_NONCOMBAT then
        cart_normal_guard.next_at = nil
        return
    end
    if cart_normal_guard.next_at and runtime_clock < cart_normal_guard.next_at then return end
    cart_normal_guard.next_at = runtime_clock + 0.05
    local distance = player_cart_body_distance(ox)
    if not distance or distance > cart_normal_guard.radius then
        return
    end
    local ok, err = pcall(function()
        local manager = sdk.get_managed_singleton("app.BattleManager")
        assert(manager, "BattleManager unavailable")
        -- The true variant was tested in-game: leaves combat without settlement.
        -- Renew its short hold while nearby; never request a forced battle on exit.
        manager:call("requestForceNormal(System.Boolean)", true)
    end)
    if not ok then
        if not cart_normal_guard.error_reported then
            log.error("[Oxcarts Journey Redux] Non-combat request failed: " .. tostring(err))
            cart_normal_guard.error_reported = true
        end
        cart_normal_guard.next_at = runtime_clock + 1.0
    else
        cart_normal_guard.error_reported = false
    end
end

local function player_battle_state()
    local ok, value = pcall(function()
        if not is_character_valid(player) then return nil end
        local human = player["<Human>k__BackingField"]
        return human and human:call("get_IsBattleMode()")
    end)
    if ok and type(value) == "boolean" then return value end
    return nil
end

local function resolve_steering_cow(ox)
    local ok, cow = pcall(function()
        if not is_character_valid(ox) then return nil end
        local parts = ox.EnemyCtrl.Ch2["<CachedConnectParts>k__BackingField"]
        return parts and parts.CowChara
    end)
    if not ok or not is_character_valid(cow) then return nil end
    return cow
end

local function stop_cart_rush(ox, reason, exit_action, keep_live_action, force_exit_action)
    trace_cart_event("ojr_stop",{reason=reason,exit_action=exit_action,keep_live_action=keep_live_action==true,
        force_exit_action=force_exit_action==true,t=runtime_clock,rush_at=cart_trip.rush_requested_at})
    cart_trip.manual_resume_at=nil
    movement_control.clear()
    if reason then
        cart_trip.stop_reason = reason
    end
    if ox then
        if (cart_trip.rush_requested_at or force_exit_action) and not keep_live_action then
            pcall(function()
                local action_manager = ox["<ActionManager>k__BackingField"]
                if action_manager then action_manager:requestActionCore(0, exit_action or "Wait", 0) end
            end)
        end
    end
    cart_trip.rush_requested_at = nil
    cart_trip.rush_ack_until = nil
    cart_trip.stopped_since = nil
    cart_trip.last_position = nil
    cart_trip.last_position_at = nil
end

function pawn_seat_physics.enforce_driver_wait(ox)
    if gameplay_is_paused() then return false end
    local reason=pawn_seat_physics.driver_wait_reason(ox)
    if not reason then return false end
    stop_cart_rush(nil,reason)
    local manager=ox["<ActionManager>k__BackingField"]
    local current=manager and manager.CurrentActionList and manager.CurrentActionList[0]
    if current and movement_control.is_move(current.Name) and current.Name~="Wait" then
        movement_control.issue(function() manager:requestActionCore(0,"Wait",0) end)
    end
    return true
end

local function release_pawns_at_intermediate_stop(reason)
    cart_trip.keep_standing_companions=nil
    pawn_seat_physics.follow_roster=false
    cart_trip.manual_standing_seats = false
    -- Keep the player's seat binding; remove only followers.
    for i = #seat_bindings, 1, -1 do
        local binding=seat_bindings[i]
        local char = binding.char
        if char ~= player then
            -- Damage protection follows the binding, so removal restores it too.
            local interacting=binding.guest and companion_interacting(char)
            pawn_seat_physics.remove(i,interacting)
            if not interacting and is_character_valid(char) then
                pcall(function()
                    local manager = char["<ActionManager>k__BackingField"]
                    if manager then manager:requestActionCore(0, "Wait", 0) end
                end)
            end
        end
    end
    if #seat_bindings == 0 then seating_lock_active = false end
end

local function check_intermediate_arrival(ox, status)
    if not cart_trip.paid_seen then return end
    local ok, waiting = pcall(function()
        local base = sdk.find_type_definition("app.OxcartStatusSaveData")
        return base:get_field("IsWaitStopoverTimer"):get_data(status)
    end)
    if not ok then return end
    if waiting == false then cart_trip.stopover_wait_armed = true; return end
    -- A new ticket can be bought while the old station's waiting timer is still
    -- active. Require a departure (timer false) before latching a new arrival.
    if waiting ~= true or not cart_trip.stopover_wait_armed then return end
    if not cart_trip.intermediate_arrival_seen then
        cart_trip.intermediate_arrival_seen = true
        stop_cart_rush(ox, "intermediate stop reached", "Wait")
    end
    cart_trip.intermediate_arrival_checked = true
    cart_trip.intermediate_arrival_result = "reached; release depends on player standing/combat"
end

local function cart_position(ox)
    if not ox then return nil end
    local ok, position = pcall(function()
        local value = ox:get_Transform():get_UniversalPosition()
        return { x = tonumber(value.x), z = tonumber(value.z) }
    end)
    if not ok or not position or not position.x or not position.z then return nil end
    return position
end

local function planar_distance(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function reset_auto_walk()
    cart_trip.walk_since, cart_trip.walk_angle, cart_trip.walk_turn = nil, nil, 0
    cart_trip.walk_position, cart_trip.walk_position_at = nil, nil
end

local function reset_trip_for_cart_change(ox)
    cart_trip.manual_speed,cart_trip.speed_input_frame=nil,nil
    cart_trip.keep_standing_companions=nil
    -- A different cart must not inherit the previous actor's trip state.
    stop_cart_rush(ox, "cart changed: refresh live locomotion", nil, true)
    cart_trip.paid_status_address = nil
    cart_trip.paid_seen, cart_trip.paid_current, cart_trip.ticket_loss_handled = false, nil, false
    cart_trip.intermediate_arrival_seen, cart_trip.intermediate_arrival_checked = false, false
    cart_trip.stopover_wait_armed = false
    cart_trip.intermediate_arrival_result, cart_trip.destination = nil, nil
    cart_trip.final_arrival_seen, cart_trip.braked_for_destination = false, false
    cart_trip.departure_pending, cart_trip.auto_paused = false, false
    cart_trip.last_check_at = nil
    reset_auto_walk()
end

local function cart_is_overturned(ox)
    local ok, value = pcall(function()
        local cart = ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        return cart and (cart:call("get_IsExecRollover()") == true or cart:call("get_IsRollover()") == true)
    end)
    return ok and value == true
end

local function observe_cart_pause(ox)
    local pause = cart_trip.pause
    if gameplay_is_paused() then
        if not pause.active then
            pause.active, pause.resume_pending = true, false
            pause.restore_dispatched = false
            pause.ox_address = is_character_valid(ox) and ox:get_address() or nil
            pause.was_rushing = cart_trip.rush_requested_at ~= nil
            pause.rush_started_at = cart_trip.rush_requested_at
            pause.last_result = "gameplay suspended; keeping rush/follower state"
        end
    elseif pause.active then
        pause.active, pause.resume_pending = false, true
        pause.resume_at = runtime_clock
        pause.last_result = "waiting for post-menu state to settle"
    end
end

local function finish_cart_pause(ox)
    local pause = cart_trip.pause
    if not pause.resume_pending then return true end
    if pause.restore_dispatched then
        if get_cart_action(ox):lower() == "dash" then
            pause.resume_pending = false
            pause.last_result = "previous rush restored; no three-second restart"
            return true
        end
        if runtime_clock < pause.restore_deadline then return false end
        pause.resume_pending = false
        pause.last_result = "rush not acknowledged; use normal recovery"
        return true
    end
    local elapsed = runtime_clock - pause.resume_at
    if elapsed < 0.25 then return false end
    if not is_character_valid(ox) or ox:get_address() ~= pause.ox_address then
        pause.resume_pending = false
        pause.last_result = "changed cart; use normal Walk rules"
        return true
    end
    local status = read_cart_status(ox)
    local distance = player_cart_distance(ox)
    local destination = cart_destination_probe(ox, status)
    if not status or not distance or (not destination.distance and not destination.final_distance and not destination.reason) then
        if elapsed < 1.0 then return false end
        pause.resume_pending = false
        pause.last_result = "post-menu data unavailable; use normal recovery"
        return true
    end
    -- The same actor can expose a rebuilt status wrapper after a menu; that alone
    -- is not a save reload and must not discard its passenger/rush state.
    cart_trip.paid_status_address = status:get_address()
    local blocked = distance > 15 or destination.reason or cart_is_overturned(ox)
        or status_is_true(status, "isBroken_OxCart") or status_is_true(status, "isDead_Ox")
        or status_is_true(status, "isArrived")
    if pause.was_rushing and cart_trip.rush_requested_at and not blocked and not cart_trip.auto_paused then
        local remaining = options.DASH_DURATION - (runtime_clock - pause.rush_started_at)
        if remaining > 0 then
            if get_cart_action(ox):lower() == "dash" then
                movement_control.hold(ox,"Dash",remaining,runtime_clock)
            else
                -- Restoring an existing rush is not a new auto-start: the player
                -- may have stood up before opening the menu, but is still nearby.
                request_cart_locomotion(ox, "Dash", true, true)
                pause.restore_dispatched = true
                pause.restore_deadline = runtime_clock + 0.5
            end
            if cart_trip.rush_requested_at then
                cart_trip.rush_requested_at = pause.rush_started_at
                movement_control.hold(ox,"Dash",remaining,runtime_clock)
                pause.last_result = "previous rush restored; no three-second restart"
            else
                pause.last_result = "rush request rejected; use normal recovery"
            end
        else
            pause.last_result = "rush duration expired; use normal rules"
        end
    else
        pause.last_result = "no rush to restore / stop condition present"
    end
    cart_trip.last_position, cart_trip.last_position_at, cart_trip.stopped_since = nil, nil, nil
    reset_auto_walk()
    if pause.restore_dispatched then return false end
    pause.resume_pending = false
    return true
end

local function update_auto_rush(ox, status, destination, sitting)
    if cart_trip.manual_speed then return end
    local blocked
    if not options.AUTO_RUSH then blocked = "automatic rush disabled"
    elseif cart_trip.auto_paused then blocked = "manual pause; use Resume automatic rush"
    elseif not sitting then blocked = "player is not seated"
    elseif destination.reason then blocked = "approaching/waiting at station: " .. destination.reason
    elseif not destination.distance then blocked = "current destination distance unavailable"
    elseif destination.distance < 25 or (destination.final_distance and destination.final_distance < 25) then
        blocked = "within 25 of destination"
    elseif status_is_true(status, "isArrived") then blocked = "final destination reached" end
    if blocked then
        reset_auto_walk()
        cart_trip.auto_reason = blocked
        return
    end
    if get_cart_action(ox):lower() ~= "walk" then
        if cart_trip.walk_since then cart_trip.departure_pending = false end
        reset_auto_walk(); cart_trip.auto_reason = "waiting for Walk"; return
    end
    local cow = resolve_steering_cow(ox)
    local ok, angle = pcall(function() return cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()") end)
    local position = cart_position(ox)
    if not ok or type(angle) ~= "number" or not position then
        reset_auto_walk(); cart_trip.auto_reason = "heading/position unavailable"; return
    end
    if cart_trip.walk_position and cart_trip.walk_position_at then
        local dt = runtime_clock - cart_trip.walk_position_at
        if dt > 0 and planar_distance(position, cart_trip.walk_position) / dt < 0.2 then
            reset_auto_walk(); cart_trip.auto_reason = "Walk is not moving"; return
        end
    end
    if cart_trip.walk_angle then
        -- Accumulate absolute turn, not net angle: a full circle must not count as straight.
        cart_trip.walk_turn = cart_trip.walk_turn + math.abs((angle - cart_trip.walk_angle + 180) % 360 - 180)
        if cart_trip.walk_turn > options.RECOVERY_MAX_TURN then
            reset_auto_walk(); cart_trip.auto_reason = "turning; restart stability window"
        end
    end
    cart_trip.walk_since = cart_trip.walk_since or runtime_clock
    cart_trip.walk_angle, cart_trip.walk_position, cart_trip.walk_position_at = angle, position, runtime_clock
    local delay = math.max(3.0, options.RECOVERY_WALK_SECONDS)
    cart_trip.auto_reason = "stable Walk check"
    if runtime_clock - cart_trip.walk_since > delay then
        local reason = cart_trip.auto_reason
        request_cart_locomotion(ox, "Dash", true, true)
        if cart_trip.rush_requested_at then
            cart_trip.auto_reason = "automatic rush: " .. reason
        end
    end
end

local function update_cart_trip(ox, physically_sitting)
    if gameplay_is_paused() or cart_trip.pause.active or cart_trip.pause.resume_pending then return end
    if not ox then
        if cart_trip.rush_requested_at then stop_cart_rush(nil, "active cart disappeared") end
        cart_trip.ox_address = nil
        cart_trip.paid_status_address = nil
        cart_trip.paid_seen, cart_trip.paid_current, cart_trip.ticket_loss_handled = false, nil, false
        cart_trip.intermediate_arrival_seen, cart_trip.intermediate_arrival_checked = false, false
        cart_trip.stopover_wait_armed = false
        cart_trip.intermediate_arrival_result = nil
        cart_trip.destination = nil
        cart_trip.final_arrival_seen, cart_trip.departure_pending, cart_trip.braked_for_destination = false, false, false
        reset_auto_walk()
        if seating_lock_active then release_pawns_at_intermediate_stop("active cart disappeared") end
        return
    end
    local status = read_cart_status(ox)
    if cart_trip.ox_address ~= ox:get_address() then
        reset_trip_for_cart_change(ox)
        cart_trip.ox_address = ox:get_address()
    end
    if status then cart_trip.paid_status_address = status:get_address() end
    -- Release followers beyond 15 units from the cart body center. An unreadable
    -- position is not evidence that the player has left the cart.
    local body_distance = player_cart_body_distance(ox)
    if body_distance and body_distance > 15.0 then
        release_pawns_at_intermediate_stop("player left cart body center beyond 15")
    end
    -- Keep the existing paid-trip braking distance independent of pawn release.
    local player_distance = player_cart_distance(ox)
    if player_distance and player_distance > 15.0 then
        reset_auto_walk()
        cart_trip.auto_reason = "player/ox distance exceeds 15"
        local paid_ok, paid = pcall(function() return status and status:call("get_isPayMoney") end)
        if paid_ok and paid == true then
            local force_wait = get_cart_action(ox):lower() ~= "wait"
            stop_cart_rush(ox, "paid player left ox beyond 15", "Wait", false, force_wait)
        end
        return
    end
    -- Damage/rollover and standing up during Walk/Wait are checked every frame,
    -- independently of the slower route/speed sampling.
    local interrupted = status_is_true(status, "isBroken_OxCart")
        or status_is_true(status, "isDead_Ox") or cart_is_overturned(ox)
    if interrupted then
        stop_cart_rush(ox, "ox/cart destroyed or overturned")
        cart_trip.auto_paused = true
        reset_auto_walk()
        release_pawns_at_intermediate_stop("ox/cart destroyed or overturned")
        return
    end
    if physically_sitting == nil then physically_sitting = player_is_physically_seated(ox) end
    if physically_sitting then
        cart_trip.manual_standing_seats = false
        cart_trip.keep_standing_companions=nil
    end
    local standing_release = not physically_sitting and not cart_trip.manual_standing_seats
        and not cart_trip.keep_standing_companions
    if cart_trip.manual_resume_at and runtime_clock>=cart_trip.manual_resume_at then
        cart_trip.manual_resume_at,cart_trip.manual_speed=nil,nil
        cart_trip.auto_paused=false
        reset_auto_walk()
    end
    local action = get_cart_action(ox):lower()
    -- Give a newly queued Dash time to enter its action; an older request is not
    -- evidence that the actor is still dashing after the engine has selected Walk.
    if action == "walk" and cart_trip.rush_requested_at
        and not (movement_control.command and movement_control.command.turning)
        and runtime_clock - cart_trip.rush_requested_at >= 0.5
        and not (cart_trip.rush_ack_until and runtime_clock < cart_trip.rush_ack_until) then
        stop_cart_rush(ox, "live Walk replaced requested rush", nil, true)
        cart_trip.departure_pending = false
        reset_auto_walk()
    end
    if standing_release and (action == "walk" or action == "wait") then
        release_pawns_at_intermediate_stop("player stood up during Walk/Wait")
    end
    local arrived = status_is_true(status, "isArrived")
    if arrived and not cart_trip.final_arrival_seen then
        cart_trip.final_arrival_seen = true
        stop_cart_rush(ox, "final arrival transition")
    end
    local near_stop = cart_trip.destination and cart_trip.destination.reason ~= nil
    if (near_stop or cart_trip.intermediate_arrival_seen or cart_trip.final_arrival_seen)
        and (standing_release or player_battle_state() == true) then
        release_pawns_at_intermediate_stop("near/at destination; player standing or in combat")
    end
    if cart_trip.last_check_at and runtime_clock - cart_trip.last_check_at < 0.1 then return end
    cart_trip.last_check_at = runtime_clock
    if status then
        local ok, paid = pcall(function() return status:call("get_isPayMoney") end)
        if ok and type(paid) == "boolean" then
            local previous_paid = cart_trip.paid_current
            cart_trip.paid_current = paid
            if paid then
                if previous_paid ~= true then
                    cart_trip.intermediate_arrival_seen, cart_trip.intermediate_arrival_checked = false, false
                    cart_trip.stopover_wait_armed = false
                    cart_trip.intermediate_arrival_result = nil
                    cart_trip.final_arrival_seen, cart_trip.braked_for_destination = false, false
                    -- This flag only disambiguates the old station's waiting
                    -- timer after a new ticket; all Walk starts use the same delay.
                    cart_trip.departure_pending, cart_trip.auto_paused = previous_paid == false, false
                    reset_auto_walk()
                end
                cart_trip.paid_seen, cart_trip.ticket_loss_handled = true, false
            end
            -- Observe the real stop even after the earlier distance-based brake.
            check_intermediate_arrival(ox, status)
            if not paid and cart_trip.paid_seen and not cart_trip.ticket_loss_handled then
                cart_trip.ticket_loss_handled = true
                stop_cart_rush(ox, "paid passenger identity lost")
                reset_auto_walk()
            end
        else
            check_intermediate_arrival(ox, status)
        end
    end
    if not seating_lock_active and not cart_trip.rush_requested_at
        and not (options.AUTO_RUSH and physically_sitting) then
        reset_auto_walk()
        cart_trip.auto_reason = not options.AUTO_RUSH and "automatic rush disabled" or "player is not seated"
        return
    end
    local start_at = cart_trip.seat_changed_at or cart_trip.rush_requested_at
    local grace_elapsed = start_at and runtime_clock - start_at >= CART_START_GRACE

    local destination = cart_destination_probe(ox, status)
    if (destination.reason or cart_trip.intermediate_arrival_seen or cart_trip.final_arrival_seen)
        and (standing_release or player_battle_state() == true) then
        release_pawns_at_intermediate_stop("near/at destination; player standing or in combat")
    end
    if destination.reason and not (destination.waiting and cart_trip.departure_pending
        and not cart_trip.stopover_wait_armed) then cart_trip.braked_for_destination = true end
    if arrived then cart_trip.final_arrival_seen = true end
    local command=movement_control.command
    if command and command.node=="Run" and destination.reason then
        local exit_action=destination.waiting and "Wait" or "Walk"
        stop_cart_rush(ox,destination.reason,exit_action,false,true)
        cart_trip.braked_for_destination=true
        return
    end
    if not cart_trip.rush_requested_at then
        update_auto_rush(ox, status, destination, physically_sitting)
        return
    end
    if grace_elapsed and runtime_clock - cart_trip.rush_requested_at >= options.DASH_DURATION then
        stop_cart_rush(ox, "dash duration elapsed")
        cart_trip.auto_paused = true -- Do not immediately restart an expired rush.
        return
    end

    local current_position = cart_position(ox)
    if not current_position then return end

    -- Arrival braking is not subject to the ten-second startup grace period.
    -- Clear the Dash filter first; the game's own Walk/Run/Wait can then proceed.
    local brake_reason = destination.reason
    if brake_reason then
        local exit_action = brake_reason == "intermediate stop waiting timer active" and "Wait" or "Walk"
        stop_cart_rush(ox, brake_reason, exit_action)
        cart_trip.braked_for_destination = true
        return
    end

    if movement_control.command and movement_control.command.turning then
        -- Turning in place is not a stalled Dash. Keep arrival/duration checks
        -- above, but restart the movement sample after native turning finishes.
        cart_trip.stopped_since,cart_trip.last_position,cart_trip.last_position_at=nil,nil,nil
        return
    end

    if cart_trip.last_position and cart_trip.last_position_at then
        local elapsed = runtime_clock - cart_trip.last_position_at
        if elapsed < 0.25 then return end
        local speed = planar_distance(current_position, cart_trip.last_position) / elapsed
        if speed >= 1.0 then cart_trip.has_moved_in_rush = true end
        if grace_elapsed and cart_trip.has_moved_in_rush and speed <= RUSH_STOP_SPEED then
            cart_trip.stopped_since = cart_trip.stopped_since or runtime_clock
            if runtime_clock - cart_trip.stopped_since >= RUSH_STOP_CONFIRM then
                stop_cart_rush(ox, "movement stopped for confirmation interval")
                reset_auto_walk()
                return
            end
        else
            cart_trip.stopped_since = nil
        end
    end
    cart_trip.last_position = current_position
    cart_trip.last_position_at = runtime_clock
end

local function photo_mode_is_open()
    local active = false
    pcall(function()
        active = gui_manager["<IsDispPhotoModeAll>k__BackingField"] == true
    end)
    return active
end

-- Keep world-space seat constraints separate from gameplay/input processing so
-- they can continue safely while the game is paused specifically for Photo Mode.
local function enforce_seat_transforms(ox, position_only)
    if not seating_lock_active or #seat_bindings == 0 then return end

    local anchor_valid = false
    if seat_anchor_transform then
        pcall(function()
            local go = seat_anchor_transform:get_GameObject()
            anchor_valid = go and go:get_Valid() or false
        end)
    end

    if not anchor_valid then
        -- Do not dismantle passenger state from inside a paused Photo Mode
        -- frame. Normal gameplay will perform the existing cleanup if needed.
        if not position_only then
            seating_lock_active = false
            detach_bound_characters()
        end
        return
    end

    for i = #seat_bindings, 1, -1 do
        local binding = seat_bindings[i]
        local character = binding.char
        local seat_spec = binding.seat_spec
        local char_valid = false

        if character then
            pcall(function() char_valid = character:get_Valid() end)
        end

        if not char_valid then
            if not position_only then pawn_seat_physics.remove(i) end
        else
            local pose_ok = true
            local anchor_transform = seat_anchor_transform
            if anchor_transform then
                local updated, update_error = pcall(function()
                    if character==player or not position_only then
                        pawn_seat_physics.place(character,binding.root_spec or seat_spec)
                    end
                    if character~=player then
                        local display=rawget(_G,"OJR_CompanionDisplay")
                        if display then display.apply(binding,seat_anchor_transform) end
                    end
                end)
                if not updated and binding.position_error ~= tostring(update_error) then
                    binding.position_error = tostring(update_error)
                    log.error("[Oxcarts Journey Redux] Pawn seat sync failed: " .. binding.position_error)
                elseif updated then
                    binding.position_error = nil
                end
                pose_ok = updated
            else
                pose_ok = false
            end

            if not pose_ok then
                if not position_only then pawn_seat_physics.remove(i) end
            elseif not position_only then
                if not binding.pose_failed and seat_spec.randomIdle and binding.next_idle_time and runtime_clock >= binding.next_idle_time then
                    local random_anim = passenger_idle_nodes[math.random(1, #passenger_idle_nodes)]
                    local ok, err = pcall(start_seated_animation, character, seat_spec, random_anim)
                    if not ok and character ~= player then
                        binding.pose_failed=true
                        pawn_seat_physics.remove(i)
                        log.error("[Oxcarts Journey Redux] Pawn random pose failed: " .. tostring(err))
                    end
                    binding.next_idle_time = runtime_clock + (math.random() * 35 + 10)
                end
                if not binding.pose_failed and character~=player then
                    local ok,err=pcall(pawn_seat_physics.update_fsm,binding)
                    if not ok then pawn_seat_physics.remove(i);log.error("[Oxcarts Journey Redux] Companion FSM failed: "..tostring(err)) end
                end
            end
        end
    end
end


local journey_handoff = { suspended = false, restore_seats = false }
driving_bus.journey = {
    diagnostics_render = function()
        local diagnostics=rawget(_G,"OJR_RuntimeDiagnostics")
        if diagnostics and seat_anchor_transform then
            for _,binding in ipairs(seat_bindings) do
                diagnostics.sample_pose(binding,seat_anchor_transform,pawn_seat_physics.frame or 0,runtime_clock)
            end
        end
    end,
    pelvis_tick = function()
        local compensation=rawget(_G,"OJR_UnifiedPelvis")
        if compensation then compensation.tick(seat_bindings,seat_anchor_transform,player,seating_lock_active,runtime_clock) end
    end,
    passenger_active = function()
        return not external_driver_active() and player_is_cart_passenger(find_active_ox())
    end,
    passenger_camera = function()
        local ox=find_active_ox()
        if external_driver_active() or not player_is_cart_passenger(ox) then return end
        local body=find_cart_body(ox)
        if not body then return end
        local family=classify_cart_model(body)
        local preset=options.Presets[family][preset_cursor[family] or 1]
        return unified_presets.camera_for(preset,true),ox:get_address()
    end,
    stand = release_passengers_from_skill,
    resume_auto = function()
        if external_driver_active() or not player_is_cart_passenger(find_active_ox()) then return false end
        cart_trip.manual_speed,cart_trip.auto_paused=nil,false
        cart_trip.manual_resume_at=nil
        reset_auto_walk()
        return true
    end,
    speed_step = function(delta)
        if external_driver_active() or not player_is_cart_passenger(find_active_ox()) then return end
        local ox=find_active_ox()
        if not is_character_valid(ox) or pawn_seat_physics.driver_wait_reason(ox) then return end
        local frame=pawn_seat_physics.frame
        if cart_trip.speed_input_frame==frame then return end
        cart_trip.speed_input_frame=frame
        local speed=assert(rawget(_G,"OJR_UnifiedSpeed"))
        local level=speed.next(speed.level(get_cart_action(ox)),delta)
        if request_cart_locomotion(ox,speed.modes[level],level==4) then
            cart_trip.manual_speed=true
            cart_trip.manual_resume_at=level==4 and (runtime_clock+5) or nil
        end
    end,
    release = function()
        release_pawns_at_intermediate_stop("explicit companion release")
    end,
    sit = sit_with_next_preset,
    draw_backup_keybinds=function() pawn_seat_physics.draw_backup_keybinds() end,
    presets = unified_presets,
    begin_manual = function(cart)
        passenger_hud:restore()
        seating_lock_active=false
        detach_bound_characters()
        stop_cart_rush(cart.ox,"manual takeover",nil,true)
        cart_trip.auto_paused=true
        cart_trip.manual_speed=nil
        cart_trip.pause={active=false,resume_pending=false}
        prior_player_seat_state=false
        prior_cart_seat_state=false
        _G.OJR_ReseatPending=false
        reseat_requested_at=nil
        manual_cart=cart
        driving_bus.unified_manual_active=true
        last_clock_sample=os.clock()
        player=character_manager["<ManualPlayer>k__BackingField"]
        journey_handoff.suspended=true
        journey_handoff.restore_seats=false
        movement_control.clear()
    end,
    bind_manual = function(cart)
        if not manual_cart or manual_cart.body~=cart.body then return false end
        player=character_manager["<ManualPlayer>k__BackingField"]
        return bind_pawns_to_seats(true)
    end,
    end_manual = function()
        release_pawns_at_intermediate_stop("manual driving ended")
        manual_cart=nil
        driving_bus.unified_manual_active=nil
        journey_handoff.suspended=false
        journey_handoff.restore_seats=false
        last_clock_sample=os.clock()
    end,
    manual_tick = function()
        update_runtime_clock()
        pawn_seat_physics.advance_frame()
        player=character_manager["<ManualPlayer>k__BackingField"]
        if not manual_cart then return end
        local cart=manual_cart
        local ok,intact=pcall(function()
            return is_character_valid(player) and is_character_valid(cart.ox)
                and cart.body:get_GameObject():get_Valid()
                and not (cart.status and (cart.status:call("isBroken_OxCart()") or cart.status:call("isDead_Ox()")))
                and not cart_is_overturned(cart.ox)
        end)
        if not ok or not intact then
            if driving_bus.driver then driving_bus.driver.abort() else driving_bus.journey.end_manual() end
            return
        end
        if gameplay_is_paused() then
            if photo_mode_is_open() then enforce_seat_transforms(cart.ox,true) end
            return
        end
        local range=player_cart_body_distance(cart.ox)
        if range and range>5 then driving_bus.journey.release();return end
        pawn_seat_physics.prune_party()
        if seating_lock_active then bind_pawns_to_seats(false,true) end
        enforce_seat_transforms(cart.ox,false)
    end,
    manual_pose = function()
        if manual_cart then enforce_seat_transforms(manual_cart.ox,true) end
    end,
    manual_context = function(ch)
        if not manual_cart then return end
        for _,r in ipairs(seat_bindings) do if r.char==ch then return manual_cart,r.slot+1 end end
    end,
    records = function() return seat_bindings end,
    diagnostic_state = function()
        local command=movement_control.command
        return {t=runtime_clock,manual=manual_cart~=nil,auto_paused=cart_trip.auto_paused,
            manual_speed=cart_trip.manual_speed==true,manual_resume_at=cart_trip.manual_resume_at,
            stop_reason=cart_trip.stop_reason,auto_reason=cart_trip.auto_reason,
            rush_at=cart_trip.rush_requested_at,rush_ack_until=cart_trip.rush_ack_until,
            departure_pending=cart_trip.departure_pending,has_moved=cart_trip.has_moved_in_rush,
            stopped_since=cart_trip.stopped_since,last_check_at=cart_trip.last_check_at,
            pause=cart_trip.pause.active,resume_pending=cart_trip.pause.resume_pending,
            destination=cart_trip.destination and {reason=cart_trip.destination.reason,distance=cart_trip.destination.distance,
                final_distance=cart_trip.destination.final_distance,waiting=cart_trip.destination.waiting},
            speed=command and {node=command.node,until_time=command.until_time,address=tostring(command.address)},
            seat_bindings=#seat_bindings}
    end,
    enforce_driver_wait = pawn_seat_physics.enforce_driver_wait,
    seat_anchor = function(character)
        for _,binding in ipairs(seat_bindings) do
            if binding.char==character then return seat_anchor_transform end
        end
    end,
    passenger_layout = function()
        local ox = find_active_ox()
        local family = classify_cart_model(find_cart_body(ox))
        local presets = options.Presets[family]
        local preset = presets and (presets[preset_cursor[family] or 1] or presets[1])
        if not preset then return nil end
        local copy = {}
        for i, slot in ipairs(preset.pawns) do
            copy[i] = {}
            for key, value in pairs(slot) do
                if type(value) ~= "table" then copy[i][key] = value end
            end
        end
        return copy
    end,
    suspend = function()
        journey_handoff.restore_seats = seating_lock_active
        journey_handoff.suspended = true
        seating_lock_active = false
        detach_bound_characters()
        movement_control.clear()
        passenger_hud:restore()
    end,
    resume = function()
        journey_handoff.suspended = false
        last_clock_sample = os.clock()
        cart_trip.rush_requested_at, cart_trip.rush_ack_until = nil, nil
        cart_trip.walk_since, cart_trip.walk_angle, cart_trip.walk_turn = nil, nil, 0
        journey_handoff.restore_seats = false
    end,
}

local input_poll_error_reported = false
re.on_application_entry("UpdateHID", function()
    if external_driver_active() then return end
    local binds=driving_bus.driver and driving_bus.driver.get_bindings()
    if binds then
        for action,keys in pairs({sit={"Key_PadSkillTeleport","Key_MouseSkillTeleport"},
            pawn_stand={"Key_PadSkillStand","Key_MouseSkillStand"},
            up={"Key_PadSkillDash","Key_MouseSkillDash"},down={"Key_PadSkillWalk","Key_MouseSkillWalk"}}) do
            options[keys[1]]={type="gamepad",key=binds[action].gamepad}
            options[keys[2]]={type="keyboard",key=binds[action].keyboard}
        end
        rebuild_input_watchlist()
    end
    local success, err = pcall(input_bindings.update, watched_inputs)
    if not success and not input_poll_error_reported then
        input_poll_error_reported = true
        log.error("[Oxcarts Journey Redux] Failed to update input state: " .. tostring(err))
    elseif success then
        input_poll_error_reported = false
    end
end)

re.on_frame(function()
    if external_driver_active() then return end
    local ox = find_active_ox()
    observe_cart_pause(ox)
    if not cart_trip.pause.active and not cart_trip.pause.resume_pending then
        pcall(function() read_cart_status(ox) end)
    end
end)

re.on_pre_application_entry("UpdateBehavior",function() pawn_seat_physics.restore_player_display() end)

re.on_application_entry("LateUpdateBehavior", function()
    if external_driver_active() then
        passenger_hud:restore()
        local ok,err=pcall(driving_bus.journey.manual_tick)
        if ok then ok,err=pcall(pawn_seat_physics.apply_pending_preset) end
        if not ok then
            if driving_bus.driver then pcall(driving_bus.driver.abort) end
            pcall(driving_bus.journey.end_manual)
            log.error("[OJR] Manual companion cleanup: "..tostring(err))
        end
        return
    end
    if manual_cart then driving_bus.journey.end_manual() end
    update_runtime_clock()
    pawn_seat_physics.advance_frame()
    if journey_handoff.suspended then driving_bus.journey.resume() end
    local ox = find_active_ox()
    observe_cart_pause(ox)
    player = character_manager["<ManualPlayer>k__BackingField"]
    if not player or not player:get_Valid() then
        movement_control.clear()
        passenger_hud:restore()
        seating_lock_active = false
        detach_bound_characters()
        return
    end
    input = player:get_Input()

    local in_photo_mode = photo_mode_is_open()

    -- Refresh the body anchor once on Photo Mode entry, then keep applying the
    -- seat constraint while the rest of gameplay logic remains paused.
    if in_photo_mode and not photo_mode_was_active and seating_lock_active and ox then
        pcall(function()
            local cart_transform = find_cart_body(ox)
            local refreshed_anchor = resolve_seat_anchor(cart_transform)
            if refreshed_anchor then seat_anchor_transform = refreshed_anchor end
        end)
    end
    photo_mode_was_active = in_photo_mode

    if gameplay_is_paused() or in_photo_mode then
        if in_photo_mode then enforce_seat_transforms(ox, true) end
        return
    end
    pawn_seat_physics.apply_pending_preset()
    if not finish_cart_pause(ox) then return end
    update_cart_normal_guard(ox)
    pawn_seat_physics.prune_party()
    if seating_lock_active then bind_pawns_to_seats(false,true) end

    movement_control.expire(ox,runtime_clock)

    -- Rebuild seat bindings shortly after a fast-travel transition ends.
    local current_ft_state = 0
    if npc_manager and npc_manager.OxcartManager then
        pcall(function()
            local ox_mgr = npc_manager.OxcartManager
            local val = ox_mgr:call("get_FastTravelState")
            if val == nil then val = ox_mgr:get_field("_FastTravelState") end
            if val == nil then val = ox_mgr:get_field("<FastTravelState>k__BackingField") end
            if val == nil then val = ox_mgr:get_field("FastTravelState") end
            if val ~= nil then current_ft_state = tonumber(val) or 0 end
        end)
    end

    if previous_fast_travel_state ~= current_ft_state then
        if current_ft_state == 6 or (current_ft_state == 0 and previous_fast_travel_state >= 4) then
            if ox and player_is_near_cart(ox) then
                _G.OJR_ReseatPending = true
                reseat_requested_at = runtime_clock
            end
        end
    end
    previous_fast_travel_state = current_ft_state

    if _G.OJR_ReseatPending then
        if reseat_requested_at and (runtime_clock - reseat_requested_at > 2.5) then
            if ox and player_is_near_cart(ox) then
                bind_pawns_to_seats()
            end
            _G.OJR_ReseatPending = false
            reseat_requested_at = nil
        end
    end

    local is_near = ox and player_is_near_cart(ox) or false
    
    -- The per-frame trip check handles confirmed >15 body-center distance and releases only
    -- followers, without requiring a previous near -> far transition.

    local sitting = player_is_cart_passenger(ox)
    if not sitting then passenger_hud:restore() end
    local physically_sitting = player_is_physically_seated(ox)
    if not prior_cart_seat_state and physically_sitting and sitting then
        local action=get_cart_action(ox):lower()
        local companions_seated=false
        for _,binding in ipairs(seat_bindings) do
            if binding.char~=player and is_character_valid(binding.char) then companions_seated=true;break end
        end
        if not companions_seated and (action=="wait" or action=="walk") then
            bind_pawns_to_seats(true) -- One entry-edge request; keep the selected layout.
        end
    end
    
    if prior_player_seat_state and not physically_sitting then
        local action=get_cart_action(ox):lower()
        if action=="run" or action=="dash" then cart_trip.keep_standing_companions=true
        else release_pawns_at_intermediate_stop("player ended passenger interaction") end
        if seat_bindings and #seat_bindings > 0 then
            for i = #seat_bindings, 1, -1 do
                if seat_bindings[i].char == player then
                    pawn_seat_physics.remove(i)
                end
            end
            if #seat_bindings == 0 then 
                seating_lock_active = false 
            end
        end
    end
    prior_player_seat_state = physically_sitting
    prior_cart_seat_state = sitting
    
    pawn_seat_physics.enforce_driver_wait(ox)
    update_cart_trip(ox, physically_sitting)
    local command=movement_control.command
    if command and (command.turning or get_cart_action(ox)=="TurnTarget") and not pawn_seat_physics.driver_wait_reason(ox)
        and not cart_destination_brake_reason(ox) then
        local ok,resumed=pcall(movement_control.resume_turn,ox,runtime_clock,false,function(node)
            ox:get_ActionManager():requestActionCore(0,node,0)
        end)
        if not ok then
            stop_cart_rush(nil,"TurnTarget speed restoration failed")
            log.error("[OJR] TurnTarget speed restoration failed: "..tostring(resumed))
        elseif resumed then
            cart_trip.rush_ack_until=runtime_clock+0.5
            trace_cart_event("ojr_turn_resumed",{node=resumed,t=runtime_clock})
        end
    end

    -- Maintain seat transforms after gameplay state changes have settled.
    enforce_seat_transforms(ox, false)

    if driving_bus.driver and driving_bus.driver.capturing() then passenger_hud:restore();return end
    local ui_ok,ui_open=pcall(function() return reframework:is_drawing_ui() end)
    if ui_ok and ui_open then passenger_hud:restore();return end

    local modifier_held = modifier_is_down()

    local scene = nil
    if sitting then
        scene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene()")
    end

    if scene then
        local ui010201 = scene:call("findGameObject(System.String)", "ui010201")
        local ui010201Base = ui010201 and ui010201:call("getComponent(System.Type)", gui_base_type) or nil
        local labels={}
        for _,name in ipairs({"Walk","Dash","Teleport","Stand"}) do
            local feature=action_bindings[name]
            if feature.isUI and feature.skillUiKey then
                labels[feature.skillUiKey]=feature.nodeName and (feature.isDash and "Accelerate" or "Decelerate") or feature.name
            end
        end
        passenger_hud:update(ui010201Base and ui010201Base:get_DrawSelf() and ui010201Base.Root or nil,labels,
            function(root,path) return gui_get_object:call(root,path) end)
    else
        passenger_hud:restore()
    end

    if modifier_held and seating_lock_active then
        local trigger_stand = false
        if is_key_valid(options.Key_PadModifyStand) then
            local s, v = pcall(input_bindings.was_triggered, options.Key_PadModifyStand)
            if s and v then trigger_stand = true end
        end
        if is_key_valid(options.Key_MouseModifyStand) then
            local s, v = pcall(input_bindings.was_triggered, options.Key_MouseModifyStand)
            if s and v then trigger_stand = true end
        end
        if trigger_stand then
            if driving_bus.driver then driving_bus.journey.release() else release_passengers_from_modifier() end
        end
    end

    for _, feature in pairs(action_bindings) do
        if modifier_held and is_near and feature.name ~= "Pawns Stand" then
            local trigger_modify = false
            if is_key_valid(options[feature.padModifyKey]) then
                local s, v = pcall(input_bindings.was_triggered, options[feature.padModifyKey])
                trigger_modify = trigger_modify or (s and v)
            end
            if is_key_valid(options[feature.mouseModifyKey]) then
                local s, v = pcall(input_bindings.was_triggered, options[feature.mouseModifyKey])
                trigger_modify = trigger_modify or (s and v)
            end
            if trigger_modify then
                if feature.modifyAction then feature.modifyAction()
                elseif feature.nodeName then
                    if driving_bus.driver and sitting then driving_bus.journey.speed_step(feature.isDash and 1 or -1)
                    else request_cart_locomotion(ox,feature.nodeName,feature.isDash) end
                end
            end
        end

        if sitting then
            local trigger_skill = false
            if is_key_valid(options[feature.padSkillKey]) then
                local s, v = pcall(input_bindings.was_triggered, options[feature.padSkillKey])
                trigger_skill = trigger_skill or (s and v)
            end
            if feature.name == "Oxcart Dash" and input and not driving_bus.driver then
                local s, v = pcall(function() return input:isButtonTrigger(MOUSE_DASH_FLAG) end)
                trigger_skill = trigger_skill or (s and v)
            elseif feature.name == "Oxcart Walk" and input and not driving_bus.driver then
                local s, v = pcall(function() return input:isButtonTrigger(MOUSE_WALK_FLAG) end)
                trigger_skill = trigger_skill or (s and v)
            elseif is_key_valid(options[feature.mouseSkillKey]) then
                local s, v = pcall(input_bindings.was_triggered, options[feature.mouseSkillKey])
                trigger_skill = trigger_skill or (s and v)
            end

            if trigger_skill then
                if feature.skillAction then feature.skillAction()
                elseif feature.nodeName then
                    if driving_bus.driver and sitting then driving_bus.journey.speed_step(feature.isDash and 1 or -1)
                    else request_cart_locomotion(ox,feature.nodeName,feature.isDash) end
                end
            end
        end
    end
end)

local function draw_seat_editor(label, seat_spec, position_only)
    if not label or imgui.tree_node(label) then
        local c1, v1 = imgui.drag_float("X (Left/Right)", seat_spec.x, 0.05, -10.0, 10.0)
        if c1 then seat_spec.x = v1; persist_options() end
        
        local c2, v2 = imgui.drag_float("Z (Forward/Back)", seat_spec.z, 0.05, -10.0, 10.0)
        if c2 then seat_spec.z = v2; persist_options() end
        
        local c3, v3 = imgui.drag_float("Y (Height)", seat_spec.y, 0.05, -5.0, 5.0)
        if c3 then seat_spec.y = v3; persist_options() end
        
        local c4, v4 = imgui.drag_float("Look X", seat_spec.lookX, 0.1, -1.0, 1.0)
        if c4 then seat_spec.lookX = v4; persist_options() end
        
        local c5, v5 = imgui.drag_float("Look Z", seat_spec.lookZ, 0.1, -1.0, 1.0)
        if c5 then seat_spec.lookZ = v5; persist_options() end
        
        if not position_only then
            local c_pc,v_pc=imgui.checkbox("Lock Height",seat_spec.pelvisCompensation==true)
            if c_pc then seat_spec.pelvisCompensation=v_pc;persist_options() end
            imgui.same_line()
            imgui.text("[?]")
            if imgui.is_item_hovered() then
                imgui.set_tooltip("Disabled by default. Enable only if some seated animations cause vertical height jitter.")
            end
            local c_idle, v_idle = imgui.checkbox("Random Idle", seat_spec.randomIdle)
            if c_idle then seat_spec.randomIdle = v_idle; persist_options() end
            imgui.same_line()
            local c_dm, v_dm = imgui.checkbox("Use Direct Motion", seat_spec.useDirectMotion)
            if c_dm then seat_spec.useDirectMotion = v_dm; persist_options() end

            if seat_spec.useDirectMotion then
                local cb, vb = imgui.drag_int("Bank ID", seat_spec.bankID, 1, 0, 999)
                if cb then seat_spec.bankID = vb; persist_options() end

                local cm, vm = imgui.drag_int("Motion ID", seat_spec.motionID, 1, 0, 9999)
                if cm then seat_spec.motionID = vm; persist_options() end
            else
                local c6, v6 = imgui.input_text("Animation", seat_spec.anim)
                if c6 then seat_spec.anim = v6; persist_options() end
            end
        end
        
        if label then imgui.tree_pop() end
    end
end

function pawn_seat_physics.draw_backup_keybinds()
        if imgui.tree_node("Backup keybinds") then
            imgui.spacing()
            if imgui.button("Restore default keybinds") then restore_default_key_bindings() end
            imgui.spacing()

            local function draw_dual_bind(label, padKey, mouseKey)
                imgui.table_next_row()
                imgui.table_next_column();imgui.text(label)
                imgui.table_next_column()
                local p_changed, p_value = input_bindings.imgui_rebind_button(padKey, options[padKey])
                if p_changed then options[padKey] = p_value; persist_options() end
                imgui.table_next_column()
                if mouseKey == "Key_MouseSkillDash" and not driving_bus.driver then
                    imgui.text("Mouse Left")
                elseif mouseKey == "Key_MouseSkillWalk" and not driving_bus.driver then
                    imgui.text("Mouse Right")
                else
                    local m_changed, m_value = input_bindings.imgui_rebind_button(mouseKey, options[mouseKey])
                    if m_changed then options[mouseKey] = m_value; persist_options() end
                end
            end

            local function begin_bind_table(id)
                if not imgui.begin_table(id,3,1) then return false end
                imgui.table_next_row()
                for _,label in ipairs({"Action","Gamepad","Keyboard"}) do
                    imgui.table_next_column();imgui.table_header(label)
                end
                return true
            end
                if begin_bind_table("OJR cross hotbar bindings") then
                draw_dual_bind("Modifier Key", "Key_PadModifyKey", "Key_MouseModifyKey")
                draw_dual_bind("Oxcart Dash", "Key_PadModifyDash", "Key_MouseModifyDash")
                draw_dual_bind("Oxcart Walk", "Key_PadModifyWalk", "Key_MouseModifyWalk")
                draw_dual_bind("Pawns Sit/TP", "Key_PadModifyTeleport", "Key_MouseModifyTeleport")
                draw_dual_bind("Pawns Stand", "Key_PadModifyStand", "Key_MouseModifyStand")
                imgui.end_table()
                end
            imgui.tree_pop()
        end
end

re.on_draw_ui(function()
    if imgui.tree_node("Oxcarts Journey Redux") then
        if driving_bus.driver then driving_bus.driver.draw_ui()
        elseif imgui.tree_node("Keybind settings") then
            pawn_seat_physics.draw_backup_keybinds()
            imgui.tree_pop()
        end

        if imgui.tree_node("Seating Position Presets") then
            -- Show the layout family resolved from the current cart body.
            local active_cat = "Normal"
            local ox = find_active_ox()
            if ox then
                local cart_transform = find_cart_body(ox)
                active_cat = classify_cart_model(cart_transform)
            end
            
            imgui.text("Detected Cart Type: " .. active_cat)
            
            local current_preset_name = "None"
            if options.Presets[active_cat] and options.Presets[active_cat][preset_cursor[active_cat]] then
                current_preset_name = options.Presets[active_cat][preset_cursor[active_cat]].name
            end
            imgui.text("Current Active Preset: " .. current_preset_name)
            if imgui.button("Restore all built-in layouts") and unified_presets.restore_builtins() then
                if pawn_seat_physics.menu then pawn_seat_physics.menu.indices={} end
                pawn_seat_physics.queue_preset(active_cat,preset_cursor[active_cat] or 1)
            end
            
            imgui.separator()
            
            local cat_list = {
                { id = "Normal", name = "Normal Oxcart" },
                { id = "Rainy", name = "Rainproof Oxcart" },
                { id = "Wealthy", name = "Luxury Oxcart" }
            }
            
            pawn_seat_physics.menu=pawn_seat_physics.menu or {indices={}}
            local menu=pawn_seat_physics.menu
            local category=menu.category or (active_cat=="Rainy" and 2 or active_cat=="Wealthy" and 3 or 1)
            local category_changed,category_value=imgui.combo("Cart type",category,{"Normal Oxcart","Rainproof Oxcart","Luxury Oxcart"})
            if category_changed and cat_list[category_value] then category=category_value;menu.category=category end
            for _, cat_info in ipairs({cat_list[category]}) do
                local cat = cat_info.id
                do
                    local names={}
                    for _,preset in ipairs(options.Presets[cat]) do names[#names+1]=preset.name end
                    local selected=math.max(1,math.min(#names,menu.indices[cat] or preset_cursor[cat] or 1))
                    local layout_changed,layout_value=imgui.combo("Active layout",selected,names)
                    if layout_changed and names[layout_value] then
                        selected=layout_value;menu.indices[cat]=selected
                        if cat==active_cat and options.Presets[cat][selected].enabled then
                            pawn_seat_physics.queue_preset(cat,selected)
                        end
                    end
                    for i, preset in ipairs(options.Presets[cat]) do
                        imgui.push_id(cat .. "_preset_" .. i)
                        if i==selected then
                            
                            if #options.Presets[cat] < 15 and imgui.button("+ Add New Preset (Max 15)###add_preset_" .. cat) then
                                local src = preset
                                local new_preset = {
                                    name = (cat=="Wealthy" and "Luxury" or cat=="Rainy" and "Rainproof" or "Normal") .. " - " .. (#options.Presets[cat] + 1),
                                    enabled = true,
                                    teleportPlayer = src.teleportPlayer,
                                    skipPassenger = src.skipPassenger,
                                    player = {}, pawns = {}
                                }
                                for key,value in pairs(src.player) do new_preset.player[key]=value end
                                for idx=1,9 do
                                    new_preset.pawns[idx]={}
                                    for key,value in pairs(src.pawns[idx]) do new_preset.pawns[idx][key]=value end
                                end
                                if unified_presets then unified_presets.clone_player_seats(src,new_preset) end
                                table.insert(options.Presets[cat],new_preset)
                                persist_options()
                                menu.indices[cat]=#options.Presets[cat]
                                if cat==active_cat then
                                    pawn_seat_physics.queue_preset(cat,#options.Presets[cat])
                                end
                                imgui.pop_id()
                                break
                            end
                            if #options.Presets[cat] < 15 and #options.Presets[cat] > 1 then imgui.same_line() end
                            if #options.Presets[cat] > 1 then
                                if not preset._confirm_delete then
                                    if imgui.button("Delete Preset###del_" .. cat .. i) then
                                        preset._confirm_delete = true
                                    end
                                else
                                    if imgui.button("Confirm Delete###conf_" .. cat .. i) then
                                        table.remove(options.Presets[cat], i)
                                        if (preset_cursor[cat] or 1)>i then preset_cursor[cat]=preset_cursor[cat]-1
                                        elseif preset_cursor[cat]==i then preset_cursor[cat]=math.min(i,#options.Presets[cat]) end
                                        menu.indices[cat]=math.min(i,#options.Presets[cat])
                                        persist_options()
                                        if cat==active_cat then pawn_seat_physics.queue_preset(cat,preset_cursor[cat] or 1) end
                                        imgui.pop_id()
                                        break
                                    end
                                    imgui.same_line()
                                    if imgui.button("Cancel###canc_" .. cat .. i) then
                                        preset._confirm_delete = false
                                    end
                                end
                            end
                            
                            local s_changed, s_val = imgui.input_text("Preset Name", preset.name)
                            if s_changed then preset.name = s_val; persist_options() end
                            
                            local tp_changed, tp_val = imgui.checkbox("Adjust Player", preset.teleportPlayer)
                            if tp_changed then
                                preset.teleportPlayer = tp_val
                                if cat==active_cat and i==(preset_cursor[cat] or 1) then
                                    pawn_seat_physics.sync_player_adjustment(preset)
                                    if driving_bus.driver then driving_bus.driver.player_adjustment_changed(preset) end
                                end
                                persist_options()
                            end
                            imgui.same_line()
                            local skip_changed,skip_value=imgui.checkbox("Skip this preset when player is passenger",preset.skipPassenger==true)
                            if skip_changed then preset.skipPassenger=skip_value;persist_options() end
                            if imgui.tree_node("Player parameter") then
                                local automatic=driving_bus.driver and driving_bus.driver.player_is_driver() and 1 or 2
                                if menu.player_mode_last~=automatic then
                                    menu.player_mode,menu.player_mode_last=automatic,automatic
                                end
                                local mode_changed,mode=imgui.combo("Player seat",menu.player_mode or automatic,
                                    {"When player as driver","When player as passenger"})
                                if mode_changed then menu.player_mode=mode end
                                if (menu.player_mode or automatic)==1 and driving_bus.driver then
                                    driving_bus.driver.draw_player(preset)
                                else
                                    draw_seat_editor(nil,preset.player,true)
                                    if driving_bus.driver and driving_bus.driver.draw_camera then driving_bus.driver.draw_camera(preset,true) end
                                end
                                imgui.tree_pop()
                            end
                            
                            local members=collect_companions()
                            local visible=math.max(3,math.min(9,members and #members or 0))
                            for _,binding in ipairs(seat_bindings) do if binding.slot then visible=math.max(visible,binding.slot) end end
                            imgui.text("Up to 9 companions: Main Pawn, other pawns, then following NPCs.")
                            for p_idx = 1, visible do
                                draw_seat_editor((p_idx<=3 and "Pawn " or "Companion ") .. p_idx, preset.pawns[p_idx])
                            end
                        end
                        imgui.pop_id()
                    end
                    
                end
            end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
end)

sdk.hook(
    sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
    function(args)
        local ok,result=pcall(function()
            local this = sdk.to_managed_object(args[2])
            if external_driver_active() then return end
            local owner = this:get_GameObject()
            if not owner or not owner:get_Valid() then return end      
        
            local char = owner:call("getComponent(System.Type)", sdk.typeof("app.Character"))
            if not char then return end
        
            local nodeName = sdk.to_managed_object(args[4]):ToString()
            local n = nodeName:lower()

            if seating_lock_active and not cart_trip.pause.active and not cart_trip.pause.resume_pending
                and not gameplay_is_paused() then
                if char == player then
                    if n:find("warp") or n:find("ferry") or n:find("item") then
                        seating_lock_active = false
                        detach_bound_characters()
                    end
                end
            
                for i, p in ipairs(seat_bindings) do
                    if p.char == char then
                        local staggers = {"caught"}
                        for _, str in ipairs(staggers) do
                            if n:find(str) then
                                pawn_seat_physics.remove(i)
                                break
                            end
                        end
                        break
                    end
                end
            end

            if (sdk.to_int64(args[5]) & 0xffffffff)==0 and (nodeName=="Walk" or nodeName=="Run" or nodeName=="Dash")
                and char==find_active_ox() and not gameplay_is_paused() and pawn_seat_physics.driver_wait_reason(char) then
                trace_cart_event("ojr_request_blocked",{node=nodeName,reason="no seated driver"})
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            local suspended=cart_trip.pause.active or cart_trip.pause.resume_pending or gameplay_is_paused()
            if movement_control.blocks(char,nodeName,sdk.to_int64(args[5]) & 0xffffffff,runtime_clock,suspended) then
                trace_cart_event("ojr_request_blocked",{node=nodeName,reason="speed hold"})
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end)
        if ok then return result end -- Unreadable requests must remain native.
    end
)

sdk.hook(
    sdk.find_type_definition("app.MainCameraController"):get_method("switchCamera(app.CameraDefine.ControlType, app.CameraSwitchInterpParam, app.PostEffectSetting, app.CameraDefine.ToPlayerCameraOption)"),
    function(args)
        local controlType = sdk.to_int64(args[3])
        if controlType == 12 and options.DISABLE_CAMERA then          
            local ox = find_active_ox()
            if not player_is_near_cart(ox) then return end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
)

local cart_protection=assert(rawget(_G,"OJR_CartProtection"))
local protection_test=cart_protection.new(function(message,key)
    if rawget(_G,"OJR_EnableRuntimeDiagnostics")~=true then
        if message:find('failed',1,true) or key=='parts'
            or (key=='part-hook' and message:find('unavailable',1,true)) then log.warn(message) end
        return
    end
    if log.info then log.info(message) else log.warn(message) end
    if rawget(_G,"OJR_RuntimeDiagnostics") then _G.OJR_RuntimeDiagnostics.write('protection',{message=message}) end
end)
function pawn_seat_physics.cart_protection_scope()
    local ox=find_active_ox()
    if not is_character_valid(ox) or not is_character_valid(player) then return end
    local ch2=ox.EnemyCtrl and ox.EnemyCtrl.Ch2
    local controller=ch2 and ch2["<CachedOxcart>k__BackingField"]
    local c={ox=ox,controller=controller,parts={},targets={},near=player_is_near_cart(ox)}
    local connect=ch2 and ch2["<CachedConnectParts>k__BackingField"]
    c.cow=manual_cart and manual_cart.cow or connect and connect.CowChara
    if manual_cart then c.body=manual_cart.body and manual_cart.body:get_GameObject()
    elseif controller then pcall(function() c.body=controller:get_GameObject() end) end
    local function add(go,label,component)
        if cart_protection.valid(go) then
            local record={go=go,label=label..' '..tostring(go:get_Name()),component=component}
            c.targets[#c.targets+1]=record
            return record
        end
    end
    add(ox:get_GameObject(),'ox')
    if is_character_valid(c.cow) then add(c.cow:get_GameObject(),'connected ox') end
    add(c.body,'cart body')
    local ok,err=pcall(function()
        local parts=controller and controller.PartsList
        if parts then
            for i=0,parts:get_Count()-1 do
                local component=parts:get_Item(i)
                if cart_protection.valid(component) then
                    local record=add(component:get_GameObject(),'cart part '..i,component)
                    if record then c.parts[#c.parts+1]=record end
                end
            end
        end
    end)
    if not ok then protection_test:report('parts','PartsList unavailable: '..tostring(err)) end
    return c
end
function pawn_seat_physics.update_cart_protection()
    local ok,c=pcall(pawn_seat_physics.cart_protection_scope)
    if not ok then
        protection_test:report('scope','scope failed: '..tostring(c))
        protection_test:clear();return
    end
    if not c or not c.near then protection_test:clear();return end
    local now=os.clock()
    local key=c.ox:get_address()
    if protection_test.cart==key and now<(protection_test.next_at or 0) then return end
    protection_test.cart,protection_test.next_at=key,now+0.25
    local scope_key=key..':'..#c.targets..':'..#c.parts
    if protection_test.scope_key~=scope_key then
        protection_test.scope_key=scope_key
        protection_test:report('scope:'..scope_key,'scope ox='..tostring(c.ox:get_GameObject():get_Name())
            ..' targets='..#c.targets..' PartsList='..#c.parts,now)
    end
    protection_test:tick(c.targets,function(go)
        local result={}
        local component=go:call('getComponent(System.Type)',sdk.typeof('app.HitController'))
        if component then result[#result+1]=component end
        return result
    end,now)
end
re.on_application_entry('UpdateBehavior',pawn_seat_physics.update_cart_protection)

cart_protection.install_destroy_guard(function()
    -- Live native occupancy only: no delayed trip flags or motion-name fallback.
    if not is_character_valid(player) then return end
    local ox=find_active_ox()
    if not is_character_valid(ox) then return end
    local controller=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
    if not cart_protection.valid(controller) then return end
    local seat=controller:call('get_DrivingSeat')
    local occupant=seat and seat.SitChara
    local driver_seated=seat and seat:call('isSit()')==true
    local riding=controller:call('isPlayerSit()')==true
        or (driver_seated and cart_protection.same(occupant,player))
    if not riding then return end
    local manager=npc_manager.OxcartManager
    local status=manager:getStatus(ox:get_CharaID())
    return {riding=true,loading=gui_manager:call('get_IsLoadGui()'),
        fast_travel=manager:call('getFastTravelState()'),ox_id=ox:get_CharaID(),
        driver_id=driver_seated and occupant and not cart_protection.same(occupant,player)
            and occupant:get_CharaID() or nil,
        container=status and status['<CachedGenerateContainer>k__BackingField']}
end,function(key,message) protection_test:report(key,message) end)

-- Prevent only the active nearby cart's native breakup; no repair or reconnect.
function pawn_seat_physics.prevent_cart_breakup(component)
    if options.PREVENT_CART_BREAKUP~=true or not component then return false end
    local ok,result=pcall(function()
        local ox=find_active_ox()
        if not is_character_valid(ox) or not is_character_valid(player) then return false end
        local controller=ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        if not controller or controller:get_address()~=component:get_address() then return false end
        local body=component:get_GameObject()
        if not body or not body:get_Valid() then return false end
        return (player:get_Transform():get_Position()-body:get_Transform():get_Position()):length()<50
    end)
    return ok and result==true
end
function pawn_seat_physics.prevent_cart_part_breakup(component)
    if options.PREVENT_CART_BREAKUP~=true or not component then return false end
    local ok,result=pcall(function()
        local c=pawn_seat_physics.cart_protection_scope()
        if not c or not cart_protection.valid(c.body) then return false end
        if (player:get_Transform():get_Position()-c.body:get_Transform():get_Position()):length()>=50 then return false end
        for _,part in ipairs(c.parts) do
            if cart_protection.same(component,part.component) then return true end
        end
        return false
    end)
    if not ok then protection_test:report('part-break-error','part breakup check failed: '..tostring(result)) end
    return ok and result==true
end
do
    local definition=sdk.find_type_definition("app.Gm80_042")
    local method=definition and definition:get_method("executeBreak(System.Boolean)")
    if method then
        sdk.hook(method,function(args)
            local component=sdk.to_managed_object(args[2])
            local blocked=pawn_seat_physics.prevent_cart_breakup(component)
            protection_test:report('body-break','Gm80_042.executeBreak blocked='..tostring(blocked))
            if blocked then return sdk.PreHookResult.SKIP_ORIGINAL end
        end,function(retval) return retval end)
    else log.warn("[OJR] Native cart breakup protection unavailable") end
    local parts_definition=sdk.find_type_definition('app.Sm80_042_Parts')
    local parts_method=parts_definition and parts_definition:get_method('executeBreak(System.Boolean)')
    if parts_method then
        sdk.hook(parts_method,function(args)
            local component=sdk.to_managed_object(args[2])
            if pawn_seat_physics.prevent_cart_part_breakup(component) then
                protection_test:report('part-break:'..component:get_address(),'blocked Sm80_042_Parts.executeBreak: '..tostring(component:get_GameObject():get_Name()))
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            local ok,details=pcall(function()
                local c=pawn_seat_physics.cart_protection_scope()
                return 'target='..tostring(component:get_GameObject():get_Name())..' parts='..tostring(c and #c.parts)
            end)
            protection_test:report('part-break-allowed','Sm80_042_Parts.executeBreak NOT blocked: '..tostring(details))
        end,function(retval) return retval end)
        protection_test:report('part-hook','Sm80_042_Parts.executeBreak test hook installed')
    else protection_test:report('part-hook','Sm80_042_Parts.executeBreak unavailable') end
end

-- Shared damage policy for both driving modes; no attacker multipliers.
function pawn_seat_physics.protection_for(info)
    local ok,rule=pcall(function()
        local receiver=info and info["<DamageGameObject>k__BackingField"]
        if not receiver or not receiver:get_Valid() then return end
        local policy=cart_protection
        if seating_lock_active then
            for _,binding in ipairs(seat_bindings) do
                local ch=binding.char
                if ch~=player and is_character_valid(ch) and policy.same(receiver,ch:get_GameObject()) then
                    return "companion"
                end
            end
        end
        local c=pawn_seat_physics.cart_protection_scope()
        if c and policy.cart_receiver(receiver,c.ox,c.body,c.cow,c.near,c.parts) then return "cart" end
    end)
    if not ok then protection_test:report('damage-rule','damage recognition failed: '..tostring(rule)) end
    return ok and rule or nil
end
function pawn_seat_physics.record_damage(stage,controller,info,rule)
    if rawget(_G,"OJR_EnableRuntimeDiagnostics")~=true then return end
    local ok,err=pcall(function()
        local function read(fn) local success,value=pcall(fn);if success then return value end end
        local function describe(go)
            if not go then return 'nil' end
            return tostring(read(function() return go:get_Name() end))..'@'..tostring(read(function() return go:get_address() end))
        end
        local receiver=read(function() return info['<DamageGameObject>k__BackingField'] end)
        local hit_go=read(function() return controller:get_GameObject() end)
        local owner=read(function() return info['<DamageOwnerHitController>k__BackingField']:get_GameObject() end)
        local c=read(pawn_seat_physics.cart_protection_scope)
        local label=describe(receiver)..' hit='..describe(hit_go)..' owner='..describe(owner)
        if not rule and not (c and c.near) and not label:find('ch299003',1,true)
            and not label:find('gm80_',1,true) and not label:find('sm80_',1,true) then return end
        local current=read(function() return controller:call('get_IsInvincible()') end)
        protection_test:report('damage:'..stage..':'..label,stage..' rule='..tostring(rule)..' receiver='..label
            ..' damage='..tostring(read(function() return info.Damage end))..' invincible='..tostring(current)
            ..' active_ox='..tostring(c and describe(c.ox:get_GameObject()))..' near='..tostring(c and c.near)
            ..' parts='..tostring(c and #c.parts))
    end)
    if not ok then protection_test:report('damage-log-error','Damage diagnostic failed: '..tostring(err)) end
end
sdk.hook(
    sdk.find_type_definition("app.HitController"):get_method("damageProc(app.HitController.DamageInfo)"),
    function(args)
        local info=sdk.to_managed_object(args[3])
        local rule=pawn_seat_physics.protection_for(info)
        pawn_seat_physics.record_damage('damageProc',sdk.to_managed_object(args[2]),info,rule)
        if rule then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
)
sdk.hook(
    sdk.find_type_definition("app.HitController"):get_method("updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)"),
    function(args)
        local info=sdk.to_managed_object(args[3])
        local rule=pawn_seat_physics.protection_for(info)
        pawn_seat_physics.record_damage('updateDamage',sdk.to_managed_object(args[2]),info,rule)
        if rule then return sdk.PreHookResult.SKIP_ORIGINAL end
    end
)

-- Preserve ox debilitation protection, without rules for NPC drivers or guards.
sdk.hook(
    sdk.find_type_definition("app.StatusConditionCtrl"):get_method("reqStatusConditionApplyCore(app.StatusConditionDef.StatusConditionEnum, app.HitController.DamageInfo, app.StatusConditionDef.RequestInfo, System.Boolean)"),
    function(args)
        if not options.STATUS_IMMUNITY then return end
        local ok,blocked=pcall(function()
            local controller=sdk.to_managed_object(args[2])
            local ox=find_active_ox()
            local status=sdk.to_int64(args[3]) & 0xffffffff
            return status>=1 and status<=14 and is_character_valid(ox) and player_is_near_cart(ox) and controller.OwnerCharacter==ox
        end)
        if ok and blocked then return sdk.PreHookResult.SKIP_ORIGINAL end
    end
)
re.on_script_reset(function()
    protection_test:clear()
    movement_control.clear()
    passenger_hud:restore()
end)
