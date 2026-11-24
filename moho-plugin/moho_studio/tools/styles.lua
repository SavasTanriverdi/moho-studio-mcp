-- Saved Styles, Brushes, Soft Edge, Gradients, and Moho 14.4 New Style From Shape tools.
-- API signatures verified via Moho 14.4 bundled scripts (lm_randompointcolors.lua, ss_svg_import14.lua, lm_select_shape.lua)
-- and mohoscripting.com (M_Style, M_Shape, MohoDoc).

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local styleTools = {}

local function safeField(obj, key)
	if obj == nil then
		return nil
	end
	local ok, v = pcall(function() return obj[key] end)
	if ok then
		return v
	end
	return nil
end

local function safeAnimColor(ch, frame)
	if ch == nil then
		return nil
	end
	local ok, val = pcall(function()
		if ch.GetValue then
			return ch:GetValue(frame)
		end
		return ch.value
	end)
	if ok and val then
		return helpers.serializeColor(val)
	end
	return nil
end

local function readSmartBoil(style)
	if not style then
		return nil, false
	end
	local fieldNames = {
		"fBrushRandomInterval",
		"fBrushBoilInterval",
		"fBoilInterval",
		"fSmartBoilInterval",
		"fLineBoilInterval",
		"fBrushBoil",
		"fBoil",
	}
	for i = 1, #fieldNames do
		local v = safeField(style, fieldNames[i])
		if type(v) == "number" then
			return v, true
		end
	end
	local methodNames = { "BrushBoilInterval", "BoilInterval", "SmartBoilInterval" }
	for i = 1, #methodNames do
		local fn = safeField(style, methodNames[i])
		if type(fn) == "function" then
			local ok, val = pcall(function() return fn(style) end)
			if ok and type(val) == "number" then
				return val, true
			end
		end
	end
	return nil, false
end

local function writeSmartBoil(style, intervalVal, explicitRandomize)
	if not style then
		return false, "Invalid style object"
	end
	local val = math.max(0, math.floor(tonumber(intervalVal) or 0))
	local fieldNames = {
		"fBrushRandomInterval",
		"fBrushBoilInterval",
		"fBoilInterval",
		"fSmartBoilInterval",
		"fLineBoilInterval",
		"fBrushBoil",
		"fBoil",
	}
	for i = 1, #fieldNames do
		local fname = fieldNames[i]
		local cur = safeField(style, fname)
		if cur ~= nil then
			local ok = pcall(function() style[fname] = val end)
			if ok then
				if explicitRandomize ~= false then
					pcall(function() style.fBrushRandomize = true end)
				end
				return true, nil
			end
		end
	end
	local setterNames = { "SetBrushBoilInterval", "SetBoilInterval", "SetSmartBoilInterval" }
	for i = 1, #setterNames do
		local fn = safeField(style, setterNames[i])
		if type(fn) == "function" then
			local ok = pcall(function() fn(style, val) end)
			if ok then
				if explicitRandomize ~= false then
					pcall(function() style.fBrushRandomize = true end)
				end
				return true, nil
			end
		end
	end
	return false, "smartBoilInterval property not exposed in this Moho Lua build; verify M_Style via moho_apiInspect in live Moho 14.4"
end

local function readSoftEdgePx(moho, style)
	if not style then
		return nil
	end
	local methodNames = { "SoftEdge", "SoftEdgeRadius" }
	for i = 1, #methodNames do
		local fn = safeField(style, methodNames[i])
		if type(fn) == "function" then
			local ok, val = pcall(function() return fn(style) end)
			if ok and type(val) == "number" then
				return helpers.docToPx(moho, val)
			end
		end
	end
	local fieldNames = { "fSoftEdge", "fSoftEdgeRadius" }
	for i = 1, #fieldNames do
		local val = safeField(style, fieldNames[i])
		if type(val) == "number" then
			return helpers.docToPx(moho, val)
		end
	end
	return nil
end

styleTools.safeField = safeField
styleTools.safeAnimColor = safeAnimColor
styleTools.readSoftEdgePx = readSoftEdgePx

-- Moho 14.4 C++ hazard: M_Style.fName sits at offset +0x0 of M_Style, so accessing
-- st.fName collides in tolua_ubox and overwrites st's metatable with LM_String.
-- Always normalize with ensureMStyle() and read/write names via :Name() / :SetName().
function styleTools.ensureMStyle(st)
	if st == nil then
		return nil
	end
	if tolua and tolua.type and tolua.cast then
		local okT, tName = pcall(function() return tolua.type(st) end)
		if okT and tName ~= "M_Style" then
			local okC, castSt = pcall(function() return tolua.cast(st, "M_Style") end)
			if okC and castSt ~= nil then
				return castSt
			end
		end
	end
	return st
end

function styleTools.readStyleName(st)
	st = styleTools.ensureMStyle(st)
	if not st then
		return ""
	end
	local ok, name = pcall(function()
		if st.Name then
			return st:Name()
		end
		return ""
	end)
	if ok and type(name) == "string" then
		return name
	end
	return ""
end

function styleTools.resolveDocStyle(doc, ref)
	if not doc or ref == nil then
		return nil, -1, "", ""
	end
	local count = doc.CountStyles and doc:CountStyles() or 0
	if type(ref) == "number" then
		local idx = math.floor(ref)
		if idx >= 0 and idx < count and doc.StyleByID then
			local st = styleTools.ensureMStyle(doc:StyleByID(idx))
			if st then
				return st, idx, styleTools.readStyleName(st), helpers.readLmString(safeField(st, "fUUID"))
			end
		end
		return nil, -1, "", ""
	end
	local key = tostring(ref)
	if key == "" then
		return nil, -1, "", ""
	end
	if doc.StyleByID then
		for i = 0, count - 1 do
			local st = styleTools.ensureMStyle(doc:StyleByID(i))
			if st and helpers.readLmString(safeField(st, "fUUID")) == key then
				return st, i, styleTools.readStyleName(st), key
			end
		end
		for i = 0, count - 1 do
			local st = styleTools.ensureMStyle(doc:StyleByID(i))
			if st and styleTools.readStyleName(st) == key then
				return st, i, key, helpers.readLmString(safeField(st, "fUUID"))
			end
		end
	end
	if doc.Style then
		local ok, st = pcall(function() return doc:Style(key) end)
		if ok and st then
			st = styleTools.ensureMStyle(st)
			return st, -1, styleTools.readStyleName(st), helpers.readLmString(safeField(st, "fUUID"))
		end
	end
	return nil, -1, "", ""
end

function styleTools.serializeBrush(style)
	style = styleTools.ensureMStyle(style)
	if not style then
		return nil
	end
	local b = {
		name = helpers.readLmString(safeField(style, "fBrushName")),
		spacing = safeField(style, "fBrushSpacing"),
		jitter = safeField(style, "fBrushJitter"),
		align = safeField(style, "fBrushAlign"),
		randomOrder = safeField(style, "fBrushRandomOrder"),
		mergedAlpha = safeField(style, "fBrushMergedAlpha"),
		randomize = safeField(style, "fBrushRandomize"),
		isColor = safeField(style, "fBrushIsColor"),
		tint = safeField(style, "fBrushTint"),
		angleDrift = safeField(style, "fBrushAngleDrift"),
		sizeVarAmplitude = safeField(style, "fBrushSizeVariationAmp"),
		sizeVarScale = safeField(style, "fBrushSizeVariationScale"),
		hueDrift = safeField(style, "fBrushHueDrift"),
		satDrift = safeField(style, "fBrushSatDrift"),
		valDrift = safeField(style, "fBrushValDrift"),
	}
	local boilVal, boilOk = readSmartBoil(style)
	if boilOk and boilVal ~= nil then
		b.smartBoilInterval = boilVal
	end
	return b
end

function styleTools.serializeStyle(moho, style, frame, idx)
	style = styleTools.ensureMStyle(style)
	if not style then
		return nil
	end
	local f = frame or 0
	local docH = moho.document and math.max(1, moho.document:Height()) or 1
	local lw = safeField(style, "fLineWidth") or 0
	local caps = safeField(style, "fLineCaps") or 0
	return {
		id = idx,
		name = styleTools.readStyleName(style),
		uuid = helpers.readLmString(safeField(style, "fUUID")),
		defineFillColor = safeField(style, "fDefineFillCol") == true,
		defineLineColor = safeField(style, "fDefineLineCol") == true,
		defineLineWidth = safeField(style, "fDefineLineWidth") == true,
		fillColor = safeAnimColor(safeField(style, "fFillCol"), f),
		strokeColor = safeAnimColor(safeField(style, "fLineCol"), f),
		lineWidth = lw,
		lineWidthPx = lw * docH,
		lineCaps = caps,
		roundCaps = (caps == 1),
		softEdgePx = readSoftEdgePx(moho, style),
		brush = styleTools.serializeBrush(style),
	}
end

function styleTools.applyStyleProps(moho, style, src, frame, interpArgs)
	local warnings = {}
	style = styleTools.ensureMStyle(style)
	if not style or type(src) ~= "table" then
		return warnings
	end
	local f = frame or 0
	local docH = moho.document and math.max(1, moho.document:Height()) or 1
	local iName, iCycle, iV1, iV2, iInterval, iOpts = nil, nil, nil, nil, nil, nil
	if type(interpArgs) == "table" then
		iName = interpArgs.name
		iCycle = interpArgs.cycle
		iV1 = interpArgs.v1
		iV2 = interpArgs.v2
		iInterval = interpArgs.interval
		iOpts = interpArgs.opts
	end

	if src.fillColor ~= nil and style.fFillCol then
		style.fFillCol:SetValue(f, helpers.toRgbStruct(src.fillColor))
		helpers.applyKeyInterp(style.fFillCol, f, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if src.strokeColor ~= nil and style.fLineCol then
		style.fLineCol:SetValue(f, helpers.toRgbStruct(src.strokeColor))
		helpers.applyKeyInterp(style.fLineCol, f, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if src.lineWidthPx ~= nil then
		style.fLineWidth = tonumber(src.lineWidthPx) / docH
	elseif src.lineWidth ~= nil then
		style.fLineWidth = tonumber(src.lineWidth)
	end
	if src.roundCaps ~= nil then
		style.fLineCaps = (src.roundCaps == true) and 1 or 0
	elseif src.lineCaps ~= nil then
		style.fLineCaps = math.floor(tonumber(src.lineCaps) or 0)
	end

	if src.defineFillColor ~= nil then
		pcall(function() style.fDefineFillCol = (src.defineFillColor == true) end)
	end
	if src.defineLineColor ~= nil then
		pcall(function() style.fDefineLineCol = (src.defineLineColor == true) end)
	end
	if src.defineLineWidth ~= nil then
		pcall(function() style.fDefineLineWidth = (src.defineLineWidth == true) end)
	end

	if src.softEdgePx ~= nil then
		local px = tonumber(src.softEdgePx) or 0
		if px <= 0 then
			if style.SetSoftEdge then
				pcall(function() style:SetSoftEdge(0) end)
			end
			if style.ClearSoftEdge then
				pcall(function() style:ClearSoftEdge() end)
			end
		elseif style.SetSoftEdge then
			local okSE, errSE = pcall(function() style:SetSoftEdge(helpers.pxToDoc(moho, px)) end)
			if not okSE then
				warnings[#warnings + 1] = "SetSoftEdge failed: " .. tostring(errSE)
			end
		else
			warnings[#warnings + 1] = "M_Style:SetSoftEdge not available"
		end
	end
	if src.strokeSoftEdgePx ~= nil then
		local spx = math.max(0, tonumber(src.strokeSoftEdgePx) or 0)
		if style.SetStrokeSoftEdge then
			local okSSE, errSSE = pcall(function() style:SetStrokeSoftEdge(helpers.pxToDoc(moho, spx)) end)
			if not okSSE then
				warnings[#warnings + 1] = "SetStrokeSoftEdge failed: " .. tostring(errSSE)
			end
		else
			warnings[#warnings + 1] = "M_Style:SetStrokeSoftEdge not available"
		end
	end

	if type(src.gradient) == "table" then
		local g = src.gradient
		local gCode = helpers.gradientTypeCode(g.type or "linear")
		if gCode == nil then
			warnings[#warnings + 1] = "Unknown gradient type: " .. tostring(g.type)
		elseif style.SetGradient then
			local okG, errG = pcall(function() style:SetGradient(gCode, g.allowTransparency == true) end)
			if not okG then
				warnings[#warnings + 1] = "SetGradient failed: " .. tostring(errG)
			elseif type(g.stops) == "table" then
				if style.SetGradientColor then
					for si = 1, #g.stops do
						local stStop = g.stops[si]
						if type(stStop) == "table" and stStop.color ~= nil then
							local pos = math.max(0.0, math.min(1.0, tonumber(stStop.pos) or 0.0))
							local col = helpers.toRgbStruct(stStop.color)
							local okSC, errSC = pcall(function() style:SetGradientColor(pos, col) end)
							if not okSC then
								warnings[#warnings + 1] = "SetGradientColor failed at stop " .. tostring(si) .. ": " .. tostring(errSC)
							end
						end
					end
				else
					warnings[#warnings + 1] = "M_Style:SetGradientColor not available"
				end
			end
		else
			warnings[#warnings + 1] = "M_Style:SetGradient not available"
		end
	end

	local b = type(src.brush) == "table" and src.brush or {}
	local function pickBrush(flatKey, nestedKey)
		if src[flatKey] ~= nil then
			return src[flatKey]
		end
		return b[nestedKey]
	end
	local bName = pickBrush("brushName", "name")
	if bName ~= nil then
		if not helpers.writeLmString(style, "fBrushName", tostring(bName)) then
			warnings[#warnings + 1] = "Failed to set fBrushName"
		end
	end
	local brushFieldSpecs = {
		{ val = pickBrush("brushSpacing", "spacing"), field = "fBrushSpacing", kind = "number" },
		{ val = pickBrush("brushJitter", "jitter"), field = "fBrushJitter", kind = "number" },
		{ val = pickBrush("brushAlign", "align"), field = "fBrushAlign", kind = "bool" },
		{ val = pickBrush("brushRandomOrder", "randomOrder"), field = "fBrushRandomOrder", kind = "bool" },
		{
			val = (src.brushMergedAlpha ~= nil and src.brushMergedAlpha)
				or (src.mergeAlpha ~= nil and src.mergeAlpha)
				or (b.mergedAlpha ~= nil and b.mergedAlpha)
				or b.mergeAlpha,
			field = "fBrushMergedAlpha",
			kind = "bool",
		},
		{ val = pickBrush("brushAngleDrift", "angleDrift"), field = "fBrushAngleDrift", kind = "number" },
		{ val = pickBrush("brushRandomize", "randomize"), field = "fBrushRandomize", kind = "bool" },
		{ val = pickBrush("brushIsColor", "isColor"), field = "fBrushIsColor", kind = "bool" },
		{ val = pickBrush("brushTint", "tint"), field = "fBrushTint", kind = "bool_or_num" },
		{ val = pickBrush("sizeVarAmplitude", "sizeVarAmplitude"), field = "fBrushSizeVariationAmp", kind = "number" },
		{ val = pickBrush("sizeVarScale", "sizeVarScale"), field = "fBrushSizeVariationScale", kind = "number" },
		{ val = pickBrush("hueDrift", "hueDrift"), field = "fBrushHueDrift", kind = "number" },
		{ val = pickBrush("satDrift", "satDrift"), field = "fBrushSatDrift", kind = "number" },
		{ val = pickBrush("valDrift", "valDrift"), field = "fBrushValDrift", kind = "number" },
	}
	for i = 1, #brushFieldSpecs do
		local spec = brushFieldSpecs[i]
		if spec.val ~= nil then
			local okB, errB = pcall(function()
				if spec.kind == "bool" then
					style[spec.field] = (spec.val == true)
				elseif spec.kind == "bool_or_num" then
					if type(spec.val) == "boolean" then
						style[spec.field] = spec.val
					else
						style[spec.field] = tonumber(spec.val)
					end
				else
					style[spec.field] = tonumber(spec.val)
				end
			end)
			if not okB then
				warnings[#warnings + 1] = "Failed to set " .. spec.field .. ": " .. tostring(errB)
			end
		end
	end

	local boilVal = pickBrush("smartBoilInterval", "smartBoilInterval")
	if boilVal ~= nil then
		local explicitRand = pickBrush("brushRandomize", "randomize")
		local okBoil, boilWarn = writeSmartBoil(style, boilVal, explicitRand)
		if not okBoil and boilWarn then
			warnings[#warnings + 1] = boilWarn
		end
	end

	return warnings
end

function styleTools.bindShapeStyle(doc, shape, slot, styleRef)
	if not doc or not shape then
		return false, "Document or shape missing"
	end
	local sIdx = (tonumber(slot) == 2) and 2 or 1
	local nameField = (sIdx == 1) and "fInheritedStyleName" or "fInheritedStyleName2"
	local ptrField = (sIdx == 1) and "fInheritedStyle" or "fInheritedStyle2"
	local otherNameField = (sIdx == 1) and "fInheritedStyleName2" or "fInheritedStyleName"
	local otherPtrField = (sIdx == 1) and "fInheritedStyle2" or "fInheritedStyle"

	if styleRef == "" or styleRef == false or (type(styleRef) == "string" and string.lower(styleRef) == "none") then
		local otherKey = helpers.readLmString(safeField(shape, otherNameField))
		if shape.RemoveStyles then
			shape:RemoveStyles()
		else
			helpers.writeLmString(shape, nameField, "")
			pcall(function() shape[ptrField] = nil end)
		end
		if otherKey ~= "" then
			helpers.writeLmString(shape, otherNameField, otherKey)
			local otherSt = styleTools.resolveDocStyle(doc, otherKey)
			if otherSt then
				pcall(function() shape[otherPtrField] = otherSt end)
			end
		end
		return true, nil
	end

	local st, _, stName, stUuid = styleTools.resolveDocStyle(doc, styleRef)
	if not st then
		return false, "Saved style not found: " .. tostring(styleRef)
	end
	local key = (stUuid ~= "" and stUuid) or stName
	helpers.writeLmString(shape, nameField, key)
	pcall(function() shape[ptrField] = st end)
	return true, nil
end

local function effectiveShapeStyleProps(shape, f, docH)
	local mySt = styleTools.ensureMStyle(shape.fMyStyle)
	local fillCol = mySt and safeAnimColor(safeField(mySt, "fFillCol"), f) or { r = 0, g = 0, b = 0, a = 255 }
	local lineCol = mySt and safeAnimColor(safeField(mySt, "fLineCol"), f) or { r = 0, g = 0, b = 0, a = 255 }
	local lw = (mySt and safeField(mySt, "fLineWidth")) or (1 / math.max(1, docH))
	local caps = (mySt and safeField(mySt, "fLineCaps")) or 0
	local srcStyle = mySt
	local inh1 = styleTools.ensureMStyle(safeField(shape, "fInheritedStyle"))
	local inh2 = styleTools.ensureMStyle(safeField(shape, "fInheritedStyle2"))
	local layersOfStyles = { inh1, inh2 }
	for i = 1, #layersOfStyles do
		local st = styleTools.ensureMStyle(layersOfStyles[i])
		if st then
			if safeField(st, "fDefineFillCol") == true then
				local c = safeAnimColor(safeField(st, "fFillCol"), f)
				if c then fillCol = c end
			end
			if safeField(st, "fDefineLineCol") == true then
				local c = safeAnimColor(safeField(st, "fLineCol"), f)
				if c then lineCol = c end
			end
			if safeField(st, "fDefineLineWidth") == true then
				local w = safeField(st, "fLineWidth")
				if w ~= nil then lw = w end
			end
			local bn = helpers.readLmString(safeField(st, "fBrushName"))
			if bn ~= "" then
				srcStyle = st
			end
		end
	end
	local brushName = srcStyle and helpers.readLmString(safeField(srcStyle, "fBrushName")) or ""
	return {
		fillColor = fillCol,
		strokeColor = lineCol,
		lineWidth = lw,
		lineCaps = caps,
		brushName = brushName,
		brushSourceStyle = srcStyle,
	}
end

local function colorsMatch(c1, c2, tol)
	if not c1 or not c2 then
		return false
	end
	return math.abs((c1.r or 0) - (c2.r or 0)) <= tol
		and math.abs((c1.g or 0) - (c2.g or 0)) <= tol
		and math.abs((c1.b or 0) - (c2.b or 0)) <= tol
		and math.abs((c1.a or 255) - (c2.a or 255)) <= tol
end

local function collectUsedStyleKeys(moho)
	local used = {}
	helpers.walkLayers(moho, function(layer)
		if layer:LayerType() == MOHO.LT_VECTOR then
			local vl = moho:LayerAsVector(layer)
			local mesh = vl and vl:Mesh() or nil
			if mesh then
				for si = 0, mesh:CountShapes() - 1 do
					local sh = mesh:Shape(si)
					local k1 = helpers.readLmString(safeField(sh, "fInheritedStyleName"))
					local k2 = helpers.readLmString(safeField(sh, "fInheritedStyleName2"))
					if k1 ~= "" then used[k1] = true end
					if k2 ~= "" then used[k2] = true end
					local i1 = styleTools.ensureMStyle(safeField(sh, "fInheritedStyle"))
					local i2 = styleTools.ensureMStyle(safeField(sh, "fInheritedStyle2"))
					if i1 then
						local u = helpers.readLmString(safeField(i1, "fUUID"))
						local n = styleTools.readStyleName(i1)
						if u ~= "" then used[u] = true end
						if n ~= "" then used[n] = true end
					end
					if i2 then
						local u = helpers.readLmString(safeField(i2, "fUUID"))
						local n = styleTools.readStyleName(i2)
						if u ~= "" then used[u] = true end
						if n ~= "" then used[n] = true end
					end
				end
			end
		end
	end)
	return used
end

local function normalizeDir(d)
	if type(d) ~= "string" or d == "" then
		return nil
	end
	local norm = d:gsub("\\", "/")
	norm = norm:gsub("/+$", "")
	if norm == "" then
		return nil
	end
	return norm
end

local function scanBrushDir(moho, dir, seenSet, outList)
	local norm = normalizeDir(dir)
	if not norm then
		return false
	end
	local okBegin = pcall(function() moho:BeginFileListing(norm) end)
	if not okBegin then
		return false
	end
	local anyFound = false
	while true do
		local okNext, entry = pcall(function() return moho:GetNextFile() end)
		if not okNext or entry == nil or entry == "" then
			break
		end
		if entry ~= "." and entry ~= ".." then
			local name = entry:gsub("%.[mM][oO][hH][oO][bB][rR][uU][sS][hH]$", "")
			name = name:gsub("%.[pP][nN][gG]$", "")
			if name ~= "" and not seenSet[name] then
				seenSet[name] = true
				outList[#outList + 1] = name
			end
			anyFound = true
		end
	end
	return anyFound
end

function styleTools.manage(moho, params)
	params = params or {}
	local op = string.lower(tostring(params.operation or "list"))
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	if op == "list_brushes" then
		local dirs = {}
		local seenDirs = {}
		local function addDir(d)
			local norm = normalizeDir(d)
			if norm and not seenDirs[norm] then
				seenDirs[norm] = true
				dirs[#dirs + 1] = norm
			end
		end
		if params.brushesDir then
			addDir(tostring(params.brushesDir))
		end
		if moho.AppDir then
			local okA, ad = pcall(function() return moho:AppDir() end)
			if okA and type(ad) == "string" and ad ~= "" then
				addDir(ad .. "/Brushes")
				addDir(ad .. "/Resources/Support/Common/Brushes")
				addDir(ad .. "/Common/Brushes")
			end
		end
		if moho.UserContentDir then
			local okU, ucd = pcall(function() return moho:UserContentDir() end)
			if okU and type(ucd) == "string" and ucd ~= "" then
				addDir(ucd .. "/Custom Content/Brushes")
				addDir(ucd .. "/Brushes")
			end
		end
		if moho.UserAppDir then
			local okUA, uad = pcall(function() return moho:UserAppDir() end)
			if okUA and type(uad) == "string" and uad ~= "" then
				addDir(uad .. "/Brushes")
			end
		end
		local envDir = os.getenv("MOHO_BRUSHES_DIR")
		if envDir and envDir ~= "" then
			addDir(envDir)
		end

		local brushes = {}
		local seenBrushes = {}
		local scanned = {}
		for i = 1, #dirs do
			if scanBrushDir(moho, dirs[i], seenBrushes, brushes) then
				scanned[#scanned + 1] = dirs[i]
			end
		end
		if #brushes == 0 then
			local fallbackDir = "C:/Program Files/Moho 14/Resources/Support/Common/Brushes"
			if not seenDirs[fallbackDir] and scanBrushDir(moho, fallbackDir, seenBrushes, brushes) then
				scanned[#scanned + 1] = fallbackDir
			end
		end
		table.sort(brushes)
		return {
			count = #brushes,
			brushes = json.array(brushes),
			directoriesScanned = json.array(scanned),
		}
	end

	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end

	if op == "list" then
		local list = {}
		local count = doc.CountStyles and doc:CountStyles() or 0
		for i = 0, count - 1 do
			local st = styleTools.ensureMStyle(doc:StyleByID(i))
			if st then
				list[#list + 1] = styleTools.serializeStyle(moho, st, frame, i)
			end
		end
		return {
			count = #list,
			frame = frame,
			styles = json.array(list),
		}
	elseif op == "create" then
		local styleName = tostring(params.name or params.styleName or "")
		if styleName == "" then
			return nil, "name is required for style create"
		end
		local existing = styleTools.resolveDocStyle(doc, styleName)
		if existing and params.overwrite ~= true then
			return nil, "Style already exists: " .. styleName
		end
		helpers.prepUndo(moho, moho.layer, true)
		local st = styleTools.ensureMStyle(existing)
		if not st then
			local okAdd, added = pcall(function() return doc:AddStyle(styleName) end)
			if okAdd and added then
				st = styleTools.ensureMStyle(added)
			else
				st = styleTools.ensureMStyle(doc:Style(styleName))
			end
		end
		if not st then
			return nil, "MohoDoc:AddStyle failed to create style: " .. styleName
		end
		if params.fillColor ~= nil and params.defineFillColor == nil then
			pcall(function() st.fDefineFillCol = true end)
		end
		if params.strokeColor ~= nil and params.defineLineColor == nil then
			pcall(function() st.fDefineLineCol = true end)
		end
		if (params.lineWidthPx ~= nil or params.lineWidth ~= nil) and params.defineLineWidth == nil then
			pcall(function() st.fDefineLineWidth = true end)
		end
		local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
		local warnings = styleTools.applyStyleProps(moho, st, params, frame, {
			name = iName,
			cycle = iCycle,
			v1 = iV1,
			v2 = iV2,
			interval = iInterval,
			opts = iOpts,
		})
		helpers.updateUI(moho)
		local freshSt, idx = styleTools.resolveDocStyle(doc, styleName)
		return {
			created = true,
			style = styleTools.serializeStyle(moho, freshSt or st, frame, idx),
			warnings = json.array(warnings),
		}
	elseif op == "update" then
		local ref = params.styleId ~= nil and params.styleId or (params.styleUuid or params.styleName or params.name)
		local st, idx = styleTools.resolveDocStyle(doc, ref)
		st = styleTools.ensureMStyle(st)
		if not st then
			return nil, "Saved style not found: " .. tostring(ref)
		end
		helpers.prepUndo(moho, moho.layer, true)
		if params.newName ~= nil and tostring(params.newName) ~= "" then
			local nn = tostring(params.newName)
			if not st.SetName then
				return nil, "M_Style:SetName is not available to rename style"
			end
			local okRen, errRen = pcall(function() st:SetName(nn) end)
			if not okRen then
				return nil, "Failed to rename style: " .. tostring(errRen)
			end
		end
		local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
		local warnings = styleTools.applyStyleProps(moho, st, params, frame, {
			name = iName,
			cycle = iCycle,
			v1 = iV1,
			v2 = iV2,
			interval = iInterval,
			opts = iOpts,
		})
		helpers.updateUI(moho)
		local freshSt = (idx >= 0 and doc.StyleByID) and styleTools.ensureMStyle(doc:StyleByID(idx)) or styleTools.ensureMStyle(st)
		return {
			updated = true,
			style = styleTools.serializeStyle(moho, freshSt, frame, idx),
			warnings = json.array(warnings),
		}
	elseif op == "delete" then
		local ref = params.styleId ~= nil and params.styleId or (params.styleUuid or params.styleName or params.name)
		local st, idx, stName = styleTools.resolveDocStyle(doc, ref)
		if not st then
			return nil, "Saved style not found: " .. tostring(ref)
		end
		local beforeCount = doc.CountStyles and doc:CountStyles() or 0
		local delFn = safeField(doc, "DeleteStyle")
		local remFn = safeField(doc, "RemoveStyle")
		if type(delFn) == "function" then
			helpers.prepUndo(moho, moho.layer, true)
			local okDel, errDel = pcall(function() return doc:DeleteStyle(idx >= 0 and idx or st) end)
			helpers.updateUI(moho)
			if okDel then
				return {
					deleted = true,
					styleName = stName,
					styleCount = doc.CountStyles and doc:CountStyles() or 0,
				}
			end
			return nil, "Failed to delete style: " .. tostring(errDel)
		elseif type(remFn) == "function" then
			helpers.prepUndo(moho, moho.layer, true)
			helpers.walkLayers(moho, function(l)
				pcall(function() doc:RemoveStyle(st, l) end)
			end)
			helpers.updateUI(moho)
			local afterCount = doc.CountStyles and doc:CountStyles() or 0
			if afterCount < beforeCount then
				return {
					deleted = true,
					unlinkedFromAllLayers = true,
					styleName = stName,
					styleCount = afterCount,
				}
			end
			return {
				deleted = false,
				unlinkedFromAllLayers = true,
				styleName = stName,
				styleCount = afterCount,
				warning = "MohoDoc:RemoveStyle unlinks style from layers; remove unused document style entry via Window > Style > Delete Unused Styles",
			}
		end
		return {
			deleted = false,
			supported = false,
			styleName = stName,
			warning = "MohoDoc does not expose DeleteStyle in Lua; delete manually in Window > Style",
		}
	elseif op == "delete_unused" then
		local used = collectUsedStyleKeys(moho)
		local unused = {}
		local unusedIndices = {}
		local count = doc.CountStyles and doc:CountStyles() or 0
		for i = 0, count - 1 do
			local st = styleTools.ensureMStyle(doc:StyleByID(i))
			if st then
				local name = styleTools.readStyleName(st)
				local uuid = helpers.readLmString(safeField(st, "fUUID"))
				local isUsed = (used[uuid] == true) or (used[name] == true)
				if (not isUsed) and doc.IsStyleUsed then
					helpers.walkLayers(moho, function(l)
						if not isUsed then
							local okU, resU = pcall(function() return doc:IsStyleUsed(st, l) end)
							if okU and resU == true then
								isUsed = true
							end
						end
					end)
				end
				if not isUsed then
					unused[#unused + 1] = { id = i, name = name, uuid = uuid }
					unusedIndices[#unusedIndices + 1] = i
				end
			end
		end
		if type(safeField(doc, "DeleteUnusedStyles")) == "function" then
			helpers.prepUndo(moho, moho.layer, true)
			local okDU, resDU = pcall(function() return doc:DeleteUnusedStyles() end)
			helpers.updateUI(moho)
			if okDU then
				return {
					deletedCount = type(resDU) == "number" and resDU or #unused,
					supported = true,
					unusedStyles = json.array(unused),
				}
			end
		end
		local delFn = safeField(doc, "DeleteStyle")
		if type(delFn) == "function" then
			helpers.prepUndo(moho, moho.layer, true)
			local deletedCount = 0
			for i = #unusedIndices, 1, -1 do
				local okD = pcall(function() doc:DeleteStyle(unusedIndices[i]) end)
				if okD then
					deletedCount = deletedCount + 1
				end
			end
			helpers.updateUI(moho)
			return {
				deletedCount = deletedCount,
				supported = true,
				unusedStyles = json.array(unused),
			}
		end
		return {
			deletedCount = 0,
			supported = false,
			unusedStyles = json.array(unused),
			warning = "MohoDoc does not expose DeleteStyle/DeleteUnusedStyles in Lua",
		}
	elseif op == "new_from_shape" then
		local layer, layerId, lerr = helpers.resolveLayer(moho, params)
		if not layer then
			return nil, lerr
		end
		local vl = moho:LayerAsVector(layer)
		if not vl then
			return nil, "Layer '" .. layer:Name() .. "' is not a VectorLayer"
		end
		local mesh = vl:Mesh()
		local srcShape, srcShapeId = nil, -1
		if params.shapeId ~= nil then
			local idx = math.floor(tonumber(params.shapeId))
			if idx >= 0 and idx < mesh:CountShapes() then
				srcShape = mesh:Shape(idx)
				srcShapeId = idx
			end
		elseif params.shapeName ~= nil then
			srcShape = mesh:ShapeByName(tostring(params.shapeName))
			if srcShape then
				srcShapeId = mesh:ShapeID(srcShape)
			end
		elseif mesh:CountShapes() > 0 then
			srcShape = mesh:Shape(0)
			srcShapeId = 0
		end
		if not srcShape then
			return nil, "Source shape not found (provide shapeId or shapeName)"
		end

		local countStyles = doc.CountStyles and doc:CountStyles() or 0
		local sName = srcShape:Name()
		local styleName = (params.name and params.name ~= "") and tostring(params.name)
			or ((sName ~= "" and sName) or ("Style_" .. tostring(countStyles + 1)))
		local existing = styleTools.resolveDocStyle(doc, styleName)
		if existing and params.overwrite ~= true then
			return nil, "Style already exists: " .. styleName .. " (use overwrite: true or a unique name)"
		end

		local docH = math.max(1, doc:Height())
		local srcProps = effectiveShapeStyleProps(srcShape, frame, docH)

		helpers.prepUndo(moho, layer, true)
		local st = styleTools.ensureMStyle(existing)
		if not st then
			local okAdd, added = pcall(function() return doc:AddStyle(styleName) end)
			st = styleTools.ensureMStyle((okAdd and added) and added or doc:Style(styleName))
		end
		if not st then
			return nil, "MohoDoc:AddStyle failed to create style: " .. styleName
		end

		if st.fFillCol then
			st.fFillCol:SetValue(frame, helpers.toRgbStruct(srcProps.fillColor))
		end
		if st.fLineCol then
			st.fLineCol:SetValue(frame, helpers.toRgbStruct(srcProps.strokeColor))
		end
		st.fLineWidth = srcProps.lineWidth
		st.fLineCaps = srcProps.lineCaps
		local defFill = (srcShape.fHasFill == true)
		if params.defineFillColor ~= nil then defFill = (params.defineFillColor == true) end
		local defLine = (srcShape.fHasOutline == true)
		if params.defineLineColor ~= nil then defLine = (params.defineLineColor == true) end
		local defLW = (srcShape.fHasOutline == true)
		if params.defineLineWidth ~= nil then defLW = (params.defineLineWidth == true) end
		pcall(function() st.fDefineFillCol = defFill end)
		pcall(function() st.fDefineLineCol = defLine end)
		pcall(function() st.fDefineLineWidth = defLW end)

		if srcProps.brushSourceStyle then
			local bs = srcProps.brushSourceStyle
			helpers.writeLmString(st, "fBrushName", helpers.readLmString(safeField(bs, "fBrushName")))
			local copyFields = {
				"fBrushSpacing",
				"fBrushJitter",
				"fBrushAlign",
				"fBrushRandomOrder",
				"fBrushMergedAlpha",
				"fBrushRandomize",
				"fBrushRandomInterval",
				"fBrushIsColor",
				"fBrushTint",
				"fBrushAngleDrift",
				"fBrushSizeVariationAmp",
				"fBrushSizeVariationScale",
				"fBrushHueDrift",
				"fBrushSatDrift",
				"fBrushValDrift",
			}
			for i = 1, #copyFields do
				local fn = copyFields[i]
				local val = safeField(bs, fn)
				if val ~= nil then
					pcall(function() st[fn] = val end)
				end
			end
		end

		local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params, nil)
		local warnings = styleTools.applyStyleProps(moho, st, params, frame, {
			name = iName,
			cycle = iCycle,
			v1 = iV1,
			v2 = iV2,
			interval = iInterval,
			opts = iOpts,
		})

		local stIdx = -1
		local stName = styleTools.readStyleName(st)
		local stUuid = helpers.readLmString(safeField(st, "fUUID"))
		_, stIdx, stName, stUuid = styleTools.resolveDocStyle(doc, stUuid ~= "" and stUuid or styleName)
		local bindKey = (stUuid ~= "" and stUuid) or styleName

		local scope = string.lower(tostring(params.scope or "document"))
		local matchFill = (srcShape.fHasFill == true)
		if params.matchFillColor ~= nil then matchFill = (params.matchFillColor == true) end
		local matchStroke = (srcShape.fHasOutline == true)
		if params.matchStrokeColor ~= nil then matchStroke = (params.matchStrokeColor == true) end
		local matchLW = (params.matchLineWidth == true)
		local matchBrush = (params.matchBrush == true)
		local colorTol = tonumber(params.colorTolerance) or 2
		local lwTolPx = tonumber(params.lineWidthTolerancePx) or 0.25
		local slot = (tonumber(params.styleSlot) == 2) and 2 or 1

		local matched = {}
		local function processVectorLayer(vLayer, vLayerId)
			local vl2 = moho:LayerAsVector(vLayer)
			local m2 = vl2 and vl2:Mesh() or nil
			if not m2 then
				return
			end
			local touched = false
			for si = 0, m2:CountShapes() - 1 do
				local cand = m2:Shape(si)
				local isMatch = (cand == srcShape)
				if not isMatch and scope ~= "shape_only" then
					local cp = effectiveShapeStyleProps(cand, frame, docH)
					isMatch = true
					if matchFill then
						if cand.fHasFill ~= srcShape.fHasFill then
							isMatch = false
						elseif srcShape.fHasFill and not colorsMatch(cp.fillColor, srcProps.fillColor, colorTol) then
							isMatch = false
						end
					end
					if isMatch and matchStroke then
						if cand.fHasOutline ~= srcShape.fHasOutline then
							isMatch = false
						elseif srcShape.fHasOutline and not colorsMatch(cp.strokeColor, srcProps.strokeColor, colorTol) then
							isMatch = false
						end
					end
					if isMatch and matchLW then
						if math.abs((cp.lineWidth - srcProps.lineWidth) * docH) > lwTolPx then
							isMatch = false
						end
					end
					if isMatch and matchBrush then
						if cp.brushName ~= srcProps.brushName then
							isMatch = false
						end
					end
				end
				if isMatch then
					styleTools.bindShapeStyle(doc, cand, slot, bindKey)
					touched = true
					matched[#matched + 1] = {
						layerId = vLayerId,
						layerName = vLayer:Name(),
						shapeId = si,
						shapeName = cand:Name(),
					}
				end
			end
			if touched then
				vLayer:UpdateCurFrame()
			end
		end

		if scope == "document" then
			helpers.walkLayers(moho, function(l, lid)
				if l:LayerType() == MOHO.LT_VECTOR then
					processVectorLayer(l, lid)
				end
			end)
		else
			processVectorLayer(layer, layerId)
		end

		helpers.updateUI(moho)
		local freshSt = (stIdx >= 0 and doc.StyleByID) and styleTools.ensureMStyle(doc:StyleByID(stIdx)) or styleTools.ensureMStyle(st)
		return {
			created = true,
			style = styleTools.serializeStyle(moho, freshSt, frame, stIdx),
			styleSlot = slot,
			scope = scope,
			matchedCount = #matched,
			matchedShapes = json.array(matched),
			sourceLayerId = layerId,
			sourceShapeId = srcShapeId,
			warnings = json.array(warnings),
		}
	end

	return nil, "Unsupported style operation (use list, create, update, delete, delete_unused, list_brushes, new_from_shape): " .. op
end

return styleTools
