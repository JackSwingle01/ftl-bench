-- Minimal JSON encoder (Hyperspace's Lua has no JSON library).
-- Tables with keys 1..n are arrays; any other table, including an empty one, is an object.

FtlBench = FtlBench or {}

local Json = {}

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

---@param s string
---@return string
local function encode_string(s)
    return '"'
        .. s:gsub('[%c"\\]', function(c)
            return escapes[c] or ("\\u%04x"):format(c:byte())
        end)
        .. '"'
end

---@param t table
---@return boolean
local function is_array(t)
    local n = #t
    if n == 0 then
        return false
    end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count == n
end

---@param value any
---@return string
function Json.encode(value)
    local kind = type(value)
    if value == nil then
        return "null"
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        elseif math.type(value) == "integer" then
            return tostring(value)
        end
        return ("%.10g"):format(value)
    elseif kind == "string" then
        return encode_string(value)
    elseif kind == "table" then
        local parts = {}
        if is_array(value) then
            for i = 1, #value do
                parts[i] = Json.encode(value[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(value) do
            keys[#keys + 1] = tostring(k)
        end
        table.sort(keys)
        for i, k in ipairs(keys) do
            parts[i] = encode_string(k) .. ":" .. Json.encode(value[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("cannot encode " .. kind)
end

FtlBench.Json = Json
