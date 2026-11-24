-- Layer tree inspection, creation, duplication, masking, Flexi-Bind subsets, and isolated PNG rendering (v3.0.0).
-- Signatures verified against Moho Pro 14.4 bundled scripts and live Lua 5.4 runtime.

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local layers = {}

function layers.list(moho, params)
	if not moho.document then
		return nil, "No document open"
	end
	return {
		layers = helpers.buildLayerTree(moho),
	}
end

function layers.getProperties(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local tr = layer.fTranslation:GetValue(frame)
	local sc = layer.fScale:GetValue(frame)
	local orig = layer:Origin()
	local rawBlur = layer.fBlur and layer.fBlur:GetValue(frame) or 0
	local blurPx = (moho.DocToPixel and moho:DocToPixel(rawBlur)) or (rawBlur * (moho.document and moho.document:Height() or 1))
	local res = {
		id = id,
		name = layer:Name(),
		type = helpers.layerTypeName(layer),
		uuid = layer.UUID and layer:UUID() or "",
		frame = frame,
		visible = layer:IsVisible(),
		animVisible = layer.fVisibility and layer.fVisibility:GetValue(frame) or layer:IsVisible(),
		locked = layer:IsLocked(),
		shownOnTimeline = layer.IsShownOnTimeline and layer:IsShownOnTimeline() or false,
		fullyVisible = layer.IsFullyVisible and layer:IsFullyVisible() or layer:IsVisible(),
		opacity = layer.fAlpha:GetValue(frame),
		blur = rawBlur,
		blurPx = blurPx,
		translation = { x = tr.x, y = tr.y, z = tr.z },
		scale = { x = sc.x, y = sc.y, z = sc.z },
		rotationZ = math.deg(layer.fRotationZ:GetValue(frame)),
		rotationX = math.deg(layer.fRotationX:GetValue(frame)),
		rotationY = math.deg(layer.fRotationY:GetValue(frame)),
		origin = { x = orig.x, y = orig.y },
		flipH = layer.fFlipH:GetValue(frame),
		flipV = layer.fFlipV:GetValue(frame),
		parentBone = layer.LayerParentBone and layer:LayerParentBone() or -1,
		flexiBoneIds = json.array(helpers.getFlexiBoneIds(layer)),
		elbowBind = layer.IsElbowBindInEffect and layer:IsElbowBindInEffect() or false,
		editOnly = layer.IsEditOnly and layer:IsEditOnly() or false,
		renderOnly = layer.IsRenderOnly and layer:IsRenderOnly() or false,
		blendingMode = layer.BlendingMode and helpers.blendingModeName(layer:BlendingMode()) or "normal",
		blendingModeCode = layer.BlendingMode and layer:BlendingMode() or 0,
		maskingMode = layer.MaskingMode and helpers.maskingModeName(layer:MaskingMode()) or "masked",
		maskExpansion = layer.MaskExpansion and layer:MaskExpansion() or false,
		isReference = layer.IsReferencedLayer and layer:IsReferencedLayer() or false,
		isExternalReference = layer.IsReferenceExternal and layer:IsReferenceExternal() or false,
		isOutOfDate = layer.IsReferenceOutdated and layer:IsReferenceOutdated() or false,
		timingOffset = layer.TimingOffset and layer:TimingOffset() or 0,
		totalTimingOffset = layer.TotalTimingOffset and layer:TotalTimingOffset() or 0,
		labelColor = layer.LabelColor and layer:LabelColor() or 0,
		userTags = layer.UserTags and layer:UserTags() or "",
		userComments = layer.UserComments and layer:UserComments() or "",
		bounds = helpers.getLayerBounds(layer, frame),
	}
	if layer.IsImmuneToDof then
		local okD, imD = pcall(function() return layer:IsImmuneToDof() end)
		if okD then res.immuneToDof = (imD == true) end
	end
	local ow = layer.fOutlineWidth and layer.fOutlineWidth:GetValue(frame) or 0
	local so = layer.fShadowOffset and layer.fShadowOffset:GetValue(frame) or 0
	local sb = layer.fShadowBlur and layer.fShadowBlur:GetValue(frame) or 0
	local se = layer.fShadowExpansion and layer.fShadowExpansion:GetValue(frame) or 0
	local sho = layer.fShadingOffset and layer.fShadingOffset:GetValue(frame) or 0
	local shb = layer.fShadingBlur and layer.fShadingBlur:GetValue(frame) or 0
	local shc = layer.fShadingContraction and layer.fShadingContraction:GetValue(frame) or 0
	res.layerFx = {
		colorize = {
			enabled = layer.fLayerColorOn and layer.fLayerColorOn:GetValue(frame) or false,
			color = layer.fLayerColor and helpers.serializeColor(layer.fLayerColor:GetValue(frame)) or nil,
		},
		outline = {
			enabled = layer.fLayerOutline and layer.fLayerOutline:GetValue(frame) or false,
			width = ow,
			widthPx = helpers.docToPx(moho, ow),
			color = layer.fOutlineColor and helpers.serializeColor(layer.fOutlineColor:GetValue(frame)) or nil,
		},
		shadow = {
			enabled = layer.fLayerShadow and layer.fLayerShadow:GetValue(frame) or false,
			angleDeg = layer.fShadowAngle and math.deg(layer.fShadowAngle:GetValue(frame)) or 0,
			offset = so,
			offsetPx = helpers.docToPx(moho, so),
			blur = sb,
			blurPx = helpers.docToPx(moho, sb),
			expansion = se,
			expansionPx = helpers.docToPx(moho, se),
			color = layer.fShadowColor and helpers.serializeColor(layer.fShadowColor:GetValue(frame)) or nil,
		},
		shading = {
			enabled = layer.fLayerShading and layer.fLayerShading:GetValue(frame) or false,
			angleDeg = layer.fShadingAngle and math.deg(layer.fShadingAngle:GetValue(frame)) or 0,
			offset = sho,
			offsetPx = helpers.docToPx(moho, sho),
			blur = shb,
			blurPx = helpers.docToPx(moho, shb),
			contraction = shc,
			contractionPx = helpers.docToPx(moho, shc),
			color = layer.fShadingColor and helpers.serializeColor(layer.fShadingColor:GetValue(frame)) or nil,
		},
	}
	if layer:LayerType() == MOHO.LT_VECTOR then
		local vl = moho:LayerAsVector(layer)
		if vl then
			local docH = moho.document and math.max(1, moho.document:Height()) or 1
			local na = vl.fNoiseAmp or 0
			local ns = vl.fNoiseScale or 0
			res.vectorNoise = {
				noisyLines = vl.fNoisyLines == true,
				noisyShapes = vl.fNoisyShapes == true,
				animatedNoise = vl.fAnimatedNoise == true,
				extraSketchy = vl.fExtraSketchy == true,
				noiseAmp = na,
				noiseAmpPx = na * docH,
				noiseScale = ns,
				noiseScalePx = ns * docH,
			}
			if vl.fExcludeLinesFromMask ~= nil then
				res.excludeStrokes = (vl.fExcludeLinesFromMask == true)
			end
		end
	end
	if res.excludeStrokes == nil and layer.ExcludeStrokes then
		local okEx, ex = pcall(function() return layer:ExcludeStrokes() end)
		if okEx then
			res.excludeStrokes = (ex == true)
		end
	end
	local followInfo = helpers.getFollowCurveInfo(moho, layer, frame)
	if followInfo then
		res.followLayerId = followInfo.followLayerId
		res.followLayerName = followInfo.followLayerName
		res.followCurve = followInfo.followCurve
		res.followPercent = followInfo.followPercent
	end
	if layer.GetWarpLayer then
		local wl = layer:GetWarpLayer()
		if wl then
			res.warpLayerName = wl:Name()
			res.warpLayerId = helpers.getLayerId(moho, wl)
		end
	end
	if layer:IsGroupType() then
		local grp = moho:LayerAsGroup(layer)
		if grp and grp.GetGroupMask then
			res.groupMask = helpers.groupMaskName(grp:GetGroupMask())
		end
		if grp and grp.IsLayerOrderingEnabled then
			res.animatedLayerOrder = (grp:IsLayerOrderingEnabled() == true)
		end
		if grp and grp.IsDepthSorted then
			res.isDepthSorted = (grp:IsDepthSorted() == true)
		end
		if grp and grp.IsDistanceSorted then
			res.isDistanceSorted = (grp:IsDistanceSorted() == true)
		end
	end
	if layer:LayerType() == MOHO.LT_IMAGE then
		local img = moho:LayerAsImage(layer)
		if img then
			if img.SourceImage then res.sourceImage = img:SourceImage() end
			if img.Width then res.imageWidth = img:Width() end
			if img.Height then res.imageHeight = img:Height() end
			if img.PixelWidth then res.pixelWidth = img:PixelWidth() end
			if img.PixelHeight then res.pixelHeight = img:PixelHeight() end
		end
	end
	return res
end

function layers.create(moho, params)
	if not moho.document then
		return nil, "No document open"
	end
	local reqType = string.lower(tostring(params.type or "vector"))
	local ltype = helpers.layerTypeCode(reqType)
	if ltype == nil then
		return nil, "Unknown layer type: " .. tostring(params.type)
	end
	helpers.prepUndo(moho, moho.layer, true)
	local layer = moho:CreateNewLayer(ltype, true)
	if not layer then
		return nil, "CreateNewLayer returned nil"
	end
	if params.name then
		layer:SetName(tostring(params.name))
	end
	local initialFrameLayer = nil
	if (reqType == "framebyframe" or reqType == "fbf") then
		local sw = moho:LayerAsSwitch(layer)
		if sw and sw.SetFBFLayer then
			sw:SetFBFLayer(true)
		end
		if params.createInitialFrame ~= false then
			local initName = tostring(params.initialFrameName or "Frame 1")
			local childVec = moho:CreateNewLayer(MOHO.LT_VECTOR, false)
			if childVec then
				childVec:SetName(initName)
				moho:PlaceLayerInGroup(childVec, layer, true, false)
				if sw and sw.SwitchValues then
					local sv = sw:SwitchValues()
					if sv then
						sv:SetValue(0, initName)
						sv:SetValue(1, initName)
					end
				end
				initialFrameLayer = childVec
			end
		end
	end
	if ltype == MOHO.LT_IMAGE and params.sourceImage then
		local img = moho:LayerAsImage(layer)
		if img and img.SetSourceImage then
			img:SetSourceImage(tostring(params.sourceImage))
		end
	elseif ltype == MOHO.LT_NOTE and params.noteText then
		local nl = moho:LayerAsNote(layer)
		if nl and nl.SetNoteText then
			nl:SetNoteText(tostring(params.noteText))
		end
	end
	if params.parentLayerId ~= nil or params.parentLayerName ~= nil then
		local parentL = helpers.resolveLayer(moho, {
			layerId = params.parentLayerId,
			layerName = params.parentLayerName,
		})
		if parentL and parentL:IsGroupType() then
			local top = (params.insertAtTop ~= false)
			moho:PlaceLayerInGroup(layer, parentL, top, false)
		end
	end
	if params.editOnly ~= nil and layer.SetEditOnly then
		layer:SetEditOnly(params.editOnly == true)
	end
	moho:SetSelLayer(layer)
	helpers.updateUI(moho)
	local out = {
		created = true,
		id = helpers.getLayerId(moho, layer),
		name = layer:Name(),
		type = helpers.layerTypeName(layer),
		uuid = layer.UUID and layer:UUID() or "",
	}
	if initialFrameLayer then
		out.frameByFrame = true
		out.initialFrameLayerId = helpers.getLayerId(moho, initialFrameLayer)
		out.initialFrameLayerName = initialFrameLayer:Name()
	end
	return out
end

function layers.deleteLayer(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	helpers.prepUndo(moho, layer, true)
	local name = layer:Name()
	moho:DeleteLayer(layer)
	helpers.updateUI(moho)
	return { deleted = true, id = id, name = name }
end

--- Duplicate a layer (or create a live Moho Referenced Layer when asReference=true).
-- Verified in Moho Pro 14.4: moho:DuplicateLayer(layer, asReference) -> MohoLayer.
function layers.duplicateLayer(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	helpers.prepUndo(moho, layer, true)
	local asRef = (params.asReference == true)
	local dup = moho:DuplicateLayer(layer, asRef)
	if not dup then
		return nil, "DuplicateLayer returned nil"
	end
	if params.newName then
		dup:SetName(tostring(params.newName))
	end
	helpers.updateUI(moho)
	return {
		duplicated = true,
		asReference = asRef,
		sourceLayerId = id,
		id = helpers.getLayerId(moho, dup),
		name = dup:Name(),
		uuid = dup.UUID and dup:UUID() or "",
	}
end

function layers.reparent(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	helpers.prepUndo(moho, layer, true)
	if params.behindLayerId ~= nil or params.behindLayerName ~= nil then
		local target, _, terr = helpers.resolveLayer(moho, {
			layerId = params.behindLayerId,
			layerName = params.behindLayerName,
		})
		if not target then
			return nil, terr
		end
		moho:PlaceLayerBehindAnother(layer, target)
	elseif params.inFrontOfLayerId ~= nil or params.inFrontOfLayerName ~= nil then
		local target, _, terr = helpers.resolveLayer(moho, {
			layerId = params.inFrontOfLayerId,
			layerName = params.inFrontOfLayerName,
		})
		if not target then
			return nil, terr
		end
		helpers.placeLayerInFrontOf(moho, layer, target)
	elseif params.parentLayerId ~= nil or params.parentLayerName ~= nil then
		local groupL, _, gerr = helpers.resolveLayer(moho, {
			layerId = params.parentLayerId,
			layerName = params.parentLayerName,
		})
		if not groupL then
			return nil, gerr
		end
		if not groupL:IsGroupType() then
			return nil, "Target parent layer is not a group/bone/switch layer"
		end
		moho:PlaceLayerInGroup(layer, groupL, params.insertAtTop ~= false, false)
	else
		return nil, "Provide parentLayerId/parentLayerName, behindLayerId/behindLayerName, or inFrontOfLayerId/inFrontOfLayerName"
	end
	helpers.updateUI(moho)
	return {
		reparented = true,
		id = helpers.getLayerId(moho, layer),
		name = layer:Name(),
	}
end

function layers.selectLayer(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	moho:SetSelLayer(layer)
	helpers.updateUI(moho)
	return { selected = true, id = id, name = layer:Name() }
end

function layers.setProperties(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	helpers.prepUndo(moho, layer, false)

	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)

	if params.name ~= nil then
		layer:SetName(tostring(params.name))
	end
	if params.visible ~= nil then
		if frame > 0 and layer.fVisibility then
			layer.fVisibility:SetValue(frame, params.visible == true)
			helpers.applyKeyInterp(layer.fVisibility, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		else
			layer:SetVisible(params.visible == true)
		end
	end
	if params.locked ~= nil then
		layer:SetLocked(params.locked == true)
	end
	if params.editOnly ~= nil and layer.SetEditOnly then
		layer:SetEditOnly(params.editOnly == true)
	end
	if params.renderOnly ~= nil and layer.SetRenderOnly then
		layer:SetRenderOnly(params.renderOnly == true)
	end
	if params.opacity ~= nil then
		layer.fAlpha:SetValue(frame, tonumber(params.opacity))
		helpers.applyKeyInterp(layer.fAlpha, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if (params.blurPx ~= nil or params.blur ~= nil) and layer.fBlur then
		local docBlur
		if params.blurPx ~= nil then
			local px = tonumber(params.blurPx) or 0
			docBlur = (moho.PixelToDoc and moho:PixelToDoc(px)) or (px / math.max(1, moho.document and moho.document:Height() or 1))
		else
			docBlur = tonumber(params.blur) or 0
		end
		layer.fBlur:SetValue(frame, docBlur)
		helpers.applyKeyInterp(layer.fBlur, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if type(params.origin) == "table" then
		local o = LM.Vector2:new_local()
		o:Set(tonumber(params.origin.x) or 0, tonumber(params.origin.y) or 0)
		layer:SetOrigin(o)
	end
	if type(params.translation) == "table" then
		local cur = layer.fTranslation:GetValue(frame)
		local newX = params.translation.x ~= nil and tonumber(params.translation.x) or cur.x
		local newY = params.translation.y ~= nil and tonumber(params.translation.y) or cur.y
		local newZ = params.translation.z ~= nil and tonumber(params.translation.z) or cur.z
		if params.preserveApparentSize == true and params.translation.z ~= nil and moho.document and moho.document.fCameraTrack then
			local camPos = moho.document.fCameraTrack:GetValue(frame)
			local oldDist = camPos.z - cur.z
			local newDist = camPos.z - newZ
			if math.abs(oldDist) > 1e-4 and (newDist / oldDist) > 0.01 then
				local ratio = newDist / oldDist
				if params.translation.x == nil then
					newX = camPos.x + (cur.x - camPos.x) * ratio
				end
				if params.translation.y == nil then
					newY = camPos.y + (cur.y - camPos.y) * ratio
				end
				if params.scale == nil then
					local curS = layer.fScale:GetValue(frame)
					local sv = LM.Vector3:new_local()
					sv:Set(curS.x * ratio, curS.y * ratio, curS.z)
					layer.fScale:SetValue(frame, sv)
					helpers.applyKeyInterp(layer.fScale, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
				end
			end
		end
		local v = LM.Vector3:new_local()
		v:Set(newX, newY, newZ)
		layer.fTranslation:SetValue(frame, v)
		helpers.applyKeyInterp(layer.fTranslation, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		if params.translation.z ~= nil and moho.document then
			if layer:Parent() and layer:Parent().DepthSort then
				layer:Parent():DepthSort(moho.document)
			elseif moho.document.DepthSort then
				moho.document:DepthSort()
			end
		end
	end
	if type(params.scale) == "table" then
		local cur = layer.fScale:GetValue(frame)
		local v = LM.Vector3:new_local()
		v:Set(
			params.scale.x ~= nil and tonumber(params.scale.x) or cur.x,
			params.scale.y ~= nil and tonumber(params.scale.y) or cur.y,
			params.scale.z ~= nil and tonumber(params.scale.z) or cur.z
		)
		layer.fScale:SetValue(frame, v)
		helpers.applyKeyInterp(layer.fScale, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.rotationZ ~= nil then
		layer.fRotationZ:SetValue(frame, math.rad(tonumber(params.rotationZ)))
		helpers.applyKeyInterp(layer.fRotationZ, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.rotationX ~= nil then
		layer.fRotationX:SetValue(frame, math.rad(tonumber(params.rotationX)))
		helpers.applyKeyInterp(layer.fRotationX, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.rotationY ~= nil then
		layer.fRotationY:SetValue(frame, math.rad(tonumber(params.rotationY)))
		helpers.applyKeyInterp(layer.fRotationY, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.flipH ~= nil then
		layer.fFlipH:SetValue(frame, params.flipH == true)
		helpers.applyKeyInterp(layer.fFlipH, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.flipV ~= nil then
		layer.fFlipV:SetValue(frame, params.flipV == true)
		helpers.applyKeyInterp(layer.fFlipV, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.blendingMode ~= nil and layer.SetBlendingMode then
		layer:SetBlendingMode(helpers.blendingModeCode(params.blendingMode))
	end
	if params.labelColor ~= nil and layer.SetLabelColor then
		layer:SetLabelColor(math.floor(tonumber(params.labelColor)))
	end
	if params.userTags ~= nil and layer.SetUserTags then
		layer:SetUserTags(tostring(params.userTags))
	end
	if params.userComments ~= nil and layer.SetUserComments then
		layer:SetUserComments(tostring(params.userComments))
	end
	if params.timingOffset ~= nil and layer.SetTimingOffset then
		layer:SetTimingOffset(math.floor(tonumber(params.timingOffset)))
	end
	if params.shownOnTimeline ~= nil and layer.SetShownOnTimeline then
		layer:SetShownOnTimeline(params.shownOnTimeline == true)
	end
	if params.immuneToDof ~= nil and layer.SetImmuneToDof then
		layer:SetImmuneToDof(params.immuneToDof == true)
	end
	if params.depthSort == true and moho.document then
		if layer:IsGroupType() then
			local grp = moho:LayerAsGroup(layer)
			if grp and grp.FullDepthSort then grp:FullDepthSort(moho.document) end
		elseif moho.document.DepthSort then
			moho.document:DepthSort()
		end
	end
	if type(params.colorize) == "table" then
		if params.colorize.enabled ~= nil and layer.fLayerColorOn then
			layer.fLayerColorOn:SetValue(frame, params.colorize.enabled == true)
			helpers.applyKeyInterp(layer.fLayerColorOn, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if type(params.colorize.color) == "table" and layer.fLayerColor then
			layer.fLayerColor:SetValue(frame, helpers.toRgbStruct(params.colorize.color))
			helpers.applyKeyInterp(layer.fLayerColor, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
	end
	if type(params.outline) == "table" then
		if params.outline.enabled ~= nil and layer.fLayerOutline then
			layer.fLayerOutline:SetValue(frame, params.outline.enabled == true)
			helpers.applyKeyInterp(layer.fLayerOutline, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.outline.widthPx ~= nil or params.outline.width ~= nil) and layer.fOutlineWidth then
			local w = params.outline.widthPx ~= nil and helpers.pxToDoc(moho, params.outline.widthPx) or tonumber(params.outline.width)
			layer.fOutlineWidth:SetValue(frame, w)
			helpers.applyKeyInterp(layer.fOutlineWidth, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if type(params.outline.color) == "table" and layer.fOutlineColor then
			layer.fOutlineColor:SetValue(frame, helpers.toRgbStruct(params.outline.color))
			helpers.applyKeyInterp(layer.fOutlineColor, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
	end
	if type(params.shadow) == "table" then
		if params.shadow.enabled ~= nil and layer.fLayerShadow then
			layer.fLayerShadow:SetValue(frame, params.shadow.enabled == true)
			helpers.applyKeyInterp(layer.fLayerShadow, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if params.shadow.angleDeg ~= nil and layer.fShadowAngle then
			layer.fShadowAngle:SetValue(frame, math.rad(tonumber(params.shadow.angleDeg)))
			helpers.applyKeyInterp(layer.fShadowAngle, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.shadow.offsetPx ~= nil or params.shadow.offset ~= nil) and layer.fShadowOffset then
			local o = params.shadow.offsetPx ~= nil and helpers.pxToDoc(moho, params.shadow.offsetPx) or tonumber(params.shadow.offset)
			layer.fShadowOffset:SetValue(frame, o)
			helpers.applyKeyInterp(layer.fShadowOffset, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.shadow.blurPx ~= nil or params.shadow.blur ~= nil) and layer.fShadowBlur then
			local b = params.shadow.blurPx ~= nil and helpers.pxToDoc(moho, params.shadow.blurPx) or tonumber(params.shadow.blur)
			layer.fShadowBlur:SetValue(frame, b)
			helpers.applyKeyInterp(layer.fShadowBlur, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.shadow.expansionPx ~= nil or params.shadow.expansion ~= nil) and layer.fShadowExpansion then
			local ex = params.shadow.expansionPx ~= nil and helpers.pxToDoc(moho, params.shadow.expansionPx) or tonumber(params.shadow.expansion)
			layer.fShadowExpansion:SetValue(frame, ex)
			helpers.applyKeyInterp(layer.fShadowExpansion, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if type(params.shadow.color) == "table" and layer.fShadowColor then
			layer.fShadowColor:SetValue(frame, helpers.toRgbStruct(params.shadow.color))
			helpers.applyKeyInterp(layer.fShadowColor, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
	end
	if type(params.shading) == "table" then
		if params.shading.enabled ~= nil and layer.fLayerShading then
			layer.fLayerShading:SetValue(frame, params.shading.enabled == true)
			helpers.applyKeyInterp(layer.fLayerShading, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if params.shading.angleDeg ~= nil and layer.fShadingAngle then
			layer.fShadingAngle:SetValue(frame, math.rad(tonumber(params.shading.angleDeg)))
			helpers.applyKeyInterp(layer.fShadingAngle, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.shading.offsetPx ~= nil or params.shading.offset ~= nil) and layer.fShadingOffset then
			local o = params.shading.offsetPx ~= nil and helpers.pxToDoc(moho, params.shading.offsetPx) or tonumber(params.shading.offset)
			layer.fShadingOffset:SetValue(frame, o)
			helpers.applyKeyInterp(layer.fShadingOffset, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.shading.blurPx ~= nil or params.shading.blur ~= nil) and layer.fShadingBlur then
			local b = params.shading.blurPx ~= nil and helpers.pxToDoc(moho, params.shading.blurPx) or tonumber(params.shading.blur)
			layer.fShadingBlur:SetValue(frame, b)
			helpers.applyKeyInterp(layer.fShadingBlur, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if (params.shading.contractionPx ~= nil or params.shading.contraction ~= nil) and layer.fShadingContraction then
			local c = params.shading.contractionPx ~= nil and helpers.pxToDoc(moho, params.shading.contractionPx) or tonumber(params.shading.contraction)
			layer.fShadingContraction:SetValue(frame, c)
			helpers.applyKeyInterp(layer.fShadingContraction, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		if type(params.shading.color) == "table" and layer.fShadingColor then
			layer.fShadingColor:SetValue(frame, helpers.toRgbStruct(params.shading.color))
			helpers.applyKeyInterp(layer.fShadingColor, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
	end
	if type(params.vectorNoise) == "table" and layer:LayerType() == MOHO.LT_VECTOR then
		local vl = moho:LayerAsVector(layer)
		if vl then
			local docH = moho.document and math.max(1, moho.document:Height()) or 1
			if params.vectorNoise.noisyLines ~= nil then vl.fNoisyLines = (params.vectorNoise.noisyLines == true) end
			if params.vectorNoise.noisyShapes ~= nil then vl.fNoisyShapes = (params.vectorNoise.noisyShapes == true) end
			if params.vectorNoise.animatedNoise ~= nil then vl.fAnimatedNoise = (params.vectorNoise.animatedNoise == true) end
			if params.vectorNoise.extraSketchy ~= nil then vl.fExtraSketchy = (params.vectorNoise.extraSketchy == true) end
			if params.vectorNoise.noiseAmpPx ~= nil then
				vl.fNoiseAmp = tonumber(params.vectorNoise.noiseAmpPx) / docH
			elseif params.vectorNoise.noiseAmp ~= nil then
				vl.fNoiseAmp = tonumber(params.vectorNoise.noiseAmp)
			end
			if params.vectorNoise.noiseScalePx ~= nil then
				vl.fNoiseScale = tonumber(params.vectorNoise.noiseScalePx) / docH
			elseif params.vectorNoise.noiseScale ~= nil then
				vl.fNoiseScale = tonumber(params.vectorNoise.noiseScale)
			end
		end
	end

	helpers.updateUI(moho)
	return layers.getProperties(moho, { layerId = id, frame = frame })
end

--- Rigid-bind to one bone (`boneId`) or flexi-bind to an exact subset (`flexiBoneIds`).
-- Verified via lm_select_bone.lua and Moho Pro 14.4 live runtime.
function layers.bindToBone(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	helpers.prepUndo(moho, layer, true)

	local flexiApplied = {}
	if params.boneId ~= nil then
		if layer.DisableFlexiBoneSubset then
			layer:DisableFlexiBoneSubset()
		end
		layer:SetLayerParentBone(math.floor(tonumber(params.boneId)))
	elseif type(params.flexiBoneIds) == "table" then
		local parentSkel = layer:ControllingSkeleton()
		if not parentSkel then
			return nil, "Layer has no controlling parent BoneLayer skeleton"
		end
		layer:ClearFlexiBoneSubset()
		local boneCount = parentSkel:CountBones()
		for i = 1, #params.flexiBoneIds do
			local bi = math.floor(tonumber(params.flexiBoneIds[i]))
			if bi >= 0 and bi < boneCount then
				layer:AddToFlexiBoneSubset(bi)
				flexiApplied[#flexiApplied + 1] = bi
			end
		end
		if params.elbowBind ~= nil and layer.MarkFlexiBoneSubsetAsElbow then
			layer:MarkFlexiBoneSubsetAsElbow(params.elbowBind == true)
		end
		if #flexiApplied > 0 then
			layer:EnableFlexiBoneSubset()
			if layer:LayerType() == MOHO.LT_IMAGE then
				layer:SetLayerParentBone(-3)
			end
		else
			layer:DisableFlexiBoneSubset()
		end
	else
		return nil, "Provide boneId (rigid bind, -1 to unbind) or flexiBoneIds (array)"
	end

	helpers.updateUI(moho)
	return {
		bound = true,
		layerId = id,
		layerName = layer:Name(),
		parentBone = layer.LayerParentBone and layer:LayerParentBone() or -1,
		flexiBoneIds = json.array(flexiApplied),
		elbowBind = layer.IsElbowBindInEffect and layer:IsElbowBindInEffect() or false,
	}
end

function layers.setWarpLayer(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local warpL = nil
	if params.warpLayerId ~= nil or params.warpLayerName ~= nil then
		local werr
		warpL, _, werr = helpers.resolveLayer(moho, {
			layerId = params.warpLayerId,
			layerName = params.warpLayerName,
		})
		if not warpL then
			return nil, werr
		end
	end
	helpers.prepUndo(moho, layer, true)
	layer:SetWarpLayer(warpL)
	helpers.updateUI(moho)
	return {
		linked = true,
		layerId = id,
		layerName = layer:Name(),
		warpLayerName = warpL and warpL:Name() or "",
	}
end

--- Configure Group masking (`groupMask`) and/or per-layer masking (`maskingMode`, `expandByPixel`).
-- Verified in Moho Pro 14.4: SetGroupMask(mode), SetMaskingMode(mode), SetMaskExpansion(bool).
function layers.setMasking(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local preset = params.preset and string.lower(tostring(params.preset)) or nil
	if preset == "mask_inside_bottom" then
		if not layer:IsGroupType() then
			return nil, "mask_inside_bottom preset requires a Group, Bone, Switch, or Particle layer"
		end
		local grpCheck = moho:LayerAsGroup(layer)
		if not grpCheck or grpCheck:CountLayers() < 1 then
			return nil, "mask_inside_bottom preset requires at least 1 child layer inside the group"
		end
	end

	helpers.prepUndo(moho, layer, true)

	local excludeSupported = nil
	if preset == "mask_inside_bottom" then
		local grp = moho:LayerAsGroup(layer)
		grp:SetGroupMask(MOHO.GROUP_MASK_HIDE_ALL)
		local maskMode = (params.invisibleMask == true) and MOHO.MM_ADD_MASK_INVIS or MOHO.MM_ADD_MASK
		local cnt = grp:CountLayers()
		for i = 0, cnt - 1 do
			local child = grp:Layer(i)
			child:SetMaskingMode(i == 0 and maskMode or MOHO.MM_MASKED)
			if params.expandByPixel ~= nil and child.SetMaskExpansion then
				child:SetMaskExpansion(params.expandByPixel == true)
			end
			if params.excludeStrokes ~= nil and child:LayerType() == MOHO.LT_VECTOR then
				local childVl = moho:LayerAsVector(child)
				if childVl and childVl.fExcludeLinesFromMask ~= nil then
					childVl.fExcludeLinesFromMask = (params.excludeStrokes == true)
					excludeSupported = true
				end
			end
		end
	end

	if params.groupMask ~= nil then
		if not layer:IsGroupType() then
			return nil, "groupMask requires a Group, Bone, Switch, or Particle layer"
		end
		local code = helpers.groupMaskCode(params.groupMask)
		if code == nil then
			return nil, "Unknown groupMask: " .. tostring(params.groupMask)
		end
		local grp = moho:LayerAsGroup(layer)
		grp:SetGroupMask(code)
	end
	if params.maskingMode ~= nil then
		local code = helpers.maskingModeCode(params.maskingMode)
		if code == nil then
			return nil, "Unknown maskingMode: " .. tostring(params.maskingMode)
		end
		layer:SetMaskingMode(code)
	end
	if params.expandByPixel ~= nil and layer.SetMaskExpansion then
		layer:SetMaskExpansion(params.expandByPixel == true)
	end

	if params.excludeStrokes ~= nil then
		local val = (params.excludeStrokes == true)
		if layer:LayerType() == MOHO.LT_VECTOR then
			local vl = moho:LayerAsVector(layer)
			if vl and vl.fExcludeLinesFromMask ~= nil then
				vl.fExcludeLinesFromMask = val
				excludeSupported = true
			end
		end
		if excludeSupported == nil then
			if layer.SetExcludeStrokes then
				layer:SetExcludeStrokes(val)
				excludeSupported = true
			elseif layer.SetMaskExcludeStrokes then
				layer:SetMaskExcludeStrokes(val)
				excludeSupported = true
			elseif layer.SetExcludeLinesFromMask then
				layer:SetExcludeLinesFromMask(val)
				excludeSupported = true
			else
				excludeSupported = false
			end
		end
	end

	helpers.updateUI(moho)
	local out = {
		layerId = id,
		layerName = layer:Name(),
		maskingMode = helpers.maskingModeName(layer:MaskingMode()),
		expandByPixel = layer.MaskExpansion and layer:MaskExpansion() or false,
	}
	if preset ~= nil then
		out.preset = preset
	end
	if excludeSupported ~= nil then
		out.excludeStrokesSupported = excludeSupported
	end
	if layer:LayerType() == MOHO.LT_VECTOR then
		local vl = moho:LayerAsVector(layer)
		if vl and vl.fExcludeLinesFromMask ~= nil then
			out.excludeStrokes = (vl.fExcludeLinesFromMask == true)
		end
	end
	if out.excludeStrokes == nil and layer.ExcludeStrokes then
		local okEx, ex = pcall(function() return layer:ExcludeStrokes() end)
		if okEx then out.excludeStrokes = (ex == true) end
	end
	if layer:IsGroupType() then
		local grp = moho:LayerAsGroup(layer)
		if grp and grp.GetGroupMask then
			out.groupMask = helpers.groupMaskName(grp:GetGroupMask())
		end
	end
	return out
end

--- Render one isolated layer directly to a transparent PNG via MohoLayer:RenderLayerImage(options).
-- Verified via lm_render_layer_image.lua, ss_gltf_export.lua, and Moho Pro 14.4 live runtime.
function layers.renderImage(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local opts = MOHO.MohoLayerRenderOptions:new_local()
	opts.frame = frame
	opts.minDimension = math.max(16, math.floor(tonumber(params.minDimension) or 512))
	opts.maxDimension = math.max(opts.minDimension, math.floor(tonumber(params.maxDimension) or 2048))
	opts.imageExtension:Set("png")
	opts.embedColorProfile = (params.embedColorProfile == true)
	opts.trimResult = (params.trimResult == true)
	if params.polyCountX ~= nil then opts.polyCountX = math.floor(tonumber(params.polyCountX)) end
	if params.polyCountY ~= nil then opts.polyCountY = math.floor(tonumber(params.polyCountY)) end

	local ok = layer:RenderLayerImage(opts)
	if not ok then
		return nil, "RenderLayerImage returned false for layer '" .. layer:Name() .. "' (layer may be empty or hidden)"
	end

	local rawPath = opts.imagePath
	local finalPath = rawPath
	if type(params.outputPath) == "string" and #params.outputPath > 0 then
		local parentDir = params.outputPath:match("^(.*)[/\\][^/\\]+$")
		if parentDir and LM and LM.CreateDir then
			pcall(function() LM.CreateDir(parentDir) end)
		end
		os.remove(params.outputPath)
		local moved = os.rename(rawPath, params.outputPath)
		if not moved then
			-- Cross-drive fallback: binary copy
			local srcF = io.open(rawPath, "rb")
			local dstF = io.open(params.outputPath, "wb")
			if srcF and dstF then
				dstF:write(srcF:read("*a"))
				srcF:close()
				dstF:close()
				os.remove(rawPath)
				finalPath = params.outputPath
			else
				if srcF then srcF:close() end
				if dstF then dstF:close() end
			end
		else
			finalPath = params.outputPath
		end
	end

	local size = 0
	local checkF = io.open(finalPath, "rb")
	if checkF then
		size = checkF:seek("end")
		checkF:close()
	end

	local lb = opts.layerBounds
	return {
		rendered = true,
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		outputPath = finalPath,
		bytes = size,
		bounds = lb and {
			minX = lb.fMin.x,
			minY = lb.fMin.y,
			maxX = lb.fMax.x,
			maxY = lb.fMax.y,
		} or nil,
	}
end

function layers.setLayerOrder(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	if not layer:IsGroupType() then
		return nil, "Animated Layer Order requires a Group, Bone, Switch, or Particle layer"
	end
	local grp = moho:LayerAsGroup(layer)
	if not grp or not grp.GetLayerOrdering then
		return nil, "GroupLayer does not expose GetLayerOrdering"
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	local childByUuid = {}
	local childByName = {}
	local childById = {}
	local defaultUuids = {}
	for i = 0, grp:CountLayers() - 1 do
		local c = grp:Layer(i)
		local cuuid = c:UUID()
		local info = {
			layer = c,
			uuid = cuuid,
			name = c:Name(),
			id = helpers.getLayerId(moho, c),
		}
		childByUuid[cuuid] = info
		childByName[info.name] = info
		childById[info.id] = info
		defaultUuids[#defaultUuids + 1] = cuuid
	end

	local orderCh = grp:GetLayerOrdering()
	local currentUuids = {}
	local seenCurrent = {}
	local rawCur = orderCh:GetValue(frame)
	if type(rawCur) == "string" and #rawCur > 0 then
		for tok in rawCur:gmatch("[^|]+") do
			if childByUuid[tok] and not seenCurrent[tok] then
				seenCurrent[tok] = true
				currentUuids[#currentUuids + 1] = tok
			end
		end
	end
	for i = 1, #defaultUuids do
		local u = defaultUuids[i]
		if not seenCurrent[u] then
			seenCurrent[u] = true
			currentUuids[#currentUuids + 1] = u
		end
	end

	local function resolveChildToken(tok)
		if type(tok) == "number" then
			local info = childById[math.floor(tok)]
			return info and info.uuid or nil
		end
		local s = tostring(tok)
		if childByUuid[s] then return s end
		if childByName[s] then return childByName[s].uuid end
		local num = tonumber(s)
		if num ~= nil and childById[math.floor(num)] then
			return childById[math.floor(num)].uuid
		end
		return nil
	end

	local isMutating = (params.enabled ~= nil or params.order ~= nil or params.moveLayerName ~= nil or params.moveLayerId ~= nil)
	local finalUuids = currentUuids
	if isMutating then
		helpers.prepUndo(moho, layer, true)
		if params.enabled ~= nil and grp.EnableLayerOrdering then
			grp:EnableLayerOrdering(params.enabled == true)
		elseif grp.EnableLayerOrdering and not (grp.IsLayerOrderingEnabled and grp:IsLayerOrderingEnabled()) then
			grp:EnableLayerOrdering(true)
		end

		if type(params.order) == "table" and #params.order > 0 then
			local list = {}
			for i = 1, #params.order do
				list[#list + 1] = params.order[i]
			end
			if params.topToBottom == true then
				local rev = {}
				for i = #list, 1, -1 do rev[#rev + 1] = list[i] end
				list = rev
			end
			local newUuids = {}
			local used = {}
			for i = 1, #list do
				local u = resolveChildToken(list[i])
				if not u then
					return nil, "Child layer not found in group: " .. tostring(list[i])
				end
				if not used[u] then
					used[u] = true
					newUuids[#newUuids + 1] = u
				end
			end
			if params.allowPartial ~= false then
				for i = 1, #currentUuids do
					local u = currentUuids[i]
					if not used[u] then
						used[u] = true
						newUuids[#newUuids + 1] = u
					end
				end
			end
			finalUuids = newUuids
			orderCh:SetValue(frame, table.concat(finalUuids, "|") .. "|")
			local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)
			helpers.applyKeyInterp(orderCh, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		elseif params.moveLayerName ~= nil or params.moveLayerId ~= nil then
			local moveUuid = resolveChildToken(params.moveLayerId ~= nil and params.moveLayerId or params.moveLayerName)
			if not moveUuid then
				return nil, "Child layer to move not found inside group"
			end
			local filtered = {}
			for i = 1, #currentUuids do
				if currentUuids[i] ~= moveUuid then
					filtered[#filtered + 1] = currentUuids[i]
				end
			end
			local pos = string.lower(tostring(params.position or "top"))
			local insertIdx = #filtered + 1
			if pos == "bottom" then
				insertIdx = 1
			elseif pos == "above" or pos == "below" then
				local refUuid = resolveChildToken(params.referenceLayerId ~= nil and params.referenceLayerId or params.referenceLayerName)
				if not refUuid then
					return nil, "Reference child layer not found inside group"
				end
				for i = 1, #filtered do
					if filtered[i] == refUuid then
						insertIdx = (pos == "above") and (i + 1) or i
						break
					end
				end
			end
			table.insert(filtered, insertIdx, moveUuid)
			finalUuids = filtered
			orderCh:SetValue(frame, table.concat(finalUuids, "|") .. "|")
			local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)
			helpers.applyKeyInterp(orderCh, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		helpers.updateUI(moho)
	end

	local orderOut = {}
	for i = 1, #finalUuids do
		local info = childByUuid[finalUuids[i]]
		if info then
			orderOut[#orderOut + 1] = {
				bottomIndex = i - 1,
				id = info.id,
				name = info.name,
				uuid = info.uuid,
			}
		end
	end
	return {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		animatedLayerOrder = grp.IsLayerOrderingEnabled and grp:IsLayerOrderingEnabled() or false,
		order = json.array(orderOut),
	}
end

function layers.convertType(moho, params)
	local srcLayer, srcId, err = helpers.resolveLayer(moho, params)
	if not srcLayer then
		return nil, err
	end
	if not srcLayer:IsGroupType() then
		return nil, "Source layer must be a Group, Bone, or Switch layer"
	end
	local targetType = string.lower(tostring(params.targetType or ""))
	if targetType ~= "group" and targetType ~= "bone" and targetType ~= "switch" then
		return nil, "targetType must be 'group', 'bone', or 'switch'"
	end
	local oldType = helpers.layerTypeName(srcLayer)
	local targetCode = helpers.layerTypeCode(targetType)
	local srcGrp = moho:LayerAsGroup(srcLayer)
	local origName = srcLayer:Name()

	local children = {}
	if srcGrp then
		for i = 0, srcGrp:CountLayers() - 1 do
			children[#children + 1] = srcGrp:Layer(i)
		end
	end
	local bonesDropped = 0
	if srcLayer:LayerType() == MOHO.LT_BONE then
		local bl = moho:LayerAsBone(srcLayer)
		if bl and bl:Skeleton() then
			bonesDropped = bl:Skeleton():CountBones()
		end
	end

	local doc = moho.document
	local compMatches = {}
	if doc and doc.CountLayerComps then
		for ci = 0, doc:CountLayerComps() - 1 do
			local comp = doc:GetLayerComp(ci)
			if comp and comp:ContainsLayer(srcLayer) then
				compMatches[#compMatches + 1] = comp
			end
		end
	end

	helpers.prepUndo(moho, srcLayer, true)
	moho:SetSelLayer(srcLayer)
	local newLayer = moho:CreateNewLayer(targetCode, true)
	if not newLayer then
		return nil, "CreateNewLayer failed for targetType: " .. targetType
	end
	moho:PlaceLayerBehindAnother(newLayer, srcLayer)

	local parentGrp = srcLayer:Parent()
	if parentGrp and parentGrp:IsGroupType() and newLayer:Parent() ~= parentGrp then
		moho:PlaceLayerInGroup(newLayer, parentGrp, true, false)
		moho:PlaceLayerBehindAnother(newLayer, srcLayer)
	end

	newLayer:SetVisible(srcLayer:IsVisible())
	newLayer:SetLocked(srcLayer:IsLocked())
	if newLayer.SetEditOnly and srcLayer.IsEditOnly then newLayer:SetEditOnly(srcLayer:IsEditOnly()) end
	if newLayer.SetRenderOnly and srcLayer.IsRenderOnly then newLayer:SetRenderOnly(srcLayer:IsRenderOnly()) end
	if newLayer.SetBlendingMode and srcLayer.BlendingMode then newLayer:SetBlendingMode(srcLayer:BlendingMode()) end
	if newLayer.SetMaskingMode and srcLayer.MaskingMode then newLayer:SetMaskingMode(srcLayer:MaskingMode()) end
	if newLayer.SetMaskExpansion and srcLayer.MaskExpansion then newLayer:SetMaskExpansion(srcLayer:MaskExpansion()) end
	if newLayer.SetLabelColor and srcLayer.LabelColor then newLayer:SetLabelColor(srcLayer:LabelColor()) end
	if newLayer.SetUserTags and srcLayer.UserTags then newLayer:SetUserTags(srcLayer:UserTags()) end
	if newLayer.SetUserComments and srcLayer.UserComments then newLayer:SetUserComments(srcLayer:UserComments()) end
	if newLayer.SetTimingOffset and srcLayer.TimingOffset then newLayer:SetTimingOffset(srcLayer:TimingOffset()) end
	if newLayer.SetShownOnTimeline and srcLayer.IsShownOnTimeline then newLayer:SetShownOnTimeline(srcLayer:IsShownOnTimeline()) end
	if newLayer.SetImmuneToDof and srcLayer.IsImmuneToDof then newLayer:SetImmuneToDof(srcLayer:IsImmuneToDof()) end
	if newLayer.SetLayerParentBone and srcLayer.LayerParentBone and srcLayer:LayerParentBone() >= 0 then
		newLayer:SetLayerParentBone(srcLayer:LayerParentBone())
	end
	if newLayer.SetWarpLayer and srcLayer.GetWarpLayer then
		local wl = srcLayer:GetWarpLayer()
		if wl then newLayer:SetWarpLayer(wl) end
	end
	local orig2 = srcLayer:Origin()
	newLayer:SetOrigin(orig2)

	local channels = {
		"fTranslation", "fScale", "fRotationZ", "fRotationX", "fRotationY",
		"fAlpha", "fBlur", "fFlipH", "fFlipV", "fVisibility",
		"fLayerColorOn", "fLayerColor", "fLayerOutline", "fOutlineWidth", "fOutlineColor",
		"fLayerShadow", "fShadowAngle", "fShadowOffset", "fShadowBlur", "fShadowExpansion", "fShadowColor",
		"fLayerShading", "fShadingAngle", "fShadingOffset", "fShadingBlur", "fShadingContraction", "fShadingColor",
	}
	for i = 1, #channels do
		local cname = channels[i]
		helpers.copyAnimChannel(srcLayer[cname], newLayer[cname])
	end

	local newGrp = moho:LayerAsGroup(newLayer)
	if newGrp and srcGrp then
		if newGrp.SetGroupMask and srcGrp.GetGroupMask then
			newGrp:SetGroupMask(srcGrp:GetGroupMask())
		end
		for i = 1, #children do
			moho:PlaceLayerInGroup(children[i], newGrp, true, false)
		end
		if srcGrp.IsLayerOrderingEnabled and srcGrp:IsLayerOrderingEnabled() then
			if newGrp.EnableLayerOrdering then newGrp:EnableLayerOrdering(true) end
			if srcGrp.GetLayerOrdering and newGrp.GetLayerOrdering then
				helpers.copyAnimChannel(srcGrp:GetLayerOrdering(), newGrp:GetLayerOrdering())
			end
		end
	end

	if targetType == "switch" and params.frameByFrame ~= nil then
		local sw = moho:LayerAsSwitch(newLayer)
		if sw and sw.SetFBFLayer then
			sw:SetFBFLayer(params.frameByFrame == true)
		end
	end

	for i = 1, #compMatches do
		compMatches[i]:AddLayer(newLayer)
	end

	local deleteOrig = (params.deleteOriginal ~= false)
	if deleteOrig then
		moho:DeleteLayer(srcLayer)
		newLayer:SetName(origName)
	else
		newLayer:SetName(tostring(params.newName or (origName .. " (" .. targetType .. ")")))
	end
	moho:SetSelLayer(newLayer)
	helpers.updateUI(moho)

	return {
		converted = true,
		id = helpers.getLayerId(moho, newLayer),
		name = newLayer:Name(),
		oldType = oldType,
		newType = helpers.layerTypeName(newLayer),
		childCount = #children,
		bonesDropped = (targetType ~= "bone") and bonesDropped or 0,
		deletedOriginal = deleteOrig,
	}
end

function layers.groupSelection(moho, params)
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local wantIds = {}
	local wantNames = {}
	if type(params.layerIds) == "table" then
		for i = 1, #params.layerIds do
			wantIds[math.floor(tonumber(params.layerIds[i]))] = true
		end
	end
	if type(params.layerNames) == "table" then
		for i = 1, #params.layerNames do
			wantNames[tostring(params.layerNames[i])] = true
		end
	end
	if not next(wantIds) and not next(wantNames) then
		return nil, "Provide layerIds and/or layerNames to group"
	end

	local topToBottom = {}
	helpers.walkLayers(moho, function(l, lid)
		if wantIds[lid] or wantNames[l:Name()] then
			topToBottom[#topToBottom + 1] = l
		end
	end)
	if #topToBottom == 0 then
		return nil, "No matching layers found to group"
	end

	local gType = string.lower(tostring(params.groupType or "group"))
	if gType ~= "group" and gType ~= "bone" and gType ~= "switch" then
		return nil, "groupType must be 'group', 'bone', or 'switch'"
	end
	local gCode = helpers.layerTypeCode(gType)
	local topSelected = topToBottom[1]

	helpers.prepUndo(moho, topSelected, true)
	moho:SetSelLayer(topSelected)
	local newGroup = moho:CreateNewLayer(gCode, true)
	if not newGroup then
		return nil, "Failed to create container layer"
	end
	newGroup:SetName(tostring(params.name or "Group"))
	helpers.placeLayerInFrontOf(moho, newGroup, topSelected)

	for i = #topToBottom, 1, -1 do
		local child = topToBottom[i]
		if child ~= newGroup then
			moho:PlaceLayerInGroup(child, newGroup, true, false)
		end
	end

	local gid = helpers.getLayerId(moho, newGroup)
	if params.maskPreset ~= nil or params.groupMask ~= nil then
		layers.setMasking(moho, {
			layerId = gid,
			preset = params.maskPreset,
			groupMask = params.groupMask,
			expandByPixel = params.expandByPixel,
			invisibleMask = params.invisibleMask,
		})
	end

	moho:SetSelLayer(newGroup)
	helpers.updateUI(moho)
	local kidsOut = {}
	local grp = moho:LayerAsGroup(newGroup)
	if grp then
		for i = 0, grp:CountLayers() - 1 do
			local c = grp:Layer(i)
			kidsOut[#kidsOut + 1] = { id = helpers.getLayerId(moho, c), name = c:Name() }
		end
	end
	return {
		grouped = true,
		groupLayerId = gid,
		groupLayerName = newGroup:Name(),
		groupType = helpers.layerTypeName(newGroup),
		childCount = #kidsOut,
		children = json.array(kidsOut),
	}
end

function layers.followPath(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)

	if params.detach == true then
		helpers.prepUndo(moho, layer, false)
		if layer.SetFollowingCurve then
			layer:SetFollowingCurve(nil, nil, 0, false)
		end
		helpers.updateUI(moho)
		return {
			layerId = id,
			layerName = layer:Name(),
			frame = frame,
			attached = false,
		}
	elseif params.followLayerId ~= nil or params.followLayerName ~= nil then
		local fl, fid, ferr = helpers.resolveLayer(moho, {
			layerId = params.followLayerId,
			layerName = params.followLayerName,
		})
		if not fl then return nil, ferr end
		local vl = moho:LayerAsVector(fl)
		if not vl then
			return nil, "followLayer must be a VectorLayer: " .. fl:Name()
		end
		local mesh = vl:Mesh()
		local cIdx = math.floor(tonumber(params.curveIndex) or 0)
		if cIdx < 0 or cIdx >= mesh:CountCurves() then
			return nil, "curveIndex out of range: " .. tostring(cIdx)
		end
		local curve = mesh:Curve(cIdx)
		local pct = tonumber(params.percent) or 0
		local bend = (params.bendLayer == true)
		helpers.prepUndo(moho, layer, false)
		layer:SetFollowingCurve(fl, curve, pct, bend)
		if layer.fFollowing then
			layer.fFollowing:SetValue(frame, pct)
			helpers.applyKeyInterp(layer.fFollowing, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		layer:UpdateCurFrame()
		helpers.updateUI(moho)
	elseif params.percent ~= nil then
		local info = helpers.getFollowCurveInfo(moho, layer, frame)
		if not info then
			return nil, "Layer is not attached to any Follow Path curve"
		end
		helpers.prepUndo(moho, layer, false)
		if layer.fFollowing then
			layer.fFollowing:SetValue(frame, tonumber(params.percent))
			helpers.applyKeyInterp(layer.fFollowing, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
		layer:UpdateCurFrame()
		helpers.updateUI(moho)
	end

	local followInfo = helpers.getFollowCurveInfo(moho, layer, frame)
	return {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		attached = followInfo ~= nil,
		followLayerId = followInfo and followInfo.followLayerId or nil,
		followLayerName = followInfo and followInfo.followLayerName or nil,
		followCurve = followInfo and followInfo.followCurve or nil,
		percent = followInfo and followInfo.followPercent or nil,
	}
end

function layers.referenceManage(moho, params)
	local op = string.lower(tostring(params.operation or "status"))
	if op == "import_reference" then
		if not moho.document then
			return nil, "No document open"
		end
		local path = params.path
		if type(path) ~= "string" or #path == 0 then
			return nil, "path is required for import_reference"
		end
		helpers.prepUndo(moho, moho.layer, true)
		local method = "FileImport"
		if moho.ImportLayerByReference then
			moho:ImportLayerByReference(path)
			method = "ImportLayerByReference"
		else
			moho:FileImport(path, tonumber(params.mode) or 0)
		end
		helpers.updateUI(moho)
		local sel = moho.layer
		return {
			imported = true,
			method = method,
			path = path,
			layerId = sel and helpers.getLayerId(moho, sel) or -1,
			layerName = sel and sel:Name() or "",
			isReference = sel and sel.IsReferencedLayer and sel:IsReferencedLayer() or false,
		}
	end

	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	if op == "status" then
		return {
			layerId = id,
			layerName = layer:Name(),
			isReference = layer.IsReferencedLayer and layer:IsReferencedLayer() or false,
			isExternal = layer.IsReferenceExternal and layer:IsReferenceExternal() or false,
			isOutOfDate = layer.IsReferenceOutdated and layer:IsReferenceOutdated() or false,
		}
	elseif op == "break_reference" then
		helpers.prepUndo(moho, layer, true)
		if layer.BreakLayerReference then
			layer:BreakLayerReference()
		else
			return nil, "BreakLayerReference not available"
		end
		helpers.updateUI(moho)
		return {
			layerId = id,
			layerName = layer:Name(),
			broken = true,
			isReference = layer.IsReferencedLayer and layer:IsReferencedLayer() or false,
		}
	elseif op == "update_reference" then
		helpers.prepUndo(moho, layer, true)
		local opts = MOHO and MOHO.MohoLayerRefSyncOptions and MOHO.MohoLayerRefSyncOptions:new_local() or nil
		local updated = false
		if opts and layer.UpdateReferencedLayer then
			opts.fAddNewLayers = (params.addNewLayers ~= false)
			opts.fRemoveMissingLayers = (params.removeMissingLayers ~= false)
			opts.fReplaceMismatchedVectors = (params.replaceMismatchedVectors ~= false)
			opts.fReplaceMismatchedBones = (params.replaceMismatchedBones ~= false)
			updated = (layer:UpdateReferencedLayer(opts) == true)
		elseif layer.UpdateReferencedLayer then
			updated = (layer:UpdateReferencedLayer() == true)
		else
			return nil, "UpdateReferencedLayer not available"
		end
		helpers.updateUI(moho)
		return {
			layerId = id,
			layerName = layer:Name(),
			updated = updated,
			isReference = layer.IsReferencedLayer and layer:IsReferencedLayer() or false,
			isOutOfDate = layer.IsReferenceOutdated and layer:IsReferenceOutdated() or false,
		}
	elseif op == "mark_outdated" then
		helpers.prepUndo(moho, layer, false)
		if layer.MarkReferenceOutdated then
			layer:MarkReferenceOutdated()
		end
		helpers.updateUI(moho)
		return {
			layerId = id,
			layerName = layer:Name(),
			isOutOfDate = layer.IsReferenceOutdated and layer:IsReferenceOutdated() or false,
		}
	end
	return nil, "Unsupported reference operation: " .. op
end

return layers
