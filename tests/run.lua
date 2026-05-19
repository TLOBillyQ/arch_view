local function is_absolute(path)
  path = tostring(path or "")
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  local prefix = ""
  if path:sub(1, 1) == "/" then
    prefix = "/"
    path = path:sub(2)
  elseif path:match("^%a:/") then
    prefix = path:sub(1, 3)
    path = path:sub(4)
  end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then
        parts[#parts] = nil
      elseif prefix == "" then
        parts[#parts + 1] = part
      end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local joined = table.concat(parts, "/")
  if prefix == "" then
    return joined == "" and "." or joined
  end
  return joined == "" and prefix:gsub("/$", "") or (prefix .. joined)
end

local function current_dir()
  local pwd = os.getenv("PWD")
  if pwd and pwd ~= "" then
    return pwd
  end
  local handle = assert(io.popen("pwd", "r"))
  local output = handle:read("*l")
  handle:close()
  return output
end

local function dirname(path)
  path = normalize(path):gsub("/+$", "")
  return path:match("^(.*)/[^/]+$") or "."
end

local function script_path()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  if not is_absolute(source) then
    source = current_dir() .. "/" .. source
  end
  return normalize(source)
end

local test_root = dirname(script_path())
local project_root = dirname(test_root)

package.path = table.concat({
  project_root .. "/lib/?.lua",
  project_root .. "/lib/?/init.lua",
  project_root .. "/?.lua",
  package.path,
}, ";")

require("tests.bootstrap")

local test_modules = {
  "tests.test_api",
  "tests.test_cli",
}

local failures = {}
local total_tests = 0

for _, module_name in ipairs(test_modules) do
  local ok, suite = pcall(require, module_name)
  if not ok then
    io.stderr:write("Failed to load test module: " .. module_name .. "\n" .. tostring(suite) .. "\n")
    os.exit(1)
  end

  for test_name, test_fn in pairs(suite) do
    if type(test_fn) == "function" and test_name:match("^test_") then
      total_tests = total_tests + 1
      local test_ok, err = xpcall(test_fn, debug.traceback)
      if test_ok then
        io.stdout:write(".")
      else
        io.stdout:write("F")
        failures[#failures + 1] = {
          name = module_name .. "." .. test_name,
          err = err,
        }
      end
    end
  end
end

io.stdout:write("\n")

if #failures > 0 then
  for index, failure in ipairs(failures) do
    io.stderr:write(tostring(index), ") ", tostring(failure.name), "\n", tostring(failure.err), "\n")
  end
  os.exit(1)
end

print("arch_view tests ok (" .. tostring(total_tests) .. ")")
