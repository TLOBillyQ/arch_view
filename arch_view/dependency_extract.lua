-- DEPRECATED: arch_view.dependency_extract is deprecated and will be removed in a future version.
-- Use arch_view.app.go_bridge or arch_view.app.service instead.

local function _deprecated()
    error(
        "arch_view.dependency_extract is deprecated and has been removed. " ..
        "Use arch_view.app.go_bridge or arch_view.app.service instead."
    )
end

return {
    build = _deprecated,
    extract_requires = _deprecated,
}
