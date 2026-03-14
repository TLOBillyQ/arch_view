local config_loader = require("arch_view.app.config")
local engine = require("arch_view.app.engine")
local go_bridge = require("arch_view.app.go_bridge")
local paths = require("arch_view.app.paths")
local common = require("arch_view.common")
local fs = require("arch_view.support.fs")
local json_reader = require("arch_view.json_reader")
local json_writer = require("arch_view.json_writer")

local service = {}

local function _text(zh, en)
    return common.bilingual(zh, en)
end

local function _write_file(path, content)
    local ok, err = fs.write_file(path, content)
    if not ok then
        return nil, err
    end
    return true
end

local function _read_architecture_json_text(path)
    local content, err = fs.read_file(path)
    if content == nil then
        return nil, err
    end
    return tostring(content):match("^%s*(.-)%s*$")
end

local function _resolve_context(opts)
    opts = opts or {}
    local resolved, err = config_loader.resolve(opts)
    if resolved == nil then
        return nil, err
    end

    resolved.engine = opts.engine or "auto"
    resolved.package_root = opts.package_root or paths.package_root()
    resolved.toolchain_root = opts.toolchain_root and fs.resolve_path(fs.current_dir(), opts.toolchain_root) or nil
    return resolved
end

local function _analyze_with_context(resolved)
    local architecture, used_engine, extra = engine.analyze(resolved)
    if architecture == nil then
        return nil, used_engine
    end
    resolved.architecture = architecture
    resolved.engine_used = used_engine
    resolved.engine_binary = extra
    return resolved
end

function service.load_config(path)
    return config_loader.load(path)
end

function service.analyze(opts)
    local resolved, err = _resolve_context(opts)
    if resolved == nil then
        return nil, err
    end

    resolved, err = _analyze_with_context(resolved)
    if resolved == nil then
        return nil, err
    end

    return resolved.architecture
end

function service.check(opts)
    opts = opts or {}
    local resolved, err = _resolve_context(opts)
    if resolved == nil then
        return nil, err
    end

    local check_result, used_engine = engine.check(resolved)
    if check_result == nil then
        return nil, used_engine
    end

    return {
        check = check_result,
        engine = used_engine,
        project_root = resolved.project_root,
        config_path = resolved.config_path,
        engine_binary = resolved.engine_binary,
    }
end

function service.write_scan(opts)
    opts = opts or {}
    local out_path = opts.out_path and fs.resolve_path(fs.current_dir(), opts.out_path) or nil
    if out_path == nil then
        return nil, _text(
            "scan 命令需要输出文件路径",
            "scan command requires an output file path"
        )
    end

    if opts.architecture ~= nil then
        local ok, parent_err = fs.ensure_parent_dir(out_path)
        if not ok then
            return nil, parent_err
        end
        local write_ok, write_err = _write_file(out_path, json_writer.encode(opts.architecture))
        if not write_ok then
            return nil, write_err
        end

        local project_root = opts.project_root and fs.resolve_path(fs.current_dir(), opts.project_root) or nil
        return {
            out_path = out_path,
            architecture = opts.architecture,
            project_root = project_root,
            config_path = opts.config_path and fs.resolve_path(fs.current_dir(), opts.config_path) or nil,
            engine = opts.engine or "go",
            engine_binary = nil,
        }
    end

    local resolved, err = _resolve_context(opts)
    if resolved == nil then
        return nil, err
    end

    local architecture, used_engine, extra = engine.write_json(resolved, out_path)
    if used_engine ~= "go" then
        return nil, used_engine
    end

    resolved.engine_used = used_engine
    resolved.engine_binary = extra
    resolved.architecture = architecture

    return {
        out_path = out_path,
        architecture = architecture,
        project_root = resolved.project_root,
        config_path = resolved.config_path,
        engine = resolved.engine_used,
        engine_binary = resolved.engine_binary,
    }
end

function service.export_viewer(opts)
    opts = opts or {}
    local architecture = opts.architecture
    local architecture_json_text = nil
    local resolved = nil
    local err = nil

    local project_root = opts.project_root
    if project_root == nil then
        project_root = fs.resolve_path(fs.current_dir(), fs.current_dir())
    else
        project_root = fs.resolve_path(fs.current_dir(), project_root)
    end

    local out_dir = opts.out_dir and fs.resolve_path(fs.current_dir(), opts.out_dir)
        or paths.default_viewer_out_dir(project_root)
    local asset_root = opts.asset_root and fs.resolve_path(fs.current_dir(), opts.asset_root)
        or paths.default_asset_root()

    -- 如果有现成的 architecture 数据或输入 JSON，使用 Lua 快速路径
    if architecture ~= nil or opts.in_json ~= nil then
        local ok, mkdir_err = fs.ensure_dir(out_dir)
        if not ok then
            return nil, mkdir_err
        end

        local copy_ok, copy_err = fs.copy_tree(asset_root, out_dir)
        if not copy_ok then
            return nil, copy_err
        end

        local arch_json_path = fs.join_path(out_dir, "architecture.json")

        if architecture ~= nil then
            architecture_json_text = json_writer.encode(architecture)
            local write_ok, write_err = _write_file(arch_json_path, architecture_json_text)
            if not write_ok then
                return nil, write_err
            end
        else
            architecture_json_text, err = _read_architecture_json_text(fs.resolve_path(fs.current_dir(), opts.in_json))
            if architecture_json_text == nil then
                return nil, err
            end
            local write_ok, write_err = _write_file(arch_json_path, architecture_json_text)
            if not write_ok then
                return nil, write_err
            end
        end

        local payload_ok, payload_err = _write_file(
            fs.join_path(out_dir, "architecture_data.js"),
            "window.ARCH_VIEW_DATA = " .. architecture_json_text .. ";\n"
        )
        if not payload_ok then
            return nil, payload_err
        end

        local index_path = fs.join_path(out_dir, "index.html")
        if opts.open then
            local open_fn = opts.open_path or fs.open_path
            local opened, open_err = open_fn(index_path)
            if not opened then
                return nil, open_err
            end
        end

        return {
            out_dir = out_dir,
            index_path = index_path,
            architecture = architecture,
            asset_root = asset_root,
            project_root = project_root,
            engine = opts.engine or "go",
            engine_binary = nil,
        }
    end

    -- 否则使用 Go 完整导出流程
    resolved, err = _resolve_context(opts)
    if resolved == nil then
        return nil, err
    end

    local result, binary_path = go_bridge.export_viewer({
        project_root = resolved.project_root,
        config_path = resolved.config_path,
        config = resolved.config,
    }, out_dir, asset_root, {
        package_root = resolved.package_root,
        toolchain_root = resolved.toolchain_root,
    })

    if result == nil then
        return nil, binary_path
    end

    local index_path = result.index_path
    if opts.open then
        local open_fn = opts.open_path or fs.open_path
        local opened, open_err = open_fn(index_path)
        if not opened then
            return nil, open_err
        end
    end

    return {
        out_dir = result.out_dir,
        index_path = index_path,
        architecture = nil, -- Go 导出流程不返回 architecture 数据
        asset_root = asset_root,
        project_root = project_root,
        engine = "go",
        engine_binary = binary_path,
    }
end

return service
