-- Switch Layers (lip-sync / prop swap / Frame-by-Frame) and Particle Layer tools.
-- All APIs verified against Moho Pro 14.4 official scripts (lm_switch_layer.lua, lm_particle_layer.lua).

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local special = {}

--- Inspect or keyframe active child of a SwitchLayer (or configure interpolation / Frame-by-Frame mode).
function special.switchSetActive(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local sw = moho:LayerAsSwitch(layer)
	if not sw then
		return nil, "Layer '" .. layer:Name() .. "' is not a SwitchLayer"
	end

	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local children = {}
	for i = sw:CountLayers() - 1, 0, -1 do
		children[#children + 1] = sw:Layer(i):Name()
	end

	local mutated = false
	if params.childName ~= nil or type(params.keyframes) == "table" or params.interpMode ~= nil or params.frameByFrame ~= nil then
		helpers.prepUndo(moho, layer, true)
		mutated = true
	end

	local sv = sw:SwitchValues()
	if params.childName ~= nil then
		sv:SetValue(frame, tostring(params.childName))
	end
	if type(params.keyframes) == "table" then
		for i = 1, #params.keyframes do
			local k = params.keyframes[i]
			if k and k.frame ~= nil and k.childName ~= nil then
				sv:SetValue(math.floor(tonumber(k.frame)), tostring(k.childName))
			end
		end
	end
	if params.interpMode ~= nil and sw.SetInterpMode then
		sw:SetInterpMode(params.interpMode == true)
	end
	if params.frameByFrame ~= nil and sw.SetFBFLayer then
		sw:SetFBFLayer(params.frameByFrame == true)
	end

	if mutated then
		helpers.updateUI(moho)
	end

	local currentVal = ""
	if sw.GetValue then
		local ok, v = pcall(function() return sw:GetValue(frame) end)
		if ok and v ~= nil then
			currentVal = (type(v) == "userdata" and v.Buffer) and v:Buffer() or tostring(v)
		end
	end
	if currentVal == "" and sv and sv.value and sv.value.Buffer then
		currentVal = sv.value:Buffer()
	end

	return {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		activeChild = currentVal,
		interpMode = sw.InterpMode and sw:InterpMode() or false,
		frameByFrame = sw.IsFBFLayer and sw:IsFBFLayer() or false,
		children = json.array(children),
	}
end

--- Configure a Moho Pro ParticleLayer (verified against lm_particle_layer.lua, calls FinalizeSettings()).
function special.particleConfigure(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local pl = moho:LayerAsParticle(layer)
	if not pl then
		return nil, "Layer '" .. layer:Name() .. "' is not a ParticleLayer"
	end

	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or 0
	local mutateKeys = {
		"numParticles", "previewCount", "previewPercentage", "lifetime", "playbackTimeShift",
		"sourceDimensions", "velocity", "velocitySpread", "damping", "running",
		"fullSpeedStart", "orientation", "freeFloating", "evenlySpaced", "randomStartTime",
		"emitInOrder", "useBaseLayerAsSource", "randomSeed", "directionDeg",
		"directionSpreadDeg", "accelerationDeg", "accelerationRate",
	}
	local mutated = false
	for i = 1, #mutateKeys do
		if params[mutateKeys[i]] ~= nil then
			mutated = true
			break
		end
	end

	if mutated then
		helpers.prepUndo(moho, layer, true)

		if params.numParticles ~= nil then
			local n = math.max(1, math.floor(tonumber(params.numParticles)))
			local prev = params.previewCount ~= nil and math.max(1, math.floor(tonumber(params.previewCount))) or n
			pl:SetNumParticles(n, prev)
		end
		if params.previewPercentage ~= nil then
			pl:SetPreviewPercentage(tonumber(params.previewPercentage))
		end
		if params.lifetime ~= nil then
			pl:SetLifetime(math.max(0, math.floor(tonumber(params.lifetime))))
		end
		if params.playbackTimeShift ~= nil then
			pl:SetPlaybackTimeShift(math.floor(tonumber(params.playbackTimeShift)))
		end
		if type(params.sourceDimensions) == "table" then
			local sd = params.sourceDimensions
			local v = LM.Vector3:new_local()
			v:Set(tonumber(sd.width or sd.x) or 0, tonumber(sd.height or sd.y) or 0, tonumber(sd.depth or sd.z) or 0)
			pl:SetSourceDimensions(v)
		end
		if params.velocity ~= nil or params.velocitySpread ~= nil then
			local curVel, curSpread = pl:GetVelocity(0, 0)
			pl:SetVelocity(
				params.velocity ~= nil and tonumber(params.velocity) or curVel,
				params.velocitySpread ~= nil and tonumber(params.velocitySpread) or curSpread
			)
		end
		if params.damping ~= nil then
			pl:SetDamping(tonumber(params.damping))
		end
		if params.running ~= nil and pl.RunningTrack then
			pl:RunningTrack():SetValue(frame, params.running == true)
		end
		if params.fullSpeedStart ~= nil then pl:SetFullSpeedStart(params.fullSpeedStart == true) end
		if params.orientation ~= nil then pl:SetOrientation(params.orientation == true) end
		if params.freeFloating ~= nil then pl:SetFreeFloating(params.freeFloating == true) end
		if params.evenlySpaced ~= nil then pl:SetEvenlySpaced(params.evenlySpaced == true) end
		if params.randomStartTime ~= nil then pl:SetRandomStartTime(params.randomStartTime == true) end
		if params.emitInOrder ~= nil then pl:SetEmitInOrder(params.emitInOrder == true) end
		if params.useBaseLayerAsSource ~= nil then pl:SetUseBaseLayerAsSource(params.useBaseLayerAsSource == true) end
		if params.randomSeed ~= nil and pl.SetRandomSeed then
			pl:SetRandomSeed(math.floor(tonumber(params.randomSeed)))
		end
		if params.directionDeg ~= nil or params.directionSpreadDeg ~= nil then
			local curDir, curHalfSpread = pl:GetDirection(0, 0)
			local dirRad = params.directionDeg ~= nil and math.rad(tonumber(params.directionDeg)) or curDir
			local spreadHalfRad = params.directionSpreadDeg ~= nil and math.rad(tonumber(params.directionSpreadDeg) * 0.5) or curHalfSpread
			pl:SetDirection(dirRad, spreadHalfRad)
		end
		if params.accelerationDeg ~= nil or params.accelerationRate ~= nil then
			local curAccDir, curAccRate = pl:GetAcceleration(0, 0)
			local accDir = params.accelerationDeg ~= nil and math.rad(tonumber(params.accelerationDeg)) or curAccDir
			local accRate = params.accelerationRate ~= nil and tonumber(params.accelerationRate) or curAccRate
			pl:SetAcceleration(accDir, accRate)
		end

		pl:FinalizeSettings()
		helpers.updateUI(moho)
	end

	local numP, prevCount = pl:GetNumParticles(0, 0)
	local srcDim = pl.SourceDimensions and pl:SourceDimensions() or nil
	local vel, velSpread = pl:GetVelocity(0, 0)
	local dir, dirHalf = pl:GetDirection(0, 0)
	local accDir, accRate = pl:GetAcceleration(0, 0)
	local canUseBase = (pl:CountLayers() >= 2) and (pl:Layer(0):LayerType() == MOHO.LT_VECTOR)
	return {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		mutated = mutated,
		numParticles = numP,
		previewCount = prevCount,
		previewPercentage = pl.PreviewPercentage and pl:PreviewPercentage() or 0,
		lifetime = pl:Lifetime(),
		playbackTimeShift = pl.PlaybackTimeShift and pl:PlaybackTimeShift() or 0,
		sourceDimensions = srcDim and { width = srcDim.x, height = srcDim.y, depth = srcDim.z } or nil,
		velocity = vel,
		velocitySpread = velSpread,
		damping = pl:Damping(),
		directionDeg = math.deg(dir),
		directionSpreadDeg = math.deg(dirHalf * 2.0),
		accelerationDeg = math.deg(accDir),
		accelerationRate = accRate,
		running = pl:RunningTrack():GetValue(frame),
		fullSpeedStart = pl:FullSpeedStart(),
		orientation = pl.Orientation and pl:Orientation() or false,
		freeFloating = pl:FreeFloating(),
		evenlySpaced = pl:EvenlySpaced(),
		randomStartTime = pl.RandomStartTime and pl:RandomStartTime() or false,
		emitInOrder = pl:EmitInOrder(),
		useBaseLayerAsSource = pl.UseBaseLayerAsSource and pl:UseBaseLayerAsSource() or false,
		canUseBaseLayerAsSource = canUseBase,
	}
end

local function findSwitchChildByName(sw, childName)
	for i = 0, sw:CountLayers() - 1 do
		local c = sw:Layer(i)
		if c and c:Name() == childName then
			return c, i
		end
	end
	return nil, -1
end

local function uniqueChildName(sw, baseName)
	local candidate = baseName
	local n = 1
	while findSwitchChildByName(sw, candidate) ~= nil do
		n = n + 1
		candidate = baseName .. " " .. tostring(n)
	end
	return candidate
end

local function readSwitchValAt(sw, sv, frame)
	if sw.GetValue then
		local ok, v = pcall(function() return sw:GetValue(frame) end)
		if ok and v ~= nil then
			return (type(v) == "userdata" and v.Buffer) and v:Buffer() or tostring(v)
		end
	end
	if sv and sv.GetValue then
		local ok, v = pcall(function() return sv:GetValue(frame) end)
		if ok and v ~= nil then
			return (type(v) == "userdata" and v.Buffer) and v:Buffer() or tostring(v)
		end
	end
	return ""
end

local function serializeFbfTimeline(moho, layer, id, sw)
	local sv = sw:SwitchValues()
	local childByName = {}
	local children = {}
	for i = sw:CountLayers() - 1, 0, -1 do
		local c = sw:Layer(i)
		if c then
			local cname = c:Name()
			local cid = helpers.getLayerId(moho, c)
			childByName[cname] = cid
			children[#children + 1] = { id = cid, name = cname, type = helpers.layerTypeName(c) }
		end
	end
	local timeline = {}
	if sv and sv.CountKeys then
		for i = 0, sv:CountKeys() - 1 do
			local when = sv:GetKeyWhen(i)
			local val = readSwitchValAt(sw, sv, when)
			timeline[#timeline + 1] = {
				frame = when,
				childName = val,
				childLayerId = childByName[val] or -1,
			}
		end
	end
	return {
		layerId = id,
		layerName = layer:Name(),
		frameByFrame = sw.IsFBFLayer and (sw:IsFBFLayer() == true) or false,
		childCount = #children,
		children = json.array(children),
		keyCount = #timeline,
		timeline = json.array(timeline),
	}
end

--- Frame-by-Frame (FBF) SwitchLayer authoring: list_timeline, add_blank_frame, duplicate_frame, clone_frame, delete_frame, push_frames.
function special.fbfManage(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local sw = moho:LayerAsSwitch(layer)
	if not sw then
		return nil, "Layer '" .. layer:Name() .. "' is not a Switch/Frame-by-Frame layer"
	end
	local op = string.lower(tostring(params.operation or "list_timeline"))
	local sv = sw:SwitchValues()
	if not sv then
		return nil, "SwitchValues channel unavailable on layer '" .. layer:Name() .. "'"
	end

	if op == "list_timeline" then
		return serializeFbfTimeline(moho, layer, id, sw)
	end

	helpers.prepUndo(moho, layer, true)
	if params.autoEnableFbf ~= false and sw.SetFBFLayer and sw.IsFBFLayer and not sw:IsFBFLayer() then
		sw:SetFBFLayer(true)
	end

	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	if op == "add_blank_frame" then
		local prevFrame0 = readSwitchValAt(sw, sv, 0)
		local desired = (type(params.name) == "string" and #params.name > 0)
			and uniqueChildName(sw, params.name)
			or uniqueChildName(sw, "Frame " .. tostring(sw:CountLayers() + 1))
		local child = moho:CreateNewLayer(MOHO.LT_VECTOR, false)
		if not child then
			return nil, "Failed to create blank vector child layer"
		end
		child:SetName(desired)
		moho:PlaceLayerInGroup(child, layer, true, false)
		if frame > 0 and prevFrame0 ~= "" then
			sv:SetValue(0, prevFrame0)
		end
		sv:SetValue(frame, desired)
		moho:SetSelLayer(child)
		helpers.updateUI(moho)
		local out = serializeFbfTimeline(moho, layer, id, sw)
		out.addedFrame = frame
		out.createdLayerId = helpers.getLayerId(moho, child)
		out.createdLayerName = desired
		return out

	elseif op == "duplicate_frame" then
		local prevFrame0 = readSwitchValAt(sw, sv, 0)
		local srcName = params.sourceChildName
		if not srcName or srcName == "" then
			local srcFrame = params.sourceFrame ~= nil and math.floor(tonumber(params.sourceFrame)) or frame
			srcName = readSwitchValAt(sw, sv, srcFrame)
		end
		local srcLayer = srcName ~= "" and findSwitchChildByName(sw, srcName) or (sw:CountLayers() > 0 and sw:Layer(sw:CountLayers() - 1) or nil)
		if not srcLayer then
			return nil, "No source child layer found to duplicate in FBF layer"
		end
		local desired = (type(params.name) == "string" and #params.name > 0)
			and uniqueChildName(sw, params.name)
			or uniqueChildName(sw, "Frame " .. tostring(sw:CountLayers() + 1))
		local dup = moho:DuplicateLayer(srcLayer, false)
		if not dup then
			return nil, "Failed to duplicate source FBF frame layer"
		end
		dup:SetName(desired)
		if dup:Parent() ~= layer then
			moho:PlaceLayerInGroup(dup, layer, true, false)
		end
		if frame > 0 and prevFrame0 ~= "" then
			sv:SetValue(0, prevFrame0)
		end
		sv:SetValue(frame, desired)
		moho:SetSelLayer(dup)
		helpers.updateUI(moho)
		local out = serializeFbfTimeline(moho, layer, id, sw)
		out.duplicatedFrom = srcLayer:Name()
		out.frame = frame
		out.createdLayerId = helpers.getLayerId(moho, dup)
		out.createdLayerName = desired
		return out

	elseif op == "clone_frame" then
		local targetName = params.sourceChildName
		if not targetName or targetName == "" then
			local srcFrame = params.sourceFrame ~= nil and math.floor(tonumber(params.sourceFrame)) or math.max(0, frame - 1)
			targetName = readSwitchValAt(sw, sv, srcFrame)
		end
		if not targetName or targetName == "" or not findSwitchChildByName(sw, targetName) then
			return nil, "Target child layer not found for clone_frame: " .. tostring(targetName)
		end
		sv:SetValue(frame, targetName)
		helpers.updateUI(moho)
		local out = serializeFbfTimeline(moho, layer, id, sw)
		out.clonedChildName = targetName
		out.frame = frame
		return out

	elseif op == "delete_frame" then
		if frame == 0 then
			return nil, "Refusing to delete frame 0 setup switch keyframe"
		end
		local prevName = readSwitchValAt(sw, sv, frame)
		local hadKey = sv.HasKey and (sv:HasKey(frame) == true) or false
		if hadKey then
			sv:DeleteKey(frame)
		end
		local deletedLayer = false
		if params.deleteLayer == true and prevName ~= "" then
			local stillUsed = false
			for i = 0, sv:CountKeys() - 1 do
				if readSwitchValAt(sw, sv, sv:GetKeyWhen(i)) == prevName then
					stillUsed = true
					break
				end
			end
			if not stillUsed and sw:CountLayers() > 1 then
				local cl = findSwitchChildByName(sw, prevName)
				if cl then
					moho:DeleteLayer(cl)
					deletedLayer = true
				end
			end
		end
		helpers.updateUI(moho)
		local out = serializeFbfTimeline(moho, layer, id, sw)
		out.deletedFrame = frame
		out.deletedKey = hadKey
		out.deletedLayer = deletedLayer
		return out

	elseif op == "push_frames" then
		local startF = params.startFrame ~= nil and math.floor(tonumber(params.startFrame)) or frame
		local delta = math.floor(tonumber(params.delta) or 0)
		if delta == 0 then
			return serializeFbfTimeline(moho, layer, id, sw)
		end
		local keyFrames = {}
		for i = 0, sv:CountKeys() - 1 do
			local w = sv:GetKeyWhen(i)
			if w >= startF and w > 0 then
				keyFrames[#keyFrames + 1] = { id = i, when = w }
			end
		end
		table.sort(keyFrames, function(a, b) return a.when < b.when end)
		local shifted = 0
		if delta > 0 then
			for i = #keyFrames, 1, -1 do
				local kf = keyFrames[i]
				local kid = sv:GetClosestKeyID(kf.when)
				if kid >= 0 and sv:GetKeyWhen(kid) == kf.when then
					sv:SetKeyWhen(kid, kf.when + delta)
					shifted = shifted + 1
				end
			end
		else
			for i = 1, #keyFrames do
				local kf = keyFrames[i]
				local target = math.max(1, kf.when + delta)
				local kid = sv:GetClosestKeyID(kf.when)
				if kid >= 0 and sv:GetKeyWhen(kid) == kf.when then
					if target ~= kf.when and sv:HasKey(target) then
						sv:DeleteKey(target)
						kid = sv:GetClosestKeyID(kf.when)
					end
					if kid >= 0 and sv:GetKeyWhen(kid) == kf.when then
						sv:SetKeyWhen(kid, target)
						shifted = shifted + 1
					end
				end
			end
		end
		helpers.updateUI(moho)
		local out = serializeFbfTimeline(moho, layer, id, sw)
		out.pushedFrom = startF
		out.delta = delta
		out.shiftedCount = shifted
		return out
	end

	return nil, "Unsupported fbf_manage operation (use list_timeline, add_blank_frame, duplicate_frame, clone_frame, delete_frame, push_frames): " .. op
end

local RHUBARB_TO_PRESTON_BLAIR = {
	A = "MBP",
	B = "etc",
	C = "E",
	D = "AI",
	E = "O",
	F = "U",
	G = "FV",
	H = "L",
	X = "rest",
}

local function trimStr(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parsePapagayoText(rawText)
	local cues = {}
	local text = rawText:gsub("\r\n", "\n"):gsub("\r", "\n")
	for line in text:gmatch("[^\n]+") do
		local trimmed = trimStr(line)
		if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" and trimmed ~= "MohoSwitch1" then
			local fStr, ph = trimmed:match("^(%-?%d+)%s+(.+)$")
			if fStr and ph then
				cues[#cues + 1] = {
					frame = math.floor(tonumber(fStr)),
					phoneme = trimStr(ph),
					seq = #cues + 1,
				}
			end
		end
	end
	return cues
end

local function parseRhubarbTable(decoded, fps, frameOffset)
	local list = nil
	if type(decoded) == "table" then
		if type(decoded.mouthCues) == "table" then
			list = decoded.mouthCues
		elseif #decoded > 0 and type(decoded[1]) == "table" and (decoded[1].start ~= nil or decoded[1].value ~= nil) then
			list = decoded
		end
	end
	if not list then
		return nil, "Rhubarb JSON missing mouthCues array"
	end
	local cues = {}
	for i = 1, #list do
		local item = list[i]
		if type(item) == "table" then
			local ph = item.value or item.phoneme or item.childName
			if ph ~= nil and tostring(ph) ~= "" then
				local f
				if item.frame ~= nil then
					f = math.floor(tonumber(item.frame)) + frameOffset
				else
					local sec = tonumber(item.start or item.timeSec or 0) or 0
					f = math.floor(sec * fps + 0.5) + frameOffset
				end
				cues[#cues + 1] = {
					frame = f,
					phoneme = trimStr(ph),
					seq = #cues + 1,
				}
			end
		end
	end
	return cues, nil
end

--- Import Papagayo (.dat MohoSwitch1), Rhubarb Lip Sync JSON (mouthCues), or explicit cues onto a SwitchLayer.
function special.switchImportLipSync(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local sw = moho:LayerAsSwitch(layer)
	if not sw then
		return nil, "Layer '" .. layer:Name() .. "' is not a SwitchLayer"
	end
	local sv = sw:SwitchValues()
	if not sv then
		return nil, "SwitchValues channel unavailable on layer '" .. layer:Name() .. "'"
	end

	local doc = moho.document
	local fps = tonumber(params.fps) or (doc and doc:Fps()) or 24
	if fps <= 0 then fps = 24 end
	local allowFrame0 = (params.allowFrame0 == true)
	local minFrame = allowFrame0 and 0 or 1
	local fmtReq = string.lower(tostring(params.format or "auto"))
	local rawText = nil

	if type(params.filePath) == "string" and #params.filePath > 0 then
		local f, ferr = io.open(params.filePath, "rb")
		if not f then
			return nil, "Cannot open lip-sync file '" .. params.filePath .. "': " .. tostring(ferr)
		end
		rawText = f:read("*a")
		f:close()
		if rawText:sub(1, 3) == "\239\187\191" then
			rawText = rawText:sub(4)
		end
	elseif type(params.data) == "string" and #params.data > 0 then
		rawText = params.data
	end

	local rawCues = nil
	local detectedFormat = nil
	local frameOffset = nil

	if type(params.cues) == "table" and #params.cues > 0 then
		detectedFormat = "cues"
		local usesTime = false
		for i = 1, #params.cues do
			if type(params.cues[i]) == "table" and params.cues[i].frame == nil and (params.cues[i].timeSec ~= nil or params.cues[i].start ~= nil) then
				usesTime = true
				break
			end
		end
		frameOffset = params.frameOffset ~= nil and math.floor(tonumber(params.frameOffset)) or (usesTime and 1 or 0)
		rawCues = {}
		for i = 1, #params.cues do
			local c = params.cues[i]
			if type(c) == "table" then
				local ph = c.phoneme or c.value or c.childName
				if ph ~= nil and tostring(ph) ~= "" then
					local f
					if c.frame ~= nil then
						f = math.floor(tonumber(c.frame)) + frameOffset
					else
						local sec = tonumber(c.timeSec or c.start or 0) or 0
						f = math.floor(sec * fps + 0.5) + frameOffset
					end
					rawCues[#rawCues + 1] = {
						frame = f,
						phoneme = trimStr(ph),
						seq = #rawCues + 1,
					}
				end
			end
		end
	elseif rawText ~= nil then
		local trimmed = trimStr(rawText)
		local firstChar = trimmed:sub(1, 1)
		local wantJson = (fmtReq == "rhubarb_json" or fmtReq == "rhubarb" or fmtReq == "json")
			or (fmtReq == "auto" and (firstChar == "{" or firstChar == "["))
		if wantJson then
			local okDec, decoded = pcall(json.decode, trimmed)
			if not okDec then
				return nil, "Failed to decode Rhubarb JSON: " .. tostring(decoded)
			end
			frameOffset = params.frameOffset ~= nil and math.floor(tonumber(params.frameOffset)) or 1
			local parsed, perr = parseRhubarbTable(decoded, fps, frameOffset)
			if not parsed then
				return nil, perr
			end
			rawCues = parsed
			detectedFormat = "rhubarb_json"
		else
			frameOffset = params.frameOffset ~= nil and math.floor(tonumber(params.frameOffset)) or 0
			local parsed = parsePapagayoText(rawText)
			for i = 1, #parsed do
				parsed[i].frame = parsed[i].frame + frameOffset
			end
			rawCues = parsed
			detectedFormat = "papagayo"
		end
	else
		return nil, "Provide filePath, data, or non-empty cues array"
	end

	if #rawCues == 0 then
		return nil, "No valid lip-sync cues parsed from input (format=" .. tostring(detectedFormat) .. ")"
	end

	-- Index existing SwitchLayer children
	local childNames = {}
	local childExact = {}
	local childLower = {}
	for i = sw:CountLayers() - 1, 0, -1 do
		local c = sw:Layer(i)
		if c then
			local cn = c:Name()
			childNames[#childNames + 1] = cn
			childExact[cn] = cn
			local lc = string.lower(cn)
			if childLower[lc] == nil then
				childLower[lc] = cn
			end
		end
	end

	local preset = string.lower(tostring(params.preset or "none"))
	local userMap = type(params.phonemeMap) == "table" and params.phonemeMap or nil
	local caseInsensitive = (params.caseInsensitive ~= false)
	local dedupeAdjacent = (params.dedupeAdjacent ~= false)

	local function resolveChildName(name)
		if name == nil or name == "" then
			return nil
		end
		if childExact[name] then
			return childExact[name]
		end
		if caseInsensitive then
			return childLower[string.lower(name)]
		end
		return nil
	end

	local fallbackResolved = nil
	if type(params.fallbackChild) == "string" and #params.fallbackChild > 0 then
		fallbackResolved = resolveChildName(params.fallbackChild)
		if not fallbackResolved then
			return nil, "fallbackChild '" .. params.fallbackChild .. "' not found among SwitchLayer children"
		end
	end

	table.sort(rawCues, function(a, b)
		if a.frame == b.frame then
			return a.seq < b.seq
		end
		return a.frame < b.frame
	end)

	-- Collapse same-frame cues (last wins) and map phonemes to SwitchLayer children
	local byFrameOrder = {}
	local byFrameSlot = {}
	local missingSet = {}
	local skippedCount = 0
	for i = 1, #rawCues do
		local c = rawCues[i]
		local ph = c.phoneme
		local mapped = ph
		if userMap and userMap[ph] ~= nil then
			mapped = tostring(userMap[ph])
		elseif userMap and caseInsensitive then
			for k, v in pairs(userMap) do
				if string.lower(tostring(k)) == string.lower(ph) then
					mapped = tostring(v)
					break
				end
			end
		elseif preset == "rhubarb_to_preston_blair" then
			local pMapped = RHUBARB_TO_PRESTON_BLAIR[string.upper(ph)]
			if pMapped then
				mapped = pMapped
			end
		end

		local resolved = resolveChildName(mapped)
		if not resolved then
			missingSet[mapped] = true
			if fallbackResolved then
				resolved = fallbackResolved
			end
		end
		if resolved then
			local f = math.max(minFrame, c.frame)
			if byFrameSlot[f] == nil then
				byFrameOrder[#byFrameOrder + 1] = f
			end
			byFrameSlot[f] = resolved
		else
			skippedCount = skippedCount + 1
		end
	end

	local missingList = {}
	for k, _ in pairs(missingSet) do
		missingList[#missingList + 1] = k
	end
	table.sort(missingList)

	local finalKeys = {}
	local prevChild = nil
	for i = 1, #byFrameOrder do
		local f = byFrameOrder[i]
		local chName = byFrameSlot[f]
		if (not dedupeAdjacent) or (chName ~= prevChild) then
			finalKeys[#finalKeys + 1] = { frame = f, childName = chName }
			prevChild = chName
		end
	end

	helpers.prepUndo(moho, layer, true)

	local prevFrame0 = readSwitchValAt(sw, sv, 0)
	local clearedCount = 0
	if params.clearExisting == true and sv.CountKeys then
		local clearFrom = params.clearFromFrame ~= nil and math.floor(tonumber(params.clearFromFrame)) or minFrame
		clearFrom = math.max(minFrame, clearFrom)
		local toDelete = {}
		for i = 0, sv:CountKeys() - 1 do
			local w = sv:GetKeyWhen(i)
			if w >= clearFrom then
				toDelete[#toDelete + 1] = w
			end
		end
		for i = #toDelete, 1, -1 do
			sv:DeleteKey(toDelete[i])
			clearedCount = clearedCount + 1
		end
	end

	if params.interpMode ~= nil and sw.SetInterpMode then
		sw:SetInterpMode(params.interpMode == true)
	end

	for i = 1, #finalKeys do
		sv:SetValue(finalKeys[i].frame, finalKeys[i].childName)
	end
	if (not allowFrame0) and prevFrame0 ~= "" then
		sv:SetValue(0, prevFrame0)
	end

	helpers.updateUI(moho)

	return {
		imported = true,
		layerId = id,
		layerName = layer:Name(),
		sourceFormat = detectedFormat,
		fps = fps,
		frameOffset = frameOffset,
		totalCues = #rawCues,
		clearedKeys = clearedCount,
		writtenKeys = #finalKeys,
		skippedCues = skippedCount,
		missingChildren = json.array(missingList),
		children = json.array(childNames),
		interpMode = sw.InterpMode and (sw:InterpMode() == true) or false,
		timeline = json.array(finalKeys),
	}
end

return special
