-- DEPRECATED: arch_view.source_scan is deprecated and will be removed in a future version.
-- Use arch_view.app.go_bridge or arch_view.app.service instead.
--
-- Migration guide:
--   Old: local source_scan = require("arch_view.source_scan")
--        local result = source_scan.scan(config)
--
--   New: local go_bridge = require("arch_view.app.go_bridge")
--        local architecture, err = go_bridge.analyze({
--            project_root = project_root,
--            config_path = config_path,
--            config = config,
--        })

local function _deprecated()
    error(
        "arch_view.source_scan is deprecated and has been removed. " ..
        "Use arch_view.app.go_bridge or arch_view.app.service instead. " ..
        "See the module comment for migration guide."
    )
end

return {
    scan = _deprecated,
    scan_with_options = _deprecated,
}
