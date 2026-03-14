local common = require("arch_view.common")

-- DEPRECATED: This Lua module is deprecated. Use the Go core engine via arch_view.app.go_bridge or arch_view.app.service instead.

local dependency_extract = {}

local function _strip_line_comment(line)
  local comment_start = line:find("%-%-")
  if comment_start == nil then
    return line
  end
  return line:sub(1, comment_start - 1)
end

local function _collect_requires_from_line(line, sink)
  local clean_line = _strip_line_comment(line)
  for dep in clean_line:gmatch('require%s*%(%s*"([^"]+)"%s*%)') do
    sink[dep] = true
  end
  for dep in clean_line:gmatch("require%s*%(%s*'([^']+)'%s*%)") do
    sink[dep] = true
  end
  for dep in clean_line:gmatch('require%s+"([^"]+)"') do
    sink[dep] = true
  end
  for dep in clean_line:gmatch("require%s+'([^']+)'") do
    sink[dep] = true
  end
end

local function _for_each_line(text, callback)
  local cursor = 1
  local content = text or ""
  while true do
    local newline_start, newline_end = content:find("\n", cursor, true)
    if newline_start == nil then
      callback(content:sub(cursor))
      break
    end
    callback(content:sub(cursor, newline_start - 1))
    cursor = newline_end + 1
  end
end

local function _forwarding_shim_target(text)
  local normalized = tostring(text or "")
  normalized = normalized:gsub("%-%-[^\n]*", "")
  normalized = normalized:gsub("%s+", " ")
  normalized = normalized:match("^%s*(.-)%s*$") or ""
  return normalized:match('^return require%(%s*"([^"]+)"%s*%)$')
    or normalized:match("^return require%(%s*'([^']+)'%s*%)$")
end

function dependency_extract.build(scan_result)
  local modules = {}
  local edges = {}
  local edge_map = {}

  for _, module_id in ipairs(scan_result.module_list or {}) do
    local source_module = scan_result.modules[module_id]
    local internal_requires = {}
    local external_requires = {}

    if _forwarding_shim_target(source_module.source_text) == nil then
      _for_each_line(source_module.source_text, function(line)
        local line_requires = {}
        _collect_requires_from_line(line, line_requires)
        for dep in pairs(line_requires) do
          if dep ~= module_id then
            if scan_result.module_ids[dep] then
              internal_requires[dep] = true
              edge_map[common.edge_key(module_id, dep)] = {
                from = module_id,
                to = dep,
              }
            else
              external_requires[dep] = true
            end
          end
        end
      end)
    end

    modules[module_id] = {
      module_id = module_id,
      module_segments = source_module.module_segments,
      namespace_segments = source_module.namespace_segments,
      source_path = source_module.source_path,
      source_text = source_module.source_text,
      internal_requires = common.sorted_keys(internal_requires),
      external_requires = common.sorted_keys(external_requires),
      root = source_module.root,
    }
  end

  edges = common.sorted_edges(edge_map)

  return {
    graph = {
      nodes = common.copy_array(scan_result.module_list),
      edges = edges,
    },
    modules = modules,
  }
end

return dependency_extract
