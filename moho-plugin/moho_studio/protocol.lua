-- JSON-RPC 2.0 envelope helpers for Moho Studio MCP.

local protocol = {}

protocol.PARSE_ERROR = -32700
protocol.INVALID_REQUEST = -32600
protocol.METHOD_NOT_FOUND = -32601
protocol.INVALID_PARAMS = -32602
protocol.INTERNAL_ERROR = -32603

local json = nil

function protocol.init(jsonMod)
	json = jsonMod
end

function protocol.parseRequest(raw)
	local ok, data = pcall(json.decode, raw)
	if not ok then
		return nil, "JSON parse error: " .. tostring(data)
	end
	if type(data) ~= "table" or type(data.method) ~= "string" then
		return nil, "Invalid JSON-RPC request"
	end
	return {
		id = data.id,
		method = data.method,
		params = type(data.params) == "table" and data.params or {},
	}
end

function protocol.createResponse(id, result)
	return json.encode({
		jsonrpc = "2.0",
		id = id,
		result = result,
	})
end

function protocol.createError(id, code, message, data)
	local errObj = {
		code = code,
		message = tostring(message or "Unknown error"),
	}
	if data ~= nil then
		errObj.data = data
	end
	return json.encode({
		jsonrpc = "2.0",
		id = id,
		error = errObj,
	})
end

return protocol
