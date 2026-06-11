obs = obslua

-- auto-restore.lua
-- Polling every 3 seconds. For every deferred PipeWire source that has a
-- RestoreToken, tries to detect the target window via kdotool and write
-- the IPC trigger file to activate the portal session.
--
-- How it works: the script takes the OBS source name and tries matching it
-- as a kdotool search pattern. It also tries stripping common suffixes
-- like " Video", " Window", " Capture", " Source" to find a window match.
--
-- Usage: name your PipeWire window capture sources so they contain the
-- target window title. For example, if the window is called "MyGame",
-- name the source "MyGame Video" or just "MyGame".

local INT = 3  -- polling interval in seconds

-- Suffixes to strip from source names to infer window titles
local SUFFIXES = { " Video", " Window", " Capture", " Source" }

-- Cache of sources already triggered, so we don't keep polling them
local triggered = {}

function is_window_open(name)
    local escaped = name:gsub("'", "'\\''")
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
        -- Force update() so the C plugin processes the IPC file immediately
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
        local sid = obs.obs_source_get_uuid(s)

        -- Skip if we've already triggered this source
        if triggered[sid] then goto continue end

        -- Skip non-pipewire sources
        local s_id = obs.obs_source_get_id(s)
        if s_id ~= "pipewire-screen-capture-source" then goto continue end

        -- Check if it has a RestoreToken (was configured before)
        local st = obs.obs_source_get_settings(s)
        local token = obs.obs_data_get_string(st, "RestoreToken")
        if not token or token == "" then
            obs.obs_data_release(st)
            goto continue
        end

        -- Try to find the window via kdotool
        local patterns = infer_patterns(name)
        local found = false
        for _, pattern in ipairs(patterns) do
            if is_window_open(pattern) then
                obs.blog(obs.LOG_INFO, "[auto-restore] detected '" .. name .. "' via pattern '" .. pattern .. "'")
                write_ipc_trigger(name)
                triggered[sid] = true
                found = true
                break
            end
        end

        if not found then
            obs.blog(obs.LOG_DEBUG, "[auto-restore] '" .. name .. "' not found yet, will retry")
        end

        obs.obs_data_release(st)
        ::continue::
    end

    obs.source_list_release(srcs)
end

function script_description()
    return "Auto-detects PipeWire window capture sources and activates deferred portal sessions when target windows appear."
end

function script_load(s)
    obs.blog(obs.LOG_INFO, "[auto-restore] loaded (auto-detect mode)")
    obs.timer_add(tick, INT * 1000)
end