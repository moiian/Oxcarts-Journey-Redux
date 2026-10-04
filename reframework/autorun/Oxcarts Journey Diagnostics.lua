-- Optional diagnostics for Oxcarts Journey Redux. Recording is OFF by default.
-- Sampling is read-only. Verified recovery methods run ONLY on explicit button clicks.
local recording, session, output_path = false, nil, nil
local next_sample, next_save, heartbeat_at, last_signature = 0, 0, 0, nil
local message, sequence = "Idle", 0
local LIMIT = 4000
local targets, action_windows = {}, {}
local next_action_flush = 0
local SAMPLE_SECONDS = 0.1
local station_budget = 0
local sampled_status, last_ticket_signature, last_signals_signature = nil, nil, nil
local recording_frame = 0
local latest_data, recovery_message = nil, "No recovery test requested"
local stopover_hook = { installed = false, error = nil }
local pending_stopovers = {}
local waitwalk, dispatching_waitwalk = nil, false
local pending_turns, turn_followups, last_turn_request = {}, {}, nil
local latest_sample_clock = nil
local NAV_LABELS = { "ox_navigation_ai", "ox_navigation_controller", "ox_destination", "ox_navigation",
    "ox_navigation_surface", "ox_navigation_waypoint", "ox_navigation_data", "ox_navigation_temp" }
local BASE_FIELDS = { "IsStopover", "IsWaitStopoverTimer", "StopoverIndex", "StopoverTime", "StopoverTimer",
    "_isPayMoneyStopover", "_isPayMoney", "isRouteArrived", "StopIndex", "Routine", "RoutineBack" }

local function clock() return os.clock() end
local function bridge() return OxcartsJourneyDebug end
local function signature(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. signature(value[key]) end
    return "{" .. table.concat(parts, "|") .. "}"
end

local function new_session()
    sequence = sequence + 1
    output_path = "OxcartsJourney-diagnostic-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. sequence .. ".json"
    session = { version = 7, started = os.date("%Y-%m-%d %H:%M:%S"),
        sample_seconds = SAMPLE_SECONDS, ticket_sampling = "every REFramework frame using latest sampled status",
        heartbeat_seconds = 2, max_records = LIMIT, records = {}, metadata = {} }
    last_signature, heartbeat_at = nil, 0
    sampled_status, last_ticket_signature, last_signals_signature = nil, nil, nil
    recording_frame = 0
    latest_data, pending_stopovers, waitwalk = nil, {}, nil
    pending_turns, turn_followups, last_turn_request = {}, {}, nil
    latest_sample_clock = nil
    targets, action_windows, next_action_flush = {}, {}, clock() + 2
end

local function save()
    if not session then return end
    local ok, result = pcall(function() return json.dump_file(output_path, session, 2) end)
    if not ok or result == false then message = "Save failed: " .. tostring(result)
    else message = "Saved: reframework/data/" .. output_path end
end

local function append(kind, data)
    if not session then return end
    if #session.records >= LIMIT then
        recording = false
        session.limit_reached = true
        save()
        return
    end
    session.records[#session.records + 1] = { time = os.date("%H:%M:%S"),
        elapsed_clock = clock() - session.clock_start, frame = recording_frame, kind = kind, data = data }
end

local function type_name(object)
    return object:get_type_definition():get_full_name()
end

-- Metadata for station elements is captured only once per runtime type.
local function station_metadata(definition, label)
    local name = definition:get_full_name()
    if session.metadata[name] then return end
    local entry = { label = label, methods = {}, fields = {} }
    session.metadata[name] = entry
    for _, field in ipairs(definition:get_fields()) do
        pcall(function()
            entry.fields[#entry.fields + 1] = { name = field:get_name(),
                type = field:get_type():get_full_name(), static = field:is_static() }
        end)
    end
    for _, method in ipairs(definition:get_methods()) do
        pcall(function()
            local parameters = {}
            for _, parameter in ipairs(method:get_param_types()) do parameters[#parameters + 1] = parameter:get_full_name() end
            entry.methods[#entry.methods + 1] = { name = method:get_name(), parameters = parameters,
                returns = method:get_return_type():get_full_name(), static = method:is_static() }
        end)
    end
end

local function read_base_status(status, transitions_only)
    local values = {}
    if not status then return { available = false } end
    local ok, definition = pcall(function() return sdk.find_type_definition("app.OxcartStatusSaveData") end)
    if not ok or not definition then return { error = "OxcartStatusSaveData type unavailable" } end
    if session then station_metadata(definition, "status_base") end
    for _, name in ipairs(BASE_FIELDS) do
        if not transitions_only or (name ~= "StopoverTime" and name ~= "StopoverTimer") then
        local success, value = pcall(function()
            local field = definition:get_field(name)
            assert(field, "field missing")
            return field:get_data(status)
        end)
        if success and (type(value) == "boolean" or type(value) == "number" or type(value) == "string") then
            values[name] = value
        else values[name] = { error = success and "non-scalar value" or tostring(value) } end
        end
    end
    return values
end

local function install_stopover_hook()
    if stopover_hook.installed or stopover_hook.error then return end
    local ok, err = pcall(function()
        local definition = sdk.find_type_definition("app.OxcartStatus")
        assert(definition, "OxcartStatus unavailable")
        local method = definition:get_method("arrivedStopover()")
        assert(method and method:get_num_params() == 0, "arrivedStopover() unavailable")
        sdk.hook(method, function(args)
            -- No snapshots or file I/O from inside the game method.
            pcall(function()
                if not recording or not sampled_status or #pending_stopovers >= 64 then return end
                local object = sdk.to_managed_object(args[2])
                if object and object:get_address() == sampled_status:get_address() then
                    pending_stopovers[#pending_stopovers + 1] = { status_address = tostring(object:get_address()),
                        invoked_elapsed = clock() - session.clock_start, invoked_frame = recording_frame }
                end
            end)
            return sdk.PreHookResult.CALL_ORIGINAL
        end, function(retval) return retval end)
        stopover_hook.installed = true
    end)
    if not ok then stopover_hook.error = tostring(err) end
end

local function stopover_target(objects)
    local base = read_base_status(objects.status, true)
    local index = base.StopoverIndex
    if base.IsStopover ~= true or type(index) ~= "number" or index < 0 then
        return { available = false, reason = "No intermediate ticket target", index = index }
    end
    local result = { available = false, index = index, source = "StopoverIndex + getStopIndexPosition(Int32)" }
    local ok, err = pcall(function()
        local position = objects.status:call("getStopIndexPosition(System.Int32)", index)
        assert(position, "Target position unavailable")
        local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
        assert(x and y and z, "Target coordinates unreadable")
        result.position = { x = x, y = y, z = z }
        result.available = true
        if objects.ox then
            local ox_position = objects.ox:get_Transform():get_UniversalPosition()
            local dx, dy, dz = tonumber(ox_position.x) - x, tonumber(ox_position.y) - y, tonumber(ox_position.z) - z
            result.distance_3d = math.sqrt(dx * dx + dy * dy + dz * dz)
            result.distance_horizontal = math.sqrt(dx * dx + dz * dz)
        end
    end)
    if not ok then result.error = tostring(err) end
    return result
end

local function ticket_sample()
    if not sampled_status then return end
    local values = {}
    for _, name in ipairs({ "get_isPayMoney", "get_isPayMoneyTalk", "isPlayerRideNoPay" }) do
        local ok, value = pcall(function() return sampled_status:call(name .. "()") end)
        values[name] = ok and tostring(value) or "read failed"
    end
    pcall(function() values.status_address = tostring(sampled_status:get_address()) end)
    values.base_status = read_base_status(sampled_status, true)
    local current = signature(values)
    if current ~= last_ticket_signature then
        append("ticket_transition", { previous_signature = last_ticket_signature, current = values })
        last_ticket_signature = current
    end
end

local function flush_actions()
    if not next(action_windows) then return end
    local requests = {}
    for _, value in pairs(action_windows) do requests[#requests + 1] = value end
    table.sort(requests, function(a, b) return a.first_elapsed < b.first_elapsed end)
    action_windows = {}
    append("action_requests_window", requests)
end

local function export_metadata()
    local api = bridge()
    if not api then message = "Main mod bridge unavailable"; return end
    local objects = api.objects()
    for label, object in pairs(objects) do
        local ok, definition = pcall(function() return object:get_type_definition() end)
        if ok and definition then
            local name = definition:get_full_name()
            if not session.metadata[name] then
                local entry = { label = label, methods = {}, fields = {} }
                session.metadata[name] = entry
                for _, method in ipairs(definition:get_methods()) do
                    local success, info = pcall(function()
                        local parameters = {}
                        for _, parameter in ipairs(method:get_param_types()) do
                            parameters[#parameters + 1] = parameter:get_full_name()
                        end
                        return { name = method:get_name(), parameters = parameters, parameter_names = method:get_param_names(),
                            returns = method:get_return_type():get_full_name(), static = method:is_static() }
                    end)
                    if success then entry.methods[#entry.methods + 1] = info end
                end
                for _, field in ipairs(definition:get_fields()) do
                    local success, info = pcall(function()
                        return { name = field:get_name(), type = field:get_type():get_full_name(), static = field:is_static() }
                    end)
                    if success then entry.fields[#entry.fields + 1] = info end
                end
            end
            -- Inspect related state objects, without traversing whole object graphs.
            if label == "status" or label == "cart_controller" or label == "ox_controller" then
                local states = {}
                for _, field in ipairs(definition:get_fields()) do
                    local success, key, value = pcall(function()
                        if field:is_static() then return nil end
                        local key = field:get_name()
                        if not key:lower():find("save") and not key:lower():find("status") then return nil end
                        local value = field:get_data(object)
                        if not value then return nil end
                        return key, type_name(value)
                    end)
                    if success and key then states[key] = value end
                end
                session.metadata[name].related_state_types = states
            end
        end
    end
    session.enums = session.enums or {}
    for _, suffix in ipairs({ "ServiceStatusID", "ProgressStatusID", "DestinationID", "RoutineID" }) do
        local name = "app.OxcartStatusSaveData." .. suffix
        if not session.enums[name] then
            pcall(function()
                local definition = sdk.find_type_definition(name)
                if not definition then return end
                local values = {}
                for _, field in ipairs(definition:get_fields()) do
                    if field:is_static() and field:is_literal() then
                        local value = field:get_data(nil)
                        if type(value) == "number" then values[field:get_name()] = value end
                    end
                end
                session.enums[name] = values
            end)
        end
    end
    local action_enum = "app.OxcartAI.DriverAction"
    if not session.enums[action_enum] then
        pcall(function()
            local definition = sdk.find_type_definition(action_enum)
            if not definition then return end
            local values = {}
            for _, field in ipairs(definition:get_fields()) do
                if field:is_static() and field:is_literal() then values[field:get_name()] = field:get_data(nil) end
            end
            session.enums[action_enum] = values
        end)
    end
    for _, enum_name in ipairs({ "app.NavigationAI.NavigationAIState", "app.NavigationAI.TempFlag", "app.NavigationType" }) do
        if not session.enums[enum_name] then
            pcall(function()
                local definition = sdk.find_type_definition(enum_name)
                if not definition then return end
                local values = {}
                for _, field in ipairs(definition:get_fields()) do
                    if field:is_static() and field:is_literal() then
                        local value = field:get_data(nil)
                        if type(value) == "number" then values[field:get_name()] = value end
                    end
                end
                session.enums[enum_name] = values
            end)
        end
    end
end

local function sample(kind)
    local api = bridge()
    if not api then message = "Main mod bridge unavailable"; return end
    local ok, data = pcall(api.snapshot)
    if not ok then append("sample_error", tostring(data)); return end
    local objects = api.objects()
    sampled_status = objects.status
    ticket_sample()
    targets = {}
    for _, label in ipairs({ "ox", "driver" }) do
        if objects[label] then pcall(function() targets[objects[label]:get_address()] = label end) end
    end
    data.state_fields = {}
    station_budget = 128
    local function read_station(value, depth, label, declared_type)
        if value == nil then return { available = false } end
        if type(value) == "boolean" or type(value) == "number" or type(value) == "string" then return value end
        if depth > 4 or station_budget <= 0 then return { truncated = true } end
        station_budget = station_budget - 1
        -- vec3 values may be native Lua userdata, without a managed type definition.
        if declared_type == "via.Position" or declared_type == "via.vec3" then
            local result = { type = declared_type }
            local success, position = pcall(function() return { x = tonumber(value.x), y = tonumber(value.y), z = tonumber(value.z) } end)
            if success then result.position = position else result.error = "position unreadable" end
            return result
        end
        local ok, definition = pcall(function() return value:get_type_definition() end)
        if not ok or not definition then return { error = "type unavailable" } end
        local name = definition:get_full_name()
        local result = { type = name }
        if name == "via.Position" or name == "via.vec3" then
            local success, position = pcall(function() return { x = tonumber(value.x), y = tonumber(value.y), z = tonumber(value.z) } end)
            if success then result.position = position else result.error = "position unreadable" end
            return result
        end
        if name:sub(-2) == "[]" then
            local success, elements = pcall(function() return value:get_elements() end)
            if not success or type(elements) ~= "table" then
                -- Some builds return a std::vector userdata, not a Lua table.
                -- Do not put its changing wrapper address into every state signature.
                result.get_elements_error = success and ("Non-table return: " .. type(elements)) or tostring(elements)
                local size_ok, count = pcall(function() return value:get_size() end)
                if not size_ok or type(count) ~= "number" then
                    result.error = "array unreadable"; result.get_size_error = tostring(count); return result
                end
                result.count, result.items, result.reader = count, {}, "get_size/get_element"
                for i = 0, math.min(count, 16) - 1 do
                    local item_ok, item = pcall(function() return value:get_element(i) end)
                    result.items[i + 1] = item_ok and read_station(item, depth + 1, label .. "[" .. i .. "]")
                        or { error = tostring(item), index = i }
                end
                result.truncated = count > 16
                return result
            end
            result.count, result.items = #elements, {}
            result.reader = "get_elements"
            for i = 1, math.min(#elements, 16) do
                result.items[i] = read_station(elements[i], depth + 1, label .. "[" .. (i - 1) .. "]")
            end
            result.truncated = #elements > 16
            return result
        end
        station_metadata(definition, label)
        result.fields = {}
        for _, field in ipairs(definition:get_fields()) do
            if not field:is_static() then
                local key = field:get_name()
                local success, field_value = pcall(function() return field:get_data(value) end)
                if success then result.fields[key] = read_station(field_value, depth + 1, label .. "." .. key, field:get_type():get_full_name())
                else result.fields[key] = { error = "field unreadable" } end
            end
        end
        return result
    end
    -- A bounded, read-only traversal: outer stop args -> array -> stop -> fields.
    -- Report absent/unreadable data explicitly rather than treating it as no stop.
    local station_ok, station_data = pcall(read_station, objects.stopover, 0, "stopover")
    data.station_details = station_ok and station_data or { error = tostring(station_data) }
    data.state_fields.status_base = read_base_status(objects.status)
    data.stopover_target = stopover_target(objects)
    data.stopover_hook = { installed = stopover_hook.installed, error = stopover_hook.error }
    local function read_fields(object, label, depth)
        if not object then return end
        local ok, definition = pcall(function() return object:get_type_definition() end)
        if not ok then return end
        local fields = {}
        data.state_fields[label] = fields
        local definitions = { definition }
        local navigation_label = label:find("navigation", 1, true) or label:find("destination", 1, true)
        if navigation_label then
            for _ = 1, 4 do
                local success, parent = pcall(function() return definitions[#definitions]:get_parent_type() end)
                if not success or not parent then break end
                if parent:get_full_name() == "System.Object" or parent:get_full_name() == "via.Behavior" then break end
                definitions[#definitions + 1] = parent
            end
            for _, item in ipairs(definitions) do station_metadata(item, label) end
        end
        for _, item in ipairs(definitions) do
        for _, field in ipairs(item:get_fields()) do
            pcall(function()
                if field:is_static() then return end
                local name, lower = field:get_name(), field:get_name():lower()
                local relevant = false
                for _, word in ipairs({ "battle", "assault", "stop", "arriv", "route", "dest", "service", "progress", "move", "run", "rush", "dash", "speed", "halt", "pay", "path", "navi", "goal", "target", "finish", "request", "active", "state", "action", "interact", "forced" }) do
                    if lower:find(word, 1, true) then relevant = true; break end
                end
                if navigation_label then
                    for _, word in ipairs({ "dir", "angle", "rot", "fail", "enable", "disable", "temp", "value", "flag", "bit", "current", "next" }) do
                        if lower:find(word, 1, true) then relevant = true; break end
                    end
                end
                local field_type = field:get_type():get_name()
                if relevant then
                    local value = field:get_data(object)
                    if type(value) == "boolean" or type(value) == "number" or type(value) == "string" then fields[name] = value end
                    if value and (field_type == "Position" or field_type == "vec3") then
                        fields[name] = string.format("(%.2f, %.2f, %.2f)", tonumber(value.x), tonumber(value.y), tonumber(value.z))
                    end
                    if value and (lower:find("path", 1, true) or lower:find("dest", 1, true)) then
                        pcall(function() fields[name .. ".Count"] = value:call("get_Count") end)
                    end
                end
                if depth == 0 and (lower:find("save", 1, true) or lower:find("status", 1, true) or lower:find("context", 1, true)) then
                    read_fields(field:get_data(object), label .. "." .. name, 1)
                end
            end)
        end
        end
    end
    for _, label in ipairs({ "status", "cart_controller", "ox_controller", "ox_ch2", "oxcart_ai", "route", "stopover",
        "driver_navigation_ai", "driver_navigation_controller", "driver_destination", "driver_human" }) do
        read_fields(objects[label], label, 0)
    end
    data.navigation_objects = {}
    for _, label in ipairs(NAV_LABELS) do
        data.navigation_objects[label] = objects[label] ~= nil
        read_fields(objects[label], label, 0)
    end
    local signals = { paused = data.paused, battle = {}, ticket = data.ticket, mod_dash_requested = data.mod_dash_requested }
    for name, state in pairs(data.battle or {}) do signals.battle[name] = { force_false = state.force_false } end
    local signals_signature = signature(signals)
    if signals_signature ~= last_signals_signature then
        append("control_transition", { previous_signature = last_signals_signature, current = signals })
        last_signals_signature = signals_signature
    end
    local comparable = {}
    -- Continuous timer/speed fields belong in heartbeats, not the change trigger.
    for key, value in pairs(data) do
        if key ~= "positions" and key ~= "state_fields" and key ~= "stopover_target" then comparable[key] = value end
    end
    -- Target changes trigger snapshots; continuously changing distance does not.
    comparable.stopover_target = { index = data.stopover_target.index, position = data.stopover_target.position,
        available = data.stopover_target.available, error = data.stopover_target.error }
    local continuous_states = { get_RunSeconds = true, get_RunSecondsBan = true }
    comparable.states = {}
    for name, value in pairs(data.states or {}) do if not continuous_states[name] then comparable.states[name] = value end end
    comparable.state_fields = {}
    for label, fields in pairs(data.state_fields) do
        local selected = {}
        for name, value in pairs(fields) do
            local lower = name:lower()
            if type(value) == "boolean" or (type(value) == "number" and
                (lower:find("state") or lower:find("index") or lower:find("status") or lower:find("count")
                    or lower:find("flag") or lower:find("value") or lower:find("bit"))) then
                selected[name] = value
            end
        end
        comparable.state_fields[label] = selected
    end
    local current = signature(comparable)
    latest_data = data
    latest_sample_clock = clock()
    if kind or current ~= last_signature or clock() - heartbeat_at >= 2 then
        append(kind or (current ~= last_signature and "state_change" or "heartbeat"), data)
        last_signature, heartbeat_at = current, clock()
    end
end

local function snapshot()
    if not session or not recording then new_session(); session.clock_start = clock() end
    flush_actions()
    export_metadata()
    sample("manual_snapshot")
    save()
end

local function mark(label)
    if not session or not recording then new_session(); session.clock_start = clock() end
    flush_actions()
    export_metadata()
    sample("marker: " .. label)
    save()
end

local function finish_waitwalk(reason)
    if not waitwalk then return end
    append("wait_only_finished", { reason = reason, stage = waitwalk.stage, active_seconds = waitwalk.elapsed })
    waitwalk = nil
    recovery_message = reason
    save()
end

local function start_waitwalk()
    if not recording then recovery_message = "Start recording before a recovery test"; return end
    if waitwalk then recovery_message = "Wait-only test already running"; return end
    local ok, err = pcall(function()
        local api = bridge()
        assert(api and api.request_ox_action, "Reload main mod: action bridge unavailable")
        local objects = api.objects()
        assert(objects.ox and objects.status, "No active ox/cart status")
        sample("before_wait_only")
        assert(latest_data and latest_data.states.get_isPayMoney == "true", "Buy a ticket first; unpaid stop is not a recovery test")
        waitwalk = { ox_address = objects.ox:get_address(), status_address = objects.status:get_address(),
            stage = "request_wait", elapsed = 0, last_clock = clock(), next_tick = 0 }
        append("wait_only_started", { ox_address = tostring(waitwalk.ox_address), status_address = tostring(waitwalk.status_address) })
        recovery_message = "Queued ONE Wait; observe game actions for 15 seconds; Walk is NOT forced"
        save()
    end)
    if not ok then recovery_message = "Test not started: " .. tostring(err) end
end

local function tick_waitwalk()
    if not waitwalk then return end
    if waitwalk.cancelled then finish_waitwalk("Cancelled by another debug action"); return end
    local now = clock()
    if now < waitwalk.next_tick then return end
    waitwalk.next_tick = now + 0.05
    local ok, err = pcall(function()
        local api = bridge()
        local objects = api.objects()
        assert(objects.ox and objects.status and objects.ox:get_address() == waitwalk.ox_address
            and objects.status:get_address() == waitwalk.status_address, "Active ox/cart changed")
        local state = api.snapshot()
        local dt = math.max(0, now - waitwalk.last_clock)
        waitwalk.last_clock = now
        if state.paused then return end -- Pause both action dispatch and the timeout.
        assert(state.states.get_isPayMoney == "true", "Paid passenger state lost")
        waitwalk.elapsed = waitwalk.elapsed + dt
        if waitwalk.stage == "request_wait" then
            dispatching_waitwalk = true
            local success, accepted, result = pcall(api.request_ox_action, "Wait", waitwalk.ox_address)
            dispatching_waitwalk = false
            assert(success and accepted, tostring(result or accepted))
            waitwalk.stage, waitwalk.requested_at = "await_wait", waitwalk.elapsed
            append("wait_only_request", { action = "Wait", result = result })
        elseif waitwalk.stage == "await_wait" then
            if state.ox_action == "Wait" then
                if not waitwalk.observed_at then
                    waitwalk.observed_at = waitwalk.elapsed
                    append("wait_only_wait_observed", { action = state.ox_action })
                    sample("wait_only_wait_confirmed")
                end
                waitwalk.stage = "observe_game"
            end
            if waitwalk.stage == "await_wait" and waitwalk.elapsed - waitwalk.requested_at >= 3 then
                finish_waitwalk("Wait not confirmed within 3 active seconds; no further actions sent")
            end
        elseif waitwalk.stage == "observe_game" then
            if state.ox_action ~= waitwalk.last_action then
                waitwalk.last_action = state.ox_action
                append("wait_only_game_action", { action = state.ox_action, seconds_after_request = waitwalk.elapsed - waitwalk.requested_at })
                sample("wait_only_game_action_snapshot")
            end
            if waitwalk.elapsed - waitwalk.requested_at >= 15 then
                sample("wait_only_observation_complete")
                finish_waitwalk("15-second observation complete; no forced Walk/Run sent; verify road navigation")
            end
        end
    end)
    if not ok then dispatching_waitwalk = false; finish_waitwalk("Test aborted: " .. tostring(err)) end
end

local function recovery_test(method, argument)
    if not recording then recovery_message = "Start recording before a recovery test"; return end
    finish_waitwalk("Cancelled by another recovery test")
    local api = bridge()
    if not api then recovery_message = "Main mod bridge unavailable"; return end
    local ok, err = pcall(function()
        local status = api.objects().status
        assert(status, "No active cart status")
        sample("before_recovery: " .. method)
        append("recovery_request", { method = method, argument = argument, paused = latest_data and latest_data.paused })
        local success, result = pcall(function()
            if argument == nil then return status:call(method) end
            return status:call(method, argument)
        end)
        recovery_message = success and ("Called " .. method .. "; close menus and observe") or ("Failed: " .. tostring(result))
        append("recovery_result", { method = method, success = success, result = tostring(result) })
        sample("after_recovery: " .. method)
        save()
    end)
    if not ok then recovery_message = "Test failed: " .. tostring(err); append("recovery_error", recovery_message); save() end
end

local function inspect_object(label)
    local ok, err = pcall(function()
        local api = bridge()
        assert(api, "Main mod bridge unavailable")
        local object = api.objects()[label]
        assert(object, "Object unavailable: " .. label)
        assert(object_explorer, "ObjectExplorer unavailable")
        object_explorer:handle_address(object:get_address())
    end)
    if not ok then recovery_message = "Inspect failed: " .. tostring(err) end
end

local function capture_turns()
    local now = clock()
    local queued = pending_turns
    pending_turns = {}
    for _, event in ipairs(queued) do
        append("turn_target_requested", event)
        if not event.blocked_by_mod then
            turn_followups[#turn_followups + 1] = { due = now + 0.2, address = event.address, delay = 0.2 }
            turn_followups[#turn_followups + 1] = { due = now + 1.0, address = event.address, delay = 1.0 }
        end
    end
    for i = #turn_followups, 1, -1 do
        local event = turn_followups[i]
        if now >= event.due then
            table.remove(turn_followups, i)
            if targets[event.address] == "ox" then
                local ok, err = pcall(sample, "turn_target_after_" .. event.delay .. "s")
                if not ok then append("sample_error", tostring(err)) end
            end
        end
    end
end

OxcartsJourneyDiagnostics = {
    event = function(kind, data)
        if waitwalk and kind == "debug_action" and not dispatching_waitwalk then waitwalk.cancelled = true end
        if recording then append(kind, data) end
    end,
    action_requested = function(address, name, priority, layer, skipped)
        if not recording or not targets[address] then return end
        if targets[address] == "ox" and name == "TurnTarget" then
            local requested_at = clock()
            -- Capture on the next frame, not from inside the native action hook.
            if (not last_turn_request or requested_at - last_turn_request >= 0.5) and #pending_turns < 16 and #turn_followups < 32 then
                last_turn_request = requested_at
                pending_turns[#pending_turns + 1] = { address = address, priority = priority, layer = layer,
                    blocked_by_mod = not not skipped, requested_elapsed = requested_at - session.clock_start,
                    previous_sample_age_ms = latest_sample_clock and (requested_at - latest_sample_clock) * 1000 or nil,
                    previous_snapshot = latest_data }
            end
        end
        local key = targets[address] .. ":" .. name .. ":" .. tostring(priority) .. ":" .. tostring(layer) .. ":" .. tostring(not not skipped)
        local now = clock() - session.clock_start
        local entry = action_windows[key]
        if entry then entry.count = entry.count + 1; entry.last_elapsed = now
        else action_windows[key] = { character = targets[address], action = name, priority = priority,
            layer = layer, blocked_by_mod = not not skipped, count = 1, first_elapsed = now, last_elapsed = now } end
    end,
    draw_ui = function()
        if not imgui.tree_node("Diagnostics / Export") then return end
        imgui.text("Diagnostics v7: ox navigation + TurnTarget transition snapshots")
        imgui.text("arrivedStopover hook: " .. (stopover_hook.installed and "installed" or (stopover_hook.error or "pending")))
        if imgui.button("Export current snapshot") then snapshot() end
        imgui.same_line()
        if imgui.button(recording and "Stop and save recording" or "Start recording") then
            if recording then capture_turns(); finish_waitwalk("Cancelled: recording stopped"); recording = false; flush_actions(); sample("stop"); save()
            else
                new_session(); session.clock_start = clock(); recording = true
                next_sample, next_save = 0, clock() + 5
                export_metadata(); sample("start"); save()
            end
        end
        for _, label in ipairs({ "Out of battle", "In battle", "Navigation interrupted", "Intermediate arrival" }) do
            if imgui.button("Mark / export " .. label) then mark(label) end
        end
        if imgui.tree_node("Recovery tests / single call") then
            imgui.text("Start recording; disable rush; request ONE Wait, close menus, observe at least 15 seconds")
            if imgui.button("Test Wait only / observe game") then start_waitwalk() end
            if waitwalk and imgui.button("Cancel Wait observation") then finish_waitwalk("Cancelled by user") end
            if imgui.button("Test resumeIfPossible()") then recovery_test("resumeIfPossible()") end
            if imgui.button("Test setMovePause(false)") then recovery_test("setMovePause(System.Boolean)", false) end
            if imgui.button("Test setResume()") then recovery_test("setResume()") end
            imgui.text(recovery_message)
            imgui.tree_pop()
        end
        if imgui.tree_node("Current intermediate ticket target / read only") then
            local ok, target = pcall(function() return stopover_target(bridge().objects()) end)
            if not ok then imgui.text("Target read failed: " .. tostring(target))
            elseif target.position then
                imgui.text("Target index: " .. tostring(target.index))
                imgui.text(string.format("Target world position: X %.2f  Y %.2f  Z %.2f", target.position.x, target.position.y, target.position.z))
                if target.distance_3d then
                    imgui.text(string.format("Ox distance: %.2f | Horizontal: %.2f", target.distance_3d, target.distance_horizontal))
                end
                if target.error then imgui.text("Distance read failed: " .. target.error) end
            else imgui.text(target.error or target.reason or "Target unavailable") end
            imgui.text("Main mod ends rush within 35 horizontal units; original stop actions are allowed")
            imgui.tree_pop()
        end
        if imgui.tree_node("Inspect live objects / ObjectExplorer") then
            for _, label in ipairs({ "status", "oxcart_ai", "driver", "ox", "stopover", "ox_navigation_ai", "ox_navigation_controller", "ox_destination", "ox_navigation_data", "ox_navigation_temp" }) do
                if imgui.button("Inspect " .. label) then inspect_object(label) end
            end
            imgui.tree_pop()
        end
        if latest_data and imgui.tree_node("Ox navigation / last sampled") then
            imgui.text("IsDisableAIOxcart: " .. tostring(latest_data.states.ox_IsDisableAIOxcart or "unavailable"))
            for _, label in ipairs(NAV_LABELS) do
                imgui.text(label .. ": " .. (latest_data.navigation_objects[label] and "found" or "unavailable"))
                if latest_data.navigation_objects[label] and imgui.tree_node(label .. " fields") then
                    for name, value in pairs(latest_data.state_fields[label] or {}) do
                        imgui.text(name .. ": " .. tostring(value))
                    end
                    imgui.tree_pop()
                end
            end
            imgui.tree_pop()
        end
        if latest_data and imgui.tree_node("Last sampled stopover fields") then
            for _, name in ipairs(BASE_FIELDS) do
                local value = latest_data.state_fields.status_base[name]
                imgui.text(name .. ": " .. (type(value) == "table" and (value.error or "unavailable") or tostring(value)))
            end
            imgui.tree_pop()
        end
        imgui.text("Recording: " .. tostring(recording) .. " | Records: " .. (session and #session.records or 0))
        imgui.text(message)
        imgui.tree_pop()
    end,
}

re.on_frame(function()
    install_stopover_hook()
    if not recording then waitwalk = nil; return end
    recording_frame = recording_frame + 1
    ticket_sample()
    capture_turns()
    if #pending_stopovers > 0 then finish_waitwalk("Cancelled: game reported intermediate arrival") end
    tick_waitwalk()
    if #pending_stopovers > 0 then
        local events = pending_stopovers
        pending_stopovers = {}
        for _, event in ipairs(events) do append("arrived_stopover", event) end
        local ok, err = pcall(sample, "after_arrived_stopover")
        if not ok then append("sample_error", tostring(err)) end
        save()
    end
    local now = clock()
    if now >= next_action_flush then next_action_flush = now + 2; flush_actions() end
    if now >= next_sample then
        next_sample = now + SAMPLE_SECONDS
        local ok, err = pcall(sample)
        if not ok then message = "Sampling failed: " .. tostring(err); recording = false end
    end
    if now >= next_save then next_save = now + 5; save() end
end)
re.on_script_reset(function() if recording then capture_turns(); finish_waitwalk("Cancelled: script reset"); recording = false; flush_actions(); sample("script_reset"); save() end end)
