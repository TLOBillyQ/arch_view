local common = require("arch_view.common")
local layers = require("arch_view.layers")
local layout_renderer = require("arch_view.layout_renderer")

local projection = {}

local function _node_child_name(node_id)
    return node_id
end

local function _stripped_module_name(module_id)
    return common.strip_src_prefix(module_id)
end

local function _collect_scoped_modules(modules, prefix_segments)
    local scoped = {}
    for module_id, module_info in common.sorted_pairs(modules or {}) do
        if common.starts_with_segments(module_info.namespace_segments, prefix_segments)
            and #module_info.namespace_segments > #prefix_segments then
            scoped[module_id] = module_info
        end
    end
    return scoped
end

local function _module_to_child(scoped_modules, prefix_segments)
    local result = {}
    for module_id, module_info in pairs(scoped_modules or {}) do
        result[module_id] = module_info.namespace_segments[#prefix_segments + 1]
    end
    return result
end

local function _child_to_info(scoped_modules, prefix_segments, module_child_map)
    local child_info = {}
    for module_id, module_info in pairs(scoped_modules or {}) do
        local child_name = module_child_map[module_id]
        local info = child_info[child_name] or {
            exact_module = nil,
            descendant_modules = {},
        }
        if #module_info.namespace_segments == (#prefix_segments + 1) then
            info.exact_module = module_id
        else
            info.descendant_modules[module_id] = true
        end
        child_info[child_name] = info
    end
    return child_info
end

local function _module_to_node(child_info)
    local module_node_map = {}
    for child_name, info in common.sorted_pairs(child_info) do
        if info.exact_module ~= nil then
            module_node_map[info.exact_module] = child_name
        end
        for module_id in common.sorted_pairs(info.descendant_modules) do
            module_node_map[module_id] = child_name
        end
    end
    return module_node_map
end

local function _node_to_modules(module_node_map)
    local node_modules = {}
    for module_id, node_id in common.sorted_pairs(module_node_map) do
        local bucket = node_modules[node_id] or {}
        bucket[#bucket + 1] = module_id
        node_modules[node_id] = bucket
    end
    for _, module_ids in pairs(node_modules) do
        table.sort(module_ids)
    end
    return node_modules
end

local function _node_component(modules, module_ids)
    local component_name = nil
    for _, module_id in ipairs(module_ids or {}) do
        local next_component = modules[module_id] and modules[module_id].component or nil
        if component_name == nil then
            component_name = next_component
        elseif component_name ~= next_component then
            return "mixed"
        end
    end
    return component_name
end

local function _node_abstract(modules, module_ids)
    for _, module_id in ipairs(module_ids or {}) do
        if modules[module_id] and modules[module_id].abstract == true then
            return true
        end
    end
    return false
end

local function _module_feedback_set(layout)
    local involved = {}
    for _, edge in ipairs((layout and layout.feedback_edges) or {}) do
        involved[edge.from] = true
        involved[edge.to] = true
    end
    return involved
end

local function _build_breadcrumb(prefix_segments)
    local breadcrumb = {
        { key = "root", label = "src" },
    }
    local current = {}
    for _, segment in ipairs(prefix_segments or {}) do
        current[#current + 1] = segment
        breadcrumb[#breadcrumb + 1] = {
            key = common.view_key(current),
            label = segment,
        }
    end
    return breadcrumb
end

local function _display_label_for_node(node_id, child_info, modules)
    local child_name = _node_child_name(node_id)
    local info = child_info[child_name]
    local exact_module = info and info.exact_module or nil
    if exact_module ~= nil and next(info.descendant_modules) == nil then
        local source_file_name = common.source_filename_base(modules[exact_module] and modules[exact_module].source_path or
        nil)
        if source_file_name ~= nil and source_file_name ~= "" then
            return source_file_name
        end
    end
    return child_name
end

local function _full_name_for_node(node_id, prefix_segments, child_info, modules)
    local child_name = _node_child_name(node_id)
    local info = child_info[child_name]
    if info and info.exact_module ~= nil and next(info.descendant_modules) == nil then
        return _stripped_module_name(info.exact_module)
    end

    local full_name = common.copy_array(prefix_segments)
    full_name[#full_name + 1] = child_name
    return table.concat(full_name, ".")
end

local function _build_pair_map(entries)
    local pair_map = {}
    for _, entry in ipairs(entries or {}) do
        local key = common.edge_key(entry.from, entry.to)
        local existing = pair_map[key]
        if existing == nil then
            existing = {
                from = entry.from,
                to = entry.to,
                type = entry.type,
                count = 0,
                module_edges = {},
            }
            pair_map[key] = existing
        end
        existing.count = existing.count + 1
        if entry.type == "abstract" then
            existing.type = "abstract"
        end
        existing.module_edges[#existing.module_edges + 1] = {
            from = entry.module_from,
            to = entry.module_to,
            type = entry.type,
            cycle = entry.cycle,
            text = entry.text,
        }
    end
    return pair_map
end

local function _append_sorted_entries(edge)
    table.sort(edge.module_edges, function(left, right)
        if left.from == right.from then
            if left.to == right.to then
                return tostring(left.type) < tostring(right.type)
            end
            return left.to < right.to
        end
        return left.from < right.from
    end)

    local tooltip_lines = {}
    local tooltip_objects = {}
    for _, module_edge in ipairs(edge.module_edges) do
        local text = module_edge.text .. " (" .. tostring(1) .. ")"
        tooltip_lines[#tooltip_lines + 1] = text
        tooltip_objects[#tooltip_objects + 1] = {
            text = text,
            cycle = module_edge.cycle == true,
            type = module_edge.type,
        }
    end
    edge.tooltip_lines = tooltip_lines
    edge.tooltip = tooltip_objects
    edge.arrowhead = edge.type == "abstract" and "closed-triangle" or "standard"
end

local function _build_edge_maps(architecture, scoped_modules, module_node_map, module_feedback)
    local internal_entries = {}
    local cycle_entries = {}
    local outgoing_by_node = {}
    local incoming_by_node = {}

    for _, edge in ipairs(architecture.classified_edges or {}) do
        local from_in = scoped_modules[edge.from] ~= nil
        local to_in = scoped_modules[edge.to] ~= nil
        if from_in or to_in then
            local from_node = from_in and module_node_map[edge.from] or nil
            local to_node = to_in and module_node_map[edge.to] or nil
            local text = _stripped_module_name(edge.from) .. " -> " .. _stripped_module_name(edge.to)
            local cycle = module_feedback[edge.from] == true or module_feedback[edge.to] == true

            if from_node ~= nil and to_node ~= nil and from_node ~= to_node then
                local entry = {
                    from = from_node,
                    to = to_node,
                    module_from = edge.from,
                    module_to = edge.to,
                    type = edge.type,
                    cycle = cycle,
                    text = text,
                }
                internal_entries[#internal_entries + 1] = entry
                if edge.type ~= "abstract" then
                    cycle_entries[#cycle_entries + 1] = entry
                end
            end

            if from_node ~= nil then
                outgoing_by_node[from_node] = outgoing_by_node[from_node] or {}
                outgoing_by_node[from_node][#outgoing_by_node[from_node] + 1] = {
                    direction = "outgoing",
                    from = edge.from,
                    to = edge.to,
                    text = text .. " (1)",
                    type = edge.type,
                    cycle = cycle,
                }
            end

            if to_node ~= nil then
                incoming_by_node[to_node] = incoming_by_node[to_node] or {}
                incoming_by_node[to_node][#incoming_by_node[to_node] + 1] = {
                    direction = "incoming",
                    from = edge.from,
                    to = edge.to,
                    text = text .. " (1)",
                    type = edge.type,
                    cycle = cycle,
                }
            end
        end
    end

    local pair_map = _build_pair_map(internal_entries)
    local cycle_pair_map = _build_pair_map(cycle_entries)
    local classified_edges = {}
    local cycle_edge_list = {}
    for _, edge in common.sorted_pairs(pair_map) do
        _append_sorted_entries(edge)
        classified_edges[#classified_edges + 1] = edge
    end
    for _, edge in common.sorted_pairs(cycle_pair_map) do
        cycle_edge_list[#cycle_edge_list + 1] = {
            from = edge.from,
            to = edge.to,
        }
    end
    table.sort(classified_edges, function(left, right)
        if left.from == right.from then
            return left.to < right.to
        end
        return left.from < right.from
    end)

    for _, list in pairs(outgoing_by_node) do
        table.sort(list, function(left, right)
            if left.to == right.to then
                return left.from < right.from
            end
            return left.to < right.to
        end)
    end
    for _, list in pairs(incoming_by_node) do
        table.sort(list, function(left, right)
            if left.from == right.from then
                return left.to < right.to
            end
            return left.from < right.from
        end)
    end

    return {
        classified_edges = classified_edges,
        cycle_edges = cycle_edge_list,
        display_edges = common.copy_array(classified_edges),
        outgoing_by_node = outgoing_by_node,
        incoming_by_node = incoming_by_node,
    }
end

local function _build_child_feedback_set(child_layout)
    local child_feedback_set = {}
    for _, edge in ipairs((child_layout and child_layout.feedback_edges) or {}) do
        child_feedback_set[common.edge_key(edge.from, edge.to)] = true
    end
    return child_feedback_set
end

local function _subtree_cycle_map(child_info, prefix_segments, nested_views)
    local result = {}
    for child_name, info in common.sorted_pairs(child_info) do
        local key = child_name
        local has_cycle = false
        if info.exact_module ~= nil and next(info.descendant_modules) == nil then
            has_cycle = false
        else
            local child_prefix = common.copy_array(prefix_segments)
            child_prefix[#child_prefix + 1] = child_name
            local child_view = nested_views[common.view_key(child_prefix)]
            if child_view ~= nil then
                for _, node in ipairs(child_view.nodes or {}) do
                    if node.cycle == true or node.has_cycle_subtree == true then
                        has_cycle = true
                        break
                    end
                end
                if not has_cycle then
                    for _, edge in ipairs(child_view.display_edges or {}) do
                        if edge.cycle == true then
                            has_cycle = true
                            break
                        end
                    end
                end
            end
        end
        result[key] = has_cycle
    end
    return result
end

local function _build_view(architecture, prefix_segments)
    local scoped_modules = _collect_scoped_modules(architecture.modules, prefix_segments)
    local module_child_map = _module_to_child(scoped_modules, prefix_segments)
    local child_info = _child_to_info(scoped_modules, prefix_segments, module_child_map)
    local module_node_map = _module_to_node(child_info)
    local node_modules = _node_to_modules(module_node_map)
    local child_nodes = common.sorted_keys(node_modules)
    local child_graph = {
        nodes = child_nodes,
        edges = {},
    }
    local child_layout = layers.assign_layers({
        nodes = child_nodes,
        edges = {},
    })
    local node_layer_map = {}
    local module_feedback = _module_feedback_set(architecture.layout)
    local display_labels = {}
    local full_names = {}
    local node_items = {}

    local edge_maps = _build_edge_maps(architecture, scoped_modules, module_node_map, module_feedback)
    for _, edge in ipairs(edge_maps.cycle_edges or {}) do
        child_graph.edges[#child_graph.edges + 1] = {
            from = edge.from,
            to = edge.to,
        }
    end
    child_layout = layers.assign_layers(child_graph)
    local child_feedback_set = _build_child_feedback_set(child_layout)
    node_layer_map = child_layout.module_to_layer or {}

    for node_id in common.sorted_pairs(node_modules) do
        display_labels[node_id] = _display_label_for_node(node_id, child_info, architecture.modules)
        full_names[node_id] = _full_name_for_node(node_id, prefix_segments, child_info, architecture.modules)
    end

    local node_rects, layer_items = layout_renderer.build_node_rects(child_layout, display_labels, full_names)

    local nested_views = {}
    for child_name, info in common.sorted_pairs(child_info) do
        if next(info.descendant_modules) ~= nil then
            local child_prefix = common.copy_array(prefix_segments)
            child_prefix[#child_prefix + 1] = child_name
            local child_views = _build_view(architecture, child_prefix)
            for view_key, view in pairs(child_views) do
                nested_views[view_key] = view
            end
        end
    end

    local subtree_cycles = _subtree_cycle_map(child_info, prefix_segments, nested_views)

    for node_id, module_ids in common.sorted_pairs(node_modules) do
        local child_name = _node_child_name(node_id)
        local info = child_info[child_name]
        local exact_module = info and info.exact_module or nil
        local has_descendants = info ~= nil and next(info.descendant_modules) ~= nil or false
        local leaf = exact_module ~= nil and not has_descendants
        local child_prefix = common.copy_array(prefix_segments)
        child_prefix[#child_prefix + 1] = child_name
        local source_file_name = exact_module and
        common.source_filename_base(architecture.modules[exact_module] and architecture.modules[exact_module]
        .source_path or nil) or nil
        local item = {
            id = node_id,
            label = display_labels[node_id],
            display_label = display_labels[node_id],
            full_name = full_names[node_id],
            child_name = child_name,
            source_file_name = source_file_name,
            layer = node_layer_map[node_id] or 0,
            leaf = leaf,
            drillable = has_descendants,
            component = _node_component(architecture.modules, module_ids),
            abstract = _node_abstract(architecture.modules, module_ids),
            has_cycle_subtree = false,
            cycle = false,
            module_ids = common.copy_array(module_ids),
            rect = node_rects[node_id],
            view_key = has_descendants and common.view_key(child_prefix) or nil,
            incoming_dependencies = common.copy_array(edge_maps.incoming_by_node[node_id] or {}),
            outgoing_dependencies = common.copy_array(edge_maps.outgoing_by_node[node_id] or {}),
        }

        if child_feedback_set[common.edge_key(node_id, node_id)] == true then
            item.cycle = true
            item.has_cycle_subtree = true
        end

        if has_descendants and subtree_cycles[child_name] == true then
            item.has_cycle_subtree = true
            item.cycle = true
        end

        if exact_module ~= nil then
            local module_info = architecture.modules[exact_module]
            item.module_id = exact_module
            item.source_path = module_info.source_path
            item.source_text = module_info.source_text
            item.internal_requires = common.copy_array(module_info.internal_requires)
            item.external_requires = common.copy_array(module_info.external_requires)
            if module_feedback[exact_module] == true then
                item.cycle = true
                item.has_cycle_subtree = true
            end
        end

        node_items[#node_items + 1] = item
    end

    table.sort(node_items, function(left, right)
        if left.layer == right.layer then
            return left.display_label < right.display_label
        end
        return left.layer < right.layer
    end)

    local display_edges = layout_renderer.decorate_display_edges(edge_maps.display_edges, node_rects, node_layer_map,
        child_feedback_set)
    local indicators = layout_renderer.build_indicators(node_items)
    local canvas = layout_renderer.canvas_size(layer_items)

    local views = {
        [common.view_key(prefix_segments)] = {
            key = common.view_key(prefix_segments),
            label = #prefix_segments == 0 and "src" or prefix_segments[#prefix_segments],
            title = #prefix_segments == 0 and "src" or prefix_segments[#prefix_segments],
            breadcrumb = _build_breadcrumb(prefix_segments),
            canvas = canvas,
            layers = layer_items,
            nodes = node_items,
            edges = display_edges,
            classified_edges = edge_maps.classified_edges,
            display_edges = display_edges,
            indicators = indicators,
        },
    }

    for view_key, view in pairs(nested_views) do
        views[view_key] = view
    end

    return views
end

function projection.build_views(architecture)
    return _build_view(architecture, {})
end

function projection.collect_projection_cycles(views)
    local result = {}
    for _, view_key in ipairs(common.sorted_keys(views or {})) do
        local view = views[view_key]
        local feedback_edges = {}
        for _, edge in ipairs(view.display_edges or {}) do
            if edge.feedback == true then
                local module_edges = {}
                for _, me in ipairs(edge.module_edges or {}) do
                    module_edges[#module_edges + 1] = {
                        from = me.from,
                        to = me.to,
                        type = me.type,
                    }
                end
                feedback_edges[#feedback_edges + 1] = {
                    from = edge.from,
                    to = edge.to,
                    module_edges = module_edges,
                }
            end
        end
        if #feedback_edges > 0 then
            result[#result + 1] = {
                view = view_key,
                feedback_edges = feedback_edges,
            }
        end
    end
    return result
end

return projection
