local common = require("arch_view.common")

local fs = {}

function fs.normalize_path(path)
  return common.normalize_path(path)
end

function fs.current_dir()
  return common.current_dir()
end

function fs.join_path(base, child)
  return common.join_path(base, child)
end

function fs.parent_dir(path)
  return common.parent_dir(path)
end

function fs.resolve_path(base, path)
  return common.resolve_path(base, path)
end

function fs.ensure_dir(path)
  return common.ensure_dir(path)
end

function fs.ensure_parent_dir(path)
  return common.ensure_parent_dir(path)
end

function fs.read_file(path)
  return common.read_file(path)
end

function fs.write_file(path, content)
  return common.write_file(path, content)
end

function fs.path_exists(path)
  return common.path_exists(path)
end

function fs.open_path(path)
  return common.open_path(path)
end

function fs.copy_tree(source_path, target_path)
  return common.copy_tree(source_path, target_path)
end

return fs
