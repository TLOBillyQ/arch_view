local common = require("arch_view.common")

-- DEPRECATED: This Lua module is deprecated. Use the Go core engine via arch_view.app.go_bridge or arch_view.app.service instead.

local source_scan = {}

local function _module_from_path(logical_root, filesystem_root, path)
  local normalized_root = common.normalize_path(logical_root)
  local normalized_filesystem_root = common.normalize_path(filesystem_root)
  local normalized_path = common.normalize_path(path)
  local pattern = "^" .. normalized_filesystem_root:gsub("%.", "%%.") .. "/(.+)%.lua$"
  local module_path = normalized_path:match(pattern)
  if module_path == nil then
    local suffix_pattern = "/" .. normalized_filesystem_root:gsub("%.", "%%.") .. "/(.+)%.lua$"
    module_path = normalized_path:match(suffix_pattern)
  end
  if module_path == nil then
    return nil
  end

  local root_segments = common.split(normalized_root, "/")
  local path_segments = common.split(module_path, "/")
  if path_segments[#path_segments] == "init" then
    path_segments[#path_segments] = nil
  end
  local full_segments = common.copy_array(root_segments)
  for _, segment in ipairs(path_segments) do
    full_segments[#full_segments + 1] = segment
  end

  return {
    root = normalized_root,
    module_id = table.concat(full_segments, "."),
    module_segments = full_segments,
    namespace_segments = path_segments,
    source_path = normalized_path,
  }
end

function source_scan.scan(config)
  return source_scan.scan_with_options(config, nil)
end

function source_scan.scan_with_options(config, opts)
  opts = opts or {}
  local project_root = common.normalize_path(opts.project_root or common.current_dir())
  local modules = {}
  local module_ids = {}

  for _, root in ipairs(config.source_roots or {}) do
    local logical_root = common.normalize_path(root)
    local filesystem_root = common.resolve_path(project_root, root)
    local files, err = common.collect_lua_files(filesystem_root)
    if not files then
      return nil, err
    end

    for _, path in ipairs(files) do
      local resolved = _module_from_path(logical_root, filesystem_root, path)
      if resolved ~= nil then
        local source_text, read_err = common.read_file(path)
        if source_text == nil then
          return nil, read_err
        end
        modules[resolved.module_id] = {
          module_id = resolved.module_id,
          module_segments = resolved.module_segments,
          namespace_segments = resolved.namespace_segments,
          source_path = resolved.source_path,
          source_text = source_text,
          root = resolved.root,
        }
        module_ids[resolved.module_id] = true
      end
    end
  end

  return {
    modules = modules,
    module_ids = module_ids,
    module_list = common.sorted_keys(modules),
    project_root = project_root,
  }
end

return source_scan
