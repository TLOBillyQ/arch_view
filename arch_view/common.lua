local script_common = require("arch_view.script_common")

local common = {}

local _tointeger = math and math.tointeger
local _numeric_type_names = {
  number = true,
  integer = true,
  fixed = true,
}

local function _is_numeric_type_name(value_type)
  return _numeric_type_names[value_type] == true
end

local function _to_integer_safe(value)
  if value == nil then
    return nil
  end
  if _tointeger then
    local ok, as_int = pcall(_tointeger, value)
    if ok and as_int ~= nil then
      return as_int
    end
  end
  if math and math.floor then
    local ok, floored = pcall(math.floor, value)
    if ok and floored ~= nil then
      return floored
    end
  end
  return nil
end

local function _parse_integer_string(value)
  if value == nil then
    return nil
  end
  if not string.match(value, "^-?%d+$") then
    return nil
  end
  local len = #value
  if len == 0 then
    return nil
  end
  local index = 1
  local sign = 1
  if string.sub(value, 1, 1) == "-" then
    sign = -1
    index = 2
    if index > len then
      return nil
    end
  end
  local num = 0
  for cursor = index, len do
    local byte = string.byte(value, cursor)
    local digit = byte - 48
    if digit < 0 or digit > 9 then
      return nil
    end
    num = num * 10 + digit
  end
  if _tointeger then
    return _tointeger(sign * num)
  end
  return sign * num
end

local function _sorted_pairs(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local index = 0
  return function()
    index = index + 1
    local key = keys[index]
    if key == nil then
      return nil
    end
    return key, map[key]
  end
end

function common.sorted_pairs(map)
  return _sorted_pairs(map)
end

function common.bilingual(zh, en)
  return script_common.bilingual(zh, en)
end

function common.is_windows()
  return script_common.is_windows()
end

function common.is_macos()
  return script_common.is_macos()
end

function common.normalize_path(path)
  return script_common.normalize_path(path)
end

function common.current_dir()
  return script_common.current_dir()
end

function common.join_path(base, child)
  return script_common.join_path(base, child)
end

function common.parent_dir(path)
  return script_common.parent_dir(path)
end

function common.split(text, delimiter)
  return script_common.split(text, delimiter)
end

function common.join(parts, delimiter)
  return script_common.join(parts, delimiter)
end

function common.copy_array(values)
  local copied = {}
  for index, value in ipairs(values or {}) do
    copied[index] = value
  end
  return copied
end

function common.starts_with_segments(parts, prefix)
  if #prefix > #parts then
    return false
  end
  for index = 1, #prefix do
    if parts[index] ~= prefix[index] then
      return false
    end
  end
  return true
end

function common.simplify_path(path)
  local normalized = common.normalize_path(path)
  local prefix = ""
  local remainder = normalized
  if normalized:match("^%a:/") then
    prefix = normalized:sub(1, 2)
    remainder = normalized:sub(4)
  elseif normalized:match("^/[A-Za-z]/") then
    prefix = normalized:sub(2, 3)
    remainder = normalized:sub(5)
  elseif normalized:sub(1, 1) == "/" then
    prefix = "/"
    remainder = normalized:sub(2)
  end
  local parts = {}
  for _, segment in ipairs(common.split(remainder, "/")) do
    if segment ~= "" and segment ~= "." then
      if segment == ".." then
        if #parts > 0 and parts[#parts] ~= ".." then
          parts[#parts] = nil
        elseif prefix == "" then
          parts[#parts + 1] = segment
        end
      else
        parts[#parts + 1] = segment
      end
    end
  end
  local simplified = table.concat(parts, "/")
  if prefix == "" then
    return simplified
  end
  if simplified == "" then
    return prefix == "/" and "/" or (prefix .. "/")
  end
  if prefix == "/" then
    return "/" .. simplified
  end
  return prefix .. "/" .. simplified
end

function common.is_absolute_path(path)
  local normalized = common.normalize_path(path)
  if normalized:match("^%a:/") then
    return true
  end
  if normalized:match("^/[A-Za-z]/") then
    return true
  end
  if normalized:match("^//") then
    return true
  end
  return normalized:sub(1, 1) == "/"
end

function common.resolve_path(base, path)
  local normalized_path = common.normalize_path(path)
  if normalized_path == "" then
    return common.simplify_path(base)
  end
  if common.is_windows() and normalized_path:sub(1, 1) == "/" then
    if normalized_path:match("^/[A-Za-z]/") then
      return common.simplify_path(normalized_path:sub(2, 2) .. ":" .. normalized_path:sub(3))
    end
    local tmpdir = common.system_tmp_dir()
    if normalized_path == "/tmp" or normalized_path:match("^/tmp/") then
      local suffix = normalized_path:sub(5)
      return common.simplify_path(common.join_path(tmpdir, suffix))
    end
  end
  if common.is_absolute_path(normalized_path) then
    return common.simplify_path(normalized_path)
  end
  return common.simplify_path(common.join_path(base or "", normalized_path))
end

function common.system_tmp_dir()
  return script_common.system_tmp_dir()
end

function common.ensure_dir(path)
  return script_common.ensure_dir(path)
end

function common.ensure_parent_dir(path)
  return script_common.ensure_parent_dir(path)
end

function common.read_file(path)
  return script_common.read_file(path)
end

function common.write_file(path, content)
  return script_common.write_file(path, content)
end

function common.append_file(path, content)
  return script_common.append_file(path, content)
end

function common.collect_files(root, extension)
  return script_common.collect_files(root, extension)
end

function common.collect_lua_files(root)
  return script_common.collect_lua_files(root)
end

function common.path_exists(path)
  return script_common.path_exists(path)
end

function common.path_mtime(path)
  return script_common.path_mtime(path)
end

function common.remove_path(path)
  return script_common.remove_path(path)
end

function common.copy_tree(source_path, target_path)
  return script_common.copy_tree(source_path, target_path)
end

function common.run_command(command, options)
  return script_common.run_command(command, options)
end

function common.make_temp_path(prefix, suffix)
  return script_common.make_temp_path(prefix, suffix)
end

function common.command_exists(name)
  return script_common.command_exists(name)
end

function common.open_path(path)
  return script_common.open_path(path)
end

function common.build_open_command(path)
  return script_common.build_open_command(path)
end

function common.shell_quote(path)
  return script_common.shell_quote(path)
end

function common.sorted_keys(map)
  return script_common.sorted_keys(map)
end

function common.list_to_set(values)
  local set = {}
  for _, value in ipairs(values or {}) do
    set[value] = true
  end
  return set
end

function common.edge_key(from_id, to_id)
  return tostring(from_id) .. "\n" .. tostring(to_id)
end

function common.sorted_edges(edge_map)
  local edges = {}
  for _, edge in _sorted_pairs(edge_map or {}) do
    edges[#edges + 1] = edge
  end
  table.sort(edges, function(left, right)
    if left.from == right.from then
      return tostring(left.to) < tostring(right.to)
    end
    return tostring(left.from) < tostring(right.from)
  end)
  return edges
end

function common.is_numeric(value)
  local value_type = type(value)
  if value_type == "nil" then
    return false
  end
  if _is_numeric_type_name(value_type) then
    return true
  end
  if value_type == "string" then
    return false
  end
  return _to_integer_safe(value) ~= nil
end

function common.to_integer(value)
  local value_type = type(value)
  if value_type == "string" then
    local parsed = _parse_integer_string(value)
    if parsed ~= nil then
      return parsed
    end
    return nil
  end
  if common.is_numeric(value) then
    local parsed = _to_integer_safe(value)
    if parsed ~= nil then
      return parsed
    end
  end
  if value ~= nil then
    local ok, as_text = pcall(tostring, value)
    if ok and type(as_text) == "string" then
      local parsed = _parse_integer_string(as_text)
      if parsed ~= nil then
        return parsed
      end
    end
  end
  return nil
end

function common.view_key(path_segments)
  if path_segments == nil or #path_segments == 0 then
    return "root"
  end
  return table.concat(path_segments, ".")
end

function common.strip_src_prefix(module_id)
  local text = tostring(module_id or "")
  return (text:gsub("^src%.", ""))
end

function common.source_filename(path)
  local normalized = common.normalize_path(path)
  return normalized:match("([^/]+)$")
end

function common.source_filename_base(path)
  local filename = common.source_filename(path)
  if filename == nil then
    return nil
  end
  return (filename:gsub("%.[^.]+$", ""))
end

return common
