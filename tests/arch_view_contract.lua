require("tests.bootstrap")

local build = require("arch_view.build")
local checker = require("arch_view.checker")
local cli = require("arch_view.cli")
local common = require("arch_view.common")
local dependency_extract = require("arch_view.dependency_extract")
local json_reader = require("arch_view.json_reader")
local json_writer = require("arch_view.json_writer")
local layout = require("arch_view.layers")
local projection = require("arch_view.projection")
local route_engine = require("arch_view.route_engine")
local source_scan = require("arch_view.source_scan")

local repo_root = common.normalize_path(common.current_dir())
local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_contract")

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

local function _exists(path)
  return common.path_exists(path) == true
end

local function _cleanup_tmp()
  local ok, err = common.remove_path(tmp_root)
  if not ok then
    error(err)
  end
end

local function _with_clean_tmp(fn)
  _cleanup_tmp()
  local ok, err = xpcall(fn, debug.traceback)
  _cleanup_tmp()
  if not ok then
    error(err)
  end
end

local function _write_file(path, text)
  local ok, err = common.write_file(path, text)
  if not ok then
    error(err)
  end
end

local function _write_sample_project(project_root)
  _write_file(common.join_path(project_root, "src/demo/pkg/init.lua"), 'local beta = require("src.demo.beta")\nreturn beta\n')
  _write_file(common.join_path(project_root, "src/demo/pkg/child.lua"), "return {}\n")
  _write_file(common.join_path(project_root, "src/demo/beta.lua"), "return {}\n")
  _write_file(common.join_path(project_root, "arch_config.lua"), table.concat({
    "return {",
    '  source_roots = { "src" },',
    "  component_rules = {",
    '    { name = "demo", match = { "^src%.demo$", "^src%.demo%..+" }, component = "demo" },',
    "  },",
    "  abstract_rules = {},",
    "  forbidden_dependency_rules = {},",
    "}",
    "",
  }, "\n"))
end

local function _test_dependency_extract_supports_static_requires()
  local scan_result = {
    module_ids = {
      ["src.demo.a"] = true,
      ["src.demo.b"] = true,
      ["src.demo.c"] = true,
      ["src.demo.d"] = true,
    },
    module_list = {
      "src.demo.a",
      "src.demo.b",
      "src.demo.c",
      "src.demo.d",
    },
    modules = {
      ["src.demo.a"] = {
        module_id = "src.demo.a",
        module_segments = { "src", "demo", "a" },
        namespace_segments = { "demo", "a" },
        source_path = "src/demo/a.lua",
        source_text = table.concat({
          'local b = require("src.demo.b")',
          "local c = require('src.demo.c')",
          'require "src.demo.d"',
          "require 'external.pkg'",
          "local ignored = require(module_name)",
        }, "\n"),
        root = "src",
      },
      ["src.demo.b"] = {
        module_id = "src.demo.b",
        module_segments = { "src", "demo", "b" },
        namespace_segments = { "demo", "b" },
        source_path = "src/demo/b.lua",
        source_text = "",
        root = "src",
      },
      ["src.demo.c"] = {
        module_id = "src.demo.c",
        module_segments = { "src", "demo", "c" },
        namespace_segments = { "demo", "c" },
        source_path = "src/demo/c.lua",
        source_text = "",
        root = "src",
      },
      ["src.demo.d"] = {
        module_id = "src.demo.d",
        module_segments = { "src", "demo", "d" },
        namespace_segments = { "demo", "d" },
        source_path = "src/demo/d.lua",
        source_text = "",
        root = "src",
      },
    },
  }

  local extracted = dependency_extract.build(scan_result)
  local module_info = extracted.modules["src.demo.a"]

  _assert_eq(#module_info.internal_requires, 3, "static requires should capture three internal modules")
  _assert_contains(module_info.internal_requires, "src.demo.b", "require(...) should be captured")
  _assert_contains(module_info.internal_requires, "src.demo.c", "require('...') should be captured")
  _assert_contains(module_info.internal_requires, "src.demo.d", "require '...' should be captured")
  _assert_eq(#module_info.external_requires, 1, "external literal require should be captured once")
  _assert_eq(module_info.external_requires[1], "external.pkg", "dynamic require(module_name) should be ignored")
end

local function _test_source_scan_treats_init_as_package_entry()
  _with_clean_tmp(function()
    local project_root = common.join_path(tmp_root, "scan_project")
    _write_sample_project(project_root)

    local scan_result, scan_err = source_scan.scan_with_options({
      source_roots = { "src" },
    }, {
      project_root = project_root,
    })
    if scan_result == nil then
      error(scan_err)
    end

    assert(scan_result.module_ids["src.demo.pkg"] == true, "init.lua should resolve to package module id")
    assert(scan_result.module_ids["src.demo.pkg.child"] == true, "package child should keep nested module id")
    assert(scan_result.module_ids["src.demo.pkg.init"] ~= true, "init.lua should not emit foo.init module id")
  end)
end

local function _test_checker_reports_cycles()
  local architecture = {
    graph = {
      nodes = { "a", "b", "c" },
      edges = {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
      },
    },
    modules = {
      a = { component = "demo" },
      b = { component = "demo" },
      c = { component = "demo" },
    },
    projection_cycles = {},
  }

  local result = checker.run(architecture, {
    component_rules = {},
    abstract_rules = {},
    forbidden_dependency_rules = {},
  })

  assert(result.ok == false, "cycle should fail check")
  _assert_eq(result.violations[1].kind, "unexpected_cycle", "cycle should be reported")
end

local function _test_projection_collects_projection_cycles()
  local architecture = {
    graph = {
      nodes = {
        "src.alpha.a1",
        "src.alpha.a2",
        "src.beta.b1",
        "src.beta.b2",
      },
      edges = {
        { from = "src.alpha.a1", to = "src.beta.b1" },
        { from = "src.beta.b2", to = "src.alpha.a2" },
      },
    },
    modules = {
      ["src.alpha.a1"] = {
        module_id = "src.alpha.a1",
        module_segments = { "src", "alpha", "a1" },
        namespace_segments = { "alpha", "a1" },
        source_path = "src/alpha/a1.lua",
        source_text = "",
        internal_requires = { "src.beta.b1" },
        external_requires = {},
        component = "demo",
        abstract = false,
      },
      ["src.alpha.a2"] = {
        module_id = "src.alpha.a2",
        module_segments = { "src", "alpha", "a2" },
        namespace_segments = { "alpha", "a2" },
        source_path = "src/alpha/a2.lua",
        source_text = "",
        internal_requires = {},
        external_requires = {},
        component = "demo",
        abstract = false,
      },
      ["src.beta.b1"] = {
        module_id = "src.beta.b1",
        module_segments = { "src", "beta", "b1" },
        namespace_segments = { "beta", "b1" },
        source_path = "src/beta/b1.lua",
        source_text = "",
        internal_requires = {},
        external_requires = {},
        component = "demo",
        abstract = false,
      },
      ["src.beta.b2"] = {
        module_id = "src.beta.b2",
        module_segments = { "src", "beta", "b2" },
        namespace_segments = { "beta", "b2" },
        source_path = "src/beta/b2.lua",
        source_text = "",
        internal_requires = { "src.alpha.a2" },
        external_requires = {},
        component = "demo",
        abstract = false,
      },
    },
    classified_edges = {
      { from = "src.alpha.a1", to = "src.beta.b1", type = "direct" },
      { from = "src.beta.b2", to = "src.alpha.a2", type = "direct" },
    },
    layout = layout.assign_layers({
      nodes = {
        "src.alpha.a1",
        "src.alpha.a2",
        "src.beta.b1",
        "src.beta.b2",
      },
      edges = {
        { from = "src.alpha.a1", to = "src.beta.b1" },
        { from = "src.beta.b2", to = "src.alpha.a2" },
      },
    }),
  }

  architecture.views = projection.build_views(architecture)
  architecture.projection_cycles = projection.collect_projection_cycles(architecture.views)

  assert(#(architecture.projection_cycles or {}) > 0, "projection should detect view-level cycles")
end

local function _test_route_engine_avoids_exact_overlap()
  local routed = route_engine.route_edges({
    {
      id = "a->c",
      from = "a",
      to = "c",
      from_layer = 0,
      to_layer = 1,
      from_rect = { x = 0.0, y = 0.0, width = 100.0, height = 60.0 },
      to_rect = { x = 220.0, y = 160.0, width = 100.0, height = 60.0 },
    },
    {
      id = "b->c",
      from = "b",
      to = "c",
      from_layer = 0,
      to_layer = 1,
      from_rect = { x = 130.0, y = 0.0, width = 100.0, height = 60.0 },
      to_rect = { x = 220.0, y = 160.0, width = 100.0, height = 60.0 },
    },
  })

  _assert_eq(#routed, 2, "route engine should preserve both edges")
  assert(#(routed[1].route_points or {}) == 4, "route engine should emit orthogonal route points")
  assert(#(routed[2].route_points or {}) == 4, "route engine should emit orthogonal route points")
end

local function _test_json_round_trip()
  local payload = {
    hello = "world",
    count = 3,
    list = { "a", "b" },
    nested = {
      ok = true,
    },
  }

  local encoded = json_writer.encode(payload)
  local decoded = json_reader.decode(encoded)
  _assert_eq(decoded.hello, "world", "json round trip should preserve strings")
  _assert_eq(decoded.count, 3, "json round trip should preserve numbers")
  _assert_eq(decoded.nested.ok, true, "json round trip should preserve booleans")
end

local function _test_build_and_cli_respect_default_config_path()
  _with_clean_tmp(function()
    local project_root = common.join_path(tmp_root, "build_project")
    _write_sample_project(project_root)
    local config_path = common.join_path(project_root, "arch_config.lua")
    local out_path = common.join_path(project_root, "out/architecture.json")
    local out_dir = common.join_path(project_root, "viewer")

    local config_chunk = assert(loadfile(config_path))
    local architecture, err = build.analyze(config_chunk(), {
      project_root = project_root,
      config_path = config_path,
    })
    if architecture == nil then
      error(err)
    end
    _assert_eq(architecture.modules["src.demo.pkg"].component, "demo", "build should classify modules from external config")

    cli.run({
      "scan",
      "--out", out_path,
    }, {
      script_dir = repo_root,
      default_project_root = project_root,
      default_config_path = config_path,
    })

    assert(_exists(out_path), "scan should write output file")

    cli.run({
      "viewer",
      "--in-json", out_path,
      "--out-dir", out_dir,
    }, {
      script_dir = repo_root,
      default_project_root = project_root,
      default_config_path = config_path,
    })

    assert(_exists(common.join_path(out_dir, "index.html")), "viewer should export index.html")
    assert(_exists(common.join_path(out_dir, "architecture.json")), "viewer should export architecture.json")
    assert(_exists(common.join_path(out_dir, "architecture_data.js")), "viewer should export architecture_data.js")
  end)
end

local function _test_tool_is_self_contained()
  local common_source = _read_file(common.join_path(repo_root, "arch_view/common.lua"))
  local script_common_source = _read_file(common.join_path(repo_root, "arch_view/script_common.lua"))
  assert(common_source:find('require("lib.common")', 1, true) == nil, "tool should not depend on monopoly lib.common")
  assert(script_common_source:find('src.core.utils.number_utils', 1, true) == nil,
    "tool should not depend on monopoly src modules")
end

return {
  tests = {
    { name = "dependency_extract_supports_static_requires", run = _test_dependency_extract_supports_static_requires },
    { name = "source_scan_treats_init_as_package_entry", run = _test_source_scan_treats_init_as_package_entry },
    { name = "checker_reports_cycles", run = _test_checker_reports_cycles },
    { name = "projection_collects_projection_cycles", run = _test_projection_collects_projection_cycles },
    { name = "route_engine_avoids_exact_overlap", run = _test_route_engine_avoids_exact_overlap },
    { name = "json_round_trip", run = _test_json_round_trip },
    { name = "build_and_cli_respect_default_config_path", run = _test_build_and_cli_respect_default_config_path },
    { name = "tool_is_self_contained", run = _test_tool_is_self_contained },
  },
}
