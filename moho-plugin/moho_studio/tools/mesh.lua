-- Live vector authoring, shading, topology, Smart Warp (Triangulated & Quad), Curver, Curve Profile, and Liquid Shapes tools.
-- Signatures verified via Moho 14.4 bundled scripts (lm_select_shape.lua, lm_line_width.lua, lm_colorpoints.lua,
-- lm_hide_edge.lua, lm_splitcurve.lua, lm_curve_profile.lua, lm_curve_exposure.lua, lm_shape.lua, ss_svg_import14.lua).

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")
local delaunay = require("moho_studio.delaunay")
local styles = require("moho_studio.tools.styles")

local meshTools = {}

local CIRCLE_CURV_MAGIC = 0.391379

local function resolveShape(mesh, sidParam, snameParam)
	if sidParam ~= nil then
		local idx = math.floor(tonumber(sidParam))
		if idx < 0 or idx >= mesh:CountShapes() then
			return nil, -1, "shapeId out of range: " .. tostring(idx)
		end
		return mesh:Shape(idx), idx, nil
	end
	if snameParam ~= nil then
		local s = mesh:ShapeByName(tostring(snameParam))
		if not s then
			return nil, -1, "Shape not found: " .. tostring(snameParam)
		end
		return s, mesh:ShapeID(s), nil
	end
	return nil, -1, "shapeId or shapeName is required"
end

local function readCompressibleCurver(vl)
	if not vl then
		return nil, false
	end
	local fields = { "fSquashableCurveDeformer", "fCompressibleCurver", "fCompressible" }
	for i = 1, #fields do
		local val = styles.safeField(vl, fields[i])
		if type(val) == "boolean" then
			return val, true
		end
	end
	local getters = { "IsCompressibleCurver", "CompressibleCurver", "IsCompressible", "GetCompressible" }
	for i = 1, #getters do
		local fn = styles.safeField(vl, getters[i])
		if type(fn) == "function" then
			local ok, val = pcall(function() return fn(vl) end)
			if ok and type(val) == "boolean" then
				return val, true
			end
		end
	end
	return nil, false
end

local function writeCompressibleCurver(vl, enabled)
	if not vl then
		return false, "Invalid VectorLayer"
	end
	local val = (enabled == true)
	local fields = { "fSquashableCurveDeformer", "fCompressibleCurver", "fCompressible" }
	for i = 1, #fields do
		local fname = fields[i]
		if styles.safeField(vl, fname) ~= nil then
			local ok = pcall(function() vl[fname] = val end)
			if ok then
				return true, nil
			end
		end
	end
	local setters = { "SetCompressibleCurver", "SetCompressible", "SetCurverCompressible", "SetCurverStretchy" }
	for i = 1, #setters do
		local fn = styles.safeField(vl, setters[i])
		if type(fn) == "function" then
			local ok = pcall(function() fn(vl, val) end)
			if ok then
				return true, nil
			end
		end
	end
	return false, "compressible Curver property not exposed in this Moho Lua build; verify MeshLayer via moho_apiInspect in live Moho 14.4"
end

local function getShapePointsAndCentroid(mesh, shape, frame)
	local ptIds = {}
	local totalPts = mesh:CountPoints()
	if shape.CountPoints and shape.GetPoint then
		local count = shape:CountPoints()
		for k = 0, count - 1 do
			local pid = shape:GetPoint(k)
			if pid ~= nil and pid >= 0 and pid < totalPts then
				ptIds[#ptIds + 1] = pid
			end
		end
	elseif shape.ContainsPoint then
		for pi = 0, totalPts - 1 do
			if shape:ContainsPoint(pi) then
				ptIds[#ptIds + 1] = pi
			end
		end
	end
	local centroid = nil
	if #ptIds > 0 then
		local sx, sy = 0, 0
		for i = 1, #ptIds do
			local pos = mesh:Point(ptIds[i]).fAnimPos:GetValue(frame)
			sx = sx + pos.x
			sy = sy + pos.y
		end
		centroid = { x = sx / #ptIds, y = sy / #ptIds }
	end
	return ptIds, centroid
end

local function serializeShapeSlot(doc, shape, ptrField, nameField)
	local st = styles.ensureMStyle(styles.safeField(shape, ptrField))
	local key = helpers.readLmString(styles.safeField(shape, nameField))
	if not st and key ~= "" and doc then
		st = styles.resolveDocStyle(doc, key)
	end
	if not st and key == "" then
		return nil
	end
	local sName = st and styles.readStyleName(st) or ""
	local sUuid = st and helpers.readLmString(styles.safeField(st, "fUUID")) or key
	return {
		name = sName,
		uuid = sUuid ~= "" and sUuid or key,
	}
end

local function serializeShape(moho, mesh, shape, sid, frame)
	local docH = moho.document and math.max(1, moho.document:Height()) or 1
	local mySt = shape.fMyStyle
	local lw = mySt and (styles.safeField(mySt, "fLineWidth") or 0) or 0
	local caps = mySt and (styles.safeField(mySt, "fLineCaps") or 0) or 0
	local ptIds, centroid = getShapePointsAndCentroid(mesh, shape, frame)
	local inCluster = shape.IsInCluster and (shape:IsInCluster() == true) or false

	local eo = shape.fEffectOffset and shape.fEffectOffset:GetValue(frame) or nil
	local item = {
		id = sid,
		name = shape:Name(),
		hasFill = shape.fHasFill == true,
		hasOutline = shape.fHasOutline == true,
		fillColor = mySt and styles.safeAnimColor(styles.safeField(mySt, "fFillCol"), frame) or nil,
		strokeColor = mySt and styles.safeAnimColor(styles.safeField(mySt, "fLineCol"), frame) or nil,
		lineWidth = lw,
		lineWidthPx = lw * docH,
		lineCaps = caps,
		roundCaps = (caps == 1),
		softEdgePx = mySt and styles.readSoftEdgePx(moho, mySt) or nil,
		effectOffset = eo and { x = eo.x, y = eo.y } or nil,
		effectRotationDeg = shape.fEffectRotation and math.deg(shape.fEffectRotation:GetValue(frame)) or nil,
		effectScale = shape.fEffectScale and shape.fEffectScale:GetValue(frame) or nil,
		style1 = serializeShapeSlot(moho.document, shape, "fInheritedStyle", "fInheritedStyleName"),
		style2 = serializeShapeSlot(moho.document, shape, "fInheritedStyle2", "fInheritedStyleName2"),
		brush = mySt and styles.serializeBrush(mySt) or nil,
		pointIds = json.array(ptIds),
		centroid = centroid,
		comboMode = shape.fComboMode ~= nil and helpers.comboModeName(shape.fComboMode) or "normal",
		comboBlend = shape.fComboBlend and shape.fComboBlend:GetValue(frame) or 0,
		inCluster = inCluster,
	}

	if inCluster and shape.BottomOfCluster and shape.TopOfCluster and shape.NextInCluster then
		local bot = shape:BottomOfCluster()
		local top = shape:TopOfCluster()
		item.bottomShapeId = bot and mesh:ShapeID(bot) or nil
		item.topShapeId = top and mesh:ShapeID(top) or nil
		local members = {}
		local seen = {}
		local cur = bot
		local maxSteps = mesh:CountShapes() + 2
		local steps = 0
		while cur and steps < maxSteps do
			local cid = mesh:ShapeID(cur)
			if cid < 0 or seen[cid] then
				break
			end
			seen[cid] = true
			members[#members + 1] = cid
			cur = cur:NextInCluster()
			steps = steps + 1
		end
		item.clusterMembers = json.array(members)
	end

	return item
end

local function readPointCurvature(pt, frame)
	if not pt or not pt.CountCurves or not pt.Curve or pt:CountCurves() <= 0 then
		return nil
	end
	local okC, curve, ptPos = pcall(function() return pt:Curve(0, -1) end)
	if not okC or not curve or ptPos == nil or ptPos < 0 then
		return nil
	end
	if curve.GetCurvature then
		local okV, cv = pcall(function() return curve:GetCurvature(ptPos, frame) end)
		if okV and type(cv) == "number" then
			return cv
		end
	end
	if curve.Curvature then
		local okCh, ch = pcall(function() return curve:Curvature(ptPos) end)
		if okCh and ch and ch.GetValue then
			local okG, cv = pcall(function() return ch:GetValue(frame) end)
			if okG and type(cv) == "number" then
				return cv
			end
		end
	end
	return nil
end

local function makeOvalPoints(cx, cy, rx, ry)
	return {
		{ x = cx, y = cy - ry },
		{ x = cx + rx, y = cy },
		{ x = cx, y = cy + ry },
		{ x = cx - rx, y = cy },
	}
end

local function makeRectPoints(cx, cy, hw, hh)
	return {
		{ x = cx - hw, y = cy - hh },
		{ x = cx + hw, y = cy - hh },
		{ x = cx + hw, y = cy + hh },
		{ x = cx - hw, y = cy + hh },
	}
end

local function createCurveFromPoints(mesh, pts, closed, frame)
	local oldCount = mesh:CountPoints()
	local v = LM.Vector2:new_local()
	for i = 1, #pts do
		v:Set(tonumber(pts[i].x) or 0, tonumber(pts[i].y) or 0)
		if i == 1 then
			mesh:AddLonePoint(v, frame)
		else
			mesh:AppendPoint(v, frame)
		end
	end
	if closed then
		v:Set(tonumber(pts[1].x) or 0, tonumber(pts[1].y) or 0)
		mesh:AppendPoint(v, frame)
		mesh:WeldPoints(oldCount + #pts, oldCount, frame)
	end
	return oldCount, #pts
end

local function applyPointSpecs(mesh, startIdx, count, pts, peaked, defaultWidth, frame)
	local ids = {}
	for i = 0, count - 1 do
		local pid = startIdx + i
		local pt = mesh:Point(pid)
		if pt then
			local pSpec = pts and pts[i + 1] or nil
			if pSpec and pSpec.curvature ~= nil then
				pt:SetCurvature(tonumber(pSpec.curvature), frame)
			elseif peaked then
				pt:SetCurvature(MOHO.PEAKED, frame)
			end
			if pSpec and pSpec.parentBone ~= nil then
				pt.fParent = math.floor(tonumber(pSpec.parentBone))
			end
			local wVal = (pSpec and pSpec.width ~= nil) and tonumber(pSpec.width) or defaultWidth
			if wVal ~= nil and pt.fWidth then
				pt.fWidth:SetValue(frame, wVal)
			end
			if pSpec and pSpec.opacity ~= nil and pt.fOpacity then
				pt.fOpacity:SetValue(frame, math.max(0.0, math.min(1.0, tonumber(pSpec.opacity))))
			end
			if pSpec and pSpec.colorDrift ~= nil and pt.fColorDrift then
				pt.fColorDrift:SetValue(frame, math.max(0.0, math.min(1.0, tonumber(pSpec.colorDrift))))
			end
			ids[#ids + 1] = pid
		end
	end
	return ids
end

local function applyShapeEffectsAndSlots(moho, shape, params, frame, interpArgs)
	local warnings = styles.applyStyleProps(moho, shape.fMyStyle, params, frame, interpArgs)
	local iName = interpArgs and interpArgs.name or nil
	local iCycle = interpArgs and interpArgs.cycle or nil
	local iV1 = interpArgs and interpArgs.v1 or nil
	local iV2 = interpArgs and interpArgs.v2 or nil
	local iInterval = interpArgs and interpArgs.interval or nil
	local iOpts = interpArgs and interpArgs.opts or nil

	if type(params.effectOffset) == "table" and shape.fEffectOffset then
		local ev = LM.Vector2:new_local()
		ev:Set(tonumber(params.effectOffset.x) or 0, tonumber(params.effectOffset.y) or 0)
		shape.fEffectOffset:SetValue(frame, ev)
		helpers.applyKeyInterp(shape.fEffectOffset, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.effectRotationDeg ~= nil and shape.fEffectRotation then
		shape.fEffectRotation:SetValue(frame, math.rad(tonumber(params.effectRotationDeg) or 0))
		helpers.applyKeyInterp(shape.fEffectRotation, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.effectScale ~= nil and shape.fEffectScale then
		shape.fEffectScale:SetValue(frame, tonumber(params.effectScale) or 1)
		helpers.applyKeyInterp(shape.fEffectScale, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.style1 ~= nil then
		local okS1, errS1 = styles.bindShapeStyle(moho.document, shape, 1, params.style1)
		if not okS1 and errS1 then
			warnings[#warnings + 1] = errS1
		end
	end
	if params.style2 ~= nil then
		local okS2, errS2 = styles.bindShapeStyle(moho.document, shape, 2, params.style2)
		if not okS2 and errS2 then
			warnings[#warnings + 1] = errS2
		end
	end
	return warnings
end

function meshTools.getData(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end
	local mesh = vl:Mesh()
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local limit = math.floor(tonumber(params.maxPoints) or 500)
	local includePointColors = (params.includePointColors == true)
	local includeHandles = (params.includeHandles == true)

	local mat = LM.Matrix:new_local()
	local hasMat = false
	if layer.GetFullTransform then
		hasMat = pcall(function() layer:GetFullTransform(frame, mat, moho.document) end)
	end

	local pts = {}
	local wp = LM.Vector2:new_local()
	local totalPts = mesh:CountPoints()
	for i = 0, math.min(totalPts, limit) - 1 do
		local p = mesh:Point(i)
		local pos = p.fAnimPos:GetValue(frame)
		wp:Set(pos.x, pos.y)
		if hasMat then
			pcall(function() mat:Transform(wp) end)
		end
		local ptEntry = {
			id = i,
			x = pos.x,
			y = pos.y,
			worldPos = { x = wp.x, y = wp.y },
			parentBone = p.fParent,
			width = p.fWidth and p.fWidth:GetValue(frame) or -1,
			opacity = p.fOpacity and p.fOpacity:GetValue(frame) or 1,
			colorDrift = p.fColorDrift and p.fColorDrift:GetValue(frame) or 0,
			curvature = readPointCurvature(p, frame),
			colored = (p.fColored == true),
		}
		if ptEntry.colored or includePointColors then
			ptEntry.color = p.fColor and helpers.serializeColor(p.fColor:GetValue(frame)) or nil
			ptEntry.colorStrength = p.fColorStrength and p.fColorStrength:GetValue(frame) or 0
		end
		if includeHandles and p.CountCurves and p.Curve and p:CountCurves() > 0 then
			local okC, curve, ptPos = pcall(function() return p:Curve(0, -1) end)
			if okC and curve and ptPos ~= nil and ptPos >= 0 and curve.GetControlHandle then
				local okIn, hIn = pcall(function() return curve:GetControlHandle(ptPos, frame, true) end)
				local okOut, hOut = pcall(function() return curve:GetControlHandle(ptPos, frame, false) end)
				if okIn and hIn then ptEntry.inHandle = { x = hIn.x, y = hIn.y } end
				if okOut and hOut then ptEntry.outHandle = { x = hOut.x, y = hOut.y } end
			end
		end
		pts[#pts + 1] = ptEntry
	end

	local curves = {}
	for ci = 0, mesh:CountCurves() - 1 do
		local c = mesh:Curve(ci)
		local cpCount = c:CountPoints()
		local cPtIds = {}
		for pi = 0, cpCount - 1 do
			cPtIds[#cPtIds + 1] = mesh:PointID(c:Point(pi))
		end
		local isClosed = (c.fClosed == true)
		local segCount = c.CountSegments and c:CountSegments() or (isClosed and cpCount or math.max(0, cpCount - 1))
		local segsOn = {}
		for si = 0, segCount - 1 do
			if c.IsSegmentOn then
				segsOn[#segsOn + 1] = (c:IsSegmentOn(si) == true)
			else
				segsOn[#segsOn + 1] = true
			end
		end
		curves[#curves + 1] = {
			id = ci,
			closed = isClosed,
			pointCount = cpCount,
			pointIds = json.array(cPtIds),
			segmentsOn = json.array(segsOn),
			startPercent = c.fStartPercent and c.fStartPercent:GetValue(frame) or 0,
			endPercent = c.fEndPercent and c.fEndPercent:GetValue(frame) or 1,
			profileRepeat = styles.safeField(c, "fProfileRepeat") or 1,
			profileOffset = c.fProfileOffset and c.fProfileOffset:GetValue(frame) or 0,
		}
	end

	local shapes = {}
	for i = 0, mesh:CountShapes() - 1 do
		shapes[#shapes + 1] = serializeShape(moho, mesh, mesh:Shape(i), i, frame)
	end

	local out = {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		isWarpLayer = vl.IsWarpLayer and vl:IsWarpLayer() or false,
		isCurver = vl.IsCurver and vl:IsCurver() or false,
		continuousTriangulation = vl.ContinuousTriangulation and vl:ContinuousTriangulation() or false,
		pointCount = totalPts,
		curveCount = mesh:CountCurves(),
		shapeCount = mesh:CountShapes(),
		points = json.array(pts),
		curves = json.array(curves),
		shapes = json.array(shapes),
	}
	local compVal, compOk = readCompressibleCurver(vl)
	if compOk then
		out.compressibleCurver = compVal
	end
	return out
end

--- Draw a vector shape (points, primitive oval/rect, or existing pointIds + holes) with full style/effect support.
function meshTools.createShape(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end

	local mesh = vl:Mesh()
	local frame = math.floor(tonumber(params.frame) or 0)
	local primitive = params.primitive and string.lower(tostring(params.primitive)) or nil
	local peaked = (params.peaked == true)

	local createdPointIds = {}
	local selectedExisting = false
	local closed = false

	moho:SetSelLayer(layer)
	helpers.prepUndo(moho, layer, false)
	mesh:SelectNone()

	if type(params.pointIds) == "table" and #params.pointIds >= 2 then
		selectedExisting = true
		local totalPts = mesh:CountPoints()
		local countSel = 0
		for i = 1, #params.pointIds do
			local pid = math.floor(tonumber(params.pointIds[i]))
			if pid >= 0 and pid < totalPts then
				local pt = mesh:Point(pid)
				if pt then
					pt.fSelected = true
					createdPointIds[#createdPointIds + 1] = pid
					countSel = countSel + 1
					if not closed and pt.CountCurves and pt:CountCurves() > 0 then
						local okC, c = pcall(function() return pt:Curve(0, -1) end)
						if okC and c and c.fClosed then
							closed = true
						end
					end
				end
			end
		end
		if countSel < 2 then
			return nil, "pointIds must contain at least 2 valid point indices"
		end
		if params.closed ~= nil then
			closed = (params.closed == true)
		end
	elseif primitive == "oval" or primitive == "rect" then
		local cx = tonumber(params.cx) or 0
		local cy = tonumber(params.cy) or 0
		local pts
		if primitive == "oval" then
			local rx = tonumber(params.rx) or ((tonumber(params.width) or 0.4) * 0.5)
			local ry = tonumber(params.ry) or ((tonumber(params.height) or 0.4) * 0.5)
			pts = makeOvalPoints(cx, cy, rx, ry)
		else
			local hw = (tonumber(params.width) or 0.4) * 0.5
			local hh = (tonumber(params.height) or 0.4) * 0.5
			pts = makeRectPoints(cx, cy, hw, hh)
		end
		closed = true
		local startIdx, countAdded = createCurveFromPoints(mesh, pts, true, frame)
		createdPointIds = applyPointSpecs(mesh, startIdx, countAdded, nil, primitive == "rect" or peaked, nil, frame)
		if primitive == "oval" and (not peaked) then
			local rx = math.max(1e-6, math.abs(tonumber(params.rx) or ((tonumber(params.width) or 0.4) * 0.5)))
			local ry = math.max(1e-6, math.abs(tonumber(params.ry) or ((tonumber(params.height) or 0.4) * 0.5)))
			local fy = CIRCLE_CURV_MAGIC
			local fx = CIRCLE_CURV_MAGIC
			if math.abs(rx - ry) > 1e-6 then
				local maxC = 0.66667 / CIRCLE_CURV_MAGIC
				fy = math.min(rx / ry, maxC) * CIRCLE_CURV_MAGIC
				fx = math.min(ry / rx, maxC) * CIRCLE_CURV_MAGIC
			end
			if params.curvature ~= nil then
				fx = tonumber(params.curvature)
				fy = tonumber(params.curvature)
			end
			mesh:Point(startIdx):SetCurvature(fy, frame)
			mesh:Point(startIdx + 1):SetCurvature(fx, frame)
			mesh:Point(startIdx + 2):SetCurvature(fy, frame)
			mesh:Point(startIdx + 3):SetCurvature(fx, frame)
		elseif params.curvature ~= nil then
			local cv = tonumber(params.curvature)
			for i = 0, countAdded - 1 do
				mesh:Point(startIdx + i):SetCurvature(cv, frame)
			end
		end
	elseif type(params.points) == "table" and #params.points >= 2 then
		closed = (params.closed ~= false) and (#params.points >= 3)
		local startIdx, countAdded = createCurveFromPoints(mesh, params.points, closed, frame)
		createdPointIds = applyPointSpecs(mesh, startIdx, countAdded, params.points, peaked, nil, frame)
	else
		return nil, "Provide points (>=2), pointIds (>=2), or primitive ('oval' | 'rect')"
	end

	if type(params.holes) == "table" then
		for hi = 1, #params.holes do
			local hpts = params.holes[hi]
			if type(hpts) == "table" and #hpts >= 3 then
				local hStart, hCount = createCurveFromPoints(mesh, hpts, true, frame)
				local hIds = applyPointSpecs(mesh, hStart, hCount, hpts, peaked, nil, frame)
				for j = 1, #hIds do
					createdPointIds[#createdPointIds + 1] = hIds[j]
				end
			end
		end
	end

	if not selectedExisting then
		mesh:SelectNone()
		for i = 1, #createdPointIds do
			local pt = mesh:Point(createdPointIds[i])
			if pt then
				pt.fSelected = true
			end
		end
	end

	local hasFill
	if params.hasFill ~= nil then
		hasFill = (params.hasFill == true)
	else
		hasFill = closed
	end
	local hasOutline
	if params.hasOutline ~= nil then
		hasOutline = (params.hasOutline == true)
	else
		hasOutline = (not closed)
	end

	local behind = (params.behindNeighborStrokes == true)
	local shapeId = moho:CreateShape(hasFill, behind, frame)
	if shapeId < 0 and closed then
		shapeId = moho:CreateShape(true, behind, frame)
	end

	local docH = moho.document and math.max(1, moho.document:Height()) or 1
	local outLineWidth = 0
	local warnings = {}
	local serializedShape = nil
	if shapeId >= 0 then
		local shape = mesh:Shape(shapeId)
		if shape then
			if params.makePlain == true and shape.MakePlain then
				shape:MakePlain()
			end
			if params.name then
				shape:SetName(tostring(params.name))
			end
			shape.fHasFill = hasFill
			shape.fHasOutline = hasOutline
			local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
			warnings = applyShapeEffectsAndSlots(moho, shape, params, frame, {
				name = iName,
				cycle = iCycle,
				v1 = iV1,
				v2 = iV2,
				interval = iInterval,
				opts = iOpts,
			})
			outLineWidth = shape.fMyStyle and shape.fMyStyle.fLineWidth or 0
			serializedShape = serializeShape(moho, mesh, shape, shapeId, frame)
		end
	end

	layer:UpdateCurFrame()
	helpers.updateUI(moho)
	return {
		created = shapeId >= 0 or not selectedExisting,
		layerId = id,
		layerName = layer:Name(),
		shapeId = shapeId,
		hasFill = hasFill,
		hasOutline = hasOutline,
		lineWidth = outLineWidth,
		lineWidthPx = outLineWidth * docH,
		createdPointIds = json.array(createdPointIds),
		shape = serializedShape,
		pointCount = mesh:CountPoints(),
		shapeCount = mesh:CountShapes(),
		warnings = json.array(warnings),
	}
end

--- Edit, re-style, reorder, keyframe, or delete an existing vector shape.
function meshTools.editShape(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end
	local mesh = vl:Mesh()
	local shape, sid, serr = resolveShape(mesh, params.shapeId, params.shapeName)
	if not shape then
		return nil, serr
	end

	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	helpers.prepUndo(moho, layer, false)

	if params.delete == true then
		mesh:DeleteShape(sid)
		layer:UpdateCurFrame()
		helpers.updateUI(moho)
		return {
			deleted = true,
			layerId = id,
			deletedShapeId = sid,
			shapeCount = mesh:CountShapes(),
		}
	end

	if params.makePlain == true and shape.MakePlain then
		shape:MakePlain()
	end
	if params.copyStyleFromShapeId ~= nil or params.copyStyleFromShapeName ~= nil then
		local srcShape, _, srcErr = resolveShape(mesh, params.copyStyleFromShapeId, params.copyStyleFromShapeName)
		if not srcShape then
			return nil, srcErr
		end
		if shape.CopyStyleProperties then
			shape:CopyStyleProperties(srcShape, params.skipFill == true, params.skipLine == true)
		end
	end

	if params.name ~= nil then
		shape:SetName(tostring(params.name))
	end
	if params.hasFill ~= nil then
		shape.fHasFill = (params.hasFill == true)
	end
	if params.hasOutline ~= nil then
		shape.fHasOutline = (params.hasOutline == true)
	end

	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
	local warnings = applyShapeEffectsAndSlots(moho, shape, params, frame, {
		name = iName,
		cycle = iCycle,
		v1 = iV1,
		v2 = iV2,
		interval = iInterval,
		opts = iOpts,
	})

	local curId = mesh:ShapeID(shape)
	if params.raise == true or params.toTop == true then
		mesh:RaiseShape(curId, params.toTop == true)
	elseif params.lower == true or params.toBottom == true then
		mesh:LowerShape(curId, params.toBottom == true)
	elseif params.placeAboveShapeId ~= nil then
		mesh:PlaceShapeAbove(curId, math.floor(tonumber(params.placeAboveShapeId)))
	elseif params.placeBehindShapeId ~= nil then
		mesh:PlaceShapeBehind(curId, math.floor(tonumber(params.placeBehindShapeId)))
	end

	layer:UpdateCurFrame()
	helpers.updateUI(moho)
	local finalId = mesh:ShapeID(shape)
	return {
		updated = true,
		layerId = id,
		frame = frame,
		shape = serializeShape(moho, mesh, shape, finalId, frame),
		warnings = json.array(warnings),
	}
end

local function computeHandleVec(pt, frame, spec)
	local base = pt.fAnimPos:GetValue(frame)
	local hx = (spec.x ~= nil) and tonumber(spec.x) or (base.x + (tonumber(spec.dx) or 0))
	local hy = (spec.y ~= nil) and tonumber(spec.y) or (base.y + (tonumber(spec.dy) or 0))
	local hv = LM.Vector2:new_local()
	hv:Set(hx, hy)
	return hv
end

--- Move/animate existing vector or Smart Warp mesh points, adjust width/opacity/colorDrift/curvature, Point Colors, or Bezier handles.
function meshTools.editPoints(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end
	local edits = params.edits
	if type(edits) ~= "table" or #edits == 0 then
		return nil, "edits array of { pointId, x?, y?, dx?, dy?, width?, opacity?, colorDrift?, curvature?, colored?, color?, colorStrength?, inHandle?, outHandle?, parentBone? } is required"
	end

	local mesh = vl:Mesh()
	local total = mesh:CountPoints()
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	helpers.prepUndo(moho, layer, false)

	local updated = 0
	local v = LM.Vector2:new_local()
	for i = 1, #edits do
		local e = edits[i]
		local pid = e and e.pointId ~= nil and math.floor(tonumber(e.pointId)) or -1
		if pid >= 0 and pid < total then
			local pt = mesh:Point(pid)
			local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(e, params)

			if e.x ~= nil or e.y ~= nil or e.dx ~= nil or e.dy ~= nil then
				local cur = pt.fAnimPos:GetValue(frame)
				local nx = (e.x ~= nil) and tonumber(e.x) or (cur.x + (tonumber(e.dx) or 0))
				local ny = (e.y ~= nil) and tonumber(e.y) or (cur.y + (tonumber(e.dy) or 0))
				v:Set(nx, ny)
				pt.fAnimPos:SetValue(frame, v)
				helpers.applyKeyInterp(pt.fAnimPos, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end

			if e.resetWidth == true and pt.fWidth then
				pt.fWidth:SetValue(frame, -1)
				helpers.applyKeyInterp(pt.fWidth, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			elseif e.width ~= nil and pt.fWidth then
				pt.fWidth:SetValue(frame, tonumber(e.width) or 0)
				helpers.applyKeyInterp(pt.fWidth, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end

			if e.opacity ~= nil and pt.fOpacity then
				pt.fOpacity:SetValue(frame, math.max(0.0, math.min(1.0, tonumber(e.opacity) or 1.0)))
				helpers.applyKeyInterp(pt.fOpacity, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end

			if e.colorDrift ~= nil and pt.fColorDrift then
				pt.fColorDrift:SetValue(frame, math.max(0.0, math.min(1.0, tonumber(e.colorDrift) or 0.0)))
				helpers.applyKeyInterp(pt.fColorDrift, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end

			if e.resetCurvature == true then
				if pt.ResetControlHandles then
					pcall(function() pt:ResetControlHandles(frame) end)
				end
				if e.curvature == nil then
					pt:SetCurvature(MOHO.SMOOTH or 0.3, frame)
				end
			end

			if e.curvature ~= nil then
				pt:SetCurvature(tonumber(e.curvature), frame)
				if pt.CountCurves and pt.Curve then
					for cj = 0, pt:CountCurves() - 1 do
						local okC, curve, ptPos = pcall(function() return pt:Curve(cj, -1) end)
						if okC and curve and ptPos ~= nil and ptPos >= 0 and curve.Curvature then
							local okCh, cCh = pcall(function() return curve:Curvature(ptPos) end)
							if okCh and cCh then
								helpers.applyKeyInterp(cCh, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
							end
						end
					end
				end
			end

			if e.clearColor == true or e.colored == false then
				pcall(function() pt.fColored = false end)
			elseif e.colored == true or e.color ~= nil or e.colorStrength ~= nil then
				pcall(function() pt.fColored = true end)
				if e.color ~= nil and pt.fColor then
					pt.fColor:SetValue(frame, helpers.toRgbStruct(e.color))
					helpers.applyKeyInterp(pt.fColor, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
				end
				if e.colorStrength ~= nil and pt.fColorStrength then
					pt.fColorStrength:SetValue(frame, math.max(0.0, tonumber(e.colorStrength) or 0))
					helpers.applyKeyInterp(pt.fColorStrength, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
				end
			end

			if (type(e.inHandle) == "table" or type(e.outHandle) == "table") and pt.CountCurves and pt.Curve and pt:CountCurves() > 0 then
				local cj = math.floor(tonumber(e.curveIndex) or 0)
				if cj >= 0 and cj < pt:CountCurves() then
					local okC, curve, ptPos = pcall(function() return pt:Curve(cj, -1) end)
					if okC and curve and ptPos ~= nil and ptPos >= 0 and curve.SetControlHandle then
						local sync = (e.syncHandles == true)
						if type(e.inHandle) == "table" then
							local hv = computeHandleVec(pt, frame, e.inHandle)
							curve:SetControlHandle(ptPos, hv, frame, true, sync)
						end
						if type(e.outHandle) == "table" then
							local hv = computeHandleVec(pt, frame, e.outHandle)
							curve:SetControlHandle(ptPos, hv, frame, false, sync)
						end
					end
				end
			end

			if e.parentBone ~= nil then
				pt.fParent = math.floor(tonumber(e.parentBone))
			end
			updated = updated + 1
		end
	end

	layer:UpdateCurFrame()
	if vl.IsWarpLayer and vl:IsWarpLayer() and vl.UpdateWarpLayer then
		vl:UpdateWarpLayer()
	end
	helpers.updateUI(moho)
	return {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		updatedPoints = updated,
	}
end

--- Vector topology operations: split, insert, weld, connect, hide edge, delete, mirror, merge shapes, triangulate, stroke exposure.
function meshTools.editTopology(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end

	local mesh = vl:Mesh()
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local op = string.lower(tostring(params.operation or ""))

	moho:SetSelLayer(layer)
	helpers.prepUndo(moho, layer, false)

	local function selectPointIdsOrCurveOrAll()
		mesh:SelectNone()
		if type(params.pointIds) == "table" and #params.pointIds > 0 then
			local total = mesh:CountPoints()
			local n = 0
			for i = 1, #params.pointIds do
				local pid = math.floor(tonumber(params.pointIds[i]))
				if pid >= 0 and pid < total then
					mesh:Point(pid).fSelected = true
					n = n + 1
				end
			end
			return n
		elseif params.curveId ~= nil then
			local cid = math.floor(tonumber(params.curveId))
			if cid >= 0 and cid < mesh:CountCurves() then
				local c = mesh:Curve(cid)
				for pi = 0, c:CountPoints() - 1 do
					c:Point(pi).fSelected = true
				end
				return c:CountPoints()
			end
			return 0
		end
		mesh:SelectAll()
		return mesh:CountPoints()
	end

	local result = {
		layerId = id,
		layerName = layer:Name(),
		operation = op,
		frame = frame,
	}

	if op == "split_segments" then
		local countBefore = mesh:CountPoints()
		selectPointIdsOrCurveOrAll()
		local splitCount = math.max(1, math.floor(tonumber(params.splitCount) or 1))
		MOHO:SplitSelectedSegments(mesh, splitCount, frame)
		result.splitCount = splitCount
		result.addedPoints = mesh:CountPoints() - countBefore
	elseif op == "insert_point" then
		if params.x == nil or params.y == nil or params.curveId == nil or params.segmentId == nil then
			return nil, "insert_point requires x, y, curveId, segmentId"
		end
		local cid = math.floor(tonumber(params.curveId))
		if cid < 0 or cid >= mesh:CountCurves() then
			return nil, "curveId out of range: " .. tostring(cid)
		end
		local sid = math.floor(tonumber(params.segmentId))
		local countBefore = mesh:CountPoints()
		local v = LM.Vector2:new_local()
		v:Set(tonumber(params.x) or 0, tonumber(params.y) or 0)
		mesh:AddPoint(v, cid, sid, frame, params.correctBezierHandles ~= false, params.preserveCorners == true)
		result.newPointId = (mesh:CountPoints() > countBefore) and (mesh:CountPoints() - 1) or -1
	elseif op == "weld_points" then
		local pairSpecs = {}
		if type(params.pairs) == "table" and #params.pairs > 0 then
			for i = 1, #params.pairs do
				pairSpecs[#pairSpecs + 1] = params.pairs[i]
			end
		elseif params.movingPointId ~= nil and params.solidPointId ~= nil then
			pairSpecs[1] = { movingPointId = params.movingPointId, solidPointId = params.solidPointId }
		else
			return nil, "weld_points requires movingPointId + solidPointId or pairs[]"
		end

		local total = mesh:CountPoints()
		local ptPairs = {}
		for i = 1, #pairSpecs do
			local sp = pairSpecs[i]
			local mid = math.floor(tonumber(sp.movingPointId))
			local sid = math.floor(tonumber(sp.solidPointId))
			if mid >= 0 and mid < total and sid >= 0 and sid < total and mid ~= sid then
				ptPairs[#ptPairs + 1] = { mPt = mesh:Point(mid), sPt = mesh:Point(sid) }
			end
		end
		local welded = 0
		for i = 1, #ptPairs do
			local curM = mesh:PointID(ptPairs[i].mPt)
			local curS = mesh:PointID(ptPairs[i].sPt)
			if curM >= 0 and curS >= 0 and curM ~= curS then
				if mesh:WeldPoints(curM, curS, frame) then
					welded = welded + 1
				end
			end
		end
		result.weldedCount = welded
	elseif op == "connect_and_create" then
		selectPointIdsOrCurveOrAll()
		local okConn = MOHO:ConnectSelectedCurves(mesh, frame)
		local createdShapeId = -1
		if params.createShape ~= false then
			local hasFill = (params.hasFill ~= false)
			local behind = (params.behindNeighborStrokes == true)
			createdShapeId = moho:CreateShape(hasFill, behind, frame)
			if createdShapeId >= 0 then
				local sh = mesh:Shape(createdShapeId)
				if sh then
					if params.name then sh:SetName(tostring(params.name)) end
					sh.fHasFill = hasFill
					if params.hasOutline ~= nil then sh.fHasOutline = (params.hasOutline == true) end
					styles.applyStyleProps(moho, sh.fMyStyle, params, frame, nil)
				end
			end
		end
		result.connected = (okConn ~= false)
		result.shapeId = createdShapeId
	elseif op == "hide_edge" then
		local targets = {}
		local defaultVis = false
		if params.hidden ~= nil then
			defaultVis = (params.hidden ~= true)
		elseif params.visible ~= nil then
			defaultVis = (params.visible == true)
		end

		if type(params.edges) == "table" and #params.edges > 0 then
			for i = 1, #params.edges do
				local ed = params.edges[i]
				if ed.curveId ~= nil and ed.segmentId ~= nil then
					local vis = defaultVis
					if ed.hidden ~= nil then
						vis = (ed.hidden ~= true)
					elseif ed.visible ~= nil then
						vis = (ed.visible == true)
					end
					targets[#targets + 1] = {
						curveId = math.floor(tonumber(ed.curveId)),
						segmentId = math.floor(tonumber(ed.segmentId)),
						visible = vis,
					}
				end
			end
		elseif params.curveId ~= nil and params.segmentId ~= nil then
			targets[1] = {
				curveId = math.floor(tonumber(params.curveId)),
				segmentId = math.floor(tonumber(params.segmentId)),
				visible = defaultVis,
			}
		elseif params.pointIdA ~= nil and params.pointIdB ~= nil then
			local a = math.floor(tonumber(params.pointIdA))
			local b = math.floor(tonumber(params.pointIdB))
			for ci = 0, mesh:CountCurves() - 1 do
				local c = mesh:Curve(ci)
				local cp = c:CountPoints()
				local maxSeg = (c.fClosed == true) and cp or (cp - 1)
				for si = 0, maxSeg - 1 do
					local p0 = mesh:PointID(c:Point(si))
					local p1 = mesh:PointID(c:Point((si + 1) % cp))
					if (p0 == a and p1 == b) or (p0 == b and p1 == a) then
						targets[#targets + 1] = { curveId = ci, segmentId = si, visible = defaultVis }
					end
				end
			end
		else
			return nil, "hide_edge requires edges[], curveId+segmentId, or pointIdA+pointIdB"
		end

		local modified = 0
		for i = 1, #targets do
			local t = targets[i]
			if t.curveId >= 0 and t.curveId < mesh:CountCurves() then
				local c = mesh:Curve(t.curveId)
				if c and c.SetSegmentOn then
					c:SetSegmentOn(t.segmentId, t.visible)
					modified = modified + 1
				end
			end
		end
		result.updatedEdges = modified
	elseif op == "delete_points" then
		if type(params.pointIds) ~= "table" or #params.pointIds == 0 then
			return nil, "delete_points requires pointIds array"
		end
		local total = mesh:CountPoints()
		local seen = {}
		local ids = {}
		for i = 1, #params.pointIds do
			local pid = math.floor(tonumber(params.pointIds[i]))
			if pid >= 0 and pid < total and not seen[pid] then
				seen[pid] = true
				ids[#ids + 1] = pid
			end
		end
		table.sort(ids, function(a, b) return a > b end)
		local preserveHandles = (params.preserveHandles ~= false)
		for i = 1, #ids do
			mesh:DeletePoint(ids[i], preserveHandles)
		end
		result.deletedCount = #ids
	elseif op == "mirror_points" then
		local axis = string.lower(tostring(params.axis or "x"))
		local axisVal = tonumber((axis == "y") and (params.axisY or params.axisValue) or (params.axisX or params.axisValue)) or 0
		local duplicate = (params.duplicate == true)
		local weldAxis = (params.weldAxis ~= false)
		local weldTol = tonumber(params.weldTolerance) or 0.002

		local function mirrorXY(x, y)
			if axis == "y" then
				return x, 2 * axisVal - y
			end
			return 2 * axisVal - x, y
		end

		local function axisDistance(pos)
			if axis == "y" then
				return math.abs(pos.y - axisVal)
			end
			return math.abs(pos.x - axisVal)
		end

		local selSet = {}
		local total = mesh:CountPoints()
		if type(params.pointIds) == "table" and #params.pointIds > 0 then
			for i = 1, #params.pointIds do
				local pid = math.floor(tonumber(params.pointIds[i]))
				if pid >= 0 and pid < total then
					selSet[mesh:Point(pid)] = true
				end
			end
		else
			for pi = 0, total - 1 do
				selSet[mesh:Point(pi)] = true
			end
		end

		if not duplicate then
			local countMirrored = 0
			local hv = LM.Vector2:new_local()
			local pv = LM.Vector2:new_local()
			for pi = 0, total - 1 do
				local pt = mesh:Point(pi)
				if selSet[pt] then
					local pos = pt.fAnimPos:GetValue(frame)
					local mx, my = mirrorXY(pos.x, pos.y)
					local handles = {}
					if pt.CountCurves and pt.Curve then
						for cj = 0, pt:CountCurves() - 1 do
							local okC, curve, ptPos = pcall(function() return pt:Curve(cj, -1) end)
							if okC and curve and ptPos ~= nil and ptPos >= 0 and curve.GetControlHandle and curve.SetControlHandle then
								local hIn = curve:GetControlHandle(ptPos, frame, true)
								local hOut = curve:GetControlHandle(ptPos, frame, false)
								local ix, iy = mirrorXY(hIn.x, hIn.y)
								local ox, oy = mirrorXY(hOut.x, hOut.y)
								handles[#handles + 1] = { curve = curve, ptPos = ptPos, ix = ix, iy = iy, ox = ox, oy = oy }
							end
						end
					end
					pv:Set(mx, my)
					pt.fAnimPos:SetValue(frame, pv)
					for hi = 1, #handles do
						local hd = handles[hi]
						hv:Set(hd.ix, hd.iy)
						pcall(function() hd.curve:SetControlHandle(hd.ptPos, hv, frame, true, false) end)
						hv:Set(hd.ox, hd.oy)
						pcall(function() hd.curve:SetControlHandle(hd.ptPos, hv, frame, false, false) end)
					end
					countMirrored = countMirrored + 1
				end
			end
			result.mirroredPoints = countMirrored
			result.duplicated = false
		else
			local origCurveCount = mesh:CountCurves()
			local origShapeCount = mesh:CountShapes()
			local srcToDst = {}
			local pendingWelds = {}
			local axisWeldedSrc = {}
			local createdPts = 0
			local clearParent = (params.clearParentBone == true)
			local v = LM.Vector2:new_local()

			for ci = 0, origCurveCount - 1 do
				local c = mesh:Curve(ci)
				local cp = c:CountPoints()
				local runs = {}
				local curRun = {}
				local allSelected = true
				for pi = 0, cp - 1 do
					local sp = c:Point(pi)
					if selSet[sp] then
						curRun[#curRun + 1] = { pt = sp, curv = readPointCurvature(sp, frame) }
					else
						allSelected = false
						if #curRun >= 2 then
							runs[#runs + 1] = curRun
						end
						curRun = {}
					end
				end
				if #curRun >= 2 then
					runs[#runs + 1] = curRun
				end

				for ri = 1, #runs do
					local run = runs[ri]
					local closeCopy = (c.fClosed == true) and allSelected and (#run >= 3)
					local firstDstPt = nil
					for k = 1, #run do
						local sp = run[k].pt
						local pos = sp.fAnimPos:GetValue(frame)
						local mx, my = mirrorXY(pos.x, pos.y)
						v:Set(mx, my)
						if k == 1 then
							mesh:AddLonePoint(v, frame)
						else
							mesh:AppendPoint(v, frame)
						end
						local newId = mesh:CountPoints() - 1
						local dp = mesh:Point(newId)
						if k == 1 then
							firstDstPt = dp
						end
						if run[k].curv ~= nil then
							dp:SetCurvature(run[k].curv, frame)
						end
						if sp.fWidth and dp.fWidth then
							dp.fWidth:SetValue(frame, sp.fWidth:GetValue(frame))
						end
						if not clearParent then
							dp.fParent = sp.fParent
						end
						srcToDst[sp] = dp
						createdPts = createdPts + 1
						if weldAxis and axisDistance(pos) <= weldTol then
							pendingWelds[#pendingWelds + 1] = { movingPt = dp, solidPt = sp }
							axisWeldedSrc[sp] = true
						end
					end
					if closeCopy and firstDstPt then
						local p1Pos = run[1].pt.fAnimPos:GetValue(frame)
						local mx, my = mirrorXY(p1Pos.x, p1Pos.y)
						v:Set(mx, my)
						mesh:AppendPoint(v, frame)
						local closeIdx = mesh:CountPoints() - 1
						local firstIdx = mesh:PointID(firstDstPt)
						if firstIdx >= 0 then
							mesh:WeldPoints(closeIdx, firstIdx, frame)
						end
					end
				end
			end

			local weldedAxisCount = 0
			for wi = 1, #pendingWelds do
				local mId = mesh:PointID(pendingWelds[wi].movingPt)
				local sId = mesh:PointID(pendingWelds[wi].solidPt)
				if mId >= 0 and sId >= 0 and mId ~= sId then
					if mesh:WeldPoints(mId, sId, frame) then
						weldedAxisCount = weldedAxisCount + 1
					end
				end
			end

			local createdShapesCount = 0
			if params.mirrorShapes ~= false then
				for si = 0, origShapeCount - 1 do
					local sh = mesh:Shape(si)
					local shPtIds = getShapePointsAndCentroid(mesh, sh, frame)
					if #shPtIds >= 2 then
						local canMirror = true
						local dstIds = {}
						for k = 1, #shPtIds do
							local sp = mesh:Point(shPtIds[k])
							local mapped = axisWeldedSrc[sp] and sp or srcToDst[sp]
							if not mapped then
								canMirror = false
								break
							end
							local did = mesh:PointID(mapped)
							if did < 0 then
								canMirror = false
								break
							end
							dstIds[#dstIds + 1] = did
						end
						if canMirror then
							mesh:SelectNone()
							for k = 1, #dstIds do
								mesh:Point(dstIds[k]).fSelected = true
							end
							local newSid = moho:CreateShape(sh.fHasFill, false, frame)
							if newSid >= 0 then
								local newSh = mesh:Shape(newSid)
								if newSh then
									if newSh.CopyStyleProperties then
										newSh:CopyStyleProperties(sh, false, false)
									end
									newSh.fHasFill = sh.fHasFill
									newSh.fHasOutline = sh.fHasOutline
									createdShapesCount = createdShapesCount + 1
								end
							end
						end
					end
				end
			end

			result.duplicated = true
			result.createdPoints = createdPts
			result.weldedAxisPoints = weldedAxisCount
			result.createdShapes = createdShapesCount
		end
	elseif op == "merge_shapes" then
		local count = mesh:CountShapes()
		for i = 0, count - 1 do
			mesh:Shape(i).fSelected = false
		end
		local selectedCount = 0
		if type(params.shapeIds) == "table" and #params.shapeIds > 0 then
			for i = 1, #params.shapeIds do
				local sid = math.floor(tonumber(params.shapeIds[i]))
				if sid >= 0 and sid < count then
					mesh:Shape(sid).fSelected = true
					selectedCount = selectedCount + 1
				end
			end
		elseif type(params.shapeNames) == "table" and #params.shapeNames > 0 then
			for i = 1, #params.shapeNames do
				local s = mesh:ShapeByName(tostring(params.shapeNames[i]))
				if s then
					s.fSelected = true
					selectedCount = selectedCount + 1
				end
			end
		else
			for i = 0, count - 1 do
				local s = mesh:Shape(i)
				if s.fHasFill then
					s.fSelected = true
					selectedCount = selectedCount + 1
				end
			end
		end
		if selectedCount == 0 then
			return nil, "merge_shapes found no shapes to merge"
		end

		local doAgain = true
		while doAgain do
			doAgain = false
			for i = 0, mesh:CountShapes() - 1 do
				local sh = mesh:Shape(i)
				if sh.fSelected and sh.fHasFill and sh:IsInCluster() then
					local newShapeID = mesh:BakeCombinedShapes(sh, false)
					if newShapeID >= 0 then
						mesh:Shape(newShapeID).fSelected = true
						doAgain = true
					end
					break
				end
			end
		end

		local baseShape = nil
		local baseShapeID = -1
		for i = 0, mesh:CountShapes() - 1 do
			local sh = mesh:Shape(i)
			if sh.fSelected and sh.fHasFill then
				if baseShape == nil then
					baseShape = sh
					baseShapeID = mesh:ShapeID(sh)
				else
					sh.fComboMode = MOHO.COMBO_ADD
					sh.fComboBlend.value = 0
					mesh:PlaceShapeAbove(mesh:ShapeID(sh), baseShapeID)
				end
			end
		end
		local finalShapeId = baseShapeID
		if baseShape ~= nil and baseShape:IsInCluster() then
			local newShapeID = mesh:BakeCombinedShapes(baseShape, false)
			if newShapeID >= 0 then
				finalShapeId = newShapeID
				mesh:Shape(newShapeID).fSelected = true
			end
		end
		result.mergedShapeId = finalShapeId
	elseif op == "triangulate" then
		for i = 0, mesh:CountPoints() - 1 do
			local pt = mesh:Point(i)
			if params.preserveCurvature ~= true then
				pt:SetCurvature(MOHO.PEAKED, 0)
			end
			if params.preservePointBinding ~= true then
				pt.fParent = -2
			end
		end
		if vl.SetContinuousTriangulation then
			vl:SetContinuousTriangulation(params.continuousTriangulation ~= false)
		end
		if vl.MarkAsWarpLayer then
			vl:MarkAsWarpLayer(true, moho.document)
		end
		if vl.UpdateWarpLayer then
			vl:UpdateWarpLayer()
		end
		if params.editOnly ~= false and layer.SetEditOnly then
			layer:SetEditOnly(true)
		end
		if params.targetLayerId ~= nil or params.targetLayerName ~= nil then
			local targetLayer, targetId, terr = helpers.resolveLayer(moho, {
				layerId = params.targetLayerId,
				layerName = params.targetLayerName,
			})
			if not targetLayer then
				return nil, terr
			end
			pcall(function() targetLayer:SetWarpLayer(layer) end)
			result.boundTargetLayerId = targetId
		end
		result.isWarpLayer = vl.IsWarpLayer and vl:IsWarpLayer() or false
	elseif op == "stroke_exposure" then
		local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
		local cStart, cEnd = 0, mesh:CountCurves() - 1
		if params.curveId ~= nil then
			local cid = math.floor(tonumber(params.curveId))
			if cid < 0 or cid >= mesh:CountCurves() then
				return nil, "curveId out of range: " .. tostring(cid)
			end
			cStart, cEnd = cid, cid
		end
		local touched = 0
		for ci = cStart, cEnd do
			local c = mesh:Curve(ci)
			if params.startPercent ~= nil and c.fStartPercent then
				local sv = math.max(0.0, math.min(1.0, tonumber(params.startPercent) or 0))
				c.fStartPercent:SetValue(frame, sv)
				helpers.applyKeyInterp(c.fStartPercent, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end
			if params.endPercent ~= nil and c.fEndPercent then
				local ev = math.max(0.0, math.min(1.0, tonumber(params.endPercent) or 1))
				c.fEndPercent:SetValue(frame, ev)
				helpers.applyKeyInterp(c.fEndPercent, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end
			touched = touched + 1
		end
		result.updatedCurves = touched
	else
		return nil, "Unsupported mesh_editTopology operation: " .. op
	end

	layer:UpdateCurFrame()
	if vl.IsWarpLayer and vl:IsWarpLayer() and vl.UpdateWarpLayer then
		vl:UpdateWarpLayer()
	end
	helpers.updateUI(moho)
	result.pointCount = mesh:CountPoints()
	result.curveCount = mesh:CountCurves()
	result.shapeCount = mesh:CountShapes()
	return result
end

--- Create a live Smart Warp (triangulated or quad) or Moho 14 Curver (including multi-curve append) VectorLayer.
function meshTools.createSmartWarp(moho, params)
	params = params or {}
	if not moho.document then
		return nil, "No document open"
	end

	local targetLayer = nil
	local targetId = -1
	if params.targetLayerId ~= nil or params.targetLayerName ~= nil then
		local terr
		targetLayer, targetId, terr = helpers.resolveLayer(moho, {
			layerId = params.targetLayerId,
			layerName = params.targetLayerName,
		})
		if not targetLayer then
			return nil, terr
		end
	end

	helpers.prepUndo(moho, moho.layer, true)

	local mode = string.lower(tostring(params.mode or "warp"))
	local isCurver = (mode == "curver")
	local isQuad = (mode == "quad")
	local useContinuous = (params.continuousTriangulation ~= false) and (not isCurver) and (not isQuad)
	local warnings = {}

	local cx = tonumber(params.cx)
	local cy = tonumber(params.cy)
	local w = tonumber(params.width)
	local h = tonumber(params.height)
	if targetLayer then
		if targetLayer:LayerType() == MOHO.LT_IMAGE then
			local img = moho:LayerAsImage(targetLayer)
			if img and img.Width and img.Height then
				w = w or img:Width()
				h = h or img:Height()
			end
		end
		if not w or not h or cx == nil or cy == nil then
			local b = helpers.getLayerBounds(targetLayer, 0)
			if b and b.maxX > b.minX and b.maxY > b.minY then
				w = w or (b.maxX - b.minX)
				h = h or (b.maxY - b.minY)
				if cx == nil then cx = (b.minX + b.maxX) * 0.5 end
				if cy == nil then cy = (b.minY + b.maxY) * 0.5 end
			end
		end
	end
	w = (w and w > 0) and w or 1.0
	h = (h and h > 0) and h or 1.0
	cx = cx or 0.0
	cy = cy or 0.0

	local margin = tonumber(params.margin) or 0.04
	local gridCols, gridRows = nil, nil
	local gridHw, gridHh = nil, nil
	local pts = params.points

	if type(pts) ~= "table" or #pts < (isCurver and 2 or 3) then
		if isCurver then
			local segs = math.max(2, math.floor(tonumber(params.cols) or 5))
			pts = {}
			for i = 0, segs - 1 do
				local px = cx - w * 0.5 + w * (i / (segs - 1))
				pts[#pts + 1] = { x = px, y = cy }
			end
		else
			local defN = isQuad and 4 or 5
			gridCols = math.max(isQuad and 1 or 2, math.floor(tonumber(params.cols) or defN))
			gridRows = math.max(isQuad and 1 or 2, math.floor(tonumber(params.rows) or defN))
			gridHw = w * 0.5 + margin
			gridHh = h * 0.5 + margin
			if not isQuad then
				pts = {}
				for r = 0, gridRows - 1 do
					local py = cy - gridHh + (2.0 * gridHh) * (r / (gridRows - 1))
					for c = 0, gridCols - 1 do
						local px = cx - gridHw + (2.0 * gridHw) * (c / (gridCols - 1))
						pts[#pts + 1] = { x = px, y = py }
					end
				end
			end
		end
	end

	local appendingCurver = isCurver and (params.appendToLayerId ~= nil or params.appendToLayerName ~= nil)
	local warpLayer
	if appendingCurver then
		local aerr
		warpLayer, _, aerr = helpers.resolveLayer(moho, {
			layerId = params.appendToLayerId,
			layerName = params.appendToLayerName,
		})
		if not warpLayer then
			return nil, aerr
		end
		if not moho:LayerAsVector(warpLayer) then
			return nil, "appendTo layer '" .. warpLayer:Name() .. "' is not a VectorLayer"
		end
	else
		warpLayer = moho:CreateNewLayer(MOHO.LT_VECTOR, true)
		local suffix = isCurver and " (Curver)" or (isQuad and " (Quad Warp)" or " (Warp)")
		local warpName = params.name or ((targetLayer and (targetLayer:Name() .. suffix)) or (isCurver and "Curver" or "SmartWarp"))
		warpLayer:SetName(tostring(warpName))
		if warpLayer.SetEditOnly then
			warpLayer:SetEditOnly(true)
		end

		if targetLayer then
			local t0 = targetLayer.fTranslation:GetValue(0)
			local s0 = targetLayer.fScale:GetValue(0)
			warpLayer.fTranslation:SetValue(0, t0)
			warpLayer.fScale:SetValue(0, s0)
			warpLayer.fRotationZ:SetValue(0, targetLayer.fRotationZ:GetValue(0))
			local parentGrp = targetLayer:Parent()
			if parentGrp and parentGrp:IsGroupType() then
				moho:PlaceLayerInGroup(warpLayer, parentGrp, false, false)
				moho:PlaceLayerBehindAnother(warpLayer, targetLayer)
			end
		end
	end

	moho:SetSelLayer(warpLayer)
	local vl = moho:LayerAsVector(warpLayer)
	local mesh = vl:Mesh()
	local v = LM.Vector2:new_local()
	local triCount = 0
	local createdShapes = 0

	if isCurver then
		local startIdx = mesh:CountPoints()
		local curverWidth = (params.curverWidth ~= nil) and tonumber(params.curverWidth) or nil
		for i = 1, #pts do
			v:Set(tonumber(pts[i].x), tonumber(pts[i].y))
			if i == 1 then
				mesh:AddLonePoint(v, 0)
			else
				mesh:AppendPoint(v, 0)
			end
		end
		applyPointSpecs(mesh, startIdx, #pts, pts, false, curverWidth, 0)
		if vl.MarkAsCurver then
			vl:MarkAsCurver(true)
		end
		if params.compressible ~= nil then
			local okComp, compWarn = writeCompressibleCurver(vl, params.compressible == true)
			if not okComp and compWarn then
				warnings[#warnings + 1] = compWarn
			end
		end
		if appendingCurver and vl.UpdateWarpLayer then
			vl:UpdateWarpLayer()
		end
	elseif isQuad and gridCols and gridRows then
		if vl.PauseContinuousTriangulation then
			vl:PauseContinuousTriangulation(true)
		end
		local n = mesh:CountPoints()
		local function quadPt(qx, qy)
			return cx - gridHw + (2.0 * gridHw) * (qx / gridCols), cy - gridHh + (2.0 * gridHh) * (qy / gridRows)
		end
		for y = 0, gridRows do
			for x = 0, gridCols do
				local px, py = quadPt(x, y)
				v:Set(px, py)
				if x == 0 then
					mesh:AddLonePoint(v, 0)
				else
					mesh:AppendPoint(v, 0)
				end
			end
		end
		for x = 0, gridCols do
			local vBase = mesh:CountPoints()
			for y = 0, gridRows do
				local px, py = quadPt(x, y)
				v:Set(px, py)
				if y == 0 then
					mesh:AddLonePoint(v, 0)
				else
					mesh:AppendPoint(v, 0)
				end
			end
			for y = gridRows, 0, -1 do
				mesh:WeldPoints(vBase + y, n + y * (gridCols + 1) + x, 0)
			end
		end

		for i = n, mesh:CountPoints() - 1 do
			local pt = mesh:Point(i)
			pt:SetCurvature(MOHO.PEAKED, 0)
			pt.fParent = -2
		end

		for y = 0, gridRows - 1 do
			for x = 0, gridCols - 1 do
				mesh:SelectNone()
				mesh:Point(n + y * (gridCols + 1) + x).fSelected = true
				mesh:Point(n + y * (gridCols + 1) + (x + 1)).fSelected = true
				mesh:Point(n + (y + 1) * (gridCols + 1) + x).fSelected = true
				mesh:Point(n + (y + 1) * (gridCols + 1) + (x + 1)).fSelected = true
				local sid = moho:CreateShape(true, false, 0)
				if sid >= 0 then
					local sh = mesh:Shape(sid)
					if sh then
						sh.fHasFill = true
						sh.fHasOutline = false
					end
				end
			end
		end

		if vl.SetContinuousTriangulation then
			vl:SetContinuousTriangulation(false)
		end
		if vl.MarkAsWarpLayer then
			vl:MarkAsWarpLayer(true, moho.document)
		end
		if vl.PauseContinuousTriangulation then
			vl:PauseContinuousTriangulation(false)
		end
		if vl.UpdateWarpLayer then
			vl:UpdateWarpLayer()
		end
		createdShapes = mesh:CountShapes()
		triCount = createdShapes
	elseif gridCols and gridRows and useContinuous and vl.SetContinuousTriangulation then
		if vl.PauseContinuousTriangulation then
			vl:PauseContinuousTriangulation(true)
		end

		local function gridPt(c, r)
			return {
				x = cx - gridHw + (2.0 * gridHw) * (c / (gridCols - 1)),
				y = cy - gridHh + (2.0 * gridHh) * (r / (gridRows - 1)),
			}
		end

		local border = {}
		for c = 0, gridCols - 1 do border[#border + 1] = gridPt(c, 0) end
		for r = 1, gridRows - 1 do border[#border + 1] = gridPt(gridCols - 1, r) end
		for c = gridCols - 2, 0, -1 do border[#border + 1] = gridPt(c, gridRows - 1) end
		for r = gridRows - 2, 1, -1 do border[#border + 1] = gridPt(0, r) end

		v:Set(border[1].x, border[1].y)
		mesh:AddLonePoint(v, 0)
		local borderFirstId = mesh:CountPoints() - 1
		for i = 2, #border do
			v:Set(border[i].x, border[i].y)
			mesh:AppendPoint(v, 0)
		end
		v:Set(border[1].x, border[1].y)
		mesh:AppendPoint(v, 0)
		mesh:WeldPoints(mesh:CountPoints() - 1, borderFirstId, 0)

		local interior = {}
		for r = 1, gridRows - 2 do
			for c = 1, gridCols - 2 do
				interior[#interior + 1] = gridPt(c, r)
			end
		end
		if #interior >= 2 then
			v:Set(interior[1].x, interior[1].y)
			mesh:AddLonePoint(v, 0)
			for i = 2, #interior do
				v:Set(interior[i].x, interior[i].y)
				mesh:AppendPoint(v, 0)
			end
		elseif #interior == 1 then
			v:Set(border[1].x, border[1].y)
			mesh:AddLonePoint(v, 0)
			local anchorId = mesh:CountPoints() - 1
			v:Set(interior[1].x, interior[1].y)
			mesh:AppendPoint(v, 0)
			mesh:WeldPoints(anchorId, borderFirstId, 0)
		end

		for i = 0, mesh:CountPoints() - 1 do
			local pt = mesh:Point(i)
			pt:SetCurvature(MOHO.PEAKED, 0)
			pt.fParent = -2
		end

		vl:SetContinuousTriangulation(true)
		if vl.MarkAsWarpLayer then
			vl:MarkAsWarpLayer(true, moho.document)
		end
		if vl.PauseContinuousTriangulation then
			vl:PauseContinuousTriangulation(false)
		end
		if vl.UpdateWarpLayer then
			vl:UpdateWarpLayer()
		end
		createdShapes = mesh:CountShapes()
		triCount = createdShapes
	else
		local tris = delaunay.triangulate(pts)
		if #tris == 0 then
			return nil, "Delaunay triangulation produced 0 triangles"
		end
		triCount = #tris

		if vl.PauseContinuousTriangulation then
			vl:PauseContinuousTriangulation(true)
		end

		local canonicalId = {}
		local edgeAdded = {}
		local function addSegment(i1, i2)
			local a, b = i1, i2
			if a > b then a, b = b, a end
			local key = a .. ":" .. b
			if edgeAdded[key] then return end
			edgeAdded[key] = true
			local pa = pts[a]
			local pb = pts[b]
			mesh:SelectNone()
			v:Set(tonumber(pa.x), tonumber(pa.y))
			mesh:AddLonePoint(v, 0)
			local idA = mesh:CountPoints() - 1
			v:Set(tonumber(pb.x), tonumber(pb.y))
			mesh:AppendPoint(v, 0)
			local idB = mesh:CountPoints() - 1
			if canonicalId[a] ~= nil then
				mesh:WeldPoints(idA, canonicalId[a], 0)
				if idB > idA then idB = idB - 1 end
			else
				canonicalId[a] = idA
			end
			if canonicalId[b] ~= nil then
				mesh:WeldPoints(idB, canonicalId[b], 0)
			else
				canonicalId[b] = idB
			end
		end

		for ti = 1, #tris do
			local t = tris[ti]
			addSegment(t[1], t[2])
			addSegment(t[2], t[3])
			addSegment(t[3], t[1])
		end

		for i = 0, mesh:CountPoints() - 1 do
			local pt = mesh:Point(i)
			pt:SetCurvature(MOHO.PEAKED, 0)
			pt.fParent = -2
		end

		if useContinuous and vl.SetContinuousTriangulation then
			vl:SetContinuousTriangulation(true)
		else
			for ti = 1, #tris do
				local t = tris[ti]
				mesh:SelectNone()
				for k = 1, 3 do
					local cid = canonicalId[t[k]]
					local pt = cid and mesh:Point(cid) or nil
					if pt then pt.fSelected = true end
				end
				local sid = moho:CreateShape(true, false, 0)
				if sid >= 0 then
					local sh = mesh:Shape(sid)
					if sh then
						sh.fHasFill = true
						sh.fHasOutline = false
					end
					createdShapes = createdShapes + 1
				end
			end
		end

		if vl.MarkAsWarpLayer then
			vl:MarkAsWarpLayer(true, moho.document)
		end
		if vl.PauseContinuousTriangulation then
			vl:PauseContinuousTriangulation(false)
		end
		if vl.UpdateWarpLayer then
			vl:UpdateWarpLayer()
		end
		createdShapes = mesh:CountShapes()
	end

	local boundToTarget = false
	local boundToBoneId = -1
	local boundFlexiIds = {}
	if targetLayer and (not appendingCurver) and (params.bindToTarget ~= false) then
		local ok = pcall(function() targetLayer:SetWarpLayer(warpLayer) end)
		boundToTarget = ok
	end
	if targetLayer and (not appendingCurver) and (params.autoBindToTargetBone ~= false) then
		local pb = targetLayer.LayerParentBone and targetLayer:LayerParentBone() or -1
		if pb >= 0 and warpLayer.SetLayerParentBone then
			if warpLayer.DisableFlexiBoneSubset then
				pcall(function() warpLayer:DisableFlexiBoneSubset() end)
			end
			local okPB = pcall(function() warpLayer:SetLayerParentBone(pb) end)
			if okPB then
				boundToBoneId = pb
			end
		else
			local flexi = helpers.getFlexiBoneIds(targetLayer)
			if #flexi > 0 and warpLayer.ClearFlexiBoneSubset and warpLayer.AddToFlexiBoneSubset and warpLayer.EnableFlexiBoneSubset then
				local okFC = pcall(function()
					warpLayer:ClearFlexiBoneSubset()
					for fi = 1, #flexi do
						warpLayer:AddToFlexiBoneSubset(flexi[fi])
					end
					warpLayer:EnableFlexiBoneSubset()
				end)
				if okFC then
					boundFlexiIds = flexi
				end
			end
		end
	end

	helpers.updateUI(moho)
	local res = {
		created = not appendingCurver,
		appended = appendingCurver,
		mode = isCurver and "curver" or (isQuad and "quad" or "warp"),
		warpLayerId = helpers.getLayerId(moho, warpLayer),
		warpLayerName = warpLayer:Name(),
		isWarpLayer = vl.IsWarpLayer and vl:IsWarpLayer() or false,
		isWarpCandidate = vl.IsWarpLayerCandidate and vl:IsWarpLayerCandidate() or false,
		isCurver = vl.IsCurver and vl:IsCurver() or false,
		continuousTriangulation = vl.ContinuousTriangulation and vl:ContinuousTriangulation() or false,
		pointCount = mesh:CountPoints(),
		curveCount = mesh:CountCurves(),
		triangleCount = triCount,
		shapeCount = createdShapes,
		boundToTarget = boundToTarget,
		boundToBoneId = boundToBoneId,
		boundFlexiBoneIds = json.array(boundFlexiIds),
		targetLayerId = targetId,
		warnings = json.array(warnings),
	}
	local compVal, compOk = readCompressibleCurver(vl)
	if compOk then
		res.compressibleCurver = compVal
	end
	return res
end

--- Attach, configure, or detach a curve profile (lm_curve_profile.lua).
function meshTools.setCurveProfile(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end
	local mesh = vl:Mesh()
	local curveId = math.floor(tonumber(params.curveId) or 0)
	if curveId < 0 or curveId >= mesh:CountCurves() then
		return nil, "curveId out of range: " .. tostring(curveId)
	end
	local curve = mesh:Curve(curveId)
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	helpers.prepUndo(moho, layer, false)

	local detached = (params.clear == true or params.detach == true)
	if detached then
		if curve.SetProfileCurve then
			curve:SetProfileCurve(nil, nil)
		end
	elseif params.profileLayerId ~= nil or params.profileLayerName ~= nil or params.profileCurveId ~= nil then
		local pLayer = layer
		if params.profileLayerId ~= nil or params.profileLayerName ~= nil then
			local perr
			pLayer, _, perr = helpers.resolveLayer(moho, {
				layerId = params.profileLayerId,
				layerName = params.profileLayerName,
			})
			if not pLayer then
				return nil, perr
			end
		end
		local pVl = moho:LayerAsVector(pLayer)
		if not pVl then
			return nil, "Profile layer '" .. pLayer:Name() .. "' is not a VectorLayer"
		end
		local pMesh = pVl:Mesh()
		local pCid = math.floor(tonumber(params.profileCurveId) or 0)
		if pCid < 0 or pCid >= pMesh:CountCurves() then
			return nil, "profileCurveId out of range: " .. tostring(pCid)
		end
		local pCurve = pMesh:Curve(pCid)
		local argLayer = (pLayer == layer) and nil or pLayer
		if curve.SetProfileCurve then
			curve:SetProfileCurve(argLayer, pCurve)
		else
			return nil, "M_Curve:SetProfileCurve is not available"
		end
	end

	if params.profileRepeat ~= nil then
		curve.fProfileRepeat = math.max(1, math.floor(tonumber(params.profileRepeat) or 1))
	end
	if params.profileOffset ~= nil and curve.fProfileOffset then
		local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
		curve.fProfileOffset:SetValue(frame, tonumber(params.profileOffset) or 0)
		helpers.applyKeyInterp(curve.fProfileOffset, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end

	layer:UpdateCurFrame()
	helpers.updateUI(moho)
	return {
		layerId = id,
		layerName = layer:Name(),
		curveId = curveId,
		frame = frame,
		detached = detached,
		profileRepeat = styles.safeField(curve, "fProfileRepeat") or 1,
		profileOffset = curve.fProfileOffset and curve.fProfileOffset:GetValue(frame) or 0,
	}
end

--- Moho 14 Liquid Shapes authoring (set_combo, combine, bake).
function meshTools.liquidShapes(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local vl = moho:LayerAsVector(layer)
	if not vl then
		return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
	end
	local mesh = vl:Mesh()
	local op = string.lower(tostring(params.operation or "set_combo"))
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	helpers.prepUndo(moho, layer, false)

	if op == "set_combo" then
		local shape, sid, serr = resolveShape(mesh, params.shapeId, params.shapeName)
		if not shape then return nil, serr end
		if params.comboMode ~= nil then
			local code = helpers.comboModeCode(params.comboMode)
			if code == nil then return nil, "Unknown comboMode: " .. tostring(params.comboMode) end
			shape.fComboMode = code
		end
		if params.blend ~= nil and shape.fComboBlend then
			shape.fComboBlend:SetValue(frame, math.max(0.0, math.min(1.0, tonumber(params.blend) or 0)))
		end
		if params.placeAboveShapeId ~= nil then
			mesh:PlaceShapeAbove(sid, math.floor(tonumber(params.placeAboveShapeId)))
		elseif params.placeBehindShapeId ~= nil then
			mesh:PlaceShapeBehind(sid, math.floor(tonumber(params.placeBehindShapeId)))
		end
		layer:UpdateCurFrame()
		helpers.updateUI(moho)
		return serializeShape(moho, mesh, shape, mesh:ShapeID(shape), frame)
	elseif op == "combine" then
		local base, _, berr = resolveShape(mesh, params.baseShapeId, params.baseShapeName)
		if not base then return nil, berr end
		local other, _, oerr = resolveShape(mesh, params.otherShapeId or params.shapeId, params.otherShapeName or params.shapeName)
		if not other then return nil, oerr end
		local mode = helpers.comboModeCode(params.comboMode or "add") or MOHO.COMBO_ADD
		local blend = math.max(0.0, math.min(1.0, tonumber(params.blend) or 0))
		local flag = (params.flag == true)
		local newId = mesh:CombineShapes(base, other, mode, blend, flag)
		layer:UpdateCurFrame()
		helpers.updateUI(moho)
		return {
			combined = newId >= 0,
			newShapeId = newId,
			shapeCount = mesh:CountShapes(),
		}
	elseif op == "bake" then
		local shape, _, serr = resolveShape(mesh, params.shapeId or params.baseShapeId, params.shapeName or params.baseShapeName)
		if not shape then return nil, serr end
		local keepOrig = (params.keepOriginals == true)
		local newId = mesh:BakeCombinedShapes(shape, keepOrig)
		layer:UpdateCurFrame()
		helpers.updateUI(moho)
		return {
			baked = newId >= 0,
			newShapeId = newId,
			shapeCount = mesh:CountShapes(),
		}
	end

	return nil, "Unsupported liquidShapes operation (use set_combo, combine, bake): " .. op
end

return meshTools
