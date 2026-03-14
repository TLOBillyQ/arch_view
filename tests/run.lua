require("tests.bootstrap")

local test_modules = {
  "tests.test_api",
  "tests.test_cli",
  "tests.test_go_bridge",
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
