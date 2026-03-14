local common = require("arch_view.common")
local go_bridge = require("arch_view.app.go_bridge")
local paths = require("arch_view.app.paths")

local build = {}

local function _assert_array_of_strings(field_name, values)
    if type(values) ~= "table" then
        return nil, field_name .. " must be an array"
    end
    for index, value in ipairs(values) do
        if type(value) ~= "string" or value == "" then
            return nil, field_name .. "[" .. tostring(index) .. "] must be a non-empty string"
        end
    end
    return true
end

local function _validate_rule_list(field_name, rules)
    if rules == nil then
        return true
    end
    if type(rules) ~= "table" then
        return nil, field_name .. " must be an array"
    end
    for index, rule in ipairs(rules) do
        if type(rule) ~= "table" then
            return nil, field_name .. "[" .. tostring(index) .. "] must be a table"
        end
    end
    return true
end

function build.validate_config(config)
    if type(config) ~= "table" then
        return nil, "config must be a table"
    end
    local ok, err = _assert_array_of_strings("source_roots", config.source_roots or {})
    if not ok then
        return nil, err
    end
    ok, err = _validate_rule_list("component_rules", config.component_rules)
    if not ok then
        return nil, err
    end
    ok, err = _validate_rule_list("abstract_rules", config.abstract_rules)
    if not ok then
        return nil, err
    end
    ok, err = _validate_rule_list("forbidden_dependency_rules", config.forbidden_dependency_rules)
    if not ok then
        return nil, err
    end
    return true
end

local function _resolve_project_root(opts)
    return common.resolve_path(common.current_dir(), opts.project_root or common.current_dir())
end

local function _resolve_config_path(opts)
    if opts.config_path == nil or opts.config_path == "" then
        return nil
    end
    return common.resolve_path(common.current_dir(), opts.config_path)
end

function build.analyze(config, opts)
    opts = opts or {}

    local ok, config_err = build.validate_config(config)
    if not ok then
        return nil, config_err
    end

    local project_root = _resolve_project_root(opts)
    local config_path = _resolve_config_path(opts) or common.join_path(project_root, "arch_view.config.json")

    local architecture, err = go_bridge.analyze({
        project_root = project_root,
        config_path = config_path,
        config = config,
    }, {
        package_root = opts.package_root or paths.package_root(),
        toolchain_root = opts.toolchain_root,
    })

    if architecture == nil then
        return nil, err
    end

    return architecture
end

return build
