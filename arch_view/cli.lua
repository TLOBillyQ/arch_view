local build = require("arch_view.build")
local common = require("arch_view.common")
local json_reader = require("arch_view.json_reader")
local json_writer = require("arch_view.json_writer")

local cli = {}

local function _text(zh, en)
    return common.bilingual(zh, en)
end

local function _repo_root(script_dir)
    return common.parent_dir(common.parent_dir(script_dir))
end

local function _load_config(config_path)
    local chunk, err = loadfile(config_path)
    if not chunk then
        error(err)
    end
    local config = chunk()
    if type(config) ~= "table" then
        error(_text(
            "架构配置无效: " .. tostring(config_path),
            "Invalid architecture config: " .. tostring(config_path)
        ))
    end
    return config
end

local function _usage()
    io.write(_text("用法", "Usage") .. ":\n")
    io.write(
    "  " .. _text(
        "<lua> scripts/arch.lua scan --out <file> [--project-root <dir>] [--config <file>]",
        "<lua> scripts/arch.lua scan --out <file> [--project-root <dir>] [--config <file>]"
    ) .. "\n")
    io.write("  " .. _text(
        "<lua> scripts/arch.lua check [--project-root <dir>] [--config <file>]",
        "<lua> scripts/arch.lua check [--project-root <dir>] [--config <file>]"
    ) .. "\n")
    io.write(
    "  " .. _text(
        "<lua> scripts/arch.lua viewer [--out-dir <dir>] [--project-root <dir>] [--config <file>] [--in-json <file>] [--open]",
        "<lua> scripts/arch.lua viewer [--out-dir <dir>] [--project-root <dir>] [--config <file>] [--in-json <file>] [--open]"
    ) .. "\n")
    io.write("  <lua> scripts/arch.lua\n")
end

local function _parse_args(args)
    local options = {
        command = args[1],
        project_root = nil,
        config = nil,
        out = nil,
        out_dir = nil,
        in_json = nil,
        open = false,
    }
    local index = 2
    while index <= #args do
        local token = args[index]
        if token == "--project-root" then
            options.project_root = args[index + 1]
            index = index + 2
        elseif token == "--config" then
            options.config = args[index + 1]
            index = index + 2
        elseif token == "--out" then
            options.out = args[index + 1]
            index = index + 2
        elseif token == "--out-dir" then
            options.out_dir = args[index + 1]
            index = index + 2
        elseif token == "--in-json" then
            options.in_json = args[index + 1]
            index = index + 2
        elseif token == "--open" then
            options.open = true
            index = index + 1
        else
            error(_text(
                "未知参数: " .. tostring(token),
                "Unknown flag: " .. tostring(token)
            ))
        end
    end
    return options
end

local function _resolve_paths(options, env)
    local cwd = common.current_dir()
    local script_dir = common.normalize_path(env.script_dir or ".")
    local default_project_root = common.resolve_path(cwd, env.default_project_root or _repo_root(script_dir))
    local project_root = common.resolve_path(cwd, options.project_root or default_project_root)
    local default_config = common.resolve_path(cwd, env.default_config_path or common.join_path(script_dir, "config.lua"))
    local default_viewer_out_dir = common.join_path(project_root, "tmp/arch_view")
    local config_path = common.resolve_path(cwd, options.config or default_config)
    local out_path = options.out and common.resolve_path(cwd, options.out) or nil
    local out_dir = options.out_dir and common.resolve_path(cwd, options.out_dir)
        or (options.command == "viewer" and default_viewer_out_dir or nil)
    local in_json = options.in_json and common.resolve_path(cwd, options.in_json) or nil
    return {
        script_dir = script_dir,
        project_root = project_root,
        config_path = config_path,
        out_path = out_path,
        out_dir = out_dir,
        in_json = in_json,
    }
end

local function _write_scan_output(out_path, architecture)
    local ok, err = common.ensure_parent_dir(out_path)
    if not ok then
        error(err)
    end
    local write_ok, write_err = common.write_file(out_path, json_writer.encode(architecture))
    if not write_ok then
        error(write_err)
    end
end

local function _copy_viewer_asset(asset_name, paths)
    local source_path = common.join_path(common.join_path(paths.script_dir, "viewer"), asset_name)
    local source_text, err = common.read_file(source_path)
    if source_text == nil then
        error(err)
    end
    local write_ok, write_err = common.write_file(common.join_path(paths.out_dir, asset_name), source_text)
    if not write_ok then
        error(write_err)
    end
end

local function _load_architecture_from_json(path)
    local content, err = common.read_file(path)
    if content == nil then
        error(err)
    end
    return json_reader.decode(content)
end

local function _build_architecture(options, paths)
    if paths.in_json ~= nil then
        return _load_architecture_from_json(paths.in_json)
    end
    local config = _load_config(paths.config_path)
    local architecture, err = build.analyze(config, {
        project_root = paths.project_root,
        config_path = paths.config_path,
    })
    if architecture == nil then
        error(err)
    end
    return architecture
end

local function _run_scan(options, env)
    local paths = _resolve_paths(options, env)
    if paths.out_path == nil then
        error(_text(
            "scan 命令需要 --out <file>",
            "scan command requires --out <file>"
        ))
    end
    local architecture = _build_architecture(options, paths)
    _write_scan_output(paths.out_path, architecture)
    print(_text("arch_view 扫描完成: ", "arch_view scan ok: ") .. paths.out_path)
end

local function _run_check(options, env)
    local paths = _resolve_paths(options, env)
    local architecture = _build_architecture(options, paths)
    if architecture.check and architecture.check.ok then
        print(_text("arch_view 检查通过", "arch_view check ok"))
        return
    end
    io.stderr:write(_text("arch_view 检查失败", "arch_view check failed"), "\n")
    for _, violation in ipairs((architecture.check and architecture.check.violations) or {}) do
        if violation.kind == "forbidden_dependency" then
            io.stderr:write("  ", _text("禁止依赖", "forbidden_dependency"), " [", tostring(violation.rule), "] ", tostring(violation.from), " -> ",
                tostring(violation.to), "\n")
            io.stderr:write("    ", tostring(violation.description), "\n")
        elseif violation.kind == "unclassified_module" then
            io.stderr:write("  ", _text("未分类模块", "unclassified_module"), " ", tostring(violation.module_id), "\n")
        elseif violation.kind == "projection_cycle" then
            io.stderr:write("  ", _text("投影循环", "projection_cycle"), " ", tostring(violation.view), "\n")
            io.stderr:write("    ", tostring(violation.description), "\n")
        else
            io.stderr:write("  ", tostring(violation.kind), " ", table.concat(violation.cycle or {}, ", "), "\n")
            io.stderr:write("    ", tostring(violation.description), "\n")
        end
    end
    os.exit(1)
end

local function _run_viewer(options, env)
    local paths = _resolve_paths(options, env)
    if paths.out_dir == nil then
        error(_text(
            "viewer 命令需要 --out-dir <dir>",
            "viewer command requires --out-dir <dir>"
        ))
    end
    local architecture = _build_architecture(options, paths)
    local ok, mkdir_err = common.ensure_dir(paths.out_dir)
    if not ok then
        error(mkdir_err)
    end
    _copy_viewer_asset("index.html", paths)
    _copy_viewer_asset("script.js", paths)
    _copy_viewer_asset("styles.css", paths)
    _write_scan_output(common.join_path(paths.out_dir, "architecture.json"), architecture)
    local js_payload = "window.ARCH_VIEW_DATA = " .. json_writer.encode(architecture) .. ";\n"
    local write_ok, write_err = common.write_file(common.join_path(paths.out_dir, "architecture_data.js"), js_payload)
    if not write_ok then
        error(write_err)
    end
    if options.open then
        local open_fn = env.open_path or common.open_path
        local opened, open_err = open_fn(common.join_path(paths.out_dir, "index.html"))
        if not opened then
            error(open_err)
        end
    end
    print(_text("arch_view 视图已生成: ", "arch_view viewer ok: ") .. paths.out_dir)
end

function cli.run(args, env)
    env = env or {}
    local options = _parse_args(args or {})
    local command = options.command
    if command == "--help" or command == "-h" then
        _usage()
        return true
    end
    if command == nil then
        options.command = "viewer"
        options.open = true
        command = options.command
    end
    if command == "scan" then
        _run_scan(options, env)
        return true
    end
    if command == "check" then
        _run_check(options, env)
        return true
    end
    if command == "viewer" then
        _run_viewer(options, env)
        return true
    end
    _usage()
    error(_text(
        "未知命令: " .. tostring(command),
        "Unknown command: " .. tostring(command)
    ))
end

return cli
