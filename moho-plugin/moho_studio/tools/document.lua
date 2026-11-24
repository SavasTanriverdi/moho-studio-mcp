-- Document lifecycle, undo/redo, Layer Comps, import, settings, and frame rendering tools (v3.0.0).
-- Signatures verified against Moho Pro 14.4 bundled scripts and live Lua 5.4 runtime.

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local document = {}

function document.getInfo(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local frame = (type(params) == "table" and params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local totalLayers = helpers.walkLayers(moho, function() end)
	local bg = nil
	if doc.BackCol then
		local ok, c = pcall(function() return doc:BackCol() end)
		if ok and c then
			bg = { r = c.r, g = c.g, b = c.b, a = c.a }
		end
	end
	local cameraViewport = nil
	if doc.fCameraTrack and doc.fCameraZoom then
		local camPos = doc.fCameraTrack:GetValue(frame)
		local zoom = doc.fCameraZoom:GetValue(frame)
		if zoom and zoom > 1e-4 then
			local fovRad = math.rad(60.0) / zoom
			local halfH = math.abs(camPos.z) * math.tan(fovRad * 0.5)
			local aspect = doc:Width() / math.max(1, doc:Height())
			local halfW = halfH * aspect
			cameraViewport = {
				frame = frame,
				minX = camPos.x - halfW,
				maxX = camPos.x + halfW,
				minY = camPos.y - halfH,
				maxY = camPos.y + halfH,
				width = halfW * 2,
				height = halfH * 2,
				cameraZ = camPos.z,
				zoom = zoom,
			}
		end
	end
	local dof = nil
	if doc.IsDepthOfFieldEnabled or doc.FocusDistance or doc.FocusRange or doc.MaxBlur then
		dof = {}
		if doc.IsDepthOfFieldEnabled then
			local okE, en = pcall(function() return doc:IsDepthOfFieldEnabled() end)
			if okE then dof.enabled = (en == true) end
		end
		if doc.FocusDistance then
			local okFd, fd = pcall(function() return doc:FocusDistance() end)
			if okFd then dof.focusDistance = fd end
		end
		if doc.FocusRange then
			local okFr, fr = pcall(function() return doc:FocusRange() end)
			if okFr then dof.focusRange = fr end
		end
		if doc.MaxBlur then
			local okMb, mb = pcall(function() return doc:MaxBlur() end)
			if okMb then
				dof.maxBlur = mb
				dof.maxBlurPx = helpers.docToPx(moho, mb)
			end
		end
	end
	local out = {
		name = doc:Name(),
		path = doc:Path(),
		width = doc:Width(),
		height = doc:Height(),
		fps = doc:Fps(),
		startFrame = doc:StartFrame(),
		endFrame = doc:EndFrame(),
		currentFrame = moho.frame,
		durationSeconds = (doc:EndFrame() - doc:StartFrame()) / math.max(1, doc:Fps()),
		topLevelLayers = doc:CountLayers(),
		totalLayers = totalLayers,
		layerCompCount = doc.CountLayerComps and doc:CountLayerComps() or 0,
		docAction = doc.CurrentDocAction and doc:CurrentDocAction() or "",
		backColor = bg,
		cameraViewport = cameraViewport,
	}
	if dof ~= nil then
		out.dof = dof
	end
	if MOHO and MOHO.MohoGlobals then
		local mg = MOHO.MohoGlobals
		local projDof = {}
		local okE, ge = pcall(function() return mg.ProjDofEnabled end)
		if okE and ge ~= nil then projDof.enabled = (ge == true) end
		local okD, gd = pcall(function() return mg.ProjDofDistance end)
		if okD and gd ~= nil then projDof.focusDistance = gd end
		local okR, gr = pcall(function() return mg.ProjDofRange end)
		if okR and gr ~= nil then projDof.focusRange = gr end
		local okB, gb = pcall(function() return mg.ProjDofBlur end)
		if okB and gb ~= nil then
			projDof.maxBlur = gb
			projDof.maxBlurPx = helpers.docToPx(moho, gb)
		end
		if next(projDof) ~= nil then
			out.projectDefaultsDof = projDof
		end
	end
	return out
end

function document.newDoc(moho, params)
	moho:FileNew()
	if params and (params.width or params.height or params.fps or params.startFrame or params.endFrame or params.backColor) then
		document.setSettings(moho, params)
	end
	helpers.updateUI(moho)
	return document.getInfo(moho, {})
end

function document.open(moho, params)
	local path = params.path
	if type(path) ~= "string" or #path == 0 then
		return nil, "path is required"
	end
	moho:FileOpen(path)
	helpers.updateUI(moho)
	return document.getInfo(moho, {})
end

function document.save(moho, params)
	if not moho.document then
		return nil, "No document open"
	end
	moho:FileSave()
	return {
		saved = true,
		name = moho.document:Name(),
		path = moho.document:Path(),
	}
end

function document.saveAs(moho, params)
	if not moho.document then
		return nil, "No document open"
	end
	local path = params.path
	if type(path) ~= "string" or #path == 0 then
		return nil, "path is required"
	end
	moho:FileSaveAs(path)
	return {
		saved = true,
		name = moho.document:Name(),
		path = moho.document:Path(),
	}
end

local function resolveTempDiscardDir()
	local sep = package.config:sub(1, 1)
	local override = os.getenv("MOHO_STUDIO_IPC_DIR")
	local dir
	if override and override ~= "" then
		dir = override
	else
		local tmp = os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR") or "/tmp"
		local last = tmp:sub(-1)
		if last ~= "/" and last ~= "\\" then
			tmp = tmp .. sep
		end
		dir = tmp .. "moho-studio-mcp"
	end
	dir = dir:gsub("[/\\]+$", "")
	if LM and LM.CreateDir then
		pcall(function() LM.CreateDir(dir) end)
	end
	return dir .. sep
end

local function discardViaTempSave(moho)
	local dir = resolveTempDiscardDir()
	local tmpPath = dir .. "_discard_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999)) .. ".moho"
	local okSave, errSave = pcall(function()
		moho:FileSaveAs(tmpPath)
	end)
	if not okSave then
		return false, nil, "Failed to write temporary discard file (" .. tostring(errSave) .. "); aborted FileClose to avoid blocking Save modal"
	end
	local fh = io.open(tmpPath, "rb")
	if not fh then
		return false, nil, "Temporary discard file was not created at " .. tmpPath .. "; aborted FileClose to avoid blocking Save modal"
	end
	fh:close()
	return true, tmpPath, nil
end

function document.closeDoc(moho, params)
	params = params or {}
	if not moho.document then
		return nil, "No document open"
	end
	local doc = moho.document
	local closedName = doc:Name()
	local docPath = doc:Path()
	local saveFirst = (params.saveFirst ~= false)
	local force = (params.force == true)
	local tempDiscardPath = nil

	if saveFirst then
		if type(params.savePath) == "string" and #params.savePath > 0 then
			moho:FileSaveAs(params.savePath)
		elseif docPath and #docPath > 0 then
			moho:FileSave()
		elseif not force then
			return nil, "Document has no saved path; closing it could pop a blocking Save modal dialog. Save first, pass savePath, or set force=true."
		else
			local okTmp, tmpPath, errTmp = discardViaTempSave(moho)
			if not okTmp then
				return nil, errTmp
			end
			tempDiscardPath = tmpPath
		end
	else
		if not force then
			return nil, "Closing without saving on a dirty document can pop a blocking Save modal dialog; set force=true to discard changes safely via a temporary file."
		end
		-- MohoDoc:SetDirty() has no Lua clear method, so FileClose() prompts on dirty docs.
		-- Saving to a disposable temp path clears the dirty flag without touching any real file on disk.
		local okTmp, tmpPath, errTmp = discardViaTempSave(moho)
		if not okTmp then
			return nil, errTmp
		end
		tempDiscardPath = tmpPath
	end

	moho:FileClose()
	if tempDiscardPath then
		pcall(os.remove, tempDiscardPath)
	end
	helpers.updateUI(moho)
	return {
		closed = true,
		closedName = closedName,
		activeDocument = moho.document and moho.document:Name() or "",
		discardedViaTempFile = (tempDiscardPath ~= nil),
	}
end

function document.undoRedo(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local mode = string.lower(tostring(params.mode or "undo"))
	local steps = math.max(1, math.min(50, math.floor(tonumber(params.steps) or 1)))
	local done = 0
	if mode == "redo" then
		for _ = 1, steps do
			if doc:IsRedoable() then
				doc:Redo()
				done = done + 1
			else
				break
			end
		end
	else
		for _ = 1, steps do
			if doc:IsUndoable() then
				doc:Undo()
				done = done + 1
			else
				break
			end
		end
	end
	helpers.updateUI(moho)
	return {
		mode = mode,
		stepsPerformed = done,
		isUndoable = doc:IsUndoable(),
		isRedoable = doc:IsRedoable(),
	}
end

function document.setSettings(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	helpers.prepUndo(moho, moho.layer, true)
	if params.width ~= nil and params.height ~= nil and doc.SetShape then
		doc:SetShape(math.floor(params.width), math.floor(params.height))
	end
	if params.fps ~= nil and doc.SetFps then
		doc:SetFps(tonumber(params.fps))
	end
	if params.startFrame ~= nil and doc.SetStartFrame then
		doc:SetStartFrame(math.floor(params.startFrame))
	end
	if params.endFrame ~= nil and doc.SetEndFrame then
		doc:SetEndFrame(math.floor(params.endFrame))
	end
	-- Verified in Moho Pro 14.4: MohoDoc:SetBackCol takes 4-byte LM.rgb_color.
	if type(params.backColor) == "table" and doc.SetBackCol then
		doc:SetBackCol(helpers.toRgbStruct(params.backColor))
	end
	local dofSupported = nil
	local dofWarning = nil
	if type(params.dof) == "table" then
		local appliedAny = false
		if params.dof.enabled ~= nil then
			if doc.SetDepthOfFieldEnabled then
				doc:SetDepthOfFieldEnabled(params.dof.enabled == true)
				appliedAny = true
			elseif doc.EnableDepthOfField then
				doc:EnableDepthOfField(params.dof.enabled == true)
				appliedAny = true
			end
		end
		if params.dof.focusDistance ~= nil and doc.SetFocusDistance then
			doc:SetFocusDistance(tonumber(params.dof.focusDistance))
			appliedAny = true
		end
		if params.dof.focusRange ~= nil and doc.SetFocusRange then
			doc:SetFocusRange(tonumber(params.dof.focusRange))
			appliedAny = true
		end
		if (params.dof.maxBlurPx ~= nil or params.dof.maxBlur ~= nil) and doc.SetMaxBlur then
			local mb = params.dof.maxBlurPx ~= nil and helpers.pxToDoc(moho, params.dof.maxBlurPx) or tonumber(params.dof.maxBlur)
			doc:SetMaxBlur(mb)
			appliedAny = true
		end
		if (not appliedAny) and params.dof.applyToProjectDefaults == true and MOHO and MOHO.MohoGlobals then
			local mg = MOHO.MohoGlobals
			if params.dof.enabled ~= nil then
				pcall(function() mg.ProjDofEnabled = (params.dof.enabled == true) end)
				appliedAny = true
			end
			if params.dof.focusDistance ~= nil then
				pcall(function() mg.ProjDofDistance = tonumber(params.dof.focusDistance) end)
				appliedAny = true
			end
			if params.dof.focusRange ~= nil then
				pcall(function() mg.ProjDofRange = tonumber(params.dof.focusRange) end)
				appliedAny = true
			end
			if params.dof.maxBlurPx ~= nil or params.dof.maxBlur ~= nil then
				local mb = params.dof.maxBlurPx ~= nil and helpers.pxToDoc(moho, params.dof.maxBlurPx) or tonumber(params.dof.maxBlur)
				pcall(function() mg.ProjDofBlur = mb end)
				appliedAny = true
			end
		end
		dofSupported = appliedAny
		if not appliedAny then
			dofWarning = "Moho 14.4 Lua API does not expose per-document DOF on MohoDoc (use layer_setProperties immuneToDof per layer, or pass applyToProjectDefaults: true for MOHO.MohoGlobals defaults)"
		end
	end
	helpers.updateUI(moho)
	local info = document.getInfo(moho, {})
	if dofSupported ~= nil and info then
		info.dofSupported = dofSupported
		if dofWarning then
			info.dofWarning = dofWarning
		end
	end
	return info
end

local function findUpvalueByName(fn, targetName)
	if type(fn) ~= "function" or not debug or type(debug.getupvalue) ~= "function" then
		return nil, -1
	end
	local i = 1
	while true do
		local name, val = debug.getupvalue(fn, i)
		if not name then
			return nil, -1
		end
		if name == targetName then
			return val, i
		end
		i = i + 1
	end
end

local function importSvgViaBridge(moho, path, params)
	if type(SS_SVGImport) ~= "table" or type(SS_SVGImport.Run) ~= "function" then
		return nil, "SS_SVGImport is not loaded"
	end
	local upXml = findUpvalueByName(SS_SVGImport.Run, "xml2lua")
	if not upXml and type(SS_SVGImport.IsRelevant) == "function" then
		pcall(function() SS_SVGImport:IsRelevant(moho) end)
	end
	local dlogTbl = findUpvalueByName(SS_SVGImport.Run, "SS_SVGImportDialog")
	if type(dlogTbl) ~= "table" then
		return nil, "Unable to locate SS_SVGImportDialog upvalue"
	end

	local fh = io.open(path, "rb")
	if not fh then
		return nil, "SVG file not found or unreadable: " .. path
	end
	fh:close()

	local scaleBase = dlogTbl.SCALE_ or ((MOHO and MOHO.MSG_BASE or 0) + 10)
	local scaleMap = {
		fit_50 = 1,
		fit_100 = 2,
		fit_200 = 3,
		asset_50 = 5,
		asset_100 = 6,
		none = 6,
		asset_200 = 7,
	}
	local targetScaleMode = SS_SVGImport.scaleDefault or (scaleBase + 1)
	if params.scaleMode ~= nil then
		if type(params.scaleMode) == "number" then
			local idx = math.floor(params.scaleMode)
			if idx >= 1 and idx <= 7 and idx ~= 4 then
				targetScaleMode = scaleBase + idx
			end
		else
			local key = string.lower(tostring(params.scaleMode))
			local idx = scaleMap[key]
			if idx then
				targetScaleMode = scaleBase + idx
			end
		end
	end

	local saveKeys = {
		"filename", "scaleMode", "minify", "minifyLayers", "minifyLayersUnnamed",
		"minifyGroups", "minifyPostOp", "expandGroups", "recenter",
		"browseFirst", "hideDialog", "debugMode",
	}
	local saved = {}
	for i = 1, #saveKeys do
		local k = saveKeys[i]
		saved[k] = SS_SVGImport[k]
	end
	local origNew = dlogTbl.new
	local origAlert = (LM and LM.GUI) and LM.GUI.Alert or nil
	local alerts = {}

	local beforeCount = helpers.walkLayers(moho, function() end)

	SS_SVGImport.filename = path
	SS_SVGImport.scaleMode = targetScaleMode
	if params.minify ~= nil then SS_SVGImport.minify = (params.minify == true) end
	if params.minifyLayers ~= nil then SS_SVGImport.minifyLayers = (params.minifyLayers == true) end
	if params.minifyGroups ~= nil then SS_SVGImport.minifyGroups = (params.minifyGroups == true) end
	if params.minifyLayersUnnamed ~= nil then SS_SVGImport.minifyLayersUnnamed = (params.minifyLayersUnnamed == true) end
	if params.expandGroups ~= nil then SS_SVGImport.expandGroups = (params.expandGroups == true) end
	if params.recenter ~= nil then SS_SVGImport.recenter = (params.recenter == true) end
	SS_SVGImport.browseFirst = false
	SS_SVGImport.hideDialog = false
	SS_SVGImport.debugMode = false

	dlogTbl.new = function()
		return {
			DoModal = function()
				SS_SVGImport.filename = path
				return (LM and LM.GUI and LM.GUI.MSG_OK) or 0
			end,
		}
	end
	if LM and LM.GUI and origAlert then
		LM.GUI.Alert = function(...)
			local parts = {}
			local argc = select("#", ...)
			for i = 1, argc do
				parts[#parts + 1] = tostring(select(i, ...))
			end
			alerts[#alerts + 1] = table.concat(parts, " | ")
			return 0
		end
	end

	local okRun, runErr = pcall(function()
		SS_SVGImport:Run(moho)
	end)

	dlogTbl.new = origNew
	if LM and LM.GUI and origAlert then
		LM.GUI.Alert = origAlert
	end
	for i = 1, #saveKeys do
		local k = saveKeys[i]
		SS_SVGImport[k] = saved[k]
	end

	if not okRun then
		return nil, "SS_SVGImport:Run failed: " .. tostring(runErr)
	end

	local afterCount = helpers.walkLayers(moho, function() end)
	helpers.updateUI(moho)
	return {
		imported = true,
		method = "SS_SVGImport",
		path = path,
		createdLayers = math.max(0, afterCount - beforeCount),
		activeLayerId = helpers.getLayerId(moho, moho.layer),
		activeLayerName = moho.layer and moho.layer:Name() or "",
		alerts = json.array(alerts),
	}, nil
end

function document.importFile(moho, params)
	if not moho.document then
		return nil, "No document open"
	end
	local path = params.path
	if type(path) ~= "string" or #path == 0 then
		return nil, "path is required"
	end
	helpers.prepUndo(moho, moho.layer, true)
	local ext = string.lower(path:match("%.([^%.]+)$") or "")
	local asImageLayer = params.asImageLayer
	if asImageLayer == nil and (ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "bmp" or ext == "tga") then
		asImageLayer = true
	end

	if ext == "svg" and (not asImageLayer) and params.useNativeSvgImport ~= true then
		local svgRes, svgErr = importSvgViaBridge(moho, path, params)
		if svgRes then
			return svgRes
		end
		if params.requireSvgBridge == true then
			return nil, svgErr
		end
	end

	if asImageLayer then
		local layer = moho:CreateNewLayer(MOHO.LT_IMAGE, true)
		local imgLayer = moho:LayerAsImage(layer)
		if not imgLayer then
			return nil, "Failed to create ImageLayer"
		end
		imgLayer:SetSourceImage(path)
		if params.name then
			layer:SetName(tostring(params.name))
		else
			local base = path:match("([^/\\]+)$") or "Image"
			layer:SetName(base:gsub("%.[^%.]+$", ""))
		end
		if params.parentLayerId ~= nil or params.parentLayerName ~= nil then
			local parentL = helpers.resolveLayer(moho, {
				layerId = params.parentLayerId,
				layerName = params.parentLayerName,
			})
			if parentL and parentL:IsGroupType() then
				moho:PlaceLayerInGroup(layer, parentL, false, false)
			end
		end
		helpers.updateUI(moho)
		return {
			imported = true,
			method = "ImageLayer:SetSourceImage",
			path = path,
			layerId = helpers.getLayerId(moho, layer),
			layerName = layer:Name(),
		}
	end

	local mode = tonumber(params.mode) or 0
	moho:FileImport(path, mode)
	helpers.updateUI(moho)
	return {
		imported = true,
		method = "FileImport",
		path = path,
		activeLayerId = helpers.getLayerId(moho, moho.layer),
		activeLayerName = moho.layer and moho.layer:Name() or "",
	}
end

function document.setFrame(moho, params)
	if not moho.document then
		return nil, "No document open"
	end
	local frame = math.floor(tonumber(params.frame) or 0)
	moho:SetCurFrame(frame)
	helpers.updateUI(moho)
	return {
		frame = moho.frame,
		success = true,
	}
end

function document.renderFrame(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local origFrame = moho.frame
	local targetFrame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or origFrame
	local outPath = params.outputPath
	if not outPath or outPath == "" then
		local tmp = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
		local sep = package.config:sub(1, 1)
		outPath = tmp .. sep .. "moho-studio-mcp" .. sep .. "render_" .. tostring(targetFrame) .. "_" .. tostring(math.floor(os.clock() * 1000)) .. ".png"
	end

	if targetFrame ~= origFrame then
		moho:SetCurFrame(targetFrame)
		moho:UpdateUI()
	end

	moho:FileRender(outPath)

	local restoreFrame = (params.restoreFrame ~= false)
	if restoreFrame and targetFrame ~= origFrame then
		moho:SetCurFrame(origFrame)
		moho:UpdateUI()
	end

	local f = io.open(outPath, "rb")
	if not f then
		return nil, "Render output file not created: " .. outPath
	end
	local size = f:seek("end")
	f:close()

	return {
		rendered = true,
		frame = targetFrame,
		width = doc:Width(),
		height = doc:Height(),
		outputPath = outPath,
		bytes = size,
	}
end

function document.renderRange(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local outDir = params.outputDir
	if type(outDir) ~= "string" or #outDir == 0 then
		return nil, "outputDir is required"
	end
	local startF = math.floor(tonumber(params.startFrame) or doc:StartFrame())
	local endF = math.floor(tonumber(params.endFrame) or doc:EndFrame())
	local step = math.max(1, math.floor(tonumber(params.step) or 1))
	local prefix = tostring(params.prefix or "frame_")
	local sep = package.config:sub(1, 1)
	local cleanDir = outDir:gsub("[/\\]+$", "")
	if LM and LM.CreateDir then
		pcall(function() LM.CreateDir(cleanDir) end)
	end
	local origFrame = moho.frame

	local files = {}
	for f = startF, endF, step do
		moho:SetCurFrame(f)
		local p = cleanDir .. sep .. prefix .. string.format("%04d.png", f)
		moho:FileRender(p)
		files[#files + 1] = p
	end

	moho:SetCurFrame(origFrame)
	moho:UpdateUI()

	return {
		rendered = true,
		count = #files,
		startFrame = startF,
		endFrame = endF,
		step = step,
		files = json.array(files),
	}
end

-- --- Layer Comps (verified in Moho Pro 14.4: GetLayerComp, AddLayerCompWithName, DeleteLayerComp(idx), ApplyLayerComp(comp, frame)) ---

local function serializeLayerComp(moho, comp, idx)
	local members = {}
	helpers.walkLayers(moho, function(layer, lid)
		if comp:ContainsLayer(layer) then
			members[#members + 1] = { id = lid, name = layer:Name() }
		end
	end)
	return {
		index = idx,
		name = comp:Name(),
		layerCount = comp:CountLayers(),
		layers = json.array(members),
	}
end

local function findLayerComp(doc, params)
	if params.index ~= nil then
		local idx = math.floor(tonumber(params.index))
		if idx < 0 or idx >= doc:CountLayerComps() then
			return nil, -1, "LayerComp index out of range: " .. tostring(idx)
		end
		return doc:GetLayerComp(idx), idx, nil
	end
	if params.name ~= nil then
		local target = tostring(params.name)
		for i = 0, doc:CountLayerComps() - 1 do
			local c = doc:GetLayerComp(i)
			if c and c:Name() == target then
				return c, i, nil
			end
		end
		return nil, -1, "LayerComp not found: " .. target
	end
	return nil, -1, "Provide LayerComp name or index"
end

function document.layerCompList(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local list = {}
	for i = 0, doc:CountLayerComps() - 1 do
		local c = doc:GetLayerComp(i)
		if c then
			list[#list + 1] = serializeLayerComp(moho, c, i)
		end
	end
	return {
		count = #list,
		layerComps = json.array(list),
	}
end

function document.layerCompManage(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local op = string.lower(tostring(params.operation or "create"))
	helpers.prepUndo(moho, moho.layer, true)

	local includeChildren = (params.includeChildren ~= false)
	local function addLayerRecursive(comp, layer)
		if not layer then return end
		comp:AddLayer(layer)
		if includeChildren and layer:IsGroupType() then
			local grp = moho:LayerAsGroup(layer)
			if grp then
				for ci = 0, grp:CountLayers() - 1 do
					addLayerRecursive(comp, grp:Layer(ci))
				end
			end
		end
	end

	local function addSpecifiedLayers(comp)
		if type(params.layerIds) == "table" then
			for i = 1, #params.layerIds do
				local l = helpers.resolveLayer(moho, { layerId = math.floor(tonumber(params.layerIds[i])) })
				addLayerRecursive(comp, l)
			end
		end
		if type(params.layerNames) == "table" then
			for i = 1, #params.layerNames do
				local l = helpers.resolveLayer(moho, { layerName = tostring(params.layerNames[i]) })
				addLayerRecursive(comp, l)
			end
		end
	end

	if op == "create" then
		local name = tostring(params.name or "")
		if #name == 0 then
			return nil, "name is required for layercomp create"
		end
		local comp = doc:AddLayerCompWithName(name)
		if not comp then
			return nil, "AddLayerCompWithName returned nil"
		end
		if params.replaceExistingLayers ~= false and (type(params.layerIds) == "table" or type(params.layerNames) == "table") then
			comp:RemoveAllLayers()
			addSpecifiedLayers(comp)
		end
		helpers.updateUI(moho)
		return serializeLayerComp(moho, comp, doc:CountLayerComps() - 1)
	elseif op == "set_layers" then
		local comp, idx, err = findLayerComp(doc, params)
		if not comp then return nil, err end
		if params.clearFirst ~= false then
			comp:RemoveAllLayers()
		end
		addSpecifiedLayers(comp)
		helpers.updateUI(moho)
		return serializeLayerComp(moho, comp, idx)
	elseif op == "apply" then
		local comp, idx, err = findLayerComp(doc, params)
		if not comp then return nil, err end
		local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
		-- Verified in Moho Pro 14.4: doc:ApplyLayerComp(comp, frame)
		doc:ApplyLayerComp(comp, frame)
		helpers.updateUI(moho)
		return {
			applied = true,
			index = idx,
			name = comp:Name(),
			frame = frame,
		}
	elseif op == "rename" then
		local comp, idx, err = findLayerComp(doc, params)
		if not comp then return nil, err end
		local newName = tostring(params.newName or "")
		if #newName == 0 then
			return nil, "newName is required for layercomp rename"
		end
		local oldName = comp:Name()
		-- Verified in Moho Pro 14.4: LayerComp:SetName takes LM.String userdata, NOT a Lua string.
		local lmName = LM.String:new_local()
		lmName:Set(newName)
		comp:SetName(lmName)
		helpers.updateUI(moho)
		local out = serializeLayerComp(moho, comp, idx)
		out.renamed = true
		out.oldName = oldName
		return out
	elseif op == "show" or op == "hide" then
		local comp, idx, err = findLayerComp(doc, params)
		if not comp then return nil, err end
		local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
		local visible = (op == "show")
		local affected = 0
		helpers.walkLayers(moho, function(layer)
			if comp:ContainsLayer(layer) then
				if layer.fVisibility then
					layer.fVisibility:SetValue(frame, visible)
				end
				if layer.SetVisible then
					layer:SetVisible(visible)
				end
				affected = affected + 1
			end
		end)
		helpers.updateUI(moho)
		return {
			operation = op,
			index = idx,
			name = comp:Name(),
			frame = frame,
			visible = visible,
			affectedLayers = affected,
		}
	elseif op == "snapshot_visible" then
		local name = tostring(params.name or "")
		if #name == 0 then
			return nil, "name is required for layercomp snapshot_visible"
		end
		local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
		local comp, idx = findLayerComp(doc, { name = name })
		if not comp then
			comp = doc:AddLayerCompWithName(name)
			if not comp then
				return nil, "AddLayerCompWithName returned nil"
			end
			idx = doc:CountLayerComps() - 1
		end
		comp:RemoveAllLayers()
		local added = 0
		helpers.walkLayers(moho, function(layer)
			local isVis = false
			if layer.fVisibility then
				isVis = (layer.fVisibility:GetValue(frame) == true)
			elseif layer.IsVisible then
				isVis = (layer:IsVisible() == true)
			end
			if isVis then
				comp:AddLayer(layer)
				added = added + 1
			end
		end)
		helpers.updateUI(moho)
		local out = serializeLayerComp(moho, comp, idx)
		out.snapshotted = true
		out.frame = frame
		out.capturedVisibleCount = added
		return out
	elseif op == "expose_timeline" then
		local comp, idx, err = findLayerComp(doc, params)
		if not comp then return nil, err end
		local shown = (params.shown ~= false)
		local exclusive = (params.exclusive == true)
		local shownCount, hiddenCount = 0, 0
		helpers.walkLayers(moho, function(layer)
			if layer.SetShownOnTimeline then
				if comp:ContainsLayer(layer) then
					layer:SetShownOnTimeline(shown)
					if shown then shownCount = shownCount + 1 else hiddenCount = hiddenCount + 1 end
				elseif exclusive then
					layer:SetShownOnTimeline(false)
					hiddenCount = hiddenCount + 1
				end
			end
		end)
		helpers.updateUI(moho)
		return {
			exposed = true,
			index = idx,
			name = comp:Name(),
			shown = shown,
			exclusive = exclusive,
			shownLayers = shownCount,
			hiddenLayers = hiddenCount,
		}
	elseif op == "delete" then
		local comp, idx, err = findLayerComp(doc, params)
		if not comp then return nil, err end
		local cname = comp:Name()
		-- Verified: doc:DeleteLayerComp(index)
		doc:DeleteLayerComp(idx)
		helpers.updateUI(moho)
		return {
			deleted = true,
			index = idx,
			name = cname,
		}
	end

	return nil, "Unsupported layercomp operation (use create, set_layers, apply, rename, show, hide, snapshot_visible, expose_timeline, delete): " .. op
end

return document
