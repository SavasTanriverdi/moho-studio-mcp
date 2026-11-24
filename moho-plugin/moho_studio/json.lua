-- Pure Lua 5.4 JSON encoder and decoder for Moho Studio MCP.
-- ASCII-only, handles nested arrays/objects, escapes, and non-finite numbers safely.

local json = {}

local ARRAY_MT = { __is_json_array = true }

function json.array(tbl)
	return setmetatable(tbl or {}, ARRAY_MT)
end

local escapeMap = {
	["\\"] = "\\\\",
	["\""] = "\\\"",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function escapeString(str)
	return "\"" .. str:gsub("[%z\1-\31\\\"]", function(c)
		return escapeMap[c] or string.format("\\u%04x", string.byte(c))
	end) .. "\""
end

local function isArray(tbl)
	local mt = getmetatable(tbl)
	if mt and mt.__is_json_array then
		return true
	end
	local count = 0
	local maxIdx = 0
	for k, _ in pairs(tbl) do
		if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
			return false
		end
		count = count + 1
		if k > maxIdx then
			maxIdx = k
		end
	end
	return count > 0 and maxIdx == count
end

local function encodeValue(val, stack)
	local tv = type(val)
	if val == nil then
		return "null"
	elseif tv == "boolean" then
		return val and "true" or "false"
	elseif tv == "number" then
		if val ~= val or val == math.huge or val == -math.huge then
			return "null"
		end
		if math.type and math.type(val) == "integer" then
			return tostring(val)
		end
		return string.format("%.14g", val)
	elseif tv == "string" then
		return escapeString(val)
	elseif tv == "table" then
		if stack[val] then
			error("circular reference in json.encode")
		end
		stack[val] = true
		local res
		if isArray(val) then
			local parts = {}
			for i = 1, #val do
				parts[i] = encodeValue(val[i], stack)
			end
			res = "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(val) do
				if type(k) == "string" or type(k) == "number" then
					parts[#parts + 1] = escapeString(tostring(k)) .. ":" .. encodeValue(v, stack)
				end
			end
			res = "{" .. table.concat(parts, ",") .. "}"
		end
		stack[val] = nil
		return res
	else
		return escapeString(tostring(val))
	end
end

function json.encode(val)
	return encodeValue(val, {})
end

-- Decoder

local function skipWs(str, pos)
	local _, endPos = str:find("^[ \t\r\n]*", pos)
	return (endPos or (pos - 1)) + 1
end

local parseValue

local function parseString(str, pos)
	local out = {}
	local i = pos + 1
	local len = #str
	while i <= len do
		local c = str:sub(i, i)
		if c == "\"" then
			return table.concat(out), i + 1
		elseif c == "\\" then
			local nxt = str:sub(i + 1, i + 1)
			if nxt == "\"" or nxt == "\\" or nxt == "/" then
				out[#out + 1] = nxt
				i = i + 2
			elseif nxt == "b" then
				out[#out + 1] = "\b"; i = i + 2
			elseif nxt == "f" then
				out[#out + 1] = "\f"; i = i + 2
			elseif nxt == "n" then
				out[#out + 1] = "\n"; i = i + 2
			elseif nxt == "r" then
				out[#out + 1] = "\r"; i = i + 2
			elseif nxt == "t" then
				out[#out + 1] = "\t"; i = i + 2
			elseif nxt == "u" then
				local hex = str:sub(i + 2, i + 5)
				local code = tonumber(hex, 16)
				if not code then
					error("invalid unicode escape at " .. i)
				end
				if utf8 and utf8.char then
					-- Handle UTF-16 surrogate pairs
					if code >= 0xD800 and code <= 0xDBFF and str:sub(i + 6, i + 7) == "\\u" then
						local low = tonumber(str:sub(i + 8, i + 11), 16)
						if low and low >= 0xDC00 and low <= 0xDFFF then
							local cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
							out[#out + 1] = utf8.char(cp)
							i = i + 12
						else
							out[#out + 1] = "?"
							i = i + 6
						end
					else
						out[#out + 1] = utf8.char(code)
						i = i + 6
					end
				else
					out[#out + 1] = (code < 128) and string.char(code) or "?"
					i = i + 6
				end
			else
				error("invalid escape \\" .. nxt .. " at " .. i)
			end
		else
			local nextSpecial = str:find("[\"\\]", i)
			if not nextSpecial then
				error("unterminated string starting at " .. pos)
			end
			out[#out + 1] = str:sub(i, nextSpecial - 1)
			i = nextSpecial
		end
	end
	error("unterminated string starting at " .. pos)
end

local function parseNumber(str, pos)
	local s, e = str:find("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
	if not s then
		error("invalid number at " .. pos)
	end
	local num = tonumber(str:sub(s, e))
	if not num then
		error("malformed number at " .. pos)
	end
	return num, e + 1
end

local function parseArray(str, pos)
	local arr = {}
	pos = skipWs(str, pos + 1)
	if str:sub(pos, pos) == "]" then
		return arr, pos + 1
	end
	while true do
		local val
		val, pos = parseValue(str, pos)
		arr[#arr + 1] = val
		pos = skipWs(str, pos)
		local ch = str:sub(pos, pos)
		if ch == "]" then
			return arr, pos + 1
		elseif ch == "," then
			pos = skipWs(str, pos + 1)
		else
			error("expected ',' or ']' at " .. pos)
		end
	end
end

local function parseObject(str, pos)
	local obj = {}
	pos = skipWs(str, pos + 1)
	if str:sub(pos, pos) == "}" then
		return obj, pos + 1
	end
	while true do
		if str:sub(pos, pos) ~= "\"" then
			error("expected string key at " .. pos)
		end
		local key
		key, pos = parseString(str, pos)
		pos = skipWs(str, pos)
		if str:sub(pos, pos) ~= ":" then
			error("expected ':' at " .. pos)
		end
		pos = skipWs(str, pos + 1)
		local val
		val, pos = parseValue(str, pos)
		obj[key] = val
		pos = skipWs(str, pos)
		local ch = str:sub(pos, pos)
		if ch == "}" then
			return obj, pos + 1
		elseif ch == "," then
			pos = skipWs(str, pos + 1)
		else
			error("expected ',' or '}' at " .. pos)
		end
	end
end

parseValue = function(str, pos)
	pos = skipWs(str, pos)
	local ch = str:sub(pos, pos)
	if ch == "\"" then
		return parseString(str, pos)
	elseif ch == "{" then
		return parseObject(str, pos)
	elseif ch == "[" then
		return parseArray(str, pos)
	elseif ch == "-" or (ch >= "0" and ch <= "9") then
		return parseNumber(str, pos)
	elseif str:sub(pos, pos + 3) == "true" then
		return true, pos + 4
	elseif str:sub(pos, pos + 4) == "false" then
		return false, pos + 5
	elseif str:sub(pos, pos + 3) == "null" then
		return nil, pos + 4
	else
		error("unexpected character '" .. ch .. "' at " .. pos)
	end
end

function json.decode(str)
	if type(str) ~= "string" or #str == 0 then
		error("empty json input")
	end
	local val, pos = parseValue(str, 1)
	pos = skipWs(str, pos)
	if pos <= #str then
		error("trailing characters at " .. pos)
	end
	return val
end

return json
