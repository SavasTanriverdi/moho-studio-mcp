-- Shared Moho Pro 14.4 Lua 5.4 helpers for Moho Studio MCP v3.0.0.
-- All constants and methods verified against live Moho Pro 14.4 introspection and official scripts.

local json = require("moho_studio.json")

local helpers = {}

helpers.LAYER_TYPE_NAMES = {}
helpers.NAME_TO_LAYER_TYPE = {}
helpers.batchDepth = 0

function helpers.initConstants()
	local map = {
		vector = MOHO.LT_VECTOR,
		image = MOHO.LT_IMAGE,
		group = MOHO.LT_GROUP,
		bone = MOHO.LT_BONE,
		switch = MOHO.LT_SWITCH,
		particle = MOHO.LT_PARTICLE,
		note = MOHO.LT_NOTE,
		mesh3d = MOHO.LT_3D,
		audio = MOHO.LT_AUDIO,
		patch = MOHO.LT_PATCH,
		text = MOHO.LT_TEXT,
	}
	for name, code in pairs(map) do
		if code ~= nil then
			helpers.LAYER_TYPE_NAMES[code] = name
			helpers.NAME_TO_LAYER_TYPE[name] = code
		end
	end
end

function helpers.layerTypeName(layer)
	if not next(helpers.LAYER_TYPE_NAMES) then
		helpers.initConstants()
	end
	local lt = layer:LayerType()
	return helpers.LAYER_TYPE_NAMES[lt] or ("type_" .. tostring(lt))
end

function helpers.layerTypeCode(name)
	if not next(helpers.NAME_TO_LAYER_TYPE) then
		helpers.initConstants()
	end
	if type(name) == "number" then
		return name
	end
	local k = string.lower(tostring(name or ""))
	if k == "framebyframe" or k == "fbf" then
		return MOHO.LT_SWITCH
	end
	return helpers.NAME_TO_LAYER_TYPE[k]
end

local BLEND_MAP = {
	normal = "BM_NORMAL",
	multiply = "BM_MULTIPLY",
	screen = "BM_SCREEN",
	overlay = "BM_OVERLAY",
	add = "BM_ADD",
	difference = "BM_DIFFERENCE",
	hue = "BM_HUE",
	saturation = "BM_SATURATION",
	color = "BM_COLOR",
	luminosity = "BM_LUMINOSITY",
	soft_light = "BM_SOFT_LIGHT",
	color_dodge = "BM_COLOR_DODGE",
	linear_dodge = "BM_LINEAR_DODGE",
	color_burn = "BM_COLOR_BURN",
}

function helpers.blendingModeCode(val)
	if type(val) == "number" then
		return math.floor(val)
	end
	local key = BLEND_MAP[string.lower(tostring(val or "normal"))]
	if key and MOHO[key] ~= nil then
		return MOHO[key]
	end
	return MOHO.BM_NORMAL or 0
end

function helpers.blendingModeName(code)
	for name, key in pairs(BLEND_MAP) do
		if MOHO[key] == code then
			return name
		end
	end
	return "mode_" .. tostring(code)
end

local MASK_MAP = {
	masked = "MM_MASKED",
	not_masked = "MM_NOTMASKED",
	notmasked = "MM_NOTMASKED",
	add_mask = "MM_ADD_MASK",
	sub_mask = "MM_SUB_MASK",
	add_mask_invis = "MM_ADD_MASK_INVIS",
	sub_mask_invis = "MM_SUB_MASK_INVIS",
	clear_add_mask = "MM_CLEAR_ADD_MASK",
	clear_add_mask_invis = "MM_CLEAR_ADD_MASK_INVIS",
}

function helpers.maskingModeCode(val)
	if type(val) == "number" then
		return math.floor(val)
	end
	local key = MASK_MAP[string.lower(tostring(val or "masked"))]
	if key and MOHO[key] ~= nil then
		return MOHO[key]
	end
	return nil
end

function helpers.maskingModeName(code)
	for name, key in pairs(MASK_MAP) do
		if name ~= "notmasked" and MOHO[key] == code then
			return name
		end
	end
	return "mask_" .. tostring(code)
end

local GROUP_MASK_MAP = {
	none = "GROUP_MASK_NONE",
	show_all = "GROUP_MASK_SHOW_ALL",
	hide_all = "GROUP_MASK_HIDE_ALL",
}

function helpers.groupMaskCode(val)
	if type(val) == "number" then
		return math.floor(val)
	end
	local key = GROUP_MASK_MAP[string.lower(tostring(val or "none"))]
	if key and MOHO[key] ~= nil then
		return MOHO[key]
	end
	return nil
end

function helpers.groupMaskName(code)
	for name, key in pairs(GROUP_MASK_MAP) do
		if MOHO[key] == code then
			return name
		end
	end
	return "group_mask_" .. tostring(code)
end

local COMBO_MAP = {
	normal = "COMBO_NORMAL",
	add = "COMBO_ADD",
	subtract = "COMBO_SUBTRACT",
	intersect = "COMBO_INTERSECT",
	clip = "COMBO_INTERSECT",
}

function helpers.comboModeCode(val)
	if type(val) == "number" then
		return math.floor(val)
	end
	local key = COMBO_MAP[string.lower(tostring(val or "normal"))]
	if key and MOHO[key] ~= nil then
		return MOHO[key]
	end
	return nil
end

function helpers.comboModeName(code)
	for name, key in pairs(COMBO_MAP) do
		if name ~= "clip" and MOHO[key] == code then
			return name
		end
	end
	return "combo_" .. tostring(code)
end

local GRADIENT_MAP = {
	linear = { key = "GRADIENT_LINEAR", fallback = 0 },
	radial = { key = "GRADIENT_RADIAL", fallback = 1 },
	reflected = { key = "GRADIENT_REFLECTED", fallback = 2 },
	angle = { key = "GRADIENT_ANGLE", fallback = 3 },
}

function helpers.gradientTypeCode(val)
	if type(val) == "number" then
		return math.floor(val)
	end
	local spec = GRADIENT_MAP[string.lower(tostring(val or "linear"))]
	if spec then
		if MOHO and MOHO[spec.key] ~= nil then
			return MOHO[spec.key]
		end
		return spec.fallback
	end
	return nil
end

function helpers.gradientTypeName(code)
	for name, spec in pairs(GRADIENT_MAP) do
		local target = (MOHO and MOHO[spec.key] ~= nil) and MOHO[spec.key] or spec.fallback
		if target == code then
			return name
		end
	end
	return "gradient_" .. tostring(code)
end

function helpers.readLmString(val)
	if val == nil then
		return ""
	end
	if type(val) == "string" then
		return val
	end
	if type(val) == "userdata" or type(val) == "table" then
		local ok, buf = pcall(function()
			if val.Buffer then
				return val:Buffer()
			end
			return nil
		end)
		if ok and type(buf) == "string" then
			return buf
		end
	end
	return ""
end

function helpers.writeLmString(obj, fieldName, str)
	if not obj or not fieldName then
		return false
	end
	local s = tostring(str or "")
	local okCur, cur = pcall(function() return obj[fieldName] end)
	if okCur and cur ~= nil and (type(cur) == "userdata" or type(cur) == "table") and cur.Set then
		local okSet = pcall(function() cur:Set(s) end)
		if okSet then
			return true
		end
	end
	local okAssign = pcall(function() obj[fieldName] = s end)
	return okAssign == true
end

function helpers.toRgbStruct(c)
	local rgb = LM.rgb_color:new_local()
	if type(c) ~= "table" then
		rgb.r, rgb.g, rgb.b, rgb.a = 0, 0, 0, 255
		return rgb
	end
	local r = tonumber(c.r) or 0
	local g = tonumber(c.g) or 0
	local b = tonumber(c.b) or 0
	local a = c.a ~= nil and tonumber(c.a) or nil
	local normalized = (r <= 1 and g <= 1 and b <= 1 and (a == nil or a <= 1))
	local scale = normalized and 255 or 1
	rgb.r = math.max(0, math.min(255, math.floor(r * scale + 0.5)))
	rgb.g = math.max(0, math.min(255, math.floor(g * scale + 0.5)))
	rgb.b = math.max(0, math.min(255, math.floor(b * scale + 0.5)))
	rgb.a = math.max(0, math.min(255, math.floor((a ~= nil and a or (normalized and 1 or 255)) * scale + 0.5)))
	return rgb
end

--- Walk every layer in the document in deterministic depth-first order.
-- Calls visitor(layer, id, parentId, depth).
function helpers.walkLayers(moho, visitor)
	local doc = moho.document
	if not doc then
		return 0
	end
	local nextId = 0
	local function visitLayer(layer, parentId, depth)
		local myId = nextId
		nextId = nextId + 1
		visitor(layer, myId, parentId, depth)
		if layer:IsGroupType() then
			local grp = moho:LayerAsGroup(layer)
			if grp then
				local count = grp:CountLayers()
				for i = count - 1, 0, -1 do
					visitLayer(grp:Layer(i), myId, depth + 1)
				end
			end
		end
	end
	local topCount = doc:CountLayers()
	for i = topCount - 1, 0, -1 do
		visitLayer(doc:Layer(i), -1, 0)
	end
	return nextId
end

--- Resolve a layer by numeric layerId, UUID, or exact name.
function helpers.resolveLayer(moho, params)
	local doc = moho.document
	if not doc then
		return nil, -1, "No document open"
	end
	if params == nil then
		return moho.layer, helpers.getLayerId(moho, moho.layer), nil
	end
	local targetId = params.layerId
	local targetName = params.layerName
	local targetUuid = params.layerUuid
	if targetId == nil and targetName == nil and targetUuid == nil then
		return moho.layer, helpers.getLayerId(moho, moho.layer), nil
	end
	local foundLayer = nil
	local foundId = -1
	helpers.walkLayers(moho, function(layer, id)
		if foundLayer then
			return
		end
		if targetId ~= nil and id == targetId then
			foundLayer = layer
			foundId = id
		elseif targetUuid ~= nil and layer.UUID and layer:UUID() == targetUuid then
			foundLayer = layer
			foundId = id
		elseif targetName ~= nil and layer:Name() == targetName then
			foundLayer = layer
			foundId = id
		end
	end)
	if not foundLayer then
		return nil, -1, "Layer not found (layerId=" .. tostring(targetId) .. ", layerName=" .. tostring(targetName) .. ")"
	end
	return foundLayer, foundId, nil
end

function helpers.getLayerId(moho, targetLayer)
	if not targetLayer then
		return -1
	end
	local foundId = -1
	helpers.walkLayers(moho, function(layer, id)
		if foundId < 0 and layer == targetLayer then
			foundId = id
		end
	end)
	return foundId
end

function helpers.getFlexiBoneIds(layer)
	local ids = {}
	if not layer or not layer.ControllingSkeleton or not layer.IsIncludedInFlexiBoneSubset then
		return ids
	end
	local ok, skel = pcall(function() return layer:ControllingSkeleton() end)
	if not ok or not skel then
		return ids
	end
	local count = skel:CountBones()
	for i = 0, count - 1 do
		local okInc, inc = pcall(function() return layer:IsIncludedInFlexiBoneSubset(i) end)
		if okInc and inc == true then
			ids[#ids + 1] = i
		end
	end
	return ids
end

function helpers.getLayerBounds(layer, frame)
	if not layer or not layer.Bounds then
		return nil
	end
	local f = frame or 0
	local ok, bbox = pcall(function() return layer:Bounds(f) end)
	if not ok or not bbox or not bbox.fMin or not bbox.fMax then
		return nil
	end
	return {
		minX = bbox.fMin.x,
		minY = bbox.fMin.y,
		maxX = bbox.fMax.x,
		maxY = bbox.fMax.y,
	}
end

function helpers.getFollowCurveInfo(moho, layer, frame)
	if not layer or not layer.GetFollowingLayer then
		return nil
	end
	local okFl, fl = pcall(function() return layer:GetFollowingLayer() end)
	if not okFl or not fl then
		return nil
	end
	local followCurveIdx = -1
	if layer.GetFollowingCurve then
		local okFc, fc = pcall(function() return layer:GetFollowingCurve() end)
		if okFc and fc then
			local vl = moho:LayerAsVector(fl)
			local mesh = vl and vl:Mesh() or nil
			if mesh then
				for ci = 0, mesh:CountCurves() - 1 do
					if mesh:Curve(ci) == fc then
						followCurveIdx = ci
						break
					end
				end
			end
		end
	end
	local pct = nil
	if layer.fFollowing and layer.fFollowing.GetValue then
		local okP, pVal = pcall(function() return layer.fFollowing:GetValue(frame or 0) end)
		if okP then pct = pVal end
	end
	return {
		followLayerId = helpers.getLayerId(moho, fl),
		followLayerName = fl:Name(),
		followCurve = followCurveIdx,
		followPercent = pct,
	}
end

function helpers.serializeLayerNode(moho, layer, id, parentId)
	local node = {
		id = id,
		parentId = parentId,
		name = layer:Name(),
		type = helpers.layerTypeName(layer),
		visible = layer:IsVisible(),
		locked = layer:IsLocked(),
		editOnly = layer.IsEditOnly and layer:IsEditOnly() or false,
		parentBone = layer.LayerParentBone and layer:LayerParentBone() or -1,
		flexiBoneIds = json.array(helpers.getFlexiBoneIds(layer)),
		elbowBind = layer.IsElbowBindInEffect and layer:IsElbowBindInEffect() or false,
		maskingMode = layer.MaskingMode and helpers.maskingModeName(layer:MaskingMode()) or "masked",
		isReference = layer.IsReferencedLayer and layer:IsReferencedLayer() or false,
		isOutOfDate = layer.IsReferenceOutdated and layer:IsReferenceOutdated() or false,
		timingOffset = layer.TimingOffset and layer:TimingOffset() or 0,
		totalTimingOffset = layer.TotalTimingOffset and layer:TotalTimingOffset() or 0,
		uuid = layer.UUID and layer:UUID() or "",
		children = json.array({}),
	}
	if layer.ExcludeStrokes then
		local okEx, ex = pcall(function() return layer:ExcludeStrokes() end)
		if okEx then
			node.excludeStrokes = (ex == true)
		end
	end
	local followInfo = helpers.getFollowCurveInfo(moho, layer, moho.frame)
	if followInfo then
		node.followLayerId = followInfo.followLayerId
		node.followLayerName = followInfo.followLayerName
		node.followCurve = followInfo.followCurve
	end
	if layer.GetWarpLayer then
		local wl = layer:GetWarpLayer()
		if wl then
			node.warpLayerName = wl:Name()
			node.warpLayerUuid = wl.UUID and wl:UUID() or ""
		end
	end
	if layer:IsGroupType() then
		local grp = moho:LayerAsGroup(layer)
		if grp and grp.GetGroupMask then
			node.groupMask = helpers.groupMaskName(grp:GetGroupMask())
		end
		if grp and grp.IsLayerOrderingEnabled then
			node.animatedLayerOrder = (grp:IsLayerOrderingEnabled() == true)
		end
	end
	local lt = layer:LayerType()
	if lt == MOHO.LT_IMAGE then
		local img = moho:LayerAsImage(layer)
		if img and img.SourceImage then
			node.sourceImage = img:SourceImage()
		end
	elseif lt == MOHO.LT_VECTOR then
		local vl = moho:LayerAsVector(layer)
		if vl then
			if vl.IsWarpLayer then node.isWarpLayer = vl:IsWarpLayer() end
			if vl.IsCurver then node.isCurver = vl:IsCurver() end
			if vl.ContinuousTriangulation then node.continuousTriangulation = vl:ContinuousTriangulation() end
			if vl.fExcludeLinesFromMask ~= nil then
				node.excludeStrokes = (vl.fExcludeLinesFromMask == true)
			end
		end
	elseif lt == MOHO.LT_BONE then
		local bl = moho:LayerAsBone(layer)
		if bl then
			local skel = bl:Skeleton()
			if skel then
				node.boneCount = skel:CountBones()
				if skel.CountGroups then node.boneGroupCount = skel:CountGroups() end
			end
		end
	elseif lt == MOHO.LT_SWITCH then
		local sw = moho:LayerAsSwitch(layer)
		if sw then
			if sw.IsFBFLayer then node.isFrameByFrame = sw:IsFBFLayer() end
			local sv = sw:SwitchValues()
			if sv and sv.value and sv.value.Buffer then
				node.activeSwitchChild = sv.value:Buffer()
			end
		end
	end
	return node
end

function helpers.buildLayerTree(moho)
	local doc = moho.document
	if not doc then
		return json.array({})
	end
	local nextId = 0
	local function buildNode(layer, parentId)
		local myId = nextId
		nextId = nextId + 1
		local node = helpers.serializeLayerNode(moho, layer, myId, parentId)
		if layer:IsGroupType() then
			local grp = moho:LayerAsGroup(layer)
			if grp then
				local kids = {}
				for i = grp:CountLayers() - 1, 0, -1 do
					kids[#kids + 1] = buildNode(grp:Layer(i), myId)
				end
				node.children = json.array(kids)
			end
		end
		return node
	end
	local roots = {}
	for i = doc:CountLayers() - 1, 0, -1 do
		roots[#roots + 1] = buildNode(doc:Layer(i), -1)
	end
	return json.array(roots)
end

-- Verified Moho 14.4 MOHO.INTERP_* constants (ease_in_out maps to INTERP_EASE = 2).
local INTERP_MAP = {
	linear = "INTERP_LINEAR",
	smooth = "INTERP_SMOOTH",
	ease = "INTERP_EASE",
	ease_in_out = "INTERP_EASE",
	ease_in = "INTERP_EASE_IN",
	ease_out = "INTERP_EASE_OUT",
	step = "INTERP_STEP",
	noisy = "INTERP_NOISY",
	cycle = "INTERP_CYCLE",
	pose = "INTERP_POSE",
	bezier = "INTERP_BEZIER",
	bounce = "INTERP_BOUNCE",
	elastic = "INTERP_ELASTIC",
}

function helpers.resolveInterpMode(name)
	if type(name) == "number" then
		return math.floor(name)
	end
	local key = INTERP_MAP[string.lower(tostring(name or "smooth"))]
	if key and MOHO[key] ~= nil then
		return MOHO[key]
	end
	return MOHO.INTERP_SMOOTH
end

function helpers.interpModeName(code)
	if code == MOHO.INTERP_EASE then
		return "ease_in_out"
	end
	for name, constKey in pairs(INTERP_MAP) do
		if name ~= "ease" and MOHO[constKey] == code then
			return name
		end
	end
	return "mode_" .. tostring(code)
end

function helpers.extractInterpArgs(src, fallback)
	local function pick(key)
		if type(src) == "table" and src[key] ~= nil then
			return src[key]
		end
		if type(fallback) == "table" and fallback[key] ~= nil then
			return fallback[key]
		end
		return nil
	end
	local opts = {
		stagger = pick("stagger"),
		hold = pick("hold"),
		additiveCycle = pick("additiveCycle"),
		cycleMode = pick("cycleMode"),
		cycleTargetFrame = pick("cycleTargetFrame"),
		colorTag = pick("colorTag"),
		bezierComponent = pick("bezierComponent"),
		bezierInAngle = pick("bezierInAngle"),
		bezierInPercent = pick("bezierInPercent"),
		bezierOutAngle = pick("bezierOutAngle"),
		bezierOutPercent = pick("bezierOutPercent"),
	}
	return pick("interpolation"), pick("cycleBack"), pick("val1"), pick("val2"), pick("interval"), opts
end

function helpers.applyKeyInterp(channel, frame, interpName, cycleBack, v1, v2, interval, opts)
	if not channel then
		return
	end
	opts = type(opts) == "table" and opts or {}
	local hasBezier = (opts.bezierInAngle ~= nil or opts.bezierInPercent ~= nil
		or opts.bezierOutAngle ~= nil or opts.bezierOutPercent ~= nil)
	if interpName == nil and cycleBack == nil and v1 == nil and v2 == nil and interval == nil
		and opts.stagger == nil and opts.hold == nil and opts.additiveCycle == nil
		and opts.cycleMode == nil and opts.cycleTargetFrame == nil and opts.colorTag == nil
		and not hasBezier then
		return
	end
	local keyId = channel:GetClosestKeyID(frame)
	if keyId < 0 or channel:GetKeyWhen(keyId) ~= frame then
		return
	end
	local interp = MOHO.InterpSetting:new_local()
	channel:GetKeyInterpByID(keyId, interp)
	if interpName ~= nil then
		local lower = string.lower(tostring(interpName))
		if lower == "stagger" then
			interp.stagger = true
		else
			interp.interpMode = helpers.resolveInterpMode(lower)
		end
	elseif hasBezier then
		interp.interpMode = MOHO.INTERP_BEZIER
	end
	if interp.interpMode == MOHO.INTERP_CYCLE then
		local cMode = opts.cycleMode and string.lower(tostring(opts.cycleMode)) or nil
		local targetFrame = (opts.cycleTargetFrame ~= nil) and math.floor(tonumber(opts.cycleTargetFrame)) or nil
		if cMode == "absolute" or (cMode == nil and targetFrame ~= nil and cycleBack == nil and v1 == nil and v2 == nil) then
			local absFrame = targetFrame
			if absFrame == nil and v2 ~= nil then
				absFrame = math.floor(tonumber(v2))
			end
			if absFrame == nil then
				absFrame = (frame > 2) and 2 or 1
			end
			interp.val1 = (v1 ~= nil) and tonumber(v1) or 0
			interp.val2 = math.max(0, absFrame)
		elseif v2 ~= nil and tonumber(v2) >= 0 and cMode ~= "relative" then
			interp.val1 = (v1 ~= nil) and tonumber(v1) or 0
			interp.val2 = math.floor(tonumber(v2))
		else
			local relDelta
			if cycleBack ~= nil then
				relDelta = math.max(1, math.floor(tonumber(cycleBack)))
			elseif v1 ~= nil then
				relDelta = math.max(1, math.floor(tonumber(v1)))
			elseif targetFrame ~= nil then
				relDelta = math.max(1, frame - targetFrame)
			else
				relDelta = math.max(1, frame - 2)
			end
			interp.val1 = relDelta
			interp.val2 = -1
		end
	else
		if v1 ~= nil then interp.val1 = tonumber(v1) end
		if v2 ~= nil then interp.val2 = tonumber(v2) end
	end
	if interval ~= nil then
		interp.interval = math.max(1, math.floor(tonumber(interval) or 1))
	end
	if opts.stagger ~= nil then
		interp.stagger = (opts.stagger == true)
	end
	if opts.hold ~= nil then
		interp.hold = math.max(0, math.floor(tonumber(opts.hold) or 0))
	end
	if opts.colorTag ~= nil then
		pcall(function() interp.tags = math.floor(tonumber(opts.colorTag) or 0) end)
	end
	if opts.additiveCycle ~= nil and interp.SetAdditiveCycle then
		interp:SetAdditiveCycle(opts.additiveCycle == true)
	end
	local bezComp = math.max(0, math.floor(tonumber(opts.bezierComponent) or 0))
	if opts.bezierInAngle ~= nil and interp.SetBezierInAngle then
		pcall(function() interp:SetBezierInAngle(bezComp, tonumber(opts.bezierInAngle)) end)
	end
	if opts.bezierInPercent ~= nil and interp.SetBezierInPercentage then
		pcall(function() interp:SetBezierInPercentage(bezComp, tonumber(opts.bezierInPercent)) end)
	end
	if opts.bezierOutAngle ~= nil and interp.SetBezierOutAngle then
		pcall(function() interp:SetBezierOutAngle(bezComp, tonumber(opts.bezierOutAngle)) end)
	end
	if opts.bezierOutPercent ~= nil and interp.SetBezierOutPercentage then
		pcall(function() interp:SetBezierOutPercentage(bezComp, tonumber(opts.bezierOutPercent)) end)
	end
	channel:SetKeyInterpByID(keyId, interp)
end

function helpers.pxToDoc(moho, px)
	local n = tonumber(px) or 0
	if moho and moho.PixelToDoc then
		local ok, v = pcall(function() return moho:PixelToDoc(n) end)
		if ok and type(v) == "number" then
			return v
		end
	end
	local h = (moho and moho.document and moho.document.Height and moho.document:Height()) or 1
	return n / math.max(1, h)
end

function helpers.docToPx(moho, docVal)
	local n = tonumber(docVal) or 0
	if moho and moho.DocToPixel then
		local ok, v = pcall(function() return moho:DocToPixel(n) end)
		if ok and type(v) == "number" then
			return v
		end
	end
	local h = (moho and moho.document and moho.document.Height and moho.document:Height()) or 1
	return n * math.max(1, h)
end

function helpers.serializeColor(c)
	if not c then
		return nil
	end
	if c.AsColorStruct then
		local ok, cs = pcall(function() return c:AsColorStruct() end)
		if ok and cs then
			c = cs
		end
	end
	if c.r == nil then
		return nil
	end
	return { r = c.r, g = c.g, b = c.b, a = c.a }
end

function helpers.copyAnimChannel(srcCh, dstCh)
	if not srcCh or not dstCh then
		return false
	end
	if not (srcCh.CountKeys and srcCh.GetKeyWhen and srcCh.GetValue and dstCh.SetValue) then
		return false
	end
	local count = srcCh:CountKeys()
	local interp = MOHO and MOHO.InterpSetting and MOHO.InterpSetting:new_local() or nil
	for i = 0, count - 1 do
		local when = srcCh:GetKeyWhen(i)
		local val = srcCh:GetValue(when)
		pcall(function() dstCh:SetValue(when, val) end)
		if interp and srcCh.GetKeyInterpByID and dstCh.SetKeyInterpByID then
			local okGet = pcall(function() srcCh:GetKeyInterpByID(i, interp) end)
			if okGet then
				local dstId = dstCh.GetClosestKeyID and dstCh:GetClosestKeyID(when) or -1
				if dstId >= 0 and dstCh:GetKeyWhen(dstId) == when then
					pcall(function() dstCh:SetKeyInterpByID(dstId, interp) end)
				end
			end
		end
	end
	return true
end

function helpers.placeLayerInFrontOf(moho, layer, target)
	if not moho or not layer or not target or layer == target then
		return
	end
	moho:PlaceLayerBehindAnother(layer, target)
	moho:PlaceLayerBehindAnother(target, layer)
end

function helpers.prepUndo(moho, layer, multi)
	if helpers.batchDepth > 0 or not moho.document then
		return
	end
	if multi then
		moho.document:PrepMultiUndo(true)
	else
		moho.document:PrepUndo(layer or moho.layer, true)
	end
	moho.document:SetDirty()
end

function helpers.updateUI(moho)
	if helpers.batchDepth > 0 then
		return
	end
	if moho and moho.UpdateUI then
		moho:UpdateUI()
	end
end

return helpers
