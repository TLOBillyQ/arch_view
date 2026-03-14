local common = require("arch_view.common")
local route_engine = require("arch_view.route_engine")

-- DEPRECATED: This Lua module is deprecated. Use the Go core engine via arch_view.app.go_bridge or arch_view.app.service instead.

local layout_renderer = {}

local CANVAS_WIDTH = 1480.0
local NODE_WIDTH = 188.0
local NODE_HEIGHT = 60.0
local LAYER_GAP = 220.0
local HORIZONTAL_GAP = 100.0
local PADDING_X = 72.0
local PADDING_TOP = 100.0
local LAYER_LABEL_HEIGHT = 28.0

local function _copy_array(values)
    return common.copy_array(values or {})
end

local function _build_layer_rects(child_layout)
    local layer_rects = {}
    for _, layer in ipairs((child_layout and child_layout.layers) or {}) do
        local node_count = #(layer.modules or {})
        local total_width = node_count * NODE_WIDTH + math.max(0, node_count - 1) * HORIZONTAL_GAP
        local start_x = math.max(PADDING_X, (CANVAS_WIDTH - total_width) / 2.0)
        local layer_y = PADDING_TOP + layer.index * LAYER_GAP
        layer_rects[layer.index] = {
            x = start_x,
            y = layer_y,
            width = total_width,
            height = NODE_HEIGHT,
        }
    end
    return layer_rects
end

function layout_renderer.build_node_rects(child_layout, display_labels, full_names)
    local node_rects = {}
    local layer_items = {}
    local layer_rects = _build_layer_rects(child_layout)

    for _, layer in ipairs((child_layout and child_layout.layers) or {}) do
        local layer_rect = layer_rects[layer.index]
        local node_ids = _copy_array(layer.modules)
        local nodes = {}

        for index, node_id in ipairs(node_ids) do
            local x = layer_rect.x + (index - 1) * (NODE_WIDTH + HORIZONTAL_GAP)
            local y = layer_rect.y + LAYER_LABEL_HEIGHT
            local rect = {
                x = x,
                y = y,
                width = NODE_WIDTH,
                height = NODE_HEIGHT,
            }
            node_rects[node_id] = rect
            nodes[#nodes + 1] = {
                id = node_id,
                display_label = display_labels[node_id],
                full_name = full_names[node_id],
                rect = rect,
            }
        end

        layer_items[#layer_items + 1] = {
            index = layer.index,
            label = "Layer " .. tostring(layer.index),
            full_name = "Layer " .. tostring(layer.index),
            node_ids = node_ids,
            nodes = nodes,
            rect = {
                x = layer_rect.x,
                y = layer_rect.y,
                width = layer_rect.width,
                height = NODE_HEIGHT + LAYER_LABEL_HEIGHT,
            },
        }
    end

    return node_rects, layer_items
end

function layout_renderer.build_indicators(node_items)
    local indicators = {}

    for _, node in ipairs(node_items or {}) do
        if #(node.incoming_dependencies or {}) > 0 then
            local tooltip_lines = {}
            local tooltip = {}
            for _, entry in ipairs(node.incoming_dependencies) do
                tooltip_lines[#tooltip_lines + 1] = entry.text
                tooltip[#tooltip + 1] = {
                    text = entry.text,
                    cycle = entry.cycle,
                    type = entry.type,
                }
            end
            indicators[#indicators + 1] = {
                id = node.id .. ":incoming",
                node_id = node.id,
                direction = "incoming",
                cycle = node.has_cycle_subtree == true,
                count = #tooltip_lines,
                tooltip_lines = tooltip_lines,
                tooltip = tooltip,
            }
        end

        if #(node.outgoing_dependencies or {}) > 0 then
            local tooltip_lines = {}
            local tooltip = {}
            for _, entry in ipairs(node.outgoing_dependencies) do
                tooltip_lines[#tooltip_lines + 1] = entry.text
                tooltip[#tooltip + 1] = {
                    text = entry.text,
                    cycle = entry.cycle,
                    type = entry.type,
                }
            end
            indicators[#indicators + 1] = {
                id = node.id .. ":outgoing",
                node_id = node.id,
                direction = "outgoing",
                cycle = node.has_cycle_subtree == true,
                count = #tooltip_lines,
                tooltip_lines = tooltip_lines,
                tooltip = tooltip,
            }
        end
    end

    return indicators
end

function layout_renderer.decorate_display_edges(display_edges, node_rects, node_layer_map, child_feedback_set)
    local route_input = {}

    for _, edge in ipairs(display_edges or {}) do
        local next_edge = {}
        for key, value in pairs(edge) do
            next_edge[key] = value
        end
        next_edge.module_edges = _copy_array(edge.module_edges)
        next_edge.tooltip = _copy_array(edge.tooltip)
        next_edge.tooltip_lines = _copy_array(edge.tooltip_lines)
        next_edge.feedback = child_feedback_set[common.edge_key(edge.from, edge.to)] == true
        next_edge.from_rect = node_rects[edge.from]
        next_edge.to_rect = node_rects[edge.to]
        next_edge.from_layer = node_layer_map[edge.from] or 0
        next_edge.to_layer = node_layer_map[edge.to] or 0
        next_edge.id = edge.from .. "->" .. edge.to
        route_input[#route_input + 1] = next_edge
    end

    local routed = route_engine.route_edges(route_input)
    for _, edge in ipairs(routed) do
        edge.module_edges = edge.module_edges or {}
        edge.cycle = edge.feedback == true
        if edge.cycle ~= true then
            for _, module_edge in ipairs(edge.module_edges) do
                if module_edge.cycle == true then
                    edge.cycle = true
                    break
                end
            end
        end
    end

    return routed
end

function layout_renderer.canvas_size(layer_items)
    local canvas_height = PADDING_TOP + math.max(1, #(layer_items or {})) * LAYER_GAP + NODE_HEIGHT + 120.0
    return {
        width = CANVAS_WIDTH,
        height = canvas_height,
    }
end

return layout_renderer
