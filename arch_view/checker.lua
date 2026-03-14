-- DEPRECATED: arch_view.checker is deprecated and will be removed in a future version.
-- Use arch_view.app.go_bridge or arch_view.app.service instead.

local function _deprecated()
    error(
        "arch_view.checker is deprecated and has been removed. " ..
        "Use arch_view.app.go_bridge or arch_view.app.service instead."
    )
end

return {
    run = _deprecated,
    check_forbidden_dependencies = _deprecated,
    check_unclassified_modules = _deprecated,
}
