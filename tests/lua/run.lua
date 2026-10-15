-- Minimal test runner for the mod's pure modules (Lua 5.3, no game needed).
-- Usage: lua tests/lua/run.lua [test_file ...]   (defaults to every test_*.lua listed below)

local MOD = "llm-bridge/data/ftlbench/"
dofile(MOD .. "visibility.lua")
dofile(MOD .. "commands.lua")

local tests, failures = {}, 0

local t = {}

---@param name string
---@param fn fun()
function t.test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

---Deep equality with a readable diff path.
---@param actual any
---@param expected any
---@param path string?
function t.eq(actual, expected, path)
    path = path or "value"
    if type(expected) == "table" and type(actual) == "table" then
        for k, v in pairs(expected) do
            t.eq(actual[k], v, path .. "." .. tostring(k))
        end
        for k in pairs(actual) do
            if expected[k] == nil then
                error(path .. "." .. tostring(k) .. ": unexpected key", 2)
            end
        end
    elseif actual ~= expected then
        error(("%s: expected %s, got %s"):format(path, tostring(expected), tostring(actual)), 2)
    end
end

local files = { ... }
if #files == 0 then
    files = { "tests/lua/test_visibility.lua", "tests/lua/test_commands.lua" }
end
for _, f in ipairs(files) do
    assert(loadfile(f))(t)
end

for _, case in ipairs(tests) do
    local ok, err = pcall(case.fn)
    if ok then
        print("ok   " .. case.name)
    else
        failures = failures + 1
        print("FAIL " .. case.name .. "\n     " .. tostring(err))
    end
end
print(("%d tests, %d failures"):format(#tests, failures))
os.exit(failures == 0 and 0 or 1)
