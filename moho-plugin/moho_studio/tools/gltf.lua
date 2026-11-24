-- Headless Moho Pro 14.4 glTF 2.0 / GLB export wrapper and pre-flight rig auditor.
-- Bridges Moho 14.4's bundled Tool/ss_gltf_export.lua (SS_glTFExport) by bypassing
-- SS_glTFExportDialog:DoModal() cleanly via Lua 5.4 debug.getupvalue and restoring state.

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local gltfTools = {}

local KNOWN_GLTF_TAGS = {
	"gltf_comp",
	"gltf_nomesh",
	"gltf_nowarp",
	"gltf_nobones",
	"gltf_blend",
	"gltf_skinned",
	"gltf_render",
	"gltf_fps",
}

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

local function normalizeFolderWithSlash(dir)
	if type(dir) ~= "string" or dir == "" then
		return ""
	end
	local norm = dir:gsub("\\", "/")
	if norm:sub(-1) ~= "/" then
		norm = norm .. "/"
	end
	return norm
end

local function fileSizeIfExists(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local sz = f:seek("end")
	f:close()
	return sz
end

local function extractGltfTags(tagStr)
	local found = {}
	if type(tagStr) ~= "string" or tagStr == "" then
		return found
	end
	for i = 1, #KNOWN_GLTF_TAGS do
		local tag = KNOWN_GLTF_TAGS[i]
		if tagStr:find("%f[%w_]" .. tag .. "%f[^%w_]") then
			found[#found + 1] = tag
		end
	end
	for token in tagStr:gmatch("gltf_[%w_]+=?[-%w%.]*") do
		local already = false
		for i = 1, #found do
			if found[i] == token then
				already = true
				break
			end
		end
		if not already then
			found[#found + 1] = token
		end
	end
	return found
end

function gltfTools.exportGltf(moho, params)
	params = params or {}
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	if type(SS_glTFExport) ~= "table" or type(SS_glTFExport.Run) ~= "function" then
		return nil, "Moho 14.4 SS_glTFExport script is not loaded in this Moho session"
	end

	-- Ensure json/base64 upvalues inside SS_glTFExport are initialized.
	local upJson = findUpvalueByName(SS_glTFExport.Run, "json")
	if not upJson and type(SS_glTFExport.IsRelevant) == "function" then
		pcall(function() SS_glTFExport:IsRelevant(moho) end)
	end

	local dlogTbl = findUpvalueByName(SS_glTFExport.Run, "SS_glTFExportDialog")
	if type(dlogTbl) ~= "table" then
		return nil, "Unable to locate SS_glTFExportDialog upvalue for headless bypass"
	end

	local docPath = doc:Path() or ""
	local docName = doc:Name() or "export.moho"
	local docBase = docName:match("(.+)%..+$") or docName
	local docDir = ""
	if docPath ~= "" then
		docDir = docPath:sub(1, math.max(0, #docPath - #docName))
	end

	local targetDir = ""
	if type(params.outputDir) == "string" and #params.outputDir > 0 then
		targetDir = normalizeFolderWithSlash(params.outputDir)
	elseif docDir ~= "" then
		targetDir = normalizeFolderWithSlash(docDir)
	else
		return nil, "Document is not saved on disk and outputDir was not provided. Save the document or pass outputDir."
	end

	local cleanDir = targetDir:gsub("[/\\]+$", "")
	if LM and LM.CreateDir then
		pcall(function() LM.CreateDir(cleanDir) end)
	end

	local targetFileName = (type(params.fileName) == "string" and #params.fileName > 0)
		and params.fileName:gsub("%.[gG][lL][bBtT][fF]?$", "")
		or docBase

	local fmt = string.lower(tostring(params.format or "glb"))
	local exportGLB = (fmt == "glb" or fmt == "both")
	local exportGLTF = (fmt == "gltf" or fmt == "both")
	if not exportGLB and not exportGLTF then
		return nil, "Invalid format (use glb, gltf, or both): " .. tostring(params.format)
	end

	local reRenderMap = {
		none = 1,
		all = 2,
		selected = 3,
		once = 4,
	}
	local rrKey = string.lower(tostring(params.reRender or "none"))
	local rrId = reRenderMap[rrKey] or 1

	local scaleVal = params.scale ~= nil and tonumber(params.scale) or 1.0
	scaleVal = math.max(SS_glTFExport.MIN_GLTF_SCALE or 0.1, math.min(SS_glTFExport.MAX_GLTF_SCALE or 10, scaleVal))

	local gridDensity = params.gridDensity ~= nil and math.floor(tonumber(params.gridDensity)) or 20
	gridDensity = math.max(SS_glTFExport.MIN_GLTF_GRID_DENSITY or 1, math.min(SS_glTFExport.MAX_GLTF_GRID_DENSITY or 100, gridDensity))

	local zOffset = params.zOffset ~= nil and tonumber(params.zOffset) or 1
	zOffset = math.max(SS_glTFExport.MIN_GLTF_ZOFFSET or 0.1, math.min(SS_glTFExport.MAX_GLTF_ZOFFSET or 100, zOffset))

	local flipZOrder = (params.flipZOrder == true)
	local doFbf = (params.fbf == true)
	local fbfStep = params.fbfStep ~= nil and math.floor(tonumber(params.fbfStep)) or 1
	fbfStep = math.max(SS_glTFExport.MIN_GLTF_FBFSTEP or 1, math.min(SS_glTFExport.MAX_GLTF_FBFSTEP or 999, fbfStep))

	local commentStr = params.comment ~= nil and tostring(params.comment) or ""
	local copyrightStr = params.copyright ~= nil and tostring(params.copyright) or ""

	-- Save existing SS_glTFExport state for guaranteed restoration.
	local saveKeys = {
		"gltf_exportGLB", "gltf_exportGLTF", "gltf_FBF", "gltf_FBFStep",
		"gltf_gridDensity", "gltf_renderid", "gltf_render", "gltf_scale",
		"gltf_zOffset", "gltf_flipZOrder", "Z_OFFSET", "gltf_fileName",
		"gltf_folderPath", "gltf_folderPath_", "gltf_fileName_",
		"gltf_comment", "gltf_copyright", "gltf_logLevel", "gltf_logDelayed",
	}
	local savedState = {}
	for i = 1, #saveKeys do
		local k = saveKeys[i]
		savedState[k] = SS_glTFExport[k]
	end

	local origNew = dlogTbl.new
	local origAlert = (LM and LM.GUI) and LM.GUI.Alert or nil
	local alerts = {}

	local function applyHeadlessSettings()
		SS_glTFExport.gltf_exportGLB = exportGLB
		SS_glTFExport.gltf_exportGLTF = exportGLTF
		SS_glTFExport.gltf_FBF = doFbf
		SS_glTFExport.gltf_FBFStep = fbfStep
		SS_glTFExport.gltf_gridDensity = gridDensity
		SS_glTFExport.gltf_renderid = rrId
		SS_glTFExport.gltf_render = SS_glTFExport.RE_RENDER and SS_glTFExport.RE_RENDER[rrId] or false
		SS_glTFExport.gltf_scale = scaleVal
		SS_glTFExport.gltf_zOffset = zOffset
		SS_glTFExport.gltf_flipZOrder = flipZOrder
		SS_glTFExport.Z_OFFSET = zOffset * (SS_glTFExport.Z_OFFSETTER or -0.0001)
		SS_glTFExport.gltf_fileName = targetFileName
		SS_glTFExport.gltf_fileName_ = targetFileName
		SS_glTFExport.gltf_folderPath = targetDir
		SS_glTFExport.gltf_folderPath_ = targetDir
		SS_glTFExport.gltf_comment = commentStr
		SS_glTFExport.gltf_copyright = copyrightStr
		SS_glTFExport.gltf_logLevel = SS_glTFExport.LOG_LEVEL_NONE or 1
		SS_glTFExport.gltf_logDelayed = true
	end

	dlogTbl.new = function()
		return {
			DoModal = function()
				applyHeadlessSettings()
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

	local okRun, runRet = pcall(function()
		return SS_glTFExport:Run(moho)
	end)

	-- Restore dialog hook, Alert hook, and script globals unconditionally.
	dlogTbl.new = origNew
	if LM and LM.GUI and origAlert then
		LM.GUI.Alert = origAlert
	end
	for i = 1, #saveKeys do
		local k = saveKeys[i]
		SS_glTFExport[k] = savedState[k]
	end

	helpers.updateUI(moho)

	if not okRun then
		return nil, "SS_glTFExport:Run failed: " .. tostring(runRet)
	end

	local files = {}
	if exportGLB then
		local p = targetDir .. targetFileName .. ".glb"
		local sz = fileSizeIfExists(p)
		if sz ~= nil then
			files[#files + 1] = { format = "glb", path = p, bytes = sz }
		end
	end
	if exportGLTF then
		local p = targetDir .. targetFileName .. ".gltf"
		local sz = fileSizeIfExists(p)
		if sz ~= nil then
			files[#files + 1] = { format = "gltf", path = p, bytes = sz }
		end
	end

	if #files == 0 then
		return nil, "glTF export completed without producing output files in " .. targetDir
			.. (#alerts > 0 and (" (alerts: " .. table.concat(alerts, "; ") .. ")") or "")
	end

	return {
		exported = true,
		format = fmt,
		outputDir = targetDir,
		fileName = targetFileName,
		files = json.array(files),
		returnValue = type(runRet) == "string" and runRet or nil,
		alerts = json.array(alerts),
		options = {
			scale = scaleVal,
			gridDensity = gridDensity,
			zOffset = zOffset,
			flipZOrder = flipZOrder,
			fbf = doFbf,
			fbfStep = fbfStep,
			reRender = rrKey,
		},
	}
end

function gltfTools.auditGltf(moho, params)
	params = params or {}
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end

	local issues = {}
	local layerTags = {}
	local docTagStr = doc.UserTags and doc:UserTags() or ""
	local docTags = extractGltfTags(docTagStr)
	local docSaved = (doc:Path() ~= nil and doc:Path() ~= "")

	if not docSaved then
		issues[#issues + 1] = {
			severity = "warning",
			code = "document_unsaved",
			message = "Document has no saved path on disk; save before exporting or pass explicit outputDir to document_exportGltf.",
		}
	end

	local stats = {
		totalLayers = 0,
		vectorLayers = 0,
		animatedVectorsWithoutWarp = 0,
		boneLayersWithDynamics = 0,
		nonInPlaceActions = 0,
		taggedLayers = 0,
	}

	local ancestorComped = {}
	helpers.walkLayers(moho, function(layer, lid, parentId)
		stats.totalLayers = stats.totalLayers + 1
		local tagStr = layer.UserTags and layer:UserTags() or ""
		local tags = extractGltfTags(tagStr)
		local isComped = (parentId >= 0 and ancestorComped[parentId] == true)
		for i = 1, #tags do
			if tags[i] == "gltf_comp" then
				isComped = true
			end
		end
		ancestorComped[lid] = isComped

		if #tags > 0 then
			stats.taggedLayers = stats.taggedLayers + 1
			layerTags[#layerTags + 1] = {
				layerId = lid,
				layerName = layer:Name(),
				layerType = helpers.layerTypeName(layer),
				tags = json.array(tags),
			}
		end

		local lt = layer:LayerType()
		if lt == MOHO.LT_VECTOR then
			stats.vectorLayers = stats.vectorLayers + 1
			local vl = moho:LayerAsVector(layer)
			local mesh = vl and vl:Mesh() or nil
			local warpLayer = layer.WarpLayer and layer:WarpLayer() or nil
			local isWarpSelf = vl and vl.IsWarpLayer and (vl:IsWarpLayer() == true) or false
			if mesh and (not warpLayer) and (not isWarpSelf) and (not isComped) then
				local animatedPts = 0
				for pi = 0, mesh:CountPoints() - 1 do
					local pt = mesh:Point(pi)
					if pt and pt.fAnimPos and pt.fAnimPos:CountKeys() > 1 then
						animatedPts = animatedPts + 1
					end
				end
				if animatedPts > 0 then
					stats.animatedVectorsWithoutWarp = stats.animatedVectorsWithoutWarp + 1
					issues[#issues + 1] = {
						severity = "warning",
						code = "animated_vector_without_warp",
						layerId = lid,
						layerName = layer:Name(),
						animatedPoints = animatedPts,
						message = "Vector layer has " .. tostring(animatedPts)
							.. " point-animated vertices without a Warp Layer; Moho glTF exports vector layers as static textures unless driven by bones/Smart Warp or baked via fbf=true.",
					}
				end
			end
		elseif lt == MOHO.LT_BONE then
			local bl = moho:LayerAsBone(layer)
			local skel = bl and bl:Skeleton() or nil
			if skel then
				local dynBones = {}
				local function hasAxisDyn(ch)
					if ch == nil then return false end
					if type(ch) == "boolean" then return ch end
					if ch.GetValue then
						local ok, v = pcall(function() return ch:GetValue(0) end)
						return ok and (v == true)
					end
					return false
				end
				for bi = 0, skel:CountBones() - 1 do
					local b = skel:Bone(bi)
					if b and b.fBoneDynamics and b.fBoneDynamics:GetValue(0) == true then
						local anyAxis = hasAxisDyn(b.fAngleDynamics)
							or hasAxisDyn(b.fPosDynamics)
							or hasAxisDyn(b.fScaleDynamics)
							or hasAxisDyn(b.fWindDynamics)
						if anyAxis then
							dynBones[#dynBones + 1] = b:Name()
						end
					end
				end
				if #dynBones > 0 then
					stats.boneLayersWithDynamics = stats.boneLayersWithDynamics + 1
					issues[#issues + 1] = {
						severity = "info",
						code = "bone_dynamics_active",
						layerId = lid,
						layerName = layer:Name(),
						bones = json.array(dynBones),
						message = "Bone dynamics active on " .. tostring(#dynBones)
							.. " bone(s); export with fbf=true (Bake every frame) to preserve secondary dynamics in glTF.",
					}
				end
			end
		end

		-- Check non-Smart-Bone Actions for root translation drift (non-in-place Actions).
		if layer.CountActions and layer:CountActions() > 0 then
			local driftTol = tonumber(params.inPlaceTolerance) or 0.15
			for ai = 0, layer:CountActions() - 1 do
				local actName = layer:ActionName(ai)
				local isSmart = layer.IsSmartBoneAction and (layer:IsSmartBoneAction(actName) == true) or false
				if (not isSmart) and actName ~= "" then
					local dur = layer.ActionDuration and layer:ActionDuration(actName) or 0
					if dur > 1 and layer.fTranslation and layer.fTranslation.ActionByName then
						local rawActCh = layer.fTranslation:ActionByName(actName)
						local actCh = (rawActCh and moho.ChannelAsAnimVec3) and moho:ChannelAsAnimVec3(rawActCh) or rawActCh
						if actCh and actCh.GetValue and actCh:CountKeys() > 1 then
							local vStart = actCh:GetValue(1)
							local vEnd = actCh:GetValue(dur)
							local dx = (vEnd.x - vStart.x)
							local dy = (vEnd.y - vStart.y)
							local dist = math.sqrt(dx * dx + dy * dy)
							if dist > driftTol then
								stats.nonInPlaceActions = stats.nonInPlaceActions + 1
								issues[#issues + 1] = {
									severity = "warning",
									code = "non_in_place_action",
									layerId = lid,
									layerName = layer:Name(),
									actionName = actName,
									translationDrift = dist,
									message = "Regular Action '" .. actName .. "' translates layer '" .. layer:Name()
										.. "' by " .. string.format("%.3f", dist)
										.. " doc units; game-engine glTF clips should normally be authored in-place.",
								}
							end
						end
					end
				end
			end
		end
	end)

	local errorCount, warnCount, infoCount = 0, 0, 0
	for i = 1, #issues do
		local sev = issues[i].severity
		if sev == "error" then errorCount = errorCount + 1
		elseif sev == "warning" then warnCount = warnCount + 1
		else infoCount = infoCount + 1 end
	end

	return {
		ready = (errorCount == 0),
		documentName = doc:Name(),
		documentSaved = docSaved,
		docTags = json.array(docTags),
		layerTags = json.array(layerTags),
		issues = json.array(issues),
		summary = {
			errors = errorCount,
			warnings = warnCount,
			infos = infoCount,
			totalLayers = stats.totalLayers,
			vectorLayers = stats.vectorLayers,
			animatedVectorsWithoutWarp = stats.animatedVectorsWithoutWarp,
			boneLayersWithDynamics = stats.boneLayersWithDynamics,
			nonInPlaceActions = stats.nonInPlaceActions,
			taggedLayers = stats.taggedLayers,
		},
	}
end

return gltfTools
