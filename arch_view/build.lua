local source_scan = require("arch_view.source_scan")
local dependency_extract = require("arch_view.dependency_extract")
local checker = require("arch_view.checker")
local layers = require("arch_view.layers")
local projection = require("arch_view.projection")
local common = require("arch_view.common")

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

function build.analyze(config, opts)
  opts = opts or {}
  local ok, config_err = build.validate_config(config)
  if not ok then
    return nil, config_err
  end
  local project_root = common.resolve_path(common.current_dir(), opts.project_root or common.current_dir())
  local scan_result, scan_err = source_scan.scan_with_options(config, {
    project_root = project_root,
  })
  if scan_result == nil then
    return nil, scan_err
  end

  local extracted = dependency_extract.build(scan_result)
  local classified_modules = checker.classify_modules(extracted.modules, config)
  local graph = {
    nodes = extracted.graph.nodes,
    edges = extracted.graph.edges,
  }
  local layout = layers.assign_layers(graph)
  local classified_edges = checker.classify_edges(graph, classified_modules)

  local architecture = {
    graph = graph,
    modules = classified_modules,
    layout = layout,
    classified_edges = classified_edges,
  }

  architecture.views = projection.build_views(architecture)
  architecture.projection_cycles = projection.collect_projection_cycles(architecture.views)
  architecture.check = checker.run(architecture, config)
  architecture.schema_version = 1
  architecture.project_root = project_root
  architecture.config_path = opts.config_path and common.resolve_path(common.current_dir(), opts.config_path) or nil

  return architecture
end

return build
