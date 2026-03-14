require("tests.bootstrap")

local core_bridge = require("arch_view.internal.core_bridge")
local common = require("arch_view.runtime.common")
local json_reader = require("arch_view.runtime.json_reader")

local repo_root = common.normalize_path(common.current_dir())
local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_core_bridge")

local function _write_file(path, content)
    local ok, err = common.write_file(path, content)
    if not ok then
        error(err)
    end
end

local function _exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function _mkdir(path)
    os.execute("mkdir -p " .. path)
end

local function _with_clean_tmp(fn)
    os.execute("rm -rf " .. tmp_root)
    _mkdir(tmp_root)
    local ok, err = pcall(fn)
    os.execute("rm -rf " .. tmp_root)
    if not ok then
        error(err)
    end
end

local function _write_sample_project(project_root)
    _mkdir(project_root)
    _mkdir(common.join_path(project_root, "src"))
    _write_file(common.join_path(project_root, "arch_view.config.json"), [[
{
  "source_roots": ["src"],
  "component_rules": [
    {"name": "core", "match": ["core.*"]}
  ]
}
]])
    _write_file(common.join_path(project_root, "src/init.lua"), "return {}")
    _write_file(common.join_path(project_root, "src/core_module.lua"), 'local init = require("init")\nreturn {}')
end

local function test_core_bridge_ensure_binary()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "bridge_binary")
        _write_sample_project(project_root)

        local binary_path, err = core_bridge.ensure_binary(project_root, {
            package_root = repo_root,
        })

        assert(binary_path ~= nil, "should build or find binary: " .. tostring(err))
        assert(_exists(binary_path), "binary should exist at path: " .. binary_path)
    end)
end

local function test_core_bridge_analyze()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "bridge_analyze")
        _write_sample_project(project_root)

        local architecture, binary_path = core_bridge.analyze({
            project_root = project_root,
            config_path = common.join_path(project_root, "arch_view.config.json"),
            config = {
                source_roots = {"src"},
            },
        }, {
            package_root = repo_root,
        })

        assert(architecture ~= nil, "analyze should return architecture")
        assert(type(architecture.graph) == "table", "architecture should have graph")
        assert(type(architecture.modules) == "table", "architecture should have modules")
        assert(binary_path ~= nil, "should return binary path")
    end)
end

local function test_core_bridge_check()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "bridge_check")
        _write_sample_project(project_root)

        local check_result, binary_path = core_bridge.check({
            project_root = project_root,
            config_path = common.join_path(project_root, "arch_view.config.json"),
            config = {
                source_roots = {"src"},
            },
        }, {
            package_root = repo_root,
        })

        assert(check_result ~= nil, "check should return result")
        assert(type(check_result.ok) == "boolean", "check result should have ok field")
        assert(binary_path ~= nil, "should return binary path")
    end)
end

local function test_core_bridge_write_architecture_json()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "bridge_write")
        local out_path = common.join_path(project_root, "architecture.json")
        _write_sample_project(project_root)

        local result, binary_path = core_bridge.write_architecture_json({
            project_root = project_root,
            config_path = common.join_path(project_root, "arch_view.config.json"),
            config = {
                source_roots = {"src"},
            },
        }, out_path, {
            package_root = repo_root,
        })

        assert(result == out_path, "should return output path")
        assert(_exists(out_path), "should write JSON file")

        local content = common.read_file(out_path)
        local ok, decoded = pcall(json_reader.decode, content)
        assert(ok, "output should be valid JSON")
        assert(type(decoded.graph) == "table", "JSON should have graph field")
    end)
end

local function test_core_bridge_export_viewer()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "bridge_export")
        local out_dir = common.join_path(project_root, "viewer")
        local asset_root = common.join_path(repo_root, "viewer")
        _write_sample_project(project_root)

        local result, binary_path = core_bridge.export_viewer({
            project_root = project_root,
            config_path = common.join_path(project_root, "arch_view.config.json"),
            config = {
                source_roots = {"src"},
            },
        }, out_dir, asset_root, {
            package_root = repo_root,
        })

        assert(result ~= nil, "export_viewer should return result: " .. tostring(binary_path))
        assert(result.out_dir == out_dir, "result should contain out_dir")
        assert(_exists(result.index_path), "should write index.html")
        assert(_exists(common.join_path(out_dir, "architecture.json")), "should write architecture.json")
        assert(_exists(common.join_path(out_dir, "architecture_data.js")), "should write architecture_data.js")
    end)
end

return {
    test_core_bridge_ensure_binary = test_core_bridge_ensure_binary,
    test_core_bridge_analyze = test_core_bridge_analyze,
    test_core_bridge_check = test_core_bridge_check,
    test_core_bridge_write_architecture_json = test_core_bridge_write_architecture_json,
    test_core_bridge_export_viewer = test_core_bridge_export_viewer,
}
