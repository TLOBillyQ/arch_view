-- DEPRECATED: arch_view.layers is deprecated and will be removed in a future version.
-- Use arch_view.app.go_bridge or arch_view.app.service instead.

local function _deprecated()
    error(
        "arch_view.layers is deprecated and has been removed. " ..
        "Use arch_view.app.go_bridge or arch_view.app.service instead."
    )
end

return {
    assign_layers = _deprecated,
    feedback_edge_set = _deprecated,
    detect_cycles = _deprecated,
}
