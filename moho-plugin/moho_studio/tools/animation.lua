-- Keyframes, interpolation, Bezier handles, Separate Dimensions, Smart Bone Actions (incl. 360-deg),
-- Range Cycles, Scoped Retiming, Weighted Tweening, Timeline Markers, and Camera tools (v3.0.0).
-- All Moho Pro 14.4 Lua 5.4 signatures verified against bundled scripts and live runtime introspection.

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local animation = {}

local MARKER_SENTINEL_FRAME = -1000000

local function parseDimension(dimVal)
	if dimVal == nil then
		return nil
	end
	if type(dimVal) == "number" then
		local d = math.floor(dimVal)
		if d >= 0 and d <= 2 then
			return d
		end
		return nil
	end
	local s = string.lower(tostring(dimVal))
	if s == "x" or s == "0" then return 0 end
	if s == "y" or s == "1" then return 1 end
	if s == "z" or s == "2" then return 2 end
	return nil
end

local function applyDimensionIfRequested(ch, kind, params, forWrite)
	local dimIdx = parseDimension(params.dimension)
	if dimIdx == nil then
		return ch, kind, nil, nil
	end
	if kind ~= "vec3" and kind ~= "vec2" and kind ~= "angle2" then
		return nil, nil, nil, "dimension '" .. tostring(params.dimension) .. "' only applies to vector channels"
	end
	if (kind == "vec2" or kind == "angle2") and dimIdx > 1 then
		return nil, nil, nil, "2D channel has no Z dimension"
	end
	if not ch.AreDimensionsSplit or not ch.DimensionChannel then
		return nil, nil, nil, "Channel does not support Separate Dimensions"
	end
	if not ch:AreDimensionsSplit() then
		if params.splitDimensions == true or forWrite then
			ch:SplitDimensions(true)
		else
			return nil, nil, nil, "Channel dimensions are not split (pass splitDimensions: true to split)"
		end
	end
	local sub = ch:DimensionChannel(dimIdx)
	if not sub then
		return nil, nil, nil, "DimensionChannel(" .. tostring(dimIdx) .. ") returned nil"
	end
	local subKind = (kind == "angle2") and "angle" or "val"
	return sub, subKind, ch, nil
end

local function resolveBoneInSkeleton(skel, params)
	if not skel then
		return nil, -1
	end
	if params.boneId ~= nil then
		local bid = math.floor(tonumber(params.boneId))
		if bid >= 0 and bid < skel:CountBones() then
			return skel:Bone(bid), bid
		end
		return nil, -1
	end
	if params.boneName ~= nil then
		local target = tostring(params.boneName)
		for i = 0, skel:CountBones() - 1 do
			local b = skel:Bone(i)
			if b and b:Name() == target then
				return b, i
			end
		end
	end
	return nil, -1
end

local function resolveChannel(moho, params, forWrite)
	params = params or {}
	local doc = moho.document
	if not doc then
		return nil, nil, nil, nil, "No document open"
	end

	local rawCh = string.lower(tostring(params.channel or ""))
	local effParams = params
	-- Support dimension suffix shortcuts like translation_x, scale_y, bone_pos_x, point_pos_y, camera_track_z
	local basePrefix, dimSuffix = rawCh:match("^(.+)_([xyz])$")
	if basePrefix and (basePrefix == "translation" or basePrefix == "scale" or basePrefix == "bone_pos"
		or basePrefix == "point_pos" or basePrefix == "camera_track" or basePrefix == "camera_pantilt") then
		rawCh = basePrefix
		effParams = {}
		for k, v in pairs(params) do effParams[k] = v end
		if effParams.dimension == nil then
			effParams.dimension = dimSuffix
		end
	end

	-- Document-level camera channels
	if rawCh == "camera_track" then
		local sub, subKind, parentCh, derr = applyDimensionIfRequested(doc.fCameraTrack, "vec3", effParams, forWrite)
		return sub, subKind, moho.layer, parentCh, derr
	elseif rawCh == "camera_zoom" then
		return doc.fCameraZoom, "val", moho.layer, nil, nil
	elseif rawCh == "camera_roll" then
		return doc.fCameraRoll, "angle", moho.layer, nil, nil
	elseif rawCh == "camera_pantilt" then
		local sub, subKind, parentCh, derr = applyDimensionIfRequested(doc.fCameraPanTilt, "angle2", effParams, forWrite)
		return sub, subKind, moho.layer, parentCh, derr
	end

	local layer, _, err = helpers.resolveLayer(moho, effParams)
	if not layer then
		return nil, nil, nil, nil, err
	end

	-- Standard layer channels
	if rawCh == "translation" then
		local sub, subKind, parentCh, derr = applyDimensionIfRequested(layer.fTranslation, "vec3", effParams, forWrite)
		return sub, subKind, layer, parentCh, derr
	elseif rawCh == "scale" then
		local sub, subKind, parentCh, derr = applyDimensionIfRequested(layer.fScale, "vec3", effParams, forWrite)
		return sub, subKind, layer, parentCh, derr
	elseif rawCh == "rotationz" or rawCh == "rotation" then
		return layer.fRotationZ, "angle", layer, nil, nil
	elseif rawCh == "rotationx" then
		return layer.fRotationX, "angle", layer, nil, nil
	elseif rawCh == "rotationy" then
		return layer.fRotationY, "angle", layer, nil, nil
	elseif rawCh == "opacity" or rawCh == "alpha" then
		return layer.fAlpha, "val", layer, nil, nil
	elseif rawCh == "visibility" then
		return layer.fVisibility, "bool", layer, nil, nil
	elseif rawCh == "blur" then
		return layer.fBlur, "val", layer, nil, nil
	elseif rawCh == "follow_path" then
		if layer.fFollowing then
			return layer.fFollowing, "val", layer, nil, nil
		end
		return nil, nil, layer, nil, "Layer has no fFollowing channel"
	end

	-- Group / Switch channels
	if rawCh == "layer_order" then
		if not layer:IsGroupType() then
			return nil, nil, layer, nil, "layer_order requires a Group, Bone, or Switch layer"
		end
		local grp = moho:LayerAsGroup(layer)
		if forWrite and grp.EnableLayerOrdering then
			grp:EnableLayerOrdering(true)
		end
		local lo = grp.GetLayerOrdering and grp:GetLayerOrdering() or nil
		if not lo then
			return nil, nil, layer, nil, "GetLayerOrdering unavailable on layer '" .. layer:Name() .. "'"
		end
		return lo, "string", layer, nil, nil
	elseif rawCh == "switch" then
		local sw = moho:LayerAsSwitch(layer)
		if not sw then
			return nil, nil, layer, nil, "switch channel requires a SwitchLayer"
		end
		return sw:SwitchValues(), "string", layer, nil, nil
	end

	-- Vector mesh channels
	if rawCh == "point_pos" or rawCh == "point_width" or rawCh == "point_curvature"
		or rawCh == "shape_color" or rawCh == "shape_fill_color" or rawCh == "shape_stroke_color"
		or rawCh == "combo_blend" then
		local vl = moho:LayerAsVector(layer)
		if not vl then
			return nil, nil, layer, nil, "Channel '" .. rawCh .. "' requires a VectorLayer"
		end
		local mesh = vl:Mesh()
		if not mesh then
			return nil, nil, layer, nil, "VectorLayer has no mesh"
		end
		if rawCh == "point_pos" or rawCh == "point_width" or rawCh == "point_curvature" then
			local pid = effParams.pointId ~= nil and math.floor(tonumber(effParams.pointId)) or 0
			if pid < 0 or pid >= mesh:CountPoints() then
				return nil, nil, layer, nil, "pointId out of range: " .. tostring(pid)
			end
			local pt = mesh:Point(pid)
			if rawCh == "point_pos" then
				local sub, subKind, parentCh, derr = applyDimensionIfRequested(pt.fAnimPos, "vec2", effParams, forWrite)
				return sub, subKind, layer, parentCh, derr
			elseif rawCh == "point_width" then
				return pt.fWidth, "val", layer, nil, nil
			else
				local cIdx = effParams.curveIndex ~= nil and math.floor(tonumber(effParams.curveIndex)) or 0
				if not pt.CountCurves or pt:CountCurves() == 0 then
					return nil, nil, layer, nil, "Point " .. tostring(pid) .. " does not belong to any curve"
				end
				if cIdx < 0 or cIdx >= pt:CountCurves() then
					return nil, nil, layer, nil, "curveIndex out of range: " .. tostring(cIdx)
				end
				local okC, curve, ptPos = pcall(function() return pt:Curve(cIdx, -1) end)
				if not okC or not curve or ptPos == nil or ptPos < 0 or not curve.Curvature then
					return nil, nil, layer, nil, "Unable to access curvature channel for point " .. tostring(pid)
				end
				return curve:Curvature(ptPos), "val", layer, nil, nil
			end
		else
			local shape = nil
			if effParams.shapeId ~= nil then
				local sid = math.floor(tonumber(effParams.shapeId))
				if sid >= 0 and sid < mesh:CountShapes() then
					shape = mesh:Shape(sid)
				end
			elseif effParams.shapeName ~= nil then
				shape = mesh:ShapeByName(tostring(effParams.shapeName))
			elseif mesh:CountShapes() > 0 then
				shape = mesh:Shape(0)
			end
			if not shape then
				return nil, nil, layer, nil, "Shape not found for channel " .. rawCh
			end
			if rawCh == "shape_color" or rawCh == "shape_fill_color" then
				return shape.fMyStyle.fFillCol, "color", layer, nil, nil
			elseif rawCh == "shape_stroke_color" then
				return shape.fMyStyle.fLineCol, "color", layer, nil, nil
			elseif rawCh == "combo_blend" then
				local cb = shape.fComboBlend
				if type(cb) == "userdata" and cb.CountKeys then
					return cb, "val", layer, nil, nil
				end
				return nil, nil, layer, nil, "shape.fComboBlend is a non-animated float property in Moho 14.4; use mesh_liquidShapes to adjust blend"
			end
		end
	end

	-- BoneLayer + Skeleton + Vitruvian channels
	local bl = moho:LayerAsBone(layer)
	if bl then
		if rawCh == "wind_strength" and bl.fWindStrength then return bl.fWindStrength, "val", layer, nil, nil end
		if rawCh == "wind_direction" and bl.fWindDirection then return bl.fWindDirection, "angle", layer, nil, nil end
		if rawCh == "wind_turbulent_amplitude" and bl.fWindTurbulentAmplitude then return bl.fWindTurbulentAmplitude, "val", layer, nil, nil end
		if rawCh == "wind_turbulent_frequency" and bl.fWindTurbulentFrequency then return bl.fWindTurbulentFrequency, "val", layer, nil, nil end
		if rawCh == "gravity_strength" and bl.fGravityStrength then return bl.fGravityStrength, "val", layer, nil, nil end
		if rawCh == "gravity_direction" and bl.fGravityDirection then return bl.fGravityDirection, "angle", layer, nil, nil end

		if rawCh == "vitruvian_active_bone" then
			local skel = bl:Skeleton()
			if not skel or not skel.CountGroups then
				return nil, nil, layer, nil, "BoneLayer has no Vitruvian groups"
			end
			local grp = nil
			if effParams.groupIndex ~= nil then
				local gi = math.floor(tonumber(effParams.groupIndex))
				if gi >= 0 and gi < skel:CountGroups() then
					grp = skel:Group(gi)
				end
			elseif effParams.groupName ~= nil then
				local gn = tostring(effParams.groupName)
				for i = 0, skel:CountGroups() - 1 do
					local g = skel:Group(i)
					if g and g:Name() == gn then
						grp = g
						break
					end
				end
			elseif skel:CountGroups() > 0 then
				grp = skel:Group(0)
			end
			if not grp or not grp.fActiveBone then
				return nil, nil, layer, nil, "Vitruvian group not found on BoneLayer '" .. layer:Name() .. "'"
			end
			return grp.fActiveBone, "int", layer, nil, nil
		end

		if effParams.boneId ~= nil or effParams.boneName ~= nil then
			local skel = bl:Skeleton()
			local bone = resolveBoneInSkeleton(skel, effParams)
			if not bone then
				return nil, nil, layer, nil, "Bone not found for channel " .. rawCh
			end
			if rawCh == "bone_angle" then return bone.fAnimAngle, "angle", layer, nil, nil end
			if rawCh == "bone_pos" then
				local sub, subKind, parentCh, derr = applyDimensionIfRequested(bone.fAnimPos, "vec2", effParams, forWrite)
				return sub, subKind, layer, parentCh, derr
			end
			if rawCh == "bone_scale" then return bone.fAnimScale, "val", layer, nil, nil end
			if rawCh == "bone_dynamics" and bone.fBoneDynamics then return bone.fBoneDynamics, "bool", layer, nil, nil end
			if rawCh == "bone_flip_h" and bone.fFlipH then return bone.fFlipH, "bool", layer, nil, nil end
			if rawCh == "bone_flip_v" and bone.fFlipV then return bone.fFlipV, "bool", layer, nil, nil end
			if rawCh == "bone_target" and bone.fTargetBone then return bone.fTargetBone, "int", layer, nil, nil end
		end
	end

	return nil, nil, layer, nil, "Unsupported channel: " .. tostring(params.channel)
end

local function readChannelVal(ch, kind, frame)
	if kind == "vec3" then
		local v = ch:GetValue(frame)
		return { x = v.x, y = v.y, z = v.z }
	elseif kind == "vec2" then
		local v = ch:GetValue(frame)
		return { x = v.x, y = v.y }
	elseif kind == "angle2" then
		local v = ch:GetValue(frame)
		return { x = math.deg(v.x), y = math.deg(v.y) }
	elseif kind == "angle" then
		return math.deg(ch:GetValue(frame))
	elseif kind == "bool" then
		return (ch:GetValue(frame) == true)
	elseif kind == "string" then
		local v = ch:GetValue(frame)
		return helpers.readLmString(v)
	elseif kind == "color" then
		return helpers.serializeColor(ch:GetValue(frame))
	elseif kind == "int" then
		return math.floor(tonumber(ch:GetValue(frame)) or 0)
	else
		return ch:GetValue(frame)
	end
end

local function writeChannelVal(ch, kind, frame, v, parentCh)
	if kind == "vec3" then
		local vec = LM.Vector3:new_local()
		vec:Set(tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0)
		ch:SetValue(frame, vec)
	elseif kind == "vec2" then
		local vec = LM.Vector2:new_local()
		vec:Set(tonumber(v.x) or 0, tonumber(v.y) or 0)
		ch:SetValue(frame, vec)
	elseif kind == "angle2" then
		local vec = LM.Vector2:new_local()
		vec:Set(math.rad(tonumber(v.x) or 0), math.rad(tonumber(v.y) or 0))
		ch:SetValue(frame, vec)
	elseif kind == "angle" then
		ch:SetValue(frame, math.rad(tonumber(v) or 0))
	elseif kind == "bool" then
		ch:SetValue(frame, v == true)
	elseif kind == "string" then
		ch:SetValue(frame, tostring(v or ""))
	elseif kind == "color" then
		ch:SetValue(frame, helpers.toRgbStruct(v))
	elseif kind == "int" then
		ch:SetValue(frame, math.floor(tonumber(v) or 0))
	else
		ch:SetValue(frame, tonumber(v) or 0)
	end
	if parentCh and parentCh.SyncSplitDimensionsBack then
		pcall(function() parentCh:SyncSplitDimensionsBack() end)
	end
end

local function serializeInterpEntry(frame, val, interp)
	local entry = {
		frame = frame,
		value = val,
		interpolation = helpers.interpModeName(interp.interpMode),
		val1 = interp.val1,
		val2 = interp.val2,
		interval = interp.interval,
		hold = interp.hold,
		stagger = interp.stagger == true,
	}
	if interp.tags ~= nil then
		entry.colorTag = interp.tags
	end
	if interp.IsAdditiveCycle then
		local okAd, isAdd = pcall(function() return interp:IsAdditiveCycle() end)
		if okAd then
			entry.additiveCycle = (isAdd == true)
		end
	end
	if interp.interpMode == MOHO.INTERP_CYCLE then
		if interp.val2 > -1 then
			entry.cycleMode = "absolute"
			entry.cycleTargetFrame = interp.val2
		else
			entry.cycleMode = "relative"
			entry.cycleTargetFrame = frame - interp.val1
		end
	end
	if interp.interpMode == MOHO.INTERP_BEZIER then
		if interp.BezierInAngle then
			local ok, v = pcall(function() return interp:BezierInAngle(0) end)
			if ok then entry.bezierInAngle = v end
		end
		if interp.BezierInPercentage then
			local ok, v = pcall(function() return interp:BezierInPercentage(0) end)
			if ok then entry.bezierInPercent = v end
		end
		if interp.BezierOutAngle then
			local ok, v = pcall(function() return interp:BezierOutAngle(0) end)
			if ok then entry.bezierOutAngle = v end
		end
		if interp.BezierOutPercentage then
			local ok, v = pcall(function() return interp:BezierOutPercentage(0) end)
			if ok then entry.bezierOutPercent = v end
		end
	end
	return entry
end

function animation.getKeyframes(moho, params)
	local ch, kind, layer, parentCh, err = resolveChannel(moho, params, false)
	if not ch then
		return nil, err
	end
	local keys = {}
	local interp = MOHO.InterpSetting:new_local()
	for i = 0, ch:CountKeys() - 1 do
		local frame = ch:GetKeyWhen(i)
		ch:GetKeyInterpByID(i, interp)
		local val = readChannelVal(ch, kind, frame)
		keys[#keys + 1] = serializeInterpEntry(frame, val, interp)
	end
	local out = {
		layerName = layer and layer:Name() or "",
		channel = params.channel,
		dimension = params.dimension,
		count = #keys,
		keyframes = json.array(keys),
	}
	if parentCh and parentCh.AreDimensionsSplit then
		out.dimensionsSplit = (parentCh:AreDimensionsSplit() == true)
	elseif ch.AreDimensionsSplit then
		out.dimensionsSplit = (ch:AreDimensionsSplit() == true)
	end
	return out
end

function animation.setKeyframes(moho, params)
	local ch, kind, layer, parentCh, err = resolveChannel(moho, params, true)
	if not ch then
		return nil, err
	end
	local list = params.keyframes
	if type(list) ~= "table" or #list == 0 then
		return nil, "keyframes array is required"
	end
	helpers.prepUndo(moho, layer, false)
	for i = 1, #list do
		local k = list[i]
		local frame = math.floor(tonumber(k.frame) or 0)
		writeChannelVal(ch, kind, frame, k.value, parentCh)
		local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(k, params)
		helpers.applyKeyInterp(ch, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if layer and layer.UpdateCurFrame then
		layer:UpdateCurFrame()
	end
	helpers.updateUI(moho)
	return animation.getKeyframes(moho, params)
end

function animation.deleteKeyframe(moho, params)
	local ch, _, layer, parentCh, err = resolveChannel(moho, params, false)
	if not ch then
		return nil, err
	end
	local frame = math.floor(tonumber(params.frame) or 0)
	if frame == 0 then
		return nil, "Refusing to delete frame 0 setup keyframe"
	end
	helpers.prepUndo(moho, layer, false)
	ch:DeleteKey(frame)
	if parentCh and parentCh.SyncSplitDimensionsBack then
		pcall(function() parentCh:SyncSplitDimensionsBack() end)
	end
	helpers.updateUI(moho)
	return { deleted = true, frame = frame, channel = params.channel, dimension = params.dimension }
end

local function inspectSmartBoneSweep(moho, bl, actName)
	if not bl or not actName or actName == "" then
		return nil, false
	end
	local skel = bl:Skeleton()
	if not skel then
		return nil, false
	end
	local baseName = actName:gsub(" 2$", "")
	local bone = nil
	for i = 0, skel:CountBones() - 1 do
		local b = skel:Bone(i)
		if b and (b:Name() == actName or b:Name() == baseName) then
			bone = b
			break
		end
	end
	if not bone or not bone.fAnimAngle or not bone.fAnimAngle.ActionByName then
		return nil, false
	end
	local rawCh = bone.fAnimAngle:ActionByName(actName)
	if not rawCh or rawCh:CountKeys() < 2 then
		return nil, false
	end
	local actCh = (moho and moho.ChannelAsAnimVal) and moho:ChannelAsAnimVal(rawCh) or rawCh
	if not actCh or not actCh.GetValue then
		return nil, false
	end
	local startAngle = bone.fAnimAngle:GetValue(0)
	local maxSweepDeg = 0
	local endSweepDeg = 0
	for i = 0, actCh:CountKeys() - 1 do
		local w = actCh:GetKeyWhen(i)
		local deg = math.deg(actCh:GetValue(w) - startAngle)
		if math.abs(deg) > math.abs(maxSweepDeg) then
			maxSweepDeg = deg
		end
		endSweepDeg = deg
	end
	local is360 = (math.abs(endSweepDeg) >= 359.5 or math.abs(maxSweepDeg) >= 359.5)
	return endSweepDeg, is360
end

function animation.actionList(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local bl = moho:LayerAsBone(layer)
	local actions = {}
	for i = 0, layer:CountActions() - 1 do
		local name = layer:ActionName(i)
		local isSmart = layer.IsSmartBoneAction and (layer:IsSmartBoneAction(name) == true) or false
		local item = {
			index = i,
			name = name,
			duration = layer.ActionDuration and layer:ActionDuration(name) or 0,
			isSmartBone = isSmart,
		}
		if isSmart and bl then
			local sweepDeg, is360 = inspectSmartBoneSweep(moho, bl, name)
			if sweepDeg ~= nil then
				item.angleSweepDeg = sweepDeg
				item.is360SmartBone = is360
			end
		end
		actions[#actions + 1] = item
	end
	return {
		layerId = id,
		layerName = layer:Name(),
		currentAction = layer:CurrentAction(),
		docAction = moho.document and moho.document.CurrentDocAction and moho.document:CurrentDocAction() or "",
		actions = json.array(actions),
	}
end

--- Enter/create an Action or return to Mainline (''), keeping doc action synced (per lm_select_bone.lua).
function animation.actionActivate(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local name = tostring(params.actionName or "")
	helpers.prepUndo(moho, layer, true)
	if moho.document and moho.document.SetCurrentDocAction then
		moho.document:SetCurrentDocAction(name)
	end
	layer:ActivateAction(name)
	helpers.updateUI(moho)
	return {
		layerId = id,
		layerName = layer:Name(),
		currentAction = layer:CurrentAction(),
		docAction = moho.document and moho.document.CurrentDocAction and moho.document:CurrentDocAction() or "",
	}
end

--- Create a standard or full +/-360-degree Smart Bone Action with linear bone keys and optional Frame-0-to-end mirroring.
function animation.actionCreateSmartBone(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local bl = moho:LayerAsBone(layer)
	if not bl then
		return nil, "Layer '" .. layer:Name() .. "' is not a BoneLayer"
	end
	local skel = bl:Skeleton()
	local bone, boneId = resolveBoneInSkeleton(skel, params)
	if not bone then
		return nil, "Bone not found (provide boneId or boneName)"
	end
	local boneName = bone:Name()
	if boneName == "" then
		return nil, "Smart Bone must have a non-empty name"
	end

	local mode = string.lower(tostring(params.mode or "standard"))
	local is360 = (mode == "360")
	local duration = math.max(2, math.floor(tonumber(params.duration) or 96))
	local startFrame = math.max(1, math.floor(tonumber(params.startFrame) or 1))
	local endFrame = math.max(startFrame + 1, math.floor(tonumber(params.endFrame) or duration))
	local actionName = (type(params.actionName) == "string" and #params.actionName > 0)
		and params.actionName
		or ((string.lower(tostring(params.direction or "first")) == "second") and (boneName .. " 2") or boneName)

	local zeroAngleRad = bone.fAnimAngle:GetValue(0)
	local targetAngleRad
	if is360 then
		local deltaDeg = params.deltaAngleDeg ~= nil and tonumber(params.deltaAngleDeg) or ((params.clockwise == true) and -360 or 360)
		if math.abs(deltaDeg) < 359.5 then
			deltaDeg = (deltaDeg < 0) and -360 or 360
		end
		-- Exact unwrapped +/- 2*pi per lm_transform_bone.lua:792-806 (never mod 360)
		targetAngleRad = zeroAngleRad + ((deltaDeg >= 0) and (2.0 * math.pi) or (-2.0 * math.pi))
	else
		if params.targetAngleDeg ~= nil then
			targetAngleRad = math.rad(tonumber(params.targetAngleDeg))
		else
			local deltaDeg = tonumber(params.deltaAngleDeg) or 90
			targetAngleRad = zeroAngleRad + math.rad(deltaDeg)
		end
	end

	local doc = moho.document
	local origDocAction = doc and doc.CurrentDocAction and doc:CurrentDocAction() or ""
	local origLayerAction = layer:CurrentAction() or ""

	helpers.prepUndo(moho, layer, true)
	if doc and doc.SetCurrentDocAction then
		doc:SetCurrentDocAction(actionName)
	end
	layer:ActivateAction(actionName)

	local boneInterp = tostring(params.interpolation or "linear")
	bone.fAnimAngle:SetValue(startFrame, zeroAngleRad)
	helpers.applyKeyInterp(bone.fAnimAngle, startFrame, boneInterp, nil, nil, nil, nil, {})

	if is360 and params.addMidpointKey == true then
		local midFrame = math.floor((startFrame + endFrame) * 0.5)
		local midAngle = zeroAngleRad + (targetAngleRad - zeroAngleRad) * 0.5
		bone.fAnimAngle:SetValue(midFrame, midAngle)
		helpers.applyKeyInterp(bone.fAnimAngle, midFrame, boneInterp, nil, nil, nil, nil, {})
	end

	bone.fAnimAngle:SetValue(endFrame, targetAngleRad)
	helpers.applyKeyInterp(bone.fAnimAngle, endFrame, boneInterp, nil, nil, nil, nil, {})

	local mirroredCount = 0
	if params.mirrorFrame0ToEnd == true then
		local mirrorTargets = {}
		if type(params.mirrorLayers) == "table" and #params.mirrorLayers > 0 then
			for i = 1, #params.mirrorLayers do
				local spec = params.mirrorLayers[i]
				local ml
				if type(spec) == "number" then
					ml = helpers.resolveLayer(moho, { layerId = spec })
				elseif type(spec) == "string" then
					ml = helpers.resolveLayer(moho, { layerName = spec })
				elseif type(spec) == "table" then
					ml = helpers.resolveLayer(moho, spec)
				end
				if ml then
					mirrorTargets[#mirrorTargets + 1] = ml
				end
			end
		else
			local function collectChildren(parentGrp)
				for ci = 0, parentGrp:CountLayers() - 1 do
					local cl = parentGrp:Layer(ci)
					if cl then
						mirrorTargets[#mirrorTargets + 1] = cl
						if cl:IsGroupType() then
							collectChildren(moho:LayerAsGroup(cl))
						end
					end
				end
			end
			collectChildren(moho:LayerAsGroup(layer))
		end

		local mirrorStart = (params.mirrorFrame0ToStart ~= false)
		for i = 1, #mirrorTargets do
			local ml = mirrorTargets[i]
			if ml.ActivateAction then
				ml:ActivateAction(actionName)
			end
			local framesToMirror = mirrorStart and { startFrame, endFrame } or { endFrame }
			for fi = 1, #framesToMirror do
				local tf = framesToMirror[fi]
				if ml.fTranslation then ml.fTranslation:SetValue(tf, ml.fTranslation:GetValue(0)) end
				if ml.fScale then ml.fScale:SetValue(tf, ml.fScale:GetValue(0)) end
				if ml.fRotationZ then ml.fRotationZ:SetValue(tf, ml.fRotationZ:GetValue(0)) end
				if ml:LayerType() == MOHO.LT_VECTOR then
					local vl = moho:LayerAsVector(ml)
					local mesh = vl and vl:Mesh() or nil
					if mesh then
						for pi = 0, mesh:CountPoints() - 1 do
							local pt = mesh:Point(pi)
							if pt and pt.fAnimPos then
								pt.fAnimPos:SetValue(tf, pt.fAnimPos:GetValue(0))
							end
						end
					end
				end
			end
			mirroredCount = mirroredCount + 1
		end
	end

	skel:UpdateBoneMatrix(boneId)
	local leaveActive = (params.leaveActive == true)
	if not leaveActive then
		if doc and doc.SetCurrentDocAction then
			doc:SetCurrentDocAction(origDocAction)
		end
		layer:ActivateAction(origLayerAction)
	end

	helpers.updateUI(moho)
	local sweepDeg = math.deg(targetAngleRad - zeroAngleRad)
	return {
		created = true,
		layerId = id,
		layerName = layer:Name(),
		boneId = boneId,
		boneName = boneName,
		actionName = actionName,
		mode = mode,
		is360SmartBone = (math.abs(sweepDeg) >= 359.5),
		startFrame = startFrame,
		endFrame = endFrame,
		zeroAngleDeg = math.deg(zeroAngleRad),
		targetAngleDeg = math.deg(targetAngleRad),
		angleSweepDeg = sweepDeg,
		mirroredLayers = mirroredCount,
		activeAction = layer:CurrentAction(),
	}
end

--- Manage Actions: insert, rename, delete, or blend.
function animation.actionManage(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local op = string.lower(tostring(params.operation or ""))
	helpers.prepUndo(moho, layer, true)

	if op == "insert" then
		local name = tostring(params.actionName or "")
		if #name == 0 then return nil, "actionName is required for insert" end
		local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
		local byRef = (params.byReference == true)
		layer:InsertAction(name, frame, byRef)
		helpers.updateUI(moho)
		return { inserted = true, layerId = id, actionName = name, frame = frame, byReference = byRef }
	elseif op == "rename" then
		local oldName = tostring(params.actionName or "")
		local newName = tostring(params.newName or "")
		if #oldName == 0 or #newName == 0 then return nil, "actionName and newName are required for rename" end
		layer:RenameAction(oldName, newName)
		helpers.updateUI(moho)
		return { renamed = true, layerId = id, oldName = oldName, newName = newName }
	elseif op == "delete" then
		local name = tostring(params.actionName or "")
		if #name == 0 then return nil, "actionName is required for delete" end
		if layer:CurrentAction() == name then
			if moho.document and moho.document.SetCurrentDocAction then
				moho.document:SetCurrentDocAction("")
			end
			layer:ActivateAction("")
		end
		layer:DeleteAction(name)
		helpers.updateUI(moho)
		return { deleted = true, layerId = id, actionName = name }
	elseif op == "blend" then
		local names = params.actionNames
		local weights = params.weights
		if type(names) ~= "table" or type(weights) ~= "table" or #names == 0 or #names ~= #weights then
			return nil, "actionNames and weights arrays of equal non-zero length are required for blend"
		end
		local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
		local lmNames = {}
		local numWeights = {}
		for i = 1, #names do
			local s = LM.String:new_local()
			s:Set(tostring(names[i]))
			lmNames[i] = s
			numWeights[i] = tonumber(weights[i]) or 0
		end
		if type(params.actionFrames) == "table" and #params.actionFrames == #names then
			local mode = math.floor(tonumber(params.blendMode) or 0)
			local framesArr = {}
			for i = 1, #names do
				framesArr[i] = math.floor(tonumber(params.actionFrames[i]) or 1)
			end
			layer:BlendActions(frame, mode, #names, lmNames, numWeights, framesArr)
		else
			local relative = (params.relative == true)
			layer:BlendActions(frame, relative, #names, lmNames, numWeights)
		end
		helpers.updateUI(moho)
		return { blended = true, layerId = id, frame = frame, count = #names }
	end

	return nil, "Unsupported action operation (use insert, rename, delete, blend): " .. op
end

local function expandChannelSpecs(params)
	local specs = {}
	if type(params.targets) == "table" and #params.targets > 0 then
		for i = 1, #params.targets do
			specs[#specs + 1] = params.targets[i]
		end
	elseif type(params.channels) == "table" and #params.channels > 0 then
		for i = 1, #params.channels do
			local entry = params.channels[i]
			if type(entry) == "string" then
				local merged = {}
				for k, v in pairs(params) do merged[k] = v end
				merged.channel = entry
				specs[#specs + 1] = merged
			elseif type(entry) == "table" then
				local merged = {}
				for k, v in pairs(params) do
					if k ~= "channels" and k ~= "targets" then merged[k] = v end
				end
				for k, v in pairs(entry) do merged[k] = v end
				specs[#specs + 1] = merged
			end
		end
	elseif params.channel ~= nil then
		specs[1] = params
	end
	return specs
end

--- Range-aware multi-channel cycle builder targeting startFrame + 1 (Frame 2 when starting at Frame 1).
function animation.createCycle(moho, params)
	params = params or {}
	local startFrame = math.max(1, math.floor(tonumber(params.startFrame) or 1))
	local endFrame = math.floor(tonumber(params.endFrame) or 0)
	if endFrame <= startFrame then
		return nil, "endFrame must be strictly greater than startFrame"
	end
	local cycleMode = string.lower(tostring(params.cycleMode or "relative"))
	local targetFrame = params.cycleTargetFrame ~= nil and math.floor(tonumber(params.cycleTargetFrame)) or (startFrame + 1)
	local specs = expandChannelSpecs(params)
	if #specs == 0 then
		return nil, "Provide channel or channels/targets array for animation_createCycle"
	end

	helpers.prepUndo(moho, moho.layer, true)
	local results = {}
	for i = 1, #specs do
		local sp = specs[i]
		local ch, kind, layer, parentCh, err = resolveChannel(moho, sp, true)
		if not ch then
			return nil, "Channel #" .. tostring(i) .. ": " .. tostring(err)
		end
		if params.ensureStartKey ~= false and (not ch:HasKey(startFrame)) then
			local sv = readChannelVal(ch, kind, startFrame)
			writeChannelVal(ch, kind, startFrame, sv, parentCh)
		end
		if params.interpolationAtStart ~= nil then
			helpers.applyKeyInterp(ch, startFrame, tostring(params.interpolationAtStart), nil, nil, nil, params.interval, { colorTag = params.colorTag })
		end
		local copyStart = (params.copyStartToEnd ~= false)
		if copyStart and (params.forceCopyStartToEnd == true or not ch:HasKey(endFrame)) then
			local sv = readChannelVal(ch, kind, startFrame)
			writeChannelVal(ch, kind, endFrame, sv, parentCh)
		elseif not ch:HasKey(endFrame) then
			local ev = readChannelVal(ch, kind, endFrame)
			writeChannelVal(ch, kind, endFrame, ev, parentCh)
		end
		local opts = {
			cycleMode = cycleMode,
			cycleTargetFrame = targetFrame,
			additiveCycle = params.additiveCycle,
			colorTag = params.colorTag,
		}
		helpers.applyKeyInterp(ch, endFrame, "cycle", nil, nil, nil, params.interval, opts)
		results[#results + 1] = {
			layerName = layer and layer:Name() or "",
			channel = sp.channel,
			boneName = sp.boneName,
			boneId = sp.boneId,
			dimension = sp.dimension,
			startFrame = startFrame,
			endFrame = endFrame,
			cycleTargetFrame = targetFrame,
			cycleMode = cycleMode,
		}
	end
	helpers.updateUI(moho)
	return {
		cycled = true,
		count = #results,
		startFrame = startFrame,
		endFrame = endFrame,
		cycleTargetFrame = targetFrame,
		cycleMode = cycleMode,
		channels = json.array(results),
	}
end

local function cloneInterpToTable(interp)
	local t = {
		interpMode = interp.interpMode,
		val1 = interp.val1,
		val2 = interp.val2,
		interval = interp.interval,
		hold = interp.hold,
		stagger = interp.stagger,
		tags = interp.tags,
		flags = interp.flags,
	}
	if interp.IsAdditiveCycle then
		local ok, v = pcall(function() return interp:IsAdditiveCycle() end)
		if ok then t.additiveCycle = v end
	end
	if interp.BezierInAngle then
		local ok, v = pcall(function() return interp:BezierInAngle(0) end)
		if ok then t.bInA = v end
	end
	if interp.BezierInPercentage then
		local ok, v = pcall(function() return interp:BezierInPercentage(0) end)
		if ok then t.bInP = v end
	end
	if interp.BezierOutAngle then
		local ok, v = pcall(function() return interp:BezierOutAngle(0) end)
		if ok then t.bOutA = v end
	end
	if interp.BezierOutPercentage then
		local ok, v = pcall(function() return interp:BezierOutPercentage(0) end)
		if ok then t.bOutP = v end
	end
	return t
end

local function applyClonedInterp(ch, frame, t)
	local kid = ch:GetClosestKeyID(frame)
	if kid < 0 or ch:GetKeyWhen(kid) ~= frame then
		return
	end
	local interp = MOHO.InterpSetting:new_local()
	ch:GetKeyInterpByID(kid, interp)
	interp.interpMode = t.interpMode
	interp.val1 = t.val1
	interp.val2 = t.val2
	interp.interval = t.interval
	interp.hold = t.hold
	interp.stagger = t.stagger
	if t.tags ~= nil then pcall(function() interp.tags = t.tags end) end
	if t.flags ~= nil then pcall(function() interp.flags = t.flags end) end
	if t.additiveCycle ~= nil and interp.SetAdditiveCycle then
		pcall(function() interp:SetAdditiveCycle(t.additiveCycle == true) end)
	end
	if t.bInA ~= nil and interp.SetBezierInAngle then pcall(function() interp:SetBezierInAngle(0, t.bInA) end) end
	if t.bInP ~= nil and interp.SetBezierInPercentage then pcall(function() interp:SetBezierInPercentage(0, t.bInP) end) end
	if t.bOutA ~= nil and interp.SetBezierOutAngle then pcall(function() interp:SetBezierOutAngle(0, t.bOutA) end) end
	if t.bOutP ~= nil and interp.SetBezierOutPercentage then pcall(function() interp:SetBezierOutPercentage(0, t.bOutP) end) end
	ch:SetKeyInterpByID(kid, interp)
end

local function addOffsetToValue(kind, val, offset)
	if kind == "vec3" then
		return {
			x = (val.x or 0) + (tonumber(offset.x) or 0),
			y = (val.y or 0) + (tonumber(offset.y) or 0),
			z = (val.z or 0) + (tonumber(offset.z) or 0),
		}
	elseif kind == "vec2" or kind == "angle2" then
		return {
			x = (val.x or 0) + (tonumber(offset.x) or 0),
			y = (val.y or 0) + (tonumber(offset.y) or 0),
		}
	elseif kind == "color" then
		return {
			r = math.max(0, math.min(255, (val.r or 0) + (tonumber(offset.r) or 0))),
			g = math.max(0, math.min(255, (val.g or 0) + (tonumber(offset.g) or 0))),
			b = math.max(0, math.min(255, (val.b or 0) + (tonumber(offset.b) or 0))),
			a = math.max(0, math.min(255, (val.a or 255) + (tonumber(offset.a) or 0))),
		}
	elseif kind == "angle" or kind == "val" or kind == "int" then
		return (tonumber(val) or 0) + (tonumber(offset) or 0)
	end
	return val
end

--- Scoped keyframe retiming: push_frames, scale_range (Alt+Drag), relative_offset, clear_range.
function animation.retime(moho, params)
	params = params or {}
	local op = string.lower(tostring(params.operation or ""))
	local specs = expandChannelSpecs(params)
	if #specs == 0 then
		return nil, "Scoped targets/channels array (or channel) is required for animation_retime"
	end

	helpers.prepUndo(moho, moho.layer, true)
	local totalAffected = 0
	local perChannel = {}
	local interpTmp = MOHO.InterpSetting:new_local()

	for i = 1, #specs do
		local sp = specs[i]
		local ch, kind, layer, parentCh, err = resolveChannel(moho, sp, true)
		if not ch then
			return nil, "Target #" .. tostring(i) .. ": " .. tostring(err)
		end

		local affected = 0
		if op == "push_frames" then
			local fromF = math.max(1, math.floor(tonumber(params.fromFrame or params.startFrame) or 1))
			local toF = params.toFrame or params.endFrame
			local maxF = toF ~= nil and math.floor(tonumber(toF)) or math.huge
			local delta = math.floor(tonumber(params.delta) or 0)
			if delta ~= 0 then
				local items = {}
				for ki = 0, ch:CountKeys() - 1 do
					local w = ch:GetKeyWhen(ki)
					if w >= fromF and w <= maxF and w > 0 then
						ch:GetKeyInterpByID(ki, interpTmp)
						items[#items + 1] = {
							oldFrame = w,
							newFrame = math.max(1, w + delta),
							val = readChannelVal(ch, kind, w),
							interp = cloneInterpToTable(interpTmp),
						}
					end
				end
				for j = #items, 1, -1 do
					ch:DeleteKey(items[j].oldFrame)
				end
				for j = 1, #items do
					writeChannelVal(ch, kind, items[j].newFrame, items[j].val, parentCh)
					applyClonedInterp(ch, items[j].newFrame, items[j].interp)
					affected = affected + 1
				end
			end

		elseif op == "scale_range" then
			local startF = math.max(1, math.floor(tonumber(params.startFrame) or 1))
			local endF = math.floor(tonumber(params.endFrame) or 0)
			if endF <= startF then
				return nil, "scale_range requires endFrame > startFrame"
			end
			local anchor = params.anchorFrame ~= nil and tonumber(params.anchorFrame) or startF
			local factor = tonumber(params.factor)
			local newStart = params.newStartFrame ~= nil and tonumber(params.newStartFrame) or nil
			local newEnd = params.newEndFrame ~= nil and tonumber(params.newEndFrame) or nil
			if factor == nil and newEnd ~= nil then
				local ns = newStart or startF
				factor = (newEnd - ns) / (endF - startF)
				anchor = startF
			end
			if factor == nil or factor <= 0 then
				return nil, "scale_range requires positive factor or newEndFrame"
			end

			local items = {}
			for ki = 0, ch:CountKeys() - 1 do
				local w = ch:GetKeyWhen(ki)
				if w >= startF and w <= endF and w > 0 then
					ch:GetKeyInterpByID(ki, interpTmp)
					local dest
					if newStart ~= nil and newEnd ~= nil then
						dest = newStart + (w - startF) * ((newEnd - newStart) / (endF - startF))
					else
						dest = anchor + (w - anchor) * factor
					end
					items[#items + 1] = {
						oldFrame = w,
						newFrame = math.max(1, math.floor(dest + 0.5)),
						val = readChannelVal(ch, kind, w),
						interp = cloneInterpToTable(interpTmp),
					}
				end
			end
			for j = #items, 1, -1 do
				ch:DeleteKey(items[j].oldFrame)
			end
			for j = 1, #items do
				writeChannelVal(ch, kind, items[j].newFrame, items[j].val, parentCh)
				applyClonedInterp(ch, items[j].newFrame, items[j].interp)
				affected = affected + 1
			end

		elseif op == "relative_offset" then
			if params.valueOffset == nil then
				return nil, "valueOffset is required for relative_offset"
			end
			local startF = math.max(1, math.floor(tonumber(params.startFrame) or 1))
			local endF = params.endFrame ~= nil and math.floor(tonumber(params.endFrame)) or math.huge
			for ki = 0, ch:CountKeys() - 1 do
				local w = ch:GetKeyWhen(ki)
				if w >= startF and w <= endF and w > 0 then
					local curV = readChannelVal(ch, kind, w)
					local nextV = addOffsetToValue(kind, curV, params.valueOffset)
					writeChannelVal(ch, kind, w, nextV, parentCh)
					affected = affected + 1
				end
			end

		elseif op == "clear_range" then
			local startF = math.max(1, math.floor(tonumber(params.startFrame) or 1))
			local endF = params.endFrame ~= nil and math.floor(tonumber(params.endFrame)) or math.huge
			local toDel = {}
			for ki = 0, ch:CountKeys() - 1 do
				local w = ch:GetKeyWhen(ki)
				if w >= startF and w <= endF and w > 0 then
					toDel[#toDel + 1] = w
				end
			end
			for j = #toDel, 1, -1 do
				ch:DeleteKey(toDel[j])
				affected = affected + 1
			end
		else
			return nil, "Unsupported animation_retime operation (use push_frames, scale_range, relative_offset, clear_range): " .. op
		end

		if parentCh and parentCh.SyncSplitDimensionsBack then
			pcall(function() parentCh:SyncSplitDimensionsBack() end)
		end
		if layer and layer.UpdateCurFrame then
			layer:UpdateCurFrame()
		end
		totalAffected = totalAffected + affected
		perChannel[#perChannel + 1] = {
			layerName = layer and layer:Name() or "",
			channel = sp.channel,
			boneName = sp.boneName,
			boneId = sp.boneId,
			dimension = sp.dimension,
			affectedKeys = affected,
		}
	end

	helpers.updateUI(moho)
	return {
		retimed = true,
		operation = op,
		totalAffectedKeys = totalAffected,
		channels = json.array(perChannel),
	}
end

local function lerpValue(kind, a, b, w)
	if kind == "vec3" then
		return {
			x = a.x + w * (b.x - a.x),
			y = a.y + w * (b.y - a.y),
			z = a.z + w * (b.z - a.z),
		}
	elseif kind == "vec2" or kind == "angle2" then
		return {
			x = a.x + w * (b.x - a.x),
			y = a.y + w * (b.y - a.y),
		}
	elseif kind == "color" then
		return {
			r = math.max(0, math.min(255, math.floor(a.r + w * (b.r - a.r) + 0.5))),
			g = math.max(0, math.min(255, math.floor(a.g + w * (b.g - a.g) + 0.5))),
			b = math.max(0, math.min(255, math.floor(a.b + w * (b.b - a.b) + 0.5))),
			a = math.max(0, math.min(255, math.floor(a.a + w * (b.a - a.a) + 0.5))),
		}
	elseif kind == "angle" or kind == "val" then
		return a + w * (b - a)
	elseif kind == "int" then
		return math.floor(a + w * (b - a) + 0.5)
	end
	return (w < 0.5) and a or b
end

--- Weighted breakdown / anticipation (weight < 0) / overshoot (weight > 1) between surrounding keyframes.
function animation.tween(moho, params)
	params = params or {}
	local frame = math.floor(tonumber(params.frame) or moho.frame)
	if frame <= 0 then
		return nil, "frame must be >= 1 for animation_tween"
	end
	local weight = params.weight ~= nil and tonumber(params.weight) or 0.5
	local specs = expandChannelSpecs(params)
	if #specs == 0 then
		return nil, "Provide channel or channels/targets array for animation_tween"
	end

	helpers.prepUndo(moho, moho.layer, true)
	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
	local results = {}

	for i = 1, #specs do
		local sp = specs[i]
		local ch, kind, layer, parentCh, err = resolveChannel(moho, sp, true)
		if not ch then
			return nil, "Channel #" .. tostring(i) .. ": " .. tostring(err)
		end
		local prevF = params.prevFrame ~= nil and math.floor(tonumber(params.prevFrame)) or nil
		local nextF = params.nextFrame ~= nil and math.floor(tonumber(params.nextFrame)) or nil
		if prevF == nil or nextF == nil then
			for ki = 0, ch:CountKeys() - 1 do
				local w = ch:GetKeyWhen(ki)
				if w < frame and (prevF == nil or w > prevF) then
					prevF = w
				elseif w > frame and (nextF == nil or w < nextF) then
					nextF = w
				end
			end
		end
		if prevF == nil or nextF == nil then
			return nil, "Could not find surrounding keyframes around frame " .. tostring(frame)
				.. " on channel '" .. tostring(sp.channel) .. "' (provide prevFrame/nextFrame or add boundary keys)"
		end
		local vPrev = readChannelVal(ch, kind, prevF)
		local vNext = readChannelVal(ch, kind, nextF)
		local vTween = lerpValue(kind, vPrev, vNext, weight)
		writeChannelVal(ch, kind, frame, vTween, parentCh)
		helpers.applyKeyInterp(ch, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		if layer and layer.UpdateCurFrame then
			layer:UpdateCurFrame()
		end
		results[#results + 1] = {
			layerName = layer and layer:Name() or "",
			channel = sp.channel,
			boneName = sp.boneName,
			boneId = sp.boneId,
			dimension = sp.dimension,
			frame = frame,
			prevFrame = prevF,
			nextFrame = nextF,
			weight = weight,
			value = vTween,
		}
	end

	helpers.updateUI(moho)
	return {
		tweened = true,
		frame = frame,
		weight = weight,
		count = #results,
		channels = json.array(results),
	}
end

--- Document-wide or layer-specific Timeline Markers CRUD (MohoDoc.fTimelineMarkers / MohoLayer.fTimelineMarkers).
function animation.timelineMarkers(moho, params)
	params = params or {}
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local scope = string.lower(tostring(params.scope or ((params.layerId ~= nil or params.layerName ~= nil or params.layerUuid ~= nil) and "layer" or "document")))
	local op = string.lower(tostring(params.operation or "list"))

	local markerCh = nil
	local targetLayer = nil
	local targetLayerId = -1
	if scope == "layer" then
		local layer, lid, lerr = helpers.resolveLayer(moho, params)
		if not layer then
			return nil, lerr
		end
		targetLayer = layer
		targetLayerId = lid
		markerCh = layer.fTimelineMarkers
	else
		markerCh = doc.fTimelineMarkers
	end
	if not markerCh then
		return nil, "fTimelineMarkers channel is unavailable for scope: " .. scope
	end

	local function listMarkers()
		local list = {}
		local interp = MOHO.InterpSetting:new_local()
		for i = 0, markerCh:CountKeys() - 1 do
			local w = markerCh:GetKeyWhen(i)
			if w > MARKER_SENTINEL_FRAME then
				local lbl = helpers.readLmString(markerCh:GetValue(w))
				markerCh:GetKeyInterpByID(i, interp)
				if w > 0 or lbl ~= "" then
					list[#list + 1] = {
						frame = w,
						label = lbl,
						colorTag = interp.tags or 0,
					}
				end
			end
		end
		return {
			scope = scope,
			layerId = targetLayerId >= 0 and targetLayerId or nil,
			layerName = targetLayer and targetLayer:Name() or nil,
			count = #list,
			markers = json.array(list),
		}
	end

	if op == "list" then
		return listMarkers()
	end

	helpers.prepUndo(moho, targetLayer or moho.layer, true)

	if op == "add" or op == "update" then
		local frame = math.floor(tonumber(params.frame) or moho.frame)
		local label = tostring(params.label or params.text or "")
		markerCh:SetValue(frame, label)
		if params.colorTag ~= nil then
			local kid = markerCh:GetClosestKeyID(frame)
			if kid >= 0 and markerCh:GetKeyWhen(kid) == frame then
				local interp = MOHO.InterpSetting:new_local()
				markerCh:GetKeyInterpByID(kid, interp)
				pcall(function() interp.tags = math.floor(tonumber(params.colorTag) or 0) end)
				markerCh:SetKeyInterpByID(kid, interp)
			end
		end
		helpers.updateUI(moho)
		local out = listMarkers()
		out.updatedFrame = frame
		return out
	elseif op == "delete" then
		local frame = math.floor(tonumber(params.frame) or moho.frame)
		markerCh:DeleteKey(frame)
		helpers.updateUI(moho)
		local out = listMarkers()
		out.deletedFrame = frame
		return out
	elseif op == "clear" then
		local frames = {}
		for i = 0, markerCh:CountKeys() - 1 do
			local w = markerCh:GetKeyWhen(i)
			if w > MARKER_SENTINEL_FRAME then
				frames[#frames + 1] = w
			end
		end
		for i = #frames, 1, -1 do
			markerCh:DeleteKey(frames[i])
		end
		helpers.updateUI(moho)
		local out = listMarkers()
		out.clearedCount = #frames
		return out
	end

	return nil, "Unsupported timeline_markers operation (use list, add, update, delete, clear): " .. op
end

function animation.cameraGet(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local tr = doc.fCameraTrack:GetValue(frame)
	local pt = doc.fCameraPanTilt:GetValue(frame)
	return {
		frame = frame,
		track = { x = tr.x, y = tr.y, z = tr.z },
		zoom = doc.fCameraZoom:GetValue(frame),
		rollDeg = math.deg(doc.fCameraRoll:GetValue(frame)),
		panTiltDeg = { x = math.deg(pt.x), y = math.deg(pt.y) },
	}
end

function animation.cameraSetKeyframe(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	helpers.prepUndo(moho, moho.layer, true)
	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)
	if type(params.track) == "table" then
		local cur = doc.fCameraTrack:GetValue(frame)
		local v = LM.Vector3:new_local()
		v:Set(
			params.track.x ~= nil and tonumber(params.track.x) or cur.x,
			params.track.y ~= nil and tonumber(params.track.y) or cur.y,
			params.track.z ~= nil and tonumber(params.track.z) or cur.z
		)
		doc.fCameraTrack:SetValue(frame, v)
		helpers.applyKeyInterp(doc.fCameraTrack, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.zoom ~= nil then
		doc.fCameraZoom:SetValue(frame, tonumber(params.zoom))
		helpers.applyKeyInterp(doc.fCameraZoom, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.rollDeg ~= nil then
		doc.fCameraRoll:SetValue(frame, math.rad(tonumber(params.rollDeg)))
		helpers.applyKeyInterp(doc.fCameraRoll, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if type(params.panTiltDeg) == "table" then
		local cur = doc.fCameraPanTilt:GetValue(frame)
		local v = LM.Vector2:new_local()
		v:Set(
			params.panTiltDeg.x ~= nil and math.rad(tonumber(params.panTiltDeg.x)) or cur.x,
			params.panTiltDeg.y ~= nil and math.rad(tonumber(params.panTiltDeg.y)) or cur.y
		)
		doc.fCameraPanTilt:SetValue(frame, v)
		helpers.applyKeyInterp(doc.fCameraPanTilt, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	helpers.updateUI(moho)
	return animation.cameraGet(moho, { frame = frame })
end

return animation
