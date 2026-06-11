obs = obslua

-- auto-restore.lua
-- Polling every 3 seconds. For every deferred PipeWire source that has a
-- RestoreToken, tries to detect the target window via kdotool and write
-- the IPC trigger file to activate the portal session.
--
-- Once activated, keeps monitoring the window. If the window is closed,
-- marks the source as pending again so it gets re-activated when the
-- window reopens.
--
-- How it works: the script takes the OBS source name and tries matching it
-- as a kdotool search pattern. It also tries stripping common suffixes
-- like " Video", " Window", " Capture", " Source" to find a window match.
--
-- Usage: name your PipeWire window capture sources so they contain the
-- target window title. For example, if the window is called "MyGame",
-- name the source "MyGame Video" or just "MyGame".

local INT = 3

local SUFFIXES = { " Video", " Window", " Capture", " Source" }

-- Source names to skip entirely (they are monitor captures, not windows)
local SKIP_PATTERNS = {
    "Cattura schermo", "Screen", "Monitor", "Schermo",
    "Desktop Capture", "Desktop"
}

-- source_uuid → { triggered = bool, pattern = string }
local source_state = {}

function is_window_open(pattern)
    local escaped = pattern:gsub("'", "'\\''")
    local cmd = "kdotool search --name '" .. escaped .. "' 2>/dev/null"
    local f = io.popen(cmd, "r")
    if not f then return false end
    local out = f:read("*a")
    f:close()
    return out and not out:match("^%s*$")
end

function infer_patterns(source_name)
    local patterns = {}
    table.insert(patterns, source_name)
    for _, suffix in ipairs(SUFFIXES) do
        if source_name:sub(-#suffix) == suffix then
            table.insert(patterns, source_name:sub(1, -#suffix - 1))
        end
    end
    return patterns
end

function write_ipc_trigger(source_name)
    local path = "/tmp/obs-trigger-" .. source_name
    local f = io.open(path, "w")
    if f then
        f:write("1")
        f:close()
        obs.blog(obs.LOG_INFO, "[auto-restore] wrote IPC trigger for " .. source_name)
        local srcs = obs.obs_enum_sources()
        if srcs then
            for _, s in ipairs(srcs) do
                if obs.obs_source_get_name(s) == source_name then
                    local st = obs.obs_source_get_settings(s)
                    obs.obs_source_update(s, st)
                    obs.obs_data_release(st)
                    break
                end
            end
            obs.source_list_release(srcs)
        end
        return true
    else
        obs.blog(obs.LOG_WARNING, "[auto-restore] cannot write " .. path)
        return false
    end
end

function tick()
    local srcs = obs.obs_enum_sources()
    if not srcs then return end

    for _, s in ipairs(srcs) do
        local name = obs.obs_source_get_name(s)
        local uuid = obs.obs_source_get_uuid(s)

        if obs.obs_source_get_id(s) ~= "pipewire-screen-capture-source" then goto continue end

        local st = obs.obs_source_get_settings(s)
        local token = obs.obs_data_get_string(st, "RestoreToken")
        obs.obs_data_release(st)

        -- Monitor-style sources (name contains "Screen", "Monitor", etc.)
        -- should be triggered immediately, not deferred
        local is_monitor = false
        for _, sk in ipairs(SKIP_PATTERNS) do
            if name:find(sk, 1, true) then
                is_monitor = true
                break
            end
        end
        if is_monitor then
            if not source_state[uuid] then
                obs.blog(obs.LOG_INFO, "[auto-restore] activating monitor source '" .. name .. "'")
                write_ipc_trigger(name)
                source_state[uuid] = { triggered = true, pattern = nil }
            end
            goto continue
        end

        if not token or token == "" then
            source_state[uuid] = nil
            goto continue
        end

        local state = source_state[uuid]

        if state and state.triggered and state.pattern then
            -- Source was activated. Check if window is still open.
            if not is_window_open(state.pattern) then
                obs.blog(obs.LOG_INFO, "[auto-restore] window closed for '" .. name .. "', will reactivate")
                source_state[uuid] = { triggered = false, pattern = state.pattern }
            end
            goto continue
        end

        -- Not triggered yet: try to find the window
        local patterns = infer_patterns(name)
        for _, pattern in ipairs(patterns) do
            if is_window_open(pattern) then
                obs.blog(obs.LOG_INFO, "[auto-restore] detected '" .. name .. "' via '" .. pattern .. "'")
                write_ipc_trigger(name)
                source_state[uuid] = { triggered = true, pattern = pattern }
                goto continue
            end
        end

        if not state then
            source_state[uuid] = { triggered = false, pattern = nil }
        end

        ::continue::
    end

    obs.source_list_release(srcs)
end

function script_description()
    return "Auto-detects PipeWire windows and reactivates sources when windows reopen."
end

function script_load(s)
    obs.blog(obs.LOG_INFO, "[auto-restore] loaded (reopen support)")
    obs.timer_add(tick, INT * 1000)
end