local common = require("arch_view.common")
local go_bridge = require("arch_view.app.go_bridge")
local paths = require("arch_view.app.paths")

local engine = {}

local function _text(zh, en)
    return common.bilingual(zh, en)
end

local function _go_request(resolved)
    return {
        project_root = resolved.project_root,
        config_path = resolved.config_path,
        config = resolved.config,
    }
end

local function _go_opts(resolved)
    return {
        package_root = resolved.package_root or paths.package_root(),
        toolchain_root = resolved.toolchain_root,
    }
end

local function _normalize_requested_engine(value)
    local requested = tostring(value or "auto")
    if requested == "auto" or requested == "go" or requested == "lua" then
        return requested
    end
    return "auto"
end

local function _ensure_go_mode(requested)
    if requested == "lua" then
        return nil, _text(
            "engine=lua 已废弃且不再受支持；请改用 engine=go 或 engine=auto。",
            "engine=lua is deprecated and no longer supported; use engine=go or engine=auto."
        )
    end
    return "go"
end

function engine.analyze(resolved)
    local requested = _normalize_requested_engine(resolved.engine)
    local ok_engine, engine_err = _ensure_go_mode(requested)
    if ok_engine == nil then
        return nil, engine_err
    end

    local architecture, binary_path_or_err = go_bridge.analyze(
        _go_request(resolved),
        _go_opts(resolved)
    )
    if architecture == nil then
        return nil, binary_path_or_err
    end
    return architecture, ok_engine, binary_path_or_err
end

function engine.check(resolved)
    local requested = _normalize_requested_engine(resolved.engine)
    local ok_engine, engine_err = _ensure_go_mode(requested)
    if ok_engine == nil then
        return nil, engine_err
    end

    local check_result, err = go_bridge.check(
        _go_request(resolved),
        _go_opts(resolved)
    )
    if check_result == nil then
        return nil, err
    end
    return check_result, ok_engine
end

function engine.write_json(resolved, out_path)
    local requested = _normalize_requested_engine(resolved.engine)
    local ok_engine, engine_err = _ensure_go_mode(requested)
    if ok_engine == nil then
        return nil, engine_err
    end

    local json_path, binary_path_or_err = go_bridge.write_architecture_json(
        _go_request(resolved),
        out_path,
        _go_opts(resolved)
    )
    if json_path == nil then
        return nil, binary_path_or_err
    end

    return nil, ok_engine, binary_path_or_err
end

return engine
