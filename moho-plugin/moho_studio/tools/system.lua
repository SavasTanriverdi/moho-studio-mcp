-- System, introspection, and live Lua 5.4 execution tools for Moho Studio MCP v3.0.0.

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local system = {}

function system.status(moho, params)
	local doc = moho.document
	local appVer = "unknown"
	if moho.AppVersion then
		local ok, v = pcall(function() return moho:AppVersion() end)
		if ok and v then appVer = tostring(v) end
	end
	local plugVer = (MohoStudioMCP_Server and MohoStudioMCP_Server.Version and MohoStudioMCP_Server:Version()) or "3.0.0"
	local info = {
		connected = true,
		pluginVersion = plugVer,
		mohoVersion = appVer,
		isMohoPro = MOHO.IsMohoPro and MOHO.IsMohoPro() or true,
		hasDocument = doc ~= nil,
		userContentDir = moho.UserContentDir and moho:UserContentDir() or "",
		exporterPath = moho.ExporterPath and moho:ExporterPath() or "",
	}
	if doc then
		info.document = {
			name = doc:Name(),
			path = doc:Path(),
			width = doc:Width(),
			height = doc:Height(),
			fps = doc:Fps(),
			startFrame = doc:StartFrame(),
			endFrame = doc:EndFrame(),
			currentFrame = moho.frame,
			activeLayerName = moho.layer and moho.layer:Name() or "",
			activeLayerId = helpers.getLayerId(moho, moho.layer),
			activeAction = moho.layer and moho.layer:CurrentAction() or "",
			docAction = doc.CurrentDocAction and doc:CurrentDocAction() or "",
			layerCompCount = doc.CountLayerComps and doc:CountLayerComps() or 0,
		}
	end
	return info
end

function system.apiInspect(moho, params)
	local targetName = tostring(params.target or "MOHO")
	local filter = params.filter and string.lower(tostring(params.filter)) or nil
	local maxItems = tonumber(params.limit) or 250

	local target = nil
	if targetName == "MOHO" then
		target = MOHO
	elseif targetName == "LM" then
		target = LM
	elseif targetName == "LM.GUI" then
		target = LM and LM.GUI
	elseif targetName == "moho" then
		target = getmetatable(moho) or moho
	elseif targetName == "document" and moho.document then
		target = getmetatable(moho.document) or moho.document
	elseif targetName == "layer" and moho.layer then
		target = getmetatable(moho.layer) or moho.layer
	elseif MOHO[targetName] ~= nil then
		target = MOHO[targetName]
	elseif LM and LM[targetName] ~= nil then
		target = LM[targetName]
	elseif _G[targetName] ~= nil then
		target = _G[targetName]
	end

	if target == nil then
		return nil, "Target not found: " .. targetName
	end

	local entries = {}
	local function addEntry(ks, kind, sourceTag)
		if filter and not string.find(string.lower(ks), filter, 1, true) then
			return
		end
		entries[ks .. ":" .. sourceTag] = {
			name = ks,
			kind = kind,
			source = sourceTag,
		}
	end

	local function collect(tbl, sourceTag)
		if type(tbl) ~= "table" then
			return
		end
		for k, v in pairs(tbl) do
			local ks = tostring(k)
			if ks == ".get" and type(v) == "table" then
				for pk, _ in pairs(v) do
					addEntry(tostring(pk), "property_get", sourceTag .. ".get")
				end
			elseif ks == ".set" and type(v) == "table" then
				for pk, _ in pairs(v) do
					addEntry(tostring(pk), "property_set", sourceTag .. ".set")
				end
			elseif string.sub(ks, 1, 2) ~= "__" then
				addEntry(ks, type(v), sourceTag)
			end
		end
	end

	if type(target) == "table" then
		collect(target, "table")
		local mt = getmetatable(target)
		if type(mt) == "table" and type(mt.__index) == "table" then
			collect(mt.__index, "metatable")
		end
	else
		local mt = getmetatable(target)
		if type(mt) == "table" then
			collect(mt, "metatable")
			if type(mt.__index) == "table" then
				collect(mt.__index, "index")
			end
		end
	end

	local list = {}
	for _, v in pairs(entries) do
		list[#list + 1] = v
	end
	table.sort(list, function(a, b)
		if a.name == b.name then return a.source < b.source end
		return a.name < b.name
	end)
	if #list > maxItems then
		local trimmed = {}
		for i = 1, maxItems do
			trimmed[i] = list[i]
		end
		return {
			target = targetName,
			total = #list,
			truncated = true,
			entries = json.array(trimmed),
		}
	end
	return {
		target = targetName,
		total = #list,
		truncated = false,
		entries = json.array(list),
	}
end

--- Execute arbitrary Lua 5.4 code live inside Moho with `moho`, `helpers`, `json`, and `delaunay` in scope.
function system.executeLua(moho, params)
	local code = params.code
	if type(code) ~= "string" or #code == 0 then
		return nil, "code is required and must be a non-empty string"
	end

	local useUndo = (params.undo ~= false)
	if useUndo and moho.document then
		helpers.prepUndo(moho, moho.layer, true)
	end

	local logs = {}
	local origPrint = _G.print
	local function capturePrint(...)
		local parts = {}
		local n = select("#", ...)
		for i = 1, n do
			parts[i] = tostring(select(i, ...))
		end
		logs[#logs + 1] = table.concat(parts, "\t")
	end

	local delaunay = require("moho_studio.delaunay")
	local env = setmetatable({
		moho = moho,
		helpers = helpers,
		json = json,
		delaunay = delaunay,
		args = params.args or {},
		print = capturePrint,
	}, { __index = _G })

	local chunk, loadErr = load(code, "moho_studio_lua_execute", "t", env)
	if not chunk then
		return nil, "Lua syntax error: " .. tostring(loadErr)
	end

	_G.print = capturePrint
	local ok, retVal = pcall(chunk)
	_G.print = origPrint

	helpers.updateUI(moho)

	if not ok then
		return nil, "Lua runtime error: " .. tostring(retVal) .. (#logs > 0 and (" | logs: " .. table.concat(logs, "; ")) or "")
	end

	local encOk = pcall(json.encode, retVal)
	local safeResult = encOk and retVal or tostring(retVal)

	return {
		success = true,
		result = safeResult,
		logs = json.array(logs),
	}
end

return system
