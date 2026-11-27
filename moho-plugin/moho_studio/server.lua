-- Atomic, collision-free IPC server for Moho Studio MCP v3.1.0 using Moho's native BeginFileListing.

local server = {}

local protocol = nil
local json = nil
local handlers = {}
local isRunning = false
local isPolling = false
local ipcDir = ""
local startedAt = ""
local requestCount = 0

local SEP = package.config:sub(1, 1)
local VERSION = "3.1.0"

local DOC_LIFECYCLE_METHODS = {
	["document.new"] = true,
	["document.open"] = true,
	["document.close"] = true,
	["document.exportGltf"] = true,
}

local function isDocLifecycleRequest(raw)
	if type(raw) ~= "string" or #raw == 0 then
		return false
	end
	local req = protocol.parseRequest(raw)
	if not req then
		return false
	end
	if DOC_LIFECYCLE_METHODS[req.method] then
		return true
	end
	if req.method == "batch.execute" and type(req.params) == "table" and type(req.params.operations) == "table" then
		for i = 1, #req.params.operations do
			local op = req.params.operations[i]
			if type(op) == "table" and DOC_LIFECYCLE_METHODS[op.method] then
				return true
			end
		end
	end
	return false
end

function server.init(deps)
	protocol = deps.protocol
	json = deps.json
end

function server.registerHandler(method, fn)
	handlers[method] = fn
end

function server.getHandler(method)
	return handlers[method]
end

function server.listMethods()
	local names = {}
	for k, _ in pairs(handlers) do
		names[#names + 1] = k
	end
	table.sort(names)
	return names
end

local function normalizeDir(path)
	if not path or path == "" then
		return ""
	end
	local last = path:sub(-1)
	if last ~= "/" and last ~= "\\" then
		path = path .. SEP
	end
	return path
end

local function resolveIpcDir()
	local override = os.getenv("MOHO_STUDIO_IPC_DIR")
	if override and override ~= "" then
		return normalizeDir(override)
	end
	local tmp = os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR") or "/tmp"
	return normalizeDir(tmp) .. "moho-studio-mcp" .. SEP
end

local function readFile(path)
	local f, err = io.open(path, "rb")
	if not f then
		return nil, err
	end
	local data = f:read("*a")
	f:close()
	return data
end

local function writeFileAtomic(path, content)
	local tmpPath = path .. ".tmp"
	local f, err = io.open(tmpPath, "wb")
	if not f then
		return false, "open failed: " .. tostring(err)
	end
	f:write(content)
	f:close()
	os.remove(path)
	local ok, rerr = os.rename(tmpPath, path)
	if not ok then
		os.remove(tmpPath)
		return false, "rename failed: " .. tostring(rerr)
	end
	return true
end

local function ensureDir(dir)
	local clean = dir:gsub("[/\\]+$", "")
	if LM and LM.CreateDir then
		pcall(function() LM.CreateDir(clean) end)
		return
	end
	local cmd
	if SEP == "\\" then
		cmd = 'cmd /c if not exist "' .. clean .. '" mkdir "' .. clean .. '" 2>NUL'
	else
		cmd = 'mkdir -p "' .. clean .. '" 2>/dev/null'
	end
	local h = io.popen(cmd)
	if h then
		h:close()
	end
end

local function listReqFiles(moho, dir)
	local found = {}
	if moho and moho.BeginFileListing then
		local clean = dir:gsub("[/\\]+$", "")
		moho:BeginFileListing(clean)
		local name = moho:GetNextFile()
		while name ~= nil do
			if name:match("^req_.+%.json$") then
				found[#found + 1] = name
			end
			name = moho:GetNextFile()
		end
	end
	table.sort(found)
	return found
end

function server.start(moho)
	if isRunning then
		return true
	end
	ipcDir = resolveIpcDir()
	ensureDir(ipcDir)

	local probePath = ipcDir .. ".write_probe"
	local ok, err = writeFileAtomic(probePath, "ok")
	if not ok then
		return false, "Cannot write to IPC directory " .. ipcDir .. ": " .. tostring(err)
	end
	os.remove(probePath)

	-- Clean any stale request/response files from prior runs
	if moho and moho.BeginFileListing then
		local clean = ipcDir:gsub("[/\\]+$", "")
		moho:BeginFileListing(clean)
		local name = moho:GetNextFile()
		while name ~= nil do
			if name:match("^req_.+%.json") or name:match("^resp_.+%.json") then
				os.remove(ipcDir .. name)
			end
			name = moho:GetNextFile()
		end
	end

	startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
	local appVer = "14.4"
	if moho and moho.AppVersion then
		local vok, vstr = pcall(function() return moho:AppVersion() end)
		if vok and vstr then
			appVer = tostring(vstr)
		end
	end

	writeFileAtomic(ipcDir .. "status.json", json.encode({
		running = true,
		name = "moho-studio-mcp",
		version = VERSION,
		mohoVersion = appVer,
		ipcDir = ipcDir,
		startedAt = startedAt,
	}))

	isRunning = true
	isPolling = false
	requestCount = 0
	print("[MohoStudioMCP] Started v" .. VERSION .. " | IPC: " .. ipcDir)
	return true
end

function server.stop()
	if not isRunning then
		return
	end
	os.remove(ipcDir .. "status.json")
	isRunning = false
	isPolling = false
	print("[MohoStudioMCP] Stopped")
end

function server.isRunning()
	return isRunning
end

function server.getInfo()
	return {
		running = isRunning,
		version = VERSION,
		ipcDir = ipcDir,
		startedAt = startedAt,
		requestCount = requestCount,
	}
end

local function executeRequest(raw, moho)
	local req, perr = protocol.parseRequest(raw)
	if not req then
		return protocol.createError(nil, protocol.PARSE_ERROR, perr)
	end
	local handler = handlers[req.method]
	if not handler then
		return protocol.createError(req.id, protocol.METHOD_NOT_FOUND, "Unknown method: " .. tostring(req.method))
	end
	local ok, result, herr = pcall(handler, moho, req.params)
	if not ok then
		return protocol.createError(req.id, protocol.INTERNAL_ERROR, "Lua handler error: " .. tostring(result))
	end
	if result == nil and herr ~= nil then
		return protocol.createError(req.id, protocol.INTERNAL_ERROR, tostring(herr))
	end
	return protocol.createResponse(req.id, result)
end

function server.hasPending(moho, dispatchSource)
	if not isRunning or isPolling or ipcDir == "" then
		return false
	end
	if moho and moho.BeginFileListing then
		local clean = ipcDir:gsub("[/\\]+$", "")
		moho:BeginFileListing(clean)
		local names = {}
		local name = moho:GetNextFile()
		while name ~= nil do
			if name:match("^req_.+%.json$") then
				if dispatchSource ~= "draw" then
					return true
				end
				names[#names + 1] = name
			end
			name = moho:GetNextFile()
		end
		if dispatchSource == "draw" then
			for i = 1, #names do
				local content = readFile(ipcDir .. names[i])
				if content and #content > 0 and not isDocLifecycleRequest(content) then
					return true
				end
			end
		end
	end
	return false
end

function server.poll(moho, dispatchSource)
	if not isRunning or isPolling then
		return 0
	end
	isPolling = true
	local processed = 0
	local okPoll, pollErr = pcall(function()
		local reqFiles = listReqFiles(moho, ipcDir)
		for i = 1, #reqFiles do
			if processed >= 8 then
				break
			end
			local fname = reqFiles[i]
			local reqPath = ipcDir .. fname
			local content = readFile(reqPath)
			if content and #content > 0 then
				if dispatchSource == "draw" and isDocLifecycleRequest(content) then
					-- Document lifecycle calls must run on HandleMessage/Run UI command stack, never DrawMe
				else
					-- Claim/delete request before dispatch so a re-entrant repaint never double-executes it
					os.remove(reqPath)
					local reqId = fname:match("^req_(.+)%.json$")
					local procOk, response = pcall(executeRequest, content, moho)
					if not procOk then
						response = protocol.createError(nil, protocol.INTERNAL_ERROR, "Fatal server error: " .. tostring(response))
					end
					if reqId then
						writeFileAtomic(ipcDir .. "resp_" .. reqId .. ".json", response)
					end
					requestCount = requestCount + 1
					processed = processed + 1
				end
			end
		end
	end)
	isPolling = false
	if not okPoll then
		print("[MohoStudioMCP] Poll failure: " .. tostring(pollErr))
	end
	return processed
end

return server
