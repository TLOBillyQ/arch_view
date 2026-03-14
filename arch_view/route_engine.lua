local common = require("arch_view.common")

local route_engine = {}

local SAME_LAYER_LANE_STEP = 30.0
local CROSS_LAYER_LANE_STEP = 22.0
local NODE_PORT_STEP = 24.0
local NODE_EDGE_GAP = 14.0
local CENTER_EXCLUSION_HALF_WIDTH = 20.0

local function _copy_point(point)
  return { point[1], point[2] }
end

local function _build_index_map(edge_groups)
  local result = {}
  for group_key, edges in pairs(edge_groups or {}) do
    table.sort(edges, function(left, right)
      if left.sort_key == right.sort_key then
        return left.id < right.id
      end
      return left.sort_key < right.sort_key
    end)
    local count = #edges
    for index, entry in ipairs(edges) do
      result[entry.id] = {
        index = index,
        count = count,
        group_key = group_key,
      }
    end
  end
  return result
end

local function _bucketize(edges)
  local outgoing = {}
  local incoming = {}
  local lane_groups = {}

  for _, edge in ipairs(edges or {}) do
    outgoing[edge.from] = outgoing[edge.from] or {}
    outgoing[edge.from][#outgoing[edge.from] + 1] = {
      id = edge.id,
      sort_key = tostring(edge.to),
    }

    incoming[edge.to] = incoming[edge.to] or {}
    incoming[edge.to][#incoming[edge.to] + 1] = {
      id = edge.id,
      sort_key = tostring(edge.from),
    }

    local lane_key = tostring(edge.from_layer) .. "->" .. tostring(edge.to_layer)
    lane_groups[lane_key] = lane_groups[lane_key] or {}
    lane_groups[lane_key][#lane_groups[lane_key] + 1] = {
      id = edge.id,
      sort_key = tostring(edge.from) .. "->" .. tostring(edge.to),
    }
  end

  return {
    outgoing = _build_index_map(outgoing),
    incoming = _build_index_map(incoming),
    lanes = _build_index_map(lane_groups),
  }
end

local function _port_offset(index_info)
  if index_info == nil then
    return 0.0
  end
  local count = index_info.count or 1
  local offset = ((index_info.index or 1) - (count + 1) / 2.0) * NODE_PORT_STEP
  if count > 1 and math.abs(offset) < 0.001 then
    return NODE_PORT_STEP * 0.5
  end
  return offset
end

local function _lane_offset(index_info, same_layer)
  if index_info == nil then
    return 0.0
  end
  local step = same_layer and SAME_LAYER_LANE_STEP or CROSS_LAYER_LANE_STEP
  return ((index_info.index or 1) - 1) * step
end

local function _node_center_x(rect)
  return rect.x + rect.width / 2.0
end

local function _node_center_y(rect)
  return rect.y + rect.height / 2.0
end

local function _edge_horizontal_bias(edge, index_info)
  local from_center = _node_center_x(edge.from_rect)
  local to_center = _node_center_x(edge.to_rect)
  if to_center > from_center then
    return 1.0
  end
  if to_center < from_center then
    return -1.0
  end
  if index_info ~= nil and (index_info.index or 1) <= ((index_info.count or 1) / 2.0) then
    return -1.0
  end
  return 1.0
end

local function _clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end
  if value > maximum then
    return maximum
  end
  return value
end

local function _signed(value)
  if value < 0.0 then
    return -1.0
  end
  return 1.0
end

local function _cross_layer_port_offset(rect, raw_offset, preferred_direction)
  local max_offset = math.max(0.0, rect.width / 2.0 - NODE_EDGE_GAP - 6.0)
  local offset = _clamp(raw_offset, -max_offset, max_offset)
  local minimum_offset = math.min(max_offset, CENTER_EXCLUSION_HALF_WIDTH)

  if minimum_offset > 0.0 and math.abs(offset) < minimum_offset then
    local direction = preferred_direction
    if math.abs(offset) >= 0.001 then
      direction = offset
    end
    offset = _signed(direction or 1.0) * minimum_offset
  end

  return offset
end

local function _top_port(rect, raw_offset, preferred_direction)
  local offset = _cross_layer_port_offset(rect, raw_offset, preferred_direction)
  return _node_center_x(rect) + offset, rect.y - NODE_EDGE_GAP
end

local function _bottom_port(rect, raw_offset, preferred_direction)
  local offset = _cross_layer_port_offset(rect, raw_offset, preferred_direction)
  return _node_center_x(rect) + offset, rect.y + rect.height + NODE_EDGE_GAP
end

local function _left_port(rect, raw_offset)
  local max_offset = math.max(0.0, rect.height / 2.0 - NODE_EDGE_GAP - 6.0)
  local offset = _clamp(raw_offset, -max_offset, max_offset)
  return rect.x - NODE_EDGE_GAP, _node_center_y(rect) + offset
end

local function _right_port(rect, raw_offset)
  local max_offset = math.max(0.0, rect.height / 2.0 - NODE_EDGE_GAP - 6.0)
  local offset = _clamp(raw_offset, -max_offset, max_offset)
  return rect.x + rect.width + NODE_EDGE_GAP, _node_center_y(rect) + offset
end

local function _route_same_layer(edge, bucket_info)
  local from_rect = edge.from_rect
  local to_rect = edge.to_rect
  local from_offset = _port_offset(bucket_info.outgoing[edge.id])
  local to_offset = _port_offset(bucket_info.incoming[edge.id])
  local lane_offset = _lane_offset(bucket_info.lanes[edge.id], true)
  local from_x, from_y
  local to_x, to_y
  local lane_x

  if _node_center_x(to_rect) >= _node_center_x(from_rect) then
    from_x, from_y = _right_port(from_rect, from_offset)
    to_x, to_y = _left_port(to_rect, to_offset)
    lane_x = ((from_x + to_x) / 2.0) + lane_offset
  else
    from_x, from_y = _left_port(from_rect, from_offset)
    to_x, to_y = _right_port(to_rect, to_offset)
    lane_x = ((from_x + to_x) / 2.0) - lane_offset
  end

  return {
    { from_x, from_y },
    { lane_x, from_y },
    { lane_x, to_y },
    { to_x, to_y },
  }
end

local function _route_cross_layer(edge, bucket_info)
  local from_rect = edge.from_rect
  local to_rect = edge.to_rect
  local from_index = bucket_info.outgoing[edge.id]
  local to_index = bucket_info.incoming[edge.id]
  local from_offset = _port_offset(from_index)
  local to_offset = _port_offset(to_index)
  local lane_offset = _lane_offset(bucket_info.lanes[edge.id], false)
  local horizontal_bias = _edge_horizontal_bias(edge, from_index)
  local start_x, start_y
  local end_x, end_y

  if edge.to_layer > edge.from_layer then
    start_x, start_y = _bottom_port(from_rect, from_offset, horizontal_bias)
    end_x, end_y = _top_port(to_rect, to_offset, horizontal_bias)
  else
    start_x, start_y = _top_port(from_rect, from_offset, horizontal_bias)
    end_x, end_y = _bottom_port(to_rect, to_offset, horizontal_bias)
  end
  local lane_y = ((start_y + end_y) / 2.0) + lane_offset

  return {
    { start_x, start_y },
    { start_x, lane_y },
    { end_x, lane_y },
    { end_x, end_y },
  }
end

function route_engine.route_edges(edges)
  local bucket_info = _bucketize(edges or {})
  local routed = {}

  for _, edge in ipairs(edges or {}) do
    local same_layer = edge.from_layer == edge.to_layer
    local route_points
    if same_layer then
      route_points = _route_same_layer(edge, bucket_info)
    else
      route_points = _route_cross_layer(edge, bucket_info)
    end

    local copied = {}
    for index, point in ipairs(route_points or {}) do
      copied[index] = _copy_point(point)
    end

    local next_edge = {}
    for key, value in pairs(edge) do
      next_edge[key] = value
    end
    next_edge.route_points = copied
    routed[#routed + 1] = next_edge
  end

  return routed
end

return route_engine
