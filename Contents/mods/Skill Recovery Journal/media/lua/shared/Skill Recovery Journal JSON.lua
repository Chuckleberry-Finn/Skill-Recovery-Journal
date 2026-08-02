local SRJ_JSON = {}

---Serializes a Lua table or primitive into a JSON string
function SRJ_JSON.encode(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local isArray = true
        local maxIdx = 0
        for k, v in pairs(val) do
            if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIdx then maxIdx = k end
        end
        if isArray and maxIdx > 0 then
            local parts = {}
            for i = 1, maxIdx do
                table.insert(parts, SRJ_JSON.encode(val[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, string.format("%q:%s", tostring(k), SRJ_JSON.encode(v)))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end


---Deserializes a JSON string into a Lua table
function SRJ_JSON.decode(str)
    if not str or str == "" then return nil end
    local pos = 1

    local function skipWhitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseValue()
        skipWhitespace()
        if pos > #str then return nil end
        local c = str:sub(pos, pos)

        if c == "{" then
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while pos <= #str do
                skipWhitespace()
                local key = parseValue()
                skipWhitespace()
                if str:sub(pos, pos) == ":" then pos = pos + 1 end
                local val = parseValue()
                if key ~= nil then obj[key] = val end
                skipWhitespace()
                c = str:sub(pos, pos)
                if c == "}" then
                    pos = pos + 1
                    break
                elseif c == "," then
                    pos = pos + 1
                end
            end
            return obj
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while pos <= #str do
                local val = parseValue()
                table.insert(arr, val)
                skipWhitespace()
                c = str:sub(pos, pos)
                if c == "]" then
                    pos = pos + 1
                    break
                elseif c == "," then
                    pos = pos + 1
                end
            end
            return arr
        elseif c == '"' then
            pos = pos + 1
            local startPos = pos
            while pos <= #str do
                if str:sub(pos, pos) == '"' and str:sub(pos - 1, pos - 1) ~= '\\' then
                    local s = str:sub(startPos, pos - 1)
                    pos = pos + 1
                    s = s:gsub('\\"', '"'):gsub('\\\\', '\\')
                    return s
                end
                pos = pos + 1
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local startPos = pos
            if str:sub(pos, pos) == "-" then pos = pos + 1 end
            while pos <= #str and str:sub(pos, pos):match("[%d%.eE%+]") do
                pos = pos + 1
            end
            local numStr = str:sub(startPos, pos - 1)
            return tonumber(numStr)
        end
    end

    return parseValue()
end

return SRJ_JSON
