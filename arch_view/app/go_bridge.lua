local common = require("arch_view.common")
local paths = require("arch_view.app.paths")
local fs = require("arch_view.support.fs")
local json_reader = require("arch_view.json_reader")
local json_writer = require("arch_view.json_writer")

local go_bridge = {}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function _binary_name()
  if common.is_windows() then
    return "archview-core.exe"
  end
  return "archview-core"
end

local function _go_env(cwd)
  local result = fs.run_command({ "go", "env", "GOOS", "GOARCH" }, {
    cwd = cwd,
  })
  if not result.ok then
    return nil, result.output
  end
  local lines = {}
  for line in (result.output .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      lines[#lines + 1] = _trim(line)
    end
  end
  if #lines < 2 then
    return nil, result.output
  end
  return {
    goos = lines[1],
    goarch = lines[2],
  }
end

local function _toolchain_root(project_root, opts)
  if opts.toolchain_root ~= nil then
    return fs.resolve_path(fs.current_dir(), opts.toolchain_root)
  end
  return paths.default_toolchain_root(project_root)
end

local function _binary_path(project_root, opts)
  local env, err = _go_env(opts.package_root)
  if env == nil then
    return nil, err
  end
  return fs.join_path(
    fs.join_path(_toolchain_root(project_root, opts), env.goos .. "-" .. env.goarch),
    _binary_name()
  )
end

local function _latest_source_mtime(package_root)
  local latest = 0
  local files, err = fs.collect_files(package_root, ".go")
  if not files then
    return nil, err
  end
  for _, path in ipairs(files) do
    local mtime = fs.path_mtime(path) or 0
    if mtime > latest then
      latest = mtime
    end
  end
  for _, extra in ipairs({ fs.join_path(package_root, "go.mod"), fs.join_path(package_root, "go.sum") }) do
    if fs.path_exists(extra) then
      local mtime = fs.path_mtime(extra) or 0
      if mtime > latest then
        latest = mtime
      end
    end
  end
  return latest
end

local function _should_rebuild(binary_path, package_root)
  if not fs.path_exists(binary_path) then
    return true
  end
  local binary_mtime = fs.path_mtime(binary_path) or 0
  local source_mtime = _latest_source_mtime(package_root) or 0
  return source_mtime > binary_mtime
end

function go_bridge.ensure_binary(project_root, opts)
  opts = opts or {}
  local package_root = opts.package_root or paths.package_root()
  local binary_path, path_err = _binary_path(project_root, {
    package_root = package_root,
    toolchain_root = opts.toolchain_root,
  })
  if binary_path == nil then
    return nil, path_err
  end

  if not _should_rebuild(binary_path, package_root) then
    return binary_path
  end

  local ok, err = fs.ensure_parent_dir(binary_path)
  if not ok then
    return nil, err
  end

  local build = fs.run_command({
    "go", "build", "-o", binary_path, "./cmd/archview-core",
  }, {
    cwd = package_root,
  })

  if not build.ok then
    return nil, _text(
      "构建 Go 分析引擎失败:\n" .. tostring(build.output),
      "Failed to build Go analysis engine:\n" .. tostring(build.output)
    )
  end

  return binary_path
end

function go_bridge.analyze(request, opts)
  opts = opts or {}
  local binary_path, err = go_bridge.ensure_binary(request.project_root, opts)
  if binary_path == nil then
    return nil, err
  end

  local request_path = fs.make_temp_path("archview_request", ".json")
  local write_ok, write_err = fs.write_file(request_path, json_writer.encode(request))
  if not write_ok then
    return nil, write_err
  end

  local result = fs.run_command({
    binary_path,
    "analyze",
    "--request",
    request_path,
  }, {
    cwd = request.project_root,
  })
  fs.remove_path(request_path)

  if not result.ok then
    return nil, _text(
      "Go 分析引擎运行失败:\n" .. tostring(result.output),
      "Go analysis engine failed:\n" .. tostring(result.output)
    )
  end

  local ok, decoded = pcall(json_reader.decode, result.output)
  if not ok then
    return nil, _text(
      "Go 分析引擎输出无效 JSON",
      "Go analysis engine returned invalid JSON"
    )
  end
  return decoded, binary_path
end

function go_bridge.check(request, opts)
  opts = opts or {}
  local binary_path, err = go_bridge.ensure_binary(request.project_root, opts)
  if binary_path == nil then
    return nil, err
  end

  local request_path = fs.make_temp_path("archview_request", ".json")
  local write_ok, write_err = fs.write_file(request_path, json_writer.encode(request))
  if not write_ok then
    return nil, write_err
  end

  local result = fs.run_command({
    binary_path,
    "check",
    "--request",
    request_path,
  }, {
    cwd = request.project_root,
  })
  fs.remove_path(request_path)

  if not result.ok then
    return nil, _text(
      "Go 分析引擎检查失败:\n" .. tostring(result.output),
      "Go analysis engine check failed:\n" .. tostring(result.output)
    )
  end

  local ok, decoded = pcall(json_reader.decode, result.output)
  if not ok then
    return nil, _text(
      "Go 检查输出无效 JSON",
      "Go check returned invalid JSON"
    )
  end
  return decoded, binary_path
end

return go_bridge
