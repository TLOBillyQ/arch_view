local common = require("arch_view.common")

local layers = {}

local function _nodes_to_set(nodes)
  return common.list_to_set(nodes)
end

local function _normalize_edges(nodes, edges)
  local node_set = _nodes_to_set(nodes)
  local normalized = {}
  local normalized_map = {}
  for _, edge in ipairs(edges or {}) do
    if edge.from ~= nil and edge.to ~= nil and node_set[edge.from] and node_set[edge.to] then
      normalized_map[common.edge_key(edge.from, edge.to)] = {
        from = edge.from,
        to = edge.to,
      }
    end
  end
  normalized = common.sorted_edges(normalized_map)
  return normalized
end

local function _outgoing_map(nodes, edges)
  local outgoing = {}
  for _, node in ipairs(nodes) do
    outgoing[node] = {}
  end
  for _, edge in ipairs(edges or {}) do
    local bucket = outgoing[edge.from] or {}
    bucket[edge.to] = true
    outgoing[edge.from] = bucket
  end
  return outgoing
end

local function _incoming_map(nodes, edges)
  local incoming = {}
  for _, node in ipairs(nodes) do
    incoming[node] = {}
  end
  for _, edge in ipairs(edges or {}) do
    local bucket = incoming[edge.to] or {}
    bucket[edge.from] = true
    incoming[edge.to] = bucket
  end
  return incoming
end

local function _indegree_map(nodes, edges)
  local indegree = {}
  for _, node in ipairs(nodes) do
    indegree[node] = 0
  end
  for _, edge in ipairs(edges or {}) do
    indegree[edge.to] = (indegree[edge.to] or 0) + 1
  end
  return indegree
end

local function _sorted_zero_indegree(indegree)
  local available = {}
  for node, count in common.sorted_pairs(indegree) do
    if count == 0 then
      available[#available + 1] = node
    end
  end
  return available
end

local function _topological_order(nodes, edges)
  local outgoing = _outgoing_map(nodes, edges)
  local indegree = _indegree_map(nodes, edges)
  local queue = _sorted_zero_indegree(indegree)
  local ordered = {}

  while #queue > 0 do
    local node = table.remove(queue, 1)
    ordered[#ordered + 1] = node
    local next_nodes = common.sorted_keys(outgoing[node] or {})
    for _, dep in ipairs(next_nodes) do
      local next_count = (indegree[dep] or 0) - 1
      indegree[dep] = next_count
      if next_count == 0 then
        queue[#queue + 1] = dep
        table.sort(queue)
      end
    end
  end

  return ordered
end

local function _dag(nodes, edges)
  return #nodes == #_topological_order(nodes, edges)
end

local function _strongly_connected_components(nodes, edges)
  local outgoing = _outgoing_map(nodes, edges)
  local index = 0
  local stack = {}
  local on_stack = {}
  local indices = {}
  local low_link = {}
  local components = {}

  local function strong_connect(node)
    index = index + 1
    indices[node] = index
    low_link[node] = index
    stack[#stack + 1] = node
    on_stack[node] = true

    for _, next_node in ipairs(common.sorted_keys(outgoing[node] or {})) do
      if indices[next_node] == nil then
        strong_connect(next_node)
        if low_link[next_node] < low_link[node] then
          low_link[node] = low_link[next_node]
        end
      elseif on_stack[next_node] and indices[next_node] < low_link[node] then
        low_link[node] = indices[next_node]
      end
    end

    if low_link[node] == indices[node] then
      local component = {}
      while true do
        local popped = stack[#stack]
        stack[#stack] = nil
        on_stack[popped] = nil
        component[#component + 1] = popped
        if popped == node then
          break
        end
      end
      table.sort(component)
      components[#components + 1] = component
    end
  end

  for _, node in ipairs(nodes) do
    if indices[node] == nil then
      strong_connect(node)
    end
  end

  table.sort(components, function(left, right)
    return table.concat(left, "|") < table.concat(right, "|")
  end)
  return components
end

local function _self_loop(component, edges)
  local member_set = common.list_to_set(component)
  for _, edge in ipairs(edges or {}) do
    if edge.from == edge.to and member_set[edge.from] then
      return true
    end
  end
  return false
end

local function _cyclic_component(component, edges)
  return #component > 1 or _self_loop(component, edges)
end

local function _choose_k(values, k, start_index, current, sink)
  if k == 0 then
    sink[#sink + 1] = common.copy_array(current)
    return
  end
  if start_index > #values then
    return
  end
  for index = start_index, #values do
    current[#current + 1] = values[index]
    _choose_k(values, k - 1, index + 1, current, sink)
    current[#current] = nil
  end
end

local function _exact_feedback_edges(nodes, edges)
  local edge_values = common.copy_array(edges)
  for remove_count = 0, #edge_values do
    local subsets = {}
    _choose_k(edge_values, remove_count, 1, {}, subsets)
    for _, subset in ipairs(subsets) do
      local removed = {}
      for _, edge in ipairs(subset) do
        removed[common.edge_key(edge.from, edge.to)] = true
      end
      local remaining = {}
      for _, edge in ipairs(edge_values) do
        if not removed[common.edge_key(edge.from, edge.to)] then
          remaining[#remaining + 1] = edge
        end
      end
      if _dag(nodes, remaining) then
        return subset
      end
    end
  end
  return {}
end

local function _remove_node(edges, node)
  local remaining = {}
  for _, edge in ipairs(edges or {}) do
    if edge.from ~= node and edge.to ~= node then
      remaining[#remaining + 1] = edge
    end
  end
  return remaining
end

local function _greedy_order(nodes, edges)
  local remaining = {}
  for _, node in ipairs(nodes) do
    remaining[node] = true
  end
  local active_edges = common.copy_array(edges)
  local left = {}
  local right = {}

  local function remaining_nodes()
    return common.sorted_keys(remaining)
  end

  while next(remaining) ~= nil do
    local current_nodes = remaining_nodes()
    local incoming = _incoming_map(current_nodes, active_edges)
    local outgoing = _outgoing_map(current_nodes, active_edges)
    local sources = {}
    local sinks = {}

    for _, node in ipairs(current_nodes) do
      if next(incoming[node] or {}) == nil then
        sources[#sources + 1] = node
      end
      if next(outgoing[node] or {}) == nil then
        sinks[#sinks + 1] = node
      end
    end

    if #sources > 0 then
      local node = sources[1]
      remaining[node] = nil
      active_edges = _remove_node(active_edges, node)
      left[#left + 1] = node
    elseif #sinks > 0 then
      local node = sinks[1]
      remaining[node] = nil
      active_edges = _remove_node(active_edges, node)
      right[#right + 1] = node
    else
      table.sort(current_nodes, function(left_node, right_node)
        local left_score = #(common.sorted_keys(outgoing[left_node] or {})) - #(common.sorted_keys(incoming[left_node] or {}))
        local right_score = #(common.sorted_keys(outgoing[right_node] or {})) - #(common.sorted_keys(incoming[right_node] or {}))
        if left_score == right_score then
          return tostring(left_node) < tostring(right_node)
        end
        return left_score < right_score
      end)
      local node = current_nodes[#current_nodes]
      remaining[node] = nil
      active_edges = _remove_node(active_edges, node)
      left[#left + 1] = node
    end
  end

  local ordered = common.copy_array(left)
  for index = #right, 1, -1 do
    ordered[#ordered + 1] = right[index]
  end
  return ordered
end

local function _heuristic_feedback_edges(nodes, edges)
  local order = _greedy_order(nodes, edges)
  local index_by_node = {}
  for index, node in ipairs(order) do
    index_by_node[node] = index
  end

  local feedback = {}
  for _, edge in ipairs(edges or {}) do
    if (index_by_node[edge.from] or -1) >= (index_by_node[edge.to] or -1) then
      feedback[#feedback + 1] = edge
    end
  end
  return feedback
end

local function _component_internal_edges(component, edges)
  local member_set = common.list_to_set(component)
  local internal = {}
  for _, edge in ipairs(edges or {}) do
    if member_set[edge.from] and member_set[edge.to] then
      internal[#internal + 1] = edge
    end
  end
  return internal
end

local function _component_feedback_edges(component, edges)
  local internal = _component_internal_edges(component, edges)
  if not _cyclic_component(component, internal) then
    return {}
  end
  if #component <= 8 and #internal <= 12 then
    return _exact_feedback_edges(component, internal)
  end
  return _heuristic_feedback_edges(component, internal)
end

local function _feedback_edge_list(nodes, edges)
  local components = _strongly_connected_components(nodes, edges)
  local feedback_map = {}
  for _, component in ipairs(components) do
    local feedback = _component_feedback_edges(component, edges)
    for _, edge in ipairs(feedback) do
      feedback_map[common.edge_key(edge.from, edge.to)] = {
        from = edge.from,
        to = edge.to,
      }
    end
  end
  return common.sorted_edges(feedback_map)
end

local function _topological_levels(nodes, edges)
  local outgoing = _outgoing_map(nodes, edges)
  local incoming = _incoming_map(nodes, edges)
  local indegree = _indegree_map(nodes, edges)
  local queue = _sorted_zero_indegree(indegree)
  local levels = {}

  for _, node in ipairs(nodes) do
    levels[node] = 1
  end

  while #queue > 0 do
    local node = table.remove(queue, 1)
    local node_level = levels[node] or 1
    local next_nodes = common.sorted_keys(outgoing[node] or {})
    for _, dep in ipairs(next_nodes) do
      local next_level = node_level + 1
      if next_level > (levels[dep] or 1) then
        levels[dep] = next_level
      end
      local next_count = (indegree[dep] or 0) - 1
      indegree[dep] = next_count
      if next_count == 0 then
        queue[#queue + 1] = dep
        table.sort(queue)
      end
    end

    local roots = common.sorted_keys(incoming[node] or {})
    if #roots > 0 then
      local max_level = levels[node] or 1
      for _, root_node in ipairs(roots) do
        local candidate = (levels[root_node] or 1) + 1
        if candidate > max_level then
          max_level = candidate
        end
      end
      levels[node] = max_level
    end
  end

  return levels
end

function layers.find_cycles(graph)
  local nodes = common.copy_array(graph.nodes or {})
  table.sort(nodes)
  local edges = _normalize_edges(nodes, graph.edges or {})
  local cycles = {}
  for _, component in ipairs(_strongly_connected_components(nodes, edges)) do
    if _cyclic_component(component, edges) then
      cycles[#cycles + 1] = component
    end
  end
  return cycles
end

function layers.assign_layers(graph)
  local nodes = common.copy_array(graph.nodes or {})
  table.sort(nodes)
  local edges = _normalize_edges(nodes, graph.edges or {})
  local feedback_edges = _feedback_edge_list(nodes, edges)
  local feedback_set = {}
  for _, edge in ipairs(feedback_edges) do
    feedback_set[common.edge_key(edge.from, edge.to)] = true
  end

  local acyclic_edges = {}
  for _, edge in ipairs(edges) do
    if not feedback_set[common.edge_key(edge.from, edge.to)] then
      acyclic_edges[#acyclic_edges + 1] = edge
    end
  end

  local module_to_level = _topological_levels(nodes, acyclic_edges)
  local module_to_layer = {}
  local layer_groups = {}
  for _, node in ipairs(nodes) do
    local layer_index = (module_to_level[node] or 1) - 1
    module_to_layer[node] = layer_index
    layer_groups[layer_index] = layer_groups[layer_index] or {}
    layer_groups[layer_index][#layer_groups[layer_index] + 1] = node
  end

  local grouped_layers = {}
  for _, layer_index in ipairs(common.sorted_keys(layer_groups)) do
    table.sort(layer_groups[layer_index])
    grouped_layers[#grouped_layers + 1] = {
      index = layer_index,
      modules = layer_groups[layer_index],
    }
  end

  return {
    layers = grouped_layers,
    module_to_layer = module_to_layer,
    module_to_level = module_to_level,
    feedback_edges = feedback_edges,
    acyclic_edges = acyclic_edges,
  }
end

return layers
