require("tests.bootstrap")

local arch_view = require("arch_view")
local common = require("arch_view.runtime.common")
local json_writer = require("arch_view.runtime.json_writer")

local repo_root = common.normalize_path(common.current_dir())
local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_api")

local function _assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. "\nexpected: " .. tostring(expected) .. "\nactual: " .. tostring(actual))
    end
end

local function _assert_contains(list, expected, message)
    for _, value in ipairs(list or {}) do
        if value == expected then
            return
        end
    end
    error((message or "missing value") .. "\nmissing: " .. tostring(expected))
end

local function _read_file(path)
    local content, err = common.read_file(path)
    if content == nil then
        error(err)
    end
    return content
end

local function _write_file(path, content)
    local ok, err = common.write_file(path, content)
    if not ok then
        error(err)
    end
end

local function _assert_not_contains(text, expected, message)
    if tostring(text or ""):find(expected, 1, true) ~= nil then
        error((message or "unexpected value present") .. "\nunexpected: " .. tostring(expected))
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
    {"name": "core", "match": ["^src$", "^src%..+"], "component": "core"}
  ]
}
]])
    _write_file(common.join_path(project_root, "src/init.lua"), "return {}")
    _write_file(common.join_path(project_root, "src/core_module.lua"), 'local init = require("init")\nreturn {}')
end

local function _normalize_architecture(architecture)
    local copy = {}
    for key, value in pairs(architecture) do
        if key ~= "project_root" and key ~= "config_path" and key ~= "engine_used" and key ~= "engine_binary" then
            copy[key] = value
        end
    end
    return copy
end

local function test_analyze_basic()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "analyze_project")
        _write_sample_project(project_root)

        local architecture, err = arch_view.analyze({
            project_root = project_root,
        })
        if architecture == nil then
            error(err)
        end

        assert(type(architecture.graph) == "table", "architecture should have graph")
        assert(type(architecture.modules) == "table", "architecture should have modules")
        assert(type(architecture.layout) == "table", "architecture should have layout")
        assert(type(architecture.check) == "table", "architecture should have check")
    end)
end

local function test_check_returns_result()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "check_project")
        _write_sample_project(project_root)

        local result, err = arch_view.check({
            project_root = project_root,
        })
        if result == nil then
            error(err)
        end

        assert(type(result.check) == "table", "check result should have check field")
        assert(type(result.check.ok) == "boolean", "check.ok should be boolean")
        assert(type(result.engine) == "string", "should return engine used")
    end)
end

local function test_write_scan_creates_file()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "scan_project")
        local out_path = common.join_path(project_root, ".arch_view/architecture.json")
        _write_sample_project(project_root)

        local result, err = arch_view.write_scan({
            project_root = project_root,
            out_path = out_path,
        })
        if result == nil then
            error(err)
        end

        assert(_exists(out_path), "scan should write output file")
        local content = _read_file(out_path)
        assert(#content > 0, "output file should not be empty")
    end)
end

local function test_export_viewer_creates_files()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "viewer_project")
        _write_sample_project(project_root)

        local result, err = arch_view.export_viewer({
            project_root = project_root,
        })
        if result == nil then
            error(err)
        end

        assert(_exists(result.index_path), "viewer should write index.html")
        assert(_exists(common.join_path(result.out_dir, "architecture.json")), "viewer should write architecture.json")
        assert(_exists(common.join_path(result.out_dir, "architecture_data.js")), "viewer should write architecture_data.js")
        assert(_exists(common.join_path(result.out_dir, "script.js")), "viewer should copy script.js")
        assert(_exists(common.join_path(result.out_dir, "styles.css")), "viewer should copy styles.css")
    end)
end

local function test_go_engine_matches_auto_engine()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "go_compare_project")
        _write_sample_project(project_root)

        local auto_architecture, auto_err = arch_view.analyze({
            project_root = project_root,
            engine = "auto",
        })
        if auto_architecture == nil then
            error(auto_err)
        end

        local go_architecture, go_err = arch_view.analyze({
            project_root = project_root,
            engine = "go",
        })
        if go_architecture == nil then
            error(go_err)
        end

        local normalized_go = _normalize_architecture(go_architecture)
        local normalized_auto = _normalize_architecture(auto_architecture)

        _assert_eq(json_writer.encode(normalized_go.graph), json_writer.encode(normalized_auto.graph),
            "go graph should match auto graph")
        _assert_eq(json_writer.encode(normalized_go.modules), json_writer.encode(normalized_auto.modules),
            "go modules should match auto modules")
        _assert_eq(json_writer.encode(normalized_go.layout), json_writer.encode(normalized_auto.layout),
            "go layout should match auto layout")
    end)
end

local function test_viewer_export_is_self_contained()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "self_contained_project")
        local out_dir = common.join_path(project_root, ".arch_view/viewer")
        _write_sample_project(project_root)

        local result, err = arch_view.export_viewer({
            project_root = project_root,
        })
        if result == nil then
            error(err)
        end

        local exported_index = _read_file(common.join_path(out_dir, "index.html"))
        local exported_styles = _read_file(common.join_path(out_dir, "styles.css"))
        _assert_not_contains(exported_index, "fonts.googleapis.com", "viewer should not depend on Google Fonts")
        _assert_not_contains(exported_index, "fonts.gstatic.com", "viewer should not depend on Google Fonts")
    end)
end

return {
    test_analyze_basic = test_analyze_basic,
    test_check_returns_result = test_check_returns_result,
    test_write_scan_creates_file = test_write_scan_creates_file,
    test_export_viewer_creates_files = test_export_viewer_creates_files,
    test_go_engine_matches_auto_engine = test_go_engine_matches_auto_engine,
    test_viewer_export_is_self_contained = test_viewer_export_is_self_contained,
}
