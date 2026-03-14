require("tests.bootstrap")

local suite = require("tests.arch_view_contract")
local failures = {}

for _, test in ipairs(suite.tests or {}) do
  local ok, err = xpcall(test.run, debug.traceback)
  if ok then
    io.stdout:write(".")
  else
    io.stdout:write("F")
    failures[#failures + 1] = {
      name = test.name,
      err = err,
    }
  end
end

io.stdout:write("\n")

if #failures > 0 then
  for index, failure in ipairs(failures) do
    io.stderr:write(tostring(index), ") ", tostring(failure.name), "\n", tostring(failure.err), "\n")
  end
  os.exit(1)
end

print("arch_view tests ok (" .. tostring(#(suite.tests or {})) .. ")")
