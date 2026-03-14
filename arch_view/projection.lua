-- DEPRECATED: arch_view.projection is deprecated and will be removed in a future version.
-- Use arch_view.app.go_bridge or arch_view.app.service instead.

local function _deprecated()
    error(
        "arch_view.projection is deprecated and has been removed. " ..
        "Use arch_view.app.go_bridge or arch_view.app.service instead."
    )
end

return {
    build_views = _deprecated,
    collect_projection_cycles = _deprecated,
}
