-- Oxcarts Journey Redux
-- Runtime input, passenger seating, cart control, and protection services.

-- Optional ownership handshake. No dependency when manual driving is absent.
local driving_bus = rawget(_G, "DD2_OxcartControl") or { version = 1 }
_G.DD2_OxcartControl = driving_bus
local function external_driver_active()
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
local gui_color_type = sdk.find_type_definition("via.Color")
local gui_base_type = sdk.typeof("app.GUIBase")

local cart_action_filters = {}
local frame_jobs = {}
local runtime_clock = 0
local player, input

-- Native Input action flags, not keyboard enum values. Keep the original
-- mouse mappings used by Better Oxcarts Redux for seated cart controls.
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

-- Pawn controller suspension is deferred by one frame after requesting an
-- animation so the action request can finish before AI updates are paused.
local pending_ai_lock = {}

local function is_character_valid(character)
    if not character then return false end
    local success, valid = pcall(function() return character:get_Valid() end)
    return success and valid or false
end

-- Prefer reflected backing fields because generated Lua method members may be
-- absent even while the underlying managed methods remain callable.
local function get_character_fsm(character)
    if not character then return nil end

    local human = character["<Human>k__BackingField"]
    if human and human.Fsm then
        return human.Fsm
    end

    local action_manager = character:get_ActionManager()
    return action_manager and action_manager.Fsm or nil
end

local function set_fsm_enabled(character, enabled)
    if not character then return false end

    local is_loading = false
    if gui_manager then
        pcall(function() is_loading = gui_manager:get_IsLoadGui() end)
    end
    if is_loading then return false end

    local updated = false
    local success = pcall(function()
        local fsm = get_character_fsm(character)
        if fsm then
            fsm:set_Enabled(enabled)
            updated = true
        end
    end)
    return success and updated
end

-- Release bindings left by a previous hot reload. The legacy key is read once
-- so upgrading an active session cannot leave pawns parented to the cart.
local legacy_seat_bindings = _G.BetterOxcarts_BoundPawns
local previous_seat_bindings = _G.OJR_SeatBindings or legacy_seat_bindings
if previous_seat_bindings then
    for _, item in ipairs(previous_seat_bindings) do
        local char = item
        if type(item) == "table" and item.char then char = item.char end
        if is_character_valid(char) then
            pcall(function() char:get_Transform():set_Parent(nil) end)
            set_fsm_enabled(char, true)
        end
    end
end
_G.BetterOxcarts_BoundPawns = nil
_G.OJR_SeatBindings = {}

local seating_lock_active = false
local seat_bindings = _G.OJR_SeatBindings
local seat_anchor_transform = nil 

-- Session state shared by the frame updater and damage hooks.
local prior_cart_seat_state = false
local prior_player_seat_state = false
local prior_cart_proximity = false -- 玩家是否在车附近
local cart_protection_range_active = false -- 全局标志，供HitController使用
local previous_fast_travel_state = 0
local reseat_requested_at = nil
local photo_mode_was_active = false

local CART_START_GRACE = 10.0
local RUSH_STOP_CONFIRM = 2.0
local RUSH_STOP_SPEED = 0.5
local cart_trip = {
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
    PREVENT_INSTABREAKS = true,
    DISABLE_PAWN_DAMAGE = true,
    
    -- Nearby cart protection multipliers.
    GIMMICK_DAMAGE_RECEIVED = 0.01,
    DRIVER_DAMAGE_RECEIVED = 0.01,
    OX_DAMAGE_RECEIVED = 0.01,
    GUARD_DAMAGE_RECEIVED = 0.51,
    GUARD_DAMAGE_DEALT = 1.25,

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
    return {
        {
            name = "Facing Each Other", enabled = true,
            teleportPlayer = false,
            player = { x = 0.85, z = -2.55, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = 0.85, z = -3.35, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.85, z = -3.35, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.85, z = -2.5, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        },
        {
            name = "Side by Side", enabled = true,
            teleportPlayer = false,
            player = { x = 0.85, z = -2.55, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = 0.85, z = -3.35, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.85, z = -3.35, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairCrossArmStart", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = 0.85, z = -4.1, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        },
        {
            name = "Look Around", enabled = true,
            teleportPlayer = false,
            player = { x = 0.85, z = -2.55, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = 1.35, z = -2.0, y = 0.77, lookX = 1.0, lookZ = 0.0, anim = "LivSitChairCrosslegs", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.85, z = -3.35, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = 0.85, z = -4.6, y = 0.23, lookX = 1.0, lookZ = 1.0, anim = "SitOnChairCrossArmStart", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        },
        {
            name = "Sit on the Edge", enabled = true,
            teleportPlayer = true,
            player = { x = 1.25, z = -2.55, y = 0.77, lookX = -1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = 1.25, z = -2.0, y = 0.77, lookX = -1.0, lookZ = 0.0, anim = "LivSitChairCrosslegs", useOxAnchor = false, freezeFsm = true, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -1.25, z = -3.35, y = 0.80, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.85, z = -4.2, y = 0.25, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairCrossArmStart", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        }
    }
end

local function get_default_rainy_presets()
    return {
        {
            name = "Rainy - Side by Side", enabled = true,
            teleportPlayer = false,
            player = { x = 0.85, z = -2.55, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = 0.85, z = -3.1, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.85, z = -3.35, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = 0.85, z = -4.1, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        },
        {
            name = "Rainy - Facing Each Other", enabled = true,
            teleportPlayer = false,
            player = { x = 0.85, z = -2.55, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = -1.0, z = -2.35, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.95, z = -4.1, y = 0.23, lookX = -1.0, lookZ = 0.0, anim = "SitOnChairCrossArmStart", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = 0.85, z = -4.1, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        }
    }
end

local function get_default_wealthy_presets()
    return {
        {
            name = "Luxury - Facing Each Other", enabled = true,
            teleportPlayer = false,
            player = { x = 0.85, z = -2.55, y = 0.23, lookX = 1.0, lookZ = 0.0, anim = "Wait", useOxAnchor = false, freezeFsm = false, randomIdle = false, useDirectMotion = false, bankID = 0, motionID = 0 },
            pawns = {
                { x = 0.45, z = -3.15, y = 0.23, lookX = 0.0, lookZ = -1.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = -0.5, z = -1.2, y = 0.23, lookX = 0.0, lookZ = 1.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 },
                { x = 0.5, z = -1.25, y = 0.23, lookX = 0.0, lookZ = 1.0, anim = "SitOnChairActions", useOxAnchor = false, freezeFsm = true, randomIdle = true, useDirectMotion = false, bankID = 0, motionID = 0 }
            }
        }
    }
end

-- Upgrade older settings in place and fill newly introduced seat fields.
local function normalize_presets()
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
            if type(preset.enabled) ~= "boolean" then preset.enabled = true end
            if type(preset.teleportPlayer) ~= "boolean" then preset.teleportPlayer = false end
            preset.name = preset.name or "Unnamed Preset"
            
            preset.player = preset.player or {}
            preset.player.x = preset.player.x or 0.0
            preset.player.z = preset.player.z or 0.0
            preset.player.y = preset.player.y or 0.85
            preset.player.lookX = preset.player.lookX or 0.0
            preset.player.lookZ = preset.player.lookZ or 0.0
            preset.player.anim = preset.player.anim or "SitOnChairActions"
            if type(preset.player.useOxAnchor) ~= "boolean" then preset.player.useOxAnchor = false end
            if type(preset.player.freezeFsm) ~= "boolean" then preset.player.freezeFsm = false end
            if type(preset.player.randomIdle) ~= "boolean" then preset.player.randomIdle = false end
            if type(preset.player.useDirectMotion) ~= "boolean" then preset.player.useDirectMotion = false end
            preset.player.bankID = preset.player.bankID or 0
            preset.player.motionID = preset.player.motionID or 0

            preset.pawns = preset.pawns or {}
            for i = 1, 3 do
                if not preset.pawns[i] then preset.pawns[i] = {} end
                preset.pawns[i].x = preset.pawns[i].x or 0.0
                preset.pawns[i].z = preset.pawns[i].z or 0.0
                preset.pawns[i].y = preset.pawns[i].y or 0.85
                preset.pawns[i].lookX = preset.pawns[i].lookX or 0.0
                preset.pawns[i].lookZ = preset.pawns[i].lookZ or 0.0
                preset.pawns[i].anim = preset.pawns[i].anim or "SitOnChairActions"
                if type(preset.pawns[i].useOxAnchor) ~= "boolean" then preset.pawns[i].useOxAnchor = false end
                if type(preset.pawns[i].freezeFsm) ~= "boolean" then preset.pawns[i].freezeFsm = false end
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
    rebuild_input_watchlist()
end

local function persist_options()
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

local driver_character_ids = { ["ch300795"] = true, ["ch300298"] = true, ["ch300291"] = true, ["ch300793"] = true, ["ch300367"] = true, ["ch300794"] = true }
local guard_character_ids = { ["ch300802"] = true, ["ch300803"] = true, ["ch300804"] = true, ["ch300260"] = true, ["ch300383"] = true, ["ch300258"] = true, ["ch300056"] = true, ["ch300055"] = true, ["ch300057"] = true, ["ch300797"] = true, ["ch300796"] = true, ["ch300798"] = true, ["ch300558"] = true, ["ch300369"] = true, ["ch300545"] = true, ["ch300801"] = true, ["ch300800"] = true, ["ch300799"] = true }
local protected_cart_part_ids = { ["gm80_042"] = true, ["gm80_052"] = true,["sm80_074"] = true, ["sm80_051"] = true, ["sm80_052"] = true,["gm81_004"] = true }

local entity_damage_rules = {}
local function rebuild_damage_rules()
    entity_damage_rules = {}
    for str,_ in pairs(driver_character_ids) do entity_damage_rules[str] = { received = options.DRIVER_DAMAGE_RECEIVED } end
    for str,_ in pairs(guard_character_ids) do entity_damage_rules[str] = { received = options.GUARD_DAMAGE_RECEIVED, dealt = options.GUARD_DAMAGE_DEALT } end
    for str,_ in pairs(protected_cart_part_ids) do entity_damage_rules[str] = { received = options.GIMMICK_DAMAGE_RECEIVED } end
    entity_damage_rules["ch299003"] = { received = options.OX_DAMAGE_RECEIVED }
end
rebuild_damage_rules() -- 初始化伤害倍率表

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

local function skill_binding_is_down(feature)
    if is_key_valid(options[feature.padSkillKey]) then
        local s, v = pcall(input_bindings.is_pressed, options[feature.padSkillKey])
        if s and v then return true end
    end
    if feature.name == "Oxcart Dash" and input then
        local s, v = pcall(function() return input:isButtonOn(MOUSE_DASH_FLAG) end)
        if s and v then return true end
    elseif feature.name == "Oxcart Walk" and input then
        local s, v = pcall(function() return input:isButtonOn(MOUSE_WALK_FLAG) end)
        if s and v then return true end
    elseif is_key_valid(options[feature.mouseSkillKey]) then
        local s, v = pcall(input_bindings.is_pressed, options[feature.mouseSkillKey])
        if s and v then return true end
    end
    return false
end

local function alternate_binding_is_down(feature)
    if is_key_valid(options[feature.padModifyKey]) then
        local s, v = pcall(input_bindings.is_pressed, options[feature.padModifyKey])
        if s and v then return true end
    end
    if is_key_valid(options[feature.mouseModifyKey]) then
        local s, v = pcall(input_bindings.is_pressed, options[feature.mouseModifyKey])
        if s and v then return true end
    end
    return false
end

local seated_hotbar_paths = {
    ["Y (Triangle)"] = "PNL_top/PNL_L02/PNL_txt", ["A (X)"] = "PNL_top/PNL_R03/PNL_txt",
    ["X (Square)"]   = "PNL_top/PNL_L03/PNL_txt", ["B (Circle)"] = "PNL_top/PNL_R02/PNL_txt",
    ["LT"]           = "PNL_top/PNL_L00/PNL_txt", ["RT"] = "PNL_top/PNL_R00/PNL_txt",
    ["LB"]           = "PNL_top/PNL_L01/PNL_txt", ["RB"] = "PNL_top/PNL_R01/PNL_txt",
}


local function render_seated_hotbar_slot(button, message, is_held)
    if not button then return end
    pcall(function() button:set_PlayState("DEFAULT") end)
    local textObject = button:get_Child()
    if not textObject then return end 
    pcall(function() textObject:set_Message(message) end)
    local col = ValueType.new(gui_color_type)
    col.rgba = 0x8FF0FBFF
    pcall(function() textObject:set_Color(col) end)
    local col2 = ValueType.new(gui_color_type)
    col2.rgba = 0xC8FFFFFF
    local nextObj = button:get_Next()
    if nextObj then pcall(function() nextObj:set_Color(col2) end) end 
    if is_held then
        pcall(function() button:set_ColorScale(Vector4f.new(4,4,4,4)) end)
        pcall(function() button:set_ColorOffset(Vector3f.new(15,14,10)) end)
    else
        pcall(function() button:set_ColorScale(Vector4f.new(1,1,1,1)) end)
        pcall(function() button:set_ColorOffset(Vector3f.new(0,0,0)) end)
    end
end


local function cancel_scheduled_actions(address)
    cart_action_filters[address] = nil
    frame_jobs[address] = nil
end

local function suppress_action_interrupts(character,duration)
    local address = character:get_address()
    local staggers = {"damage","dmg","repelled","caught","tumble","wince","blown","down","die","success","escape","balance","break","cliffgrab","bridge"}
    cart_action_filters[address] = function(data)
        if data.character ~= character then return end
        -- Let UI transitions run, but do not discard the gameplay filter because
        -- a pause/menu action resembles a stagger or escape action.
        if cart_trip.pause.active or cart_trip.pause.resume_pending then return end
        if data.priority == 0 then return end
        if data.layer > 1 then return end
        for _,str in ipairs(staggers) do
            if string.find(data.node:lower(),str,1,true) then
                cancel_scheduled_actions(address)
                return
            end
        end
        return true
    end
    local start = runtime_clock
    frame_jobs[address] = function()
        if runtime_clock - start > duration then cancel_scheduled_actions(address) end
    end
end

local function collect_party_pawns()
    local pawn_manager = sdk.get_managed_singleton("app.PawnManager")
    if not pawn_manager then return {nil, nil, nil} end
    local party_members = {nil, nil, nil}
    local main_pawn = pawn_manager:get_MainPawn()
    if main_pawn then
        local main_character = main_pawn:get_CachedCharacter()
        if main_character and main_character:get_Valid() then party_members[1] = main_character end
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
                    local party_slot = tonumber(pawn_manager:getPartyPawnID(pawn))
                    if party_slot == 1 then party_members[2] = pawn_character
                    elseif party_slot == 2 then party_members[3] = pawn_character
                    else
                        if not party_members[2] then party_members[2] = pawn_character
                        elseif not party_members[3] then party_members[3] = pawn_character end
                    end
                end
            end
        end
    end
    return party_members
end

-- Detach every bound character and resume normal pawn control.
local function detach_bound_characters()
    -- A queued next-frame lock must not freeze a passenger again after release.
    pending_ai_lock = {}
    for _, binding in ipairs(seat_bindings) do
        local char = binding.char
        if is_character_valid(char) then
            pcall(function() char:get_Transform():set_Parent(nil) end)
            set_fsm_enabled(char, true) -- 恢复状态机，允许随从重新自由行动
        end
    end
    for k in pairs(seat_bindings) do seat_bindings[k] = nil end
end

-- Start the requested seated motion, then suspend the pawn controller when the
-- preset requires a stable pose.
local function start_seated_animation(char, seat_spec, force_anim_node)
    if not char or not char:get_Valid() then return end
    
    if seat_spec.useDirectMotion and not force_anim_node then
        if seat_spec.freezeFsm then
            set_fsm_enabled(char, false)
        end
        pcall(function()
            local motion = char:get_Motion()
            if motion then
                local layer = motion:getLayer(0)
                if layer then
                    layer:call("changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)", seat_spec.bankID or 0, seat_spec.motionID or 0, 0.0, 12.0, 1, 1)
                end
            end
        end)
    else
        local action_manager = nil
        pcall(function() action_manager = char["<ActionManager>k__BackingField"] end)
        
        if action_manager then
            if seat_spec.freezeFsm then
                set_fsm_enabled(char, true) 
            end
            
            pcall(function()
                -- Priority 1 keeps the requested pose alive until the deferred
                -- controller lock runs on the following frame.
                action_manager:requestActionCore(1, force_anim_node or seat_spec.anim, 0)
            end)
            
            if seat_spec.freezeFsm then
                table.insert(pending_ai_lock, char)
            end
        end
    end
end

-- Release variants use different exit animations for the two hotbars.
local function release_passengers_from_skill()
    if not seating_lock_active then return end
    if not player or not player:get_Valid() then return end
    
    seating_lock_active = false
    detach_bound_characters()

    local cat = "Normal"
    local ox = find_active_ox()
    if ox then
        local ct = find_cart_body(ox)
        cat = classify_cart_model(ct)
    end
    
    local idx = preset_cursor[cat] or 1
    local preset = options.Presets[cat] and options.Presets[cat][idx]
    if not preset then preset = options.Presets.Normal and options.Presets.Normal[1] end

    if preset and preset.teleportPlayer then
        local action_manager = player["<ActionManager>k__BackingField"]
        if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
    end

    local party_members = collect_party_pawns()
    for i = 1, 3 do
        local pawn_character = party_members[i]
        if pawn_character and pawn_character ~= player then
            local action_manager = pawn_character["<ActionManager>k__BackingField"]
            if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
        end
    end
end

local function release_passengers_from_modifier()
    if not player or not player:get_Valid() then return end
    if not seating_lock_active then return end
    
    seating_lock_active = false
    detach_bound_characters()

    local cat = "Normal"
    local ox = find_active_ox()
    if ox then
        local ct = find_cart_body(ox)
        cat = classify_cart_model(ct)
    end
    
    local idx = preset_cursor[cat] or 1
    local preset = options.Presets[cat] and options.Presets[cat][idx]
    if not preset then preset = options.Presets.Normal and options.Presets.Normal[1] end

    if preset and preset.teleportPlayer then
        local action_manager = player["<ActionManager>k__BackingField"]
        if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
    end

    local party_members = collect_party_pawns()
    for i = 1, 3 do
        local pawn_character = party_members[i]
        if pawn_character and pawn_character:get_Valid() and pawn_character ~= player then
            local action_manager = pawn_character["<ActionManager>k__BackingField"]
            if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
        end
    end
end

-- Build the active bindings from the selected cart-specific layout.
local function bind_pawns_to_seats()
    if external_driver_active() then return false end
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

    cart_trip.seat_changed_at = runtime_clock
    cart_trip.stopped_since = nil
    cart_trip.arrival_was_false = false
    cart_trip.last_check_at = nil

    detach_bound_characters() 

    if preset.teleportPlayer and player and player:get_Valid() and player_uses_cart_seat_node() then
        start_seated_animation(player, preset.player)
        local next_idle = preset.player.randomIdle and (runtime_clock + math.random() * 25 + 5) or nil
        table.insert(seat_bindings, {char = player, seat_spec = preset.player, next_idle_time = next_idle})
    end

    local party_members = collect_party_pawns()
    for i = 1, 3 do
        local pawn_character = party_members[i]
        if pawn_character and pawn_character:get_Valid() and pawn_character ~= player then
            start_seated_animation(pawn_character, preset.pawns[i])
            local next_idle = preset.pawns[i].randomIdle and (runtime_clock + math.random() * 25 + 5) or nil
            table.insert(seat_bindings, {char = pawn_character, seat_spec = preset.pawns[i], next_idle_time = next_idle})
        end
    end
    
    seating_lock_active = true
    return true
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
    -- First manual Sit starts at the first enabled preset for this cart family.
    -- Later manual Sits advance; automatic reseating keeps the current preset.
    local next_idx = last_sit_preset[cat] and (preset_cursor[cat] or 1) or 0
    for i = 1, #presets do
        next_idx = next_idx % #presets + 1
        if presets[next_idx].enabled then
            preset_cursor[cat] = next_idx
            if bind_pawns_to_seats() then
                last_sit_preset[cat] = next_idx
                last_sit_request_at = runtime_clock
            end
            return
        end
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
        skillAction = release_passengers_from_skill,
        modifyAction = release_passengers_from_modifier,
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

local function request_cart_locomotion(ox, nodeName, isDash, automatic)
    if not ox then return end
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
    
    local action_name = current_action.Name
    if not action_name then return end
    for _,str in ipairs({"damage","dmg","repelled","caught","tumble","wince","blown","down","die","success","escape","balance","break","cliffgrab","bridge"}) do
        if string.find(action_name:lower(),str,1,true) then return end
    end
    
    action_manager:requestActionCore(0, nodeName, 0)
    if not automatic then cart_trip.auto_paused = not isDash end
    suppress_action_interrupts(ox, isDash and options.DASH_DURATION or 2)
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
    if reason then
        cart_trip.stop_reason = reason
    end
    if ox then
        pcall(function() cancel_scheduled_actions(ox:get_address()) end)
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

local function release_passengers_for_cart_stop()
    if not seating_lock_active then return end
    local passengers = {}
    for _, binding in ipairs(seat_bindings) do
        if binding.char and binding.char ~= player then
            table.insert(passengers, binding.char)
        end
    end
    seating_lock_active = false
    detach_bound_characters()
    for _, char in ipairs(passengers) do
        if is_character_valid(char) then
            pcall(function()
                local action_manager = char["<ActionManager>k__BackingField"]
                if action_manager then action_manager:requestActionCore(0, "Wait", 0) end
            end)
        end
    end
end

local function release_pawns_at_intermediate_stop(reason)
    -- Keep the player's seat binding; remove only followers and their queued locks.
    for i = #pending_ai_lock, 1, -1 do
        if pending_ai_lock[i] ~= player then table.remove(pending_ai_lock, i) end
    end
    for i = #seat_bindings, 1, -1 do
        local char = seat_bindings[i].char
        if char ~= player then
            if is_character_valid(char) then
                pcall(function() char:get_Transform():set_Parent(nil) end)
                set_fsm_enabled(char, true)
                pcall(function()
                    local manager = char["<ActionManager>k__BackingField"]
                    if manager then manager:requestActionCore(0, "Wait", 0) end
                end)
            end
            -- Damage protection follows the binding, so removal restores it too.
            table.remove(seat_bindings, i)
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
    local blocked = distance > 20 or destination.reason or cart_is_overturned(ox)
        or status_is_true(status, "isBroken_OxCart") or status_is_true(status, "isDead_Ox")
        or status_is_true(status, "isArrived")
    if pause.was_rushing and cart_trip.rush_requested_at and not blocked and not cart_trip.auto_paused then
        local remaining = options.DASH_DURATION - (runtime_clock - pause.rush_started_at)
        if remaining > 0 then
            if get_cart_action(ox):lower() == "dash" then
                suppress_action_interrupts(ox, remaining)
            else
                -- Restoring an existing rush is not a new auto-start: the player
                -- may have stood up before opening the menu, but is still nearby.
                request_cart_locomotion(ox, "Dash", true, true)
                pause.restore_dispatched = true
                pause.restore_deadline = runtime_clock + 0.5
            end
            if cart_trip.rush_requested_at then
                cart_trip.rush_requested_at = pause.rush_started_at
                suppress_action_interrupts(ox, remaining)
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
    -- Check distance every frame, even if the player was already far away when
    -- the actor became available. An unreadable position is not "over 20".
    local player_distance = player_cart_distance(ox)
    if player_distance and player_distance > 20.0 then
        release_pawns_at_intermediate_stop("player left cart beyond 20")
        reset_auto_walk()
        cart_trip.auto_reason = "player/cart distance exceeds 20"
        local paid_ok, paid = pcall(function() return status and status:call("get_isPayMoney") end)
        if paid_ok and paid == true then
            local force_wait = get_cart_action(ox):lower() ~= "wait"
            stop_cart_rush(ox, "paid player left cart beyond 20", "Wait", false, force_wait)
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
    local action = get_cart_action(ox):lower()
    -- Give a newly queued Dash time to enter its action; an older request is not
    -- evidence that the actor is still dashing after the engine has selected Walk.
    if action == "walk" and cart_trip.rush_requested_at
        and runtime_clock - cart_trip.rush_requested_at >= 0.5
        and not (cart_trip.rush_ack_until and runtime_clock < cart_trip.rush_ack_until) then
        stop_cart_rush(ox, "live Walk replaced requested rush", nil, true)
        cart_trip.departure_pending = false
        reset_auto_walk()
    end
    if not physically_sitting and (action == "walk" or action == "wait") then
        release_pawns_at_intermediate_stop("player stood up during Walk/Wait")
    end
    local arrived = status_is_true(status, "isArrived")
    if arrived and not cart_trip.final_arrival_seen then
        cart_trip.final_arrival_seen = true
        stop_cart_rush(ox, "final arrival transition")
    end
    local near_stop = cart_trip.destination and cart_trip.destination.reason ~= nil
    if (near_stop or cart_trip.intermediate_arrival_seen or cart_trip.final_arrival_seen)
        and (not physically_sitting or player_battle_state() == true) then
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
        and (not physically_sitting or player_battle_state() == true) then
        release_pawns_at_intermediate_stop("near/at destination; player standing or in combat")
    end
    if destination.reason and not (destination.waiting and cart_trip.departure_pending
        and not cart_trip.stopover_wait_armed) then cart_trip.braked_for_destination = true end
    if arrived then cart_trip.final_arrival_seen = true end
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

    local ox_transform = nil
    if ox then
        pcall(function()
            if ox:get_Valid() then ox_transform = ox:get_Transform() end
        end)
    end

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
            if not position_only then table.remove(seat_bindings, i) end
        else
            local anchor_transform = seat_spec.useOxAnchor and ox_transform or seat_anchor_transform
            if anchor_transform then
                pcall(function()
                    local anchorPos = anchor_transform:get_Position()
                    local axisX = anchor_transform:get_AxisX()
                    local axisY = anchor_transform:get_AxisY()
                    local axisZ = anchor_transform:get_AxisZ()

                    local offsetX_vec = vec_scale(axisX, seat_spec.x)
                    local offsetZ_vec = vec_scale(axisZ, seat_spec.z)
                    local offsetY_vec = vec_scale(axisY, seat_spec.y)
                    local final_pos = vec_add(vec_add(vec_add(anchorPos, offsetX_vec), offsetZ_vec), offsetY_vec)

                    character:get_Transform():set_Position(final_pos)

                    local lookDirX = vec_scale(axisX, seat_spec.lookX)
                    local lookDirZ = vec_scale(axisZ, seat_spec.lookZ)
                    local look_target = vec_add(final_pos, vec_add(lookDirX, lookDirZ))
                    if seat_spec.lookX == 0 and seat_spec.lookZ == 0 then
                        look_target = vec_add(final_pos, axisX)
                    end
                    character:get_Transform():lookAt(look_target, axisY)
                end)
            end

            if not position_only then
                -- Keep the AI lock authoritative for the whole ride. Some
                -- pawn controllers may be rebuilt after the seat animation.
                if seat_spec.freezeFsm then set_fsm_enabled(character, false) end

                if seat_spec.randomIdle and binding.next_idle_time and runtime_clock >= binding.next_idle_time then
                    local random_anim = passenger_idle_nodes[math.random(1, #passenger_idle_nodes)]
                    start_seated_animation(character, seat_spec, random_anim)
                    binding.next_idle_time = runtime_clock + (math.random() * 35 + 10)
                end
            end
        end
    end
end


local journey_handoff = { suspended = false, restore_seats = false }
driving_bus.journey = {
    suspend = function()
        journey_handoff.restore_seats = seating_lock_active
        journey_handoff.suspended = true
        seating_lock_active = false
        detach_bound_characters()
        for key in pairs(cart_action_filters) do cart_action_filters[key] = nil end
        for key in pairs(frame_jobs) do frame_jobs[key] = nil end
        cart_protection_range_active = false
    end,
    resume = function()
        journey_handoff.suspended = false
        last_clock_sample = os.clock()
        cart_trip.rush_requested_at, cart_trip.rush_ack_until = nil, nil
        cart_trip.walk_since, cart_trip.walk_angle, cart_trip.walk_turn = nil, nil, 0
        if journey_handoff.restore_seats then
            player = character_manager["<ManualPlayer>k__BackingField"]
            bind_pawns_to_seats()
        end
        journey_handoff.restore_seats = false
    end,
}

local input_poll_error_reported = false
re.on_application_entry("UpdateHID", function()
    if external_driver_active() then return end
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

re.on_application_entry("LateUpdateBehavior", function()
    if external_driver_active() then return end
    if journey_handoff.suspended then driving_bus.journey.resume() end
    local ox = find_active_ox()
    observe_cart_pause(ox)
    player = character_manager["<ManualPlayer>k__BackingField"]
    if not player or not player:get_Valid() then return end
    input = player:get_Input()
    update_runtime_clock()

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
    if not finish_cart_pause(ox) then return end
    update_cart_normal_guard(ox)

    if #pending_ai_lock > 0 then
        local current_refreeze = pending_ai_lock
        pending_ai_lock = {}
        for _, char in ipairs(current_refreeze) do
            if is_character_valid(char) and not set_fsm_enabled(char, false) then
                table.insert(pending_ai_lock, char)
            end
        end
    end

    for k, fn in pairs(frame_jobs) do 
        local success, _ = pcall(fn)
        if not success then frame_jobs[k] = nil end
    end

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
    cart_protection_range_active = is_near -- 赋值给全局变量供Hook使用
    
    -- The per-frame trip check handles confirmed >20 distance and releases only
    -- followers, without requiring a previous near -> far transition.
    prior_cart_proximity = is_near

    local sitting = player_is_cart_passenger(ox)
    local physically_sitting = player_is_physically_seated(ox)
    
    if prior_player_seat_state and not physically_sitting then
        if seat_bindings and #seat_bindings > 0 then
            for i = #seat_bindings, 1, -1 do
                if seat_bindings[i].char == player then
                    set_fsm_enabled(player, true)
                    table.remove(seat_bindings, i)
                end
            end
            if #seat_bindings == 0 then 
                seating_lock_active = false 
            end
        end
    end
    prior_player_seat_state = physically_sitting
    prior_cart_seat_state = sitting
    
    update_cart_trip(ox, physically_sitting)

    -- Maintain seat transforms after gameplay state changes have settled.
    enforce_seat_transforms(ox, false)

    local modifier_held = modifier_is_down()

    local scene = nil
    if sitting then
        scene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene()")
    end

    if scene then
        local ui010201 = scene:call("findGameObject(System.String)", "ui010201")
        local ui010201Base = ui010201 and ui010201:call("getComponent(System.Type)", gui_base_type) or nil

        for _, feature in pairs(action_bindings) do
            if feature.isUI then
                if sitting and ui010201Base and ui010201Base:get_DrawSelf() then
                    local path = seated_hotbar_paths[feature.skillUiKey]
                    if path then
                        local button = gui_get_object:call(ui010201Base.Root, path)
                        render_seated_hotbar_slot(button, feature.name, skill_binding_is_down(feature))
                    end
                end
            end
        end
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
        if trigger_stand then release_passengers_from_modifier() end
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
                elseif feature.nodeName then request_cart_locomotion(ox, feature.nodeName, feature.isDash) end
            end
        end

        if sitting then
            local trigger_skill = false
            if is_key_valid(options[feature.padSkillKey]) then
                local s, v = pcall(input_bindings.was_triggered, options[feature.padSkillKey])
                trigger_skill = trigger_skill or (s and v)
            end
            if feature.name == "Oxcart Dash" and input then
                local s, v = pcall(function() return input:isButtonTrigger(MOUSE_DASH_FLAG) end)
                trigger_skill = trigger_skill or (s and v)
            elseif feature.name == "Oxcart Walk" and input then
                local s, v = pcall(function() return input:isButtonTrigger(MOUSE_WALK_FLAG) end)
                trigger_skill = trigger_skill or (s and v)
            elseif is_key_valid(options[feature.mouseSkillKey]) then
                local s, v = pcall(input_bindings.was_triggered, options[feature.mouseSkillKey])
                trigger_skill = trigger_skill or (s and v)
            end

            if trigger_skill then
                if feature.skillAction then feature.skillAction()
                elseif feature.nodeName then request_cart_locomotion(ox, feature.nodeName, feature.isDash) end
            end
        end
    end
end)

local function draw_seat_editor(label, seat_spec)
    if imgui.tree_node(label) then
        local c0, v0 = imgui.checkbox("Use Ox Anchor", seat_spec.useOxAnchor)
        if c0 then seat_spec.useOxAnchor = v0; persist_options() end
        
        imgui.same_line()
        local c_fsm, v_fsm = imgui.checkbox("Freeze AI", seat_spec.freezeFsm)
        if c_fsm then seat_spec.freezeFsm = v_fsm; persist_options() end
        
        imgui.same_line()
        local c_idle, v_idle = imgui.checkbox("Random Idle", seat_spec.randomIdle)
        if c_idle then seat_spec.randomIdle = v_idle; persist_options() end
        
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
        
        imgui.tree_pop()
    end
end

re.on_draw_ui(function()
    if imgui.tree_node("Oxcarts Journey Redux") then
        
        if imgui.tree_node("Keybind Settings") then
            imgui.text("Format: [Action] : [Gamepad] | [Keyboard] ")
            imgui.spacing()
            if imgui.button("Restore default keybinds") then restore_default_key_bindings() end
            imgui.spacing()

            local function draw_dual_bind(label, padKey, mouseKey)
                imgui.text(label .. ': ')
                imgui.same_line(150)
                local p_changed, p_value = input_bindings.imgui_rebind_button(padKey, options[padKey])
                if p_changed then options[padKey] = p_value; persist_options() end
                imgui.same_line(300)
                if mouseKey == "Key_MouseSkillDash" then
                    imgui.text("Mouse Left")
                elseif mouseKey == "Key_MouseSkillWalk" then
                    imgui.text("Mouse Right")
                else
                    local m_changed, m_value = input_bindings.imgui_rebind_button(mouseKey, options[mouseKey])
                    if m_changed then options[mouseKey] = m_value; persist_options() end
                end
            end

            if imgui.tree_node("Cross Hotbar Key -- (Show only when near oxcart.)") then
                draw_dual_bind("Modifier Key", "Key_PadModifyKey", "Key_MouseModifyKey")
                imgui.separator()
                draw_dual_bind("Oxcart Dash", "Key_PadModifyDash", "Key_MouseModifyDash")
                draw_dual_bind("Oxcart Walk", "Key_PadModifyWalk", "Key_MouseModifyWalk")
                draw_dual_bind("Pawns Sit/TP", "Key_PadModifyTeleport", "Key_MouseModifyTeleport")
                draw_dual_bind("Pawns Stand", "Key_PadModifyStand", "Key_MouseModifyStand")
                imgui.tree_pop()
            end
            
            if imgui.tree_node("Right HotBar Key -- (Show only when riding oxcart.)") then
                draw_dual_bind("Oxcart Dash", "Key_PadSkillDash", "Key_MouseSkillDash")
                draw_dual_bind("Oxcart Walk", "Key_PadSkillWalk", "Key_MouseSkillWalk")
                draw_dual_bind("Pawns Sit/TP", "Key_PadSkillTeleport", "Key_MouseSkillTeleport")
                draw_dual_bind("Pawns Stand", "Key_PadSkillStand", "Key_MouseSkillStand")
                imgui.tree_pop()
            end
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
            
            imgui.separator()
            
            local cat_list = {
                { id = "Normal", name = "Normal Oxcart" },
                { id = "Rainy", name = "Rainproof Oxcart" },
                { id = "Wealthy", name = "Luxury Oxcart" }
            }
            
            for _, cat_info in ipairs(cat_list) do
                local cat = cat_info.id
                if imgui.tree_node(cat_info.name .. " Presets") then
                    for i, preset in ipairs(options.Presets[cat]) do
                        imgui.push_id(cat .. "_preset_" .. i)
                        if imgui.tree_node("[" .. i .. "] " .. preset.name .. "###preset_node_" .. cat .. i) then
                            
                            local b_changed, b_val = imgui.checkbox("Enabled", preset.enabled)
                            if b_changed then preset.enabled = b_val; persist_options() end
                            
                            imgui.same_line()
                            if #options.Presets[cat] > 1 then
                                if not preset._confirm_delete then
                                    if imgui.button("Delete Preset###del_" .. cat .. i) then
                                        preset._confirm_delete = true
                                    end
                                else
                                    if imgui.button("Confirm Delete###conf_" .. cat .. i) then
                                        table.remove(options.Presets[cat], i)
                                        if preset_cursor[cat] > #options.Presets[cat] then preset_cursor[cat] = 1 end
                                        persist_options()
                                        imgui.tree_pop()
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
                            
                            local tp_changed, tp_val = imgui.checkbox("Adjust Player (animation not work)", preset.teleportPlayer)
                            if tp_changed then preset.teleportPlayer = tp_val; persist_options() end
                            
                            if preset.teleportPlayer then
                                draw_seat_editor("Player Parameters", preset.player)
                            end
                            
                            for p_idx = 1, 3 do
                                draw_seat_editor("Pawn " .. p_idx .. " Parameters", preset.pawns[p_idx])
                            end
                            imgui.tree_pop()
                        end
                        imgui.pop_id()
                    end
                    
                    if #options.Presets[cat] < 15 then
                        imgui.spacing()
                        if imgui.button("+ Add New Preset (Max 15)###add_preset_" .. cat) then
                            local src = options.Presets[cat][1]
                            local new_preset = { 
                                name = "Preset " .. (#options.Presets[cat] + 1), 
                                enabled = true, 
                                teleportPlayer = false,
                                player = { x=src.player.x, z=src.player.z, y=src.player.y, lookX=src.player.lookX, lookZ=src.player.lookZ, anim=src.player.anim, useOxAnchor=src.player.useOxAnchor, freezeFsm=src.player.freezeFsm, randomIdle=src.player.randomIdle, useDirectMotion=src.player.useDirectMotion, bankID=src.player.bankID, motionID=src.player.motionID },
                                pawns = {} 
                            }
                            for idx = 1, 3 do
                                new_preset.pawns[idx] = { x=src.pawns[idx].x, z=src.pawns[idx].z, y=src.pawns[idx].y, lookX=src.pawns[idx].lookX, lookZ=src.pawns[idx].lookZ, anim=src.pawns[idx].anim, useOxAnchor=src.pawns[idx].useOxAnchor, freezeFsm=src.pawns[idx].freezeFsm, randomIdle=src.pawns[idx].randomIdle, useDirectMotion=src.pawns[idx].useDirectMotion, bankID=src.pawns[idx].bankID, motionID=src.pawns[idx].motionID }
                            end
                            table.insert(options.Presets[cat], new_preset)
                            persist_options()
                        end
                    end
                    imgui.tree_pop()
                end
            end
            imgui.tree_pop()
        end
        if imgui.tree_node("Other Settings") then
            local changed = false
            imgui.spacing()
            imgui.text("Damage Multipliers")

            local c_ox, v_ox = imgui.drag_float("Ox Damage Received", options.OX_DAMAGE_RECEIVED, 0.01, 0.0, 10.0)
            if c_ox then options.OX_DAMAGE_RECEIVED = v_ox; changed = true end

            local c_cart, v_cart = imgui.drag_float("Cart Damage Received", options.GIMMICK_DAMAGE_RECEIVED, 0.01, 0.0, 10.0)
            if c_cart then options.GIMMICK_DAMAGE_RECEIVED = v_cart; changed = true end

            local c_driver, v_driver = imgui.drag_float("Driver Damage Received", options.DRIVER_DAMAGE_RECEIVED, 0.01, 0.0, 10.0)
            if c_driver then options.DRIVER_DAMAGE_RECEIVED = v_driver; changed = true end

            local c_grd_recv, v_grd_recv = imgui.drag_float("Guard Damage Received", options.GUARD_DAMAGE_RECEIVED, 0.01, 0.0, 10.0)
            if c_grd_recv then options.GUARD_DAMAGE_RECEIVED = v_grd_recv; changed = true end

            local c_grd_dealt, v_grd_dealt = imgui.drag_float("Guard Damage Dealt", options.GUARD_DAMAGE_DEALT, 0.01, 0.0, 10.0)
            if c_grd_dealt then options.GUARD_DAMAGE_DEALT = v_grd_dealt; changed = true end

            if changed then
                persist_options()
                rebuild_damage_rules()
            end

            imgui.tree_pop()
        end

        imgui.tree_pop()
    end
end)

sdk.hook(
    sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
    function(args)
        local this = sdk.to_managed_object(args[2])
        if external_driver_active() then return end
        local owner = this:get_GameObject()
        if not owner:get_Valid() then return end      
        
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
                            set_fsm_enabled(char, true)
                            table.remove(seat_bindings, i)
                            if #seat_bindings == 0 then seating_lock_active = false end
                            break
                        end
                    end
                    break
                end
            end
        end

        local data = {}
        data.character = char
        data.name = data.character:get_CharaIDString()
        data.layer = sdk.to_int64(args[5]) & 0xffffffff
        data.priority = sdk.to_int64(args[3]) & 0xffffffff
        data.node = nodeName
        
        local skip = false
        for _,fn in pairs(cart_action_filters) do
            local currentSkip = fn(data,args)
            skip = skip or currentSkip
        end
        if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
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

-- Damage interception for bound passengers and the nearby cart driver.
sdk.hook(
    sdk.find_type_definition("app.HitController"):get_method("damageProc(app.HitController.DamageInfo)"),
    function(args)
        -- Driver protection depends on proximity, not passenger bindings.
        if external_driver_active() then return end
        if not cart_protection_range_active then return end
        
        local damage_info = sdk.to_managed_object(args[3])
        if not damage_info then return end
        
        local receiver = damage_info["<DamageGameObject>k__BackingField"]
        if not receiver then return end

        -- Compare stable GameObject addresses instead of managed wrappers.
        local receiver_addr = receiver:get_address()

        -- A nearby driver bypasses the damage transaction entirely.
        local receiver_name = nil
        pcall(function()
            receiver_name = string.sub(receiver:get_Name() or "", 1, 8)
        end)
        if receiver_name and driver_character_ids[receiver_name] then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        -- Passenger protection applies only while seat locking is active.
        if not seating_lock_active then return end

        for _, binding in ipairs(seat_bindings) do
            local pass_char = binding.char
            if pass_char then
                local s_go, pass_go = pcall(function() return pass_char:get_GameObject() end)
                -- Match the hit receiver against the bound character object.
                if s_go and pass_go and pass_go:get_address() == receiver_addr then
                    -- Bound passengers bypass the damage transaction entirely.
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end
        end
    end
)

sdk.hook(
    sdk.find_type_definition("app.HitController"):get_method("calcDamageValue(app.HitController.DamageInfo)"),
    function(args)
        local damage_info = sdk.to_managed_object(args[3])
        thread.get_hook_storage().damage_info = damage_info
    end,
    function(retval)
        if external_driver_active() then return retval end
        if not cart_protection_range_active then return end -- 仅在附近生效
        local damage_info = thread.get_hook_storage().damage_info
        if not damage_info then return end
        local receiver = damage_info["<DamageGameObject>k__BackingField"]
        local receiver_id = receiver and string.sub(receiver:get_Name(),1,8)
        local attacker = damage_info["<AttackOwnerObject>k__BackingField"]
        local attacker_id = attacker and string.sub(attacker:get_Name(),1,8)
        local ox = find_active_ox()

        local receiver_character = nil
        local attacker_character = nil
        if receiver then
            pcall(function() receiver_character = receiver:call("getComponent(System.Type)", sdk.typeof("app.Character")) end)
        end
        if attacker then
            pcall(function() attacker_character = attacker:call("getComponent(System.Type)", sdk.typeof("app.Character")) end)
        end
        
        if receiver_id and entity_damage_rules[receiver_id] and entity_damage_rules[receiver_id].received then
            if receiver_id ~= "ch299003" or receiver_character == ox then
                damage_info.Damage = entity_damage_rules[receiver_id].received * damage_info.Damage
            end
        end
        if attacker_id and entity_damage_rules[attacker_id] and entity_damage_rules[attacker_id].dealt then
            if attacker_id ~= "ch299003" or attacker_character == ox then
                damage_info.Damage = entity_damage_rules[attacker_id].dealt * damage_info.Damage
            end
        end
        if options.DISABLE_PAWN_DAMAGE and receiver_id and attacker_id then
            local attackerType = string.sub(attacker_id,1,3)
            if protected_cart_part_ids[receiver_id] and (attackerType == "ch1" or attackerType == "ch3") then
                damage_info.Damage = 0.0
            end
        end
    end
)

sdk.hook(
    sdk.find_type_definition("app.HitController"):get_method("updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)"),
    function(args)
        if external_driver_active() then return end
        if not cart_protection_range_active then return end -- 仅在附近生效
        local damage_info = sdk.to_managed_object(args[3])
        local receiver = damage_info["<DamageGameObject>k__BackingField"]
        local receiver_id = receiver and string.sub(receiver:get_Name(),1,8)
        if options.PREVENT_INSTABREAKS and protected_cart_part_ids[receiver_id] and damage_info.Damage > 1999.0 then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
)

local blocked_status_ids = {
    [1] = "Poison", [2] = "Sleep", [3] = "Faint", [4] = "Wet", [5] = "FireSpread", [6] = "OilSpread",
    [7] = "VirulentPoison", [8] = "Frostbite", [9] = "Freeze", [10] = "Oil", [11] = "Silence", [12] = "Stone",
    [13] = "Electric", [14] = "WetElectric",
}

sdk.hook(
    sdk.find_type_definition("app.StatusConditionCtrl"):get_method("reqStatusConditionApplyCore(app.StatusConditionDef.StatusConditionEnum, app.HitController.DamageInfo, app.StatusConditionDef.RequestInfo, System.Boolean)"),
    function(args)
        if not cart_protection_range_active then return end -- 仅在附近生效
        local status = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local statusConditionCtrl = sdk.to_managed_object(args[2])
        local owner = statusConditionCtrl.OwnerCharacter
        local ownerName = string.sub(owner and owner:get_CharaIDString() or "",1,8)
        local ox = find_active_ox()
        if options.STATUS_IMMUNITY and blocked_status_ids[status] and (guard_character_ids[ownerName] or driver_character_ids[ownerName] or (ownerName == "ch299003" and owner == ox)) then
            return sdk.PreHookResult.SKIP_ORIGINAL 
        end
    end
)
