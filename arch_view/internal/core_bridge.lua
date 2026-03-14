local common = require("arch_view.runtime.common")
local paths = require("arch_view.internal.paths")
local fs = require("arch_view.runtime.fs")
local json_reader = require("arch_view.runtime.json_reader")
local json_writer = require("arch_view.runtime.json_writer")

local core_bridge = {}
local _host_env_cache = nil

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function _binary_name()
  if common.is_windows() then
    return "arch-view-core.exe"
  end
  return "arch-view-core"
end

local function _direct_config_available(request)
  return request ~= nil and request.project_root ~= nil and request.project_root ~= ""
    and request.config_path ~= nil and request.config_path ~= ""
end

local function _host_env()
  if _host_env_cache ~= nil then
    return _host_env_cache
  end

  if common.is_windows() then
    local arch = string.lower(tostring(os.getenv("PROCESSOR_ARCHITECTURE") or "amd64"))
    if arch == "x86_64" then
      arch = "amd64"
    end
    _host_env_cache = {
      goos = "windows",
      goarch = arch,
    }
    return _host_env_cache
  end

  local result = fs.run_command({ "uname", "-m" })
  if not result.ok then
    return nil, result.output
  end
  local arch = _trim(result.output)
  if arch == "x86_64" then
    arch = "amd64"
  elseif arch == "aarch64" then
    arch = "arm64"
  end

  _host_env_cache = {
    goos = common.is_macos() and "darwin" or "linux",
    goarch = arch,
  }
  return _host_env_cache
end

local function _toolchain_root(project_root, opts)
  if opts.toolchain_root ~= nil then
    return fs.resolve_path(fs.current_dir(), opts.toolchain_root)
  end
  return paths.default_toolchain_root(project_root)
end

local function _binary_path(project_root, opts)
  local env, err = _host_env()
  if env == nil then
    return nil, err
  end
  return fs.join_path(
    fs.join_path(_toolchain_root(project_root, opts), env.goos .. "-" .. env.goarch),
    _binary_name()
  )
end

local function _has_newer_source(binary_path, package_root)
  if common.is_windows() then
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
    return latest > (fs.path_mtime(binary_path) or 0)
  end

  local command = table.concat({
    "find ",
    common.shell_quote(package_root),
    " \\( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' \\) -type f -newer ",
    common.shell_quote(binary_path),
    " | head -n 1",
  })
  local result = fs.run_command(command)
  if not result.ok then
    return nil, result.output
  end
  return _trim(result.output) ~= ""
end

local function _should_rebuild(binary_path, package_root)
  if not fs.path_exists(binary_path) then
    return true
  end
  local changed, err = _has_newer_source(binary_path, package_root)
  if changed == nil then
    return nil, err
  end
  return changed
end

function core_bridge.ensure_binary(project_root, opts)
  opts = opts or {}
  local package_root = opts.package_root or paths.package_root()
  local binary_path, path_err = _binary_path(project_root, {
    package_root = package_root,
    toolchain_root = opts.toolchain_root,
  })
  if binary_path == nil then
    return nil, path_err
  end

  local should_rebuild, rebuild_err = _should_rebuild(binary_path, package_root)
  if should_rebuild == nil then
    return nil, rebuild_err
  end
  if not should_rebuild then
    return binary_path
  end

  local ok, err = fs.ensure_parent_dir(binary_path)
  if not ok then
    return nil, err
  end

  local build = fs.run_command({
    "go", "build", "-o", binary_path, "./cmd/arch-view-core",
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

function core_bridge.analyze(request, opts)
  opts = opts or {}
  local binary_path, err = core_bridge.ensure_binary(request.project_root, opts)
  if binary_path == nil then
    return nil, err
  end

  local output_path = fs.make_temp_path("archview_response", ".lua")

  if _direct_config_available(request) then
    local result = fs.run_command({
      binary_path,
      "analyze",
      "--project-root",
      request.project_root,
      "--config",
      request.config_path,
      "--format",
      "lua",
      "--out",
      output_path,
    }, {
      cwd = request.project_root,
    })

    if not result.ok then
      return nil, _text(
        "Go 分析引擎运行失败:\n" .. tostring(result.output),
        "Go analysis engine failed:\n" .. tostring(result.output)
      )
    end

    local chunk, load_err = loadfile(output_path)
    fs.remove_path(output_path)
    if chunk == nil then
      return nil, load_err
    end
    local ok, decoded = pcall(chunk)
    if not ok then
      return nil, decoded
    end
    return decoded, binary_path
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
    "--format",
    "lua",
    "--out",
    output_path,
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

  local chunk, load_err = loadfile(output_path)
  fs.remove_path(output_path)
  if chunk == nil then
    return nil, load_err
  end
  local ok, decoded = pcall(chunk)
  if not ok then
    return nil, decoded
  end
  return decoded, binary_path
end

function core_bridge.write_architecture_json(request, out_path, opts)
  opts = opts or {}
  local binary_path, err = core_bridge.ensure_binary(request.project_root, opts)
  if binary_path == nil then
    return nil, err
  end

  if _direct_config_available(request) then
    local result = fs.run_command({
      binary_path,
      "analyze",
      "--project-root",
      request.project_root,
      "--config",
      request.config_path,
      "--out",
      out_path,
    }, {
      cwd = request.project_root,
    })

    if not result.ok then
      return nil, _text(
        "Go 分析引擎导出失败:\n" .. tostring(result.output),
        "Go analysis engine export failed:\n" .. tostring(result.output)
      )
    end

    return out_path, binary_path
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
    "--out",
    out_path,
  }, {
    cwd = request.project_root,
  })
  fs.remove_path(request_path)

  if not result.ok then
    return nil, _text(
      "Go 分析引擎导出失败:\n" .. tostring(result.output),
      "Go analysis engine export failed:\n" .. tostring(result.output)
    )
  end

  return out_path, binary_path
end

function core_bridge.check(request, opts)
  opts = opts or {}
  local binary_path, err = core_bridge.ensure_binary(request.project_root, opts)
  if binary_path == nil then
    return nil, err
  end

  if _direct_config_available(request) then
    local result = fs.run_command({
      binary_path,
      "check",
      "--project-root",
      request.project_root,
      "--config",
      request.config_path,
    }, {
      cwd = request.project_root,
    })

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

function core_bridge.export_viewer(request, out_dir, asset_root, opts)
  opts = opts or {}
  local binary_path, err = core_bridge.ensure_binary(request.project_root, opts)
  if binary_path == nil then
    return nil, err
  end

  local resolved_out_dir = fs.resolve_path(fs.current_dir(), out_dir)
  local resolved_asset_root = fs.resolve_path(fs.current_dir(), asset_root)

  local cmd = {
    binary_path,
    "export-viewer",
    "--out-dir",
    resolved_out_dir,
    "--asset-root",
    resolved_asset_root,
  }

  local request_path = nil
  if _direct_config_available(request) then
    table.insert(cmd, "--project-root")
    table.insert(cmd, request.project_root)
    table.insert(cmd, "--config")
    table.insert(cmd, request.config_path)
  else
    request_path = fs.make_temp_path("archview_request", ".json")
    local write_ok, write_err = fs.write_file(request_path, json_writer.encode(request))
    if not write_ok then
      return nil, write_err
    end
    table.insert(cmd, "--request")
    table.insert(cmd, request_path)
  end

  local result = fs.run_command(cmd, {
    cwd = request.project_root,
  })

  if request_path ~= nil then
    fs.remove_path(request_path)
  end

  if not result.ok then
    return nil, _text(
      "Go 分析引擎导出 viewer 失败:\n" .. tostring(result.output),
      "Go analysis engine export viewer failed:\n" .. tostring(result.output)
    )
  end

  local ok, decoded = pcall(json_reader.decode, result.output)
  if not ok then
    return nil, decoded
  end
  return decoded, binary_path
end

return core_bridge
