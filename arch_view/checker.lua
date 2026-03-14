local common = require("arch_view.common")
local layers = require("arch_view.layers")

-- DEPRECATED: This Lua module is deprecated. Use the Go core engine via arch_view.app.go_bridge or arch_view.app.service instead.

local checker = {}

local function _patterns(rule_field)
  if type(rule_field) == "string" then
    return { rule_field }
  end
  if type(rule_field) == "table" then
    return rule_field
  end
  return {}
end

local function _matches_any(value, patterns)
  for _, pattern in ipairs(_patterns(patterns)) do
    if tostring(value):find(pattern) then
      return true
    end
  end
  return false
end

local function _matches_rule(module_id, rule)
  return _matches_any(module_id, rule.match)
end

local function _resolve_component(module_id, config)
  for _, rule in ipairs(config.component_rules or {}) do
    if _matches_rule(module_id, rule) then
      return rule.component
    end
  end
  return nil
end

local function _resolve_abstract(module_id, config)
  for _, rule in ipairs(config.abstract_rules or {}) do
    if _matches_rule(module_id, rule) then
      return true
    end
  end
  return false
end

function checker.classify_modules(modules, config)
  local classified = {}
  for module_id, module_info in common.sorted_pairs(modules or {}) do
    classified[module_id] = {
      module_id = module_info.module_id,
      module_segments = common.copy_array(module_info.module_segments),
      namespace_segments = common.copy_array(module_info.namespace_segments),
      source_path = module_info.source_path,
      source_text = module_info.source_text,
      internal_requires = common.copy_array(module_info.internal_requires),
      external_requires = common.copy_array(module_info.external_requires),
      root = module_info.root,
      component = _resolve_component(module_id, config),
      abstract = _resolve_abstract(module_id, config),
    }
  end
  return classified
end

function checker.classify_edges(graph, modules)
  local classified = {}
  for _, edge in ipairs((graph and graph.edges) or {}) do
    local target = modules and modules[edge.to] or nil
    classified[#classified + 1] = {
      from = edge.from,
      to = edge.to,
      type = (target and target.abstract == true) and "abstract" or "direct",
    }
  end
  table.sort(classified, function(left, right)
    if left.from == right.from then
      if left.to == right.to then
        return tostring(left.type) < tostring(right.type)
      end
      return tostring(left.to) < tostring(right.to)
    end
    return tostring(left.from) < tostring(right.from)
  end)
  return classified
end

local function _rule_allows_edge(edge, rule)
  for _, allow in ipairs(rule.allow or {}) do
    if _matches_any(edge.from, allow.from) and _matches_any(edge.to, allow.to) then
      return true
    end
  end
  return false
end

local function _current_cycle_keys(graph)
  local cycle_map = {}
  local cycles = layers.find_cycles(graph)
  for _, cycle in ipairs(cycles) do
    local copied = common.copy_array(cycle)
    table.sort(copied)
    cycle_map[table.concat(copied, "|")] = copied
  end
  return cycle_map
end

local function _current_projection_cycles(architecture)
  local projection_cycles = architecture.projection_cycles
  if projection_cycles ~= nil then
    return projection_cycles
  end
  if architecture.check ~= nil and architecture.check.projection_cycles ~= nil then
    return architecture.check.projection_cycles
  end
  return {}
end

function checker.run(architecture, config)
  local violations = {}

  for module_id, module_info in common.sorted_pairs(architecture.modules or {}) do
    if module_info.component == nil then
      violations[#violations + 1] = {
        kind = "unclassified_module",
        module_id = module_id,
        description = "module is not covered by component_rules",
      }
    end
  end

  for _, edge in ipairs(architecture.graph.edges or {}) do
    for _, rule in ipairs(config.forbidden_dependency_rules or {}) do
      if _matches_any(edge.from, rule.from) and _matches_any(edge.to, rule.to) and not _rule_allows_edge(edge, rule) then
        violations[#violations + 1] = {
          kind = "forbidden_dependency",
          rule = rule.name,
          description = rule.description,
          from = edge.from,
          to = edge.to,
        }
      end
    end
  end

  local current_cycle_map = _current_cycle_keys(architecture.graph)
  for _, cycle in common.sorted_pairs(current_cycle_map) do
    violations[#violations + 1] = {
      kind = "unexpected_cycle",
      cycle = cycle,
      description = "module-level circular dependency detected",
    }
  end

  local cycle_list = {}
  for _, cycle in common.sorted_pairs(current_cycle_map) do
    cycle_list[#cycle_list + 1] = common.copy_array(cycle)
  end

  local projection_cycles = _current_projection_cycles(architecture)
  for _, entry in ipairs(projection_cycles) do
    violations[#violations + 1] = {
      kind = "projection_cycle",
      view = entry.view,
      feedback_edges = common.copy_array(entry.feedback_edges or {}),
      description = "projection-level circular dependency detected",
    }
  end

  return {
    ok = #violations == 0,
    violations = violations,
    cycles = cycle_list,
    projection_cycles = projection_cycles,
  }
end

return checker
