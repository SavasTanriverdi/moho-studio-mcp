-- Skeleton, bone rigging, Vitruvian Bones (M_BoneGroup), and BoneLayer Wind/Gravity tools.
-- All APIs verified against Moho Pro 14.4 live introspection and official Moho 14.4 scripts.

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local bones = {}

local function resolveSkeleton(moho, params)
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, nil, -1, err
	end
	local boneLayer = moho:LayerAsBone(layer)
	if not boneLayer then
		return nil, nil, id, "Layer '" .. layer:Name() .. "' is not a BoneLayer"
	end
	local skel = boneLayer:Skeleton()
	if not skel then
		return nil, nil, id, "BoneLayer has no skeleton"
	end
	return skel, boneLayer, id, nil
end

local function resolveBoneIndex(skel, params)
	if params.boneId ~= nil then
		local idx = math.floor(tonumber(params.boneId))
		if idx < 0 or idx >= skel:CountBones() then
			return nil, -1, "boneId out of range: " .. tostring(idx)
		end
		return skel:Bone(idx), idx, nil
	end
	if params.boneName ~= nil then
		local target = tostring(params.boneName)
		for i = 0, skel:CountBones() - 1 do
			local b = skel:Bone(i)
			if b:Name() == target then
				return b, i, nil
			end
		end
		return nil, -1, "Bone not found: " .. target
	end
	return nil, -1, "boneId or boneName is required"
end

local function resolveOptionalBoneId(skel, idVal, nameVal)
	if nameVal ~= nil then
		local s = tostring(nameVal)
		if s == "" then
			return -1, nil
		end
		for i = 0, skel:CountBones() - 1 do
			if skel:Bone(i):Name() == s then
				return i, nil
			end
		end
		return nil, "Bone not found: " .. s
	end
	if idVal ~= nil then
		local pid = math.floor(tonumber(idVal))
		if pid < 0 then
			return -1, nil
		end
		if pid >= skel:CountBones() then
			return nil, "boneId out of range: " .. tostring(pid)
		end
		return pid, nil
	end
	return nil, nil
end

local function resolveGeometryRef(moho, boneLayer, ref)
	local srcLayer, _, lerr = helpers.resolveLayer(moho, ref)
	if not srcLayer then
		return nil, lerr
	end
	local localPt = LM.Vector2:new_local()
	localPt:Set(0, 0)
	if ref.pointId ~= nil then
		local vl = moho:LayerAsVector(srcLayer)
		if not vl then
			return nil, "pointId ref requires a VectorLayer: " .. srcLayer:Name()
		end
		local mesh = vl:Mesh()
		local pid = math.floor(tonumber(ref.pointId))
		if pid < 0 or pid >= mesh:CountPoints() then
			return nil, "Ref pointId out of range: " .. tostring(pid)
		end
		localPt:Set(mesh:Point(pid).fAnimPos:GetValue(0))
	elseif ref.shapeId ~= nil then
		local vl = moho:LayerAsVector(srcLayer)
		if not vl then
			return nil, "shapeId ref requires a VectorLayer: " .. srcLayer:Name()
		end
		local mesh = vl:Mesh()
		local sid = math.floor(tonumber(ref.shapeId))
		if sid < 0 or sid >= mesh:CountShapes() then
			return nil, "Ref shapeId out of range: " .. tostring(sid)
		end
		local sh = mesh:Shape(sid)
		local sumX, sumY, cnt = 0, 0, 0
		for pi = 0, mesh:CountPoints() - 1 do
			if sh:ContainsPoint(pi) then
				local p0 = mesh:Point(pi).fAnimPos:GetValue(0)
				sumX = sumX + p0.x
				sumY = sumY + p0.y
				cnt = cnt + 1
			end
		end
		if cnt > 0 then
			localPt:Set(sumX / cnt, sumY / cnt)
		end
	else
		local anchor = string.lower(tostring(ref.anchor or "center"))
		if anchor == "origin" then
			localPt:Set(srcLayer:Origin())
		else
			local bbox = srcLayer.Bounds and srcLayer:Bounds(0) or nil
			if bbox and bbox.fMin and bbox.fMax then
				local cx = (bbox.fMin.x + bbox.fMax.x) * 0.5
				local cy = (bbox.fMin.y + bbox.fMax.y) * 0.5
				if anchor == "top" then
					localPt:Set(cx, bbox.fMax.y)
				elseif anchor == "bottom" then
					localPt:Set(cx, bbox.fMin.y)
				elseif anchor == "left" then
					localPt:Set(bbox.fMin.x, cy)
				elseif anchor == "right" then
					localPt:Set(bbox.fMax.x, cy)
				elseif anchor == "top_left" then
					localPt:Set(bbox.fMin.x, bbox.fMax.y)
				elseif anchor == "top_right" then
					localPt:Set(bbox.fMax.x, bbox.fMax.y)
				elseif anchor == "bottom_left" then
					localPt:Set(bbox.fMin.x, bbox.fMin.y)
				elseif anchor == "bottom_right" then
					localPt:Set(bbox.fMax.x, bbox.fMin.y)
				else
					localPt:Set(cx, cy)
				end
			else
				localPt:Set(srcLayer:Origin())
			end
		end
	end

	local w3 = LM.Vector3:new_local()
	w3:Set(localPt.x, localPt.y, 0)
	local srcMat = LM.Matrix:new_local()
	if srcLayer.GetFullTransform then
		srcLayer:GetFullTransform(0, srcMat, nil)
		srcMat:Transform(w3)
	end
	if boneLayer.GetFullTransform then
		local boneMat = LM.Matrix:new_local()
		boneLayer:GetFullTransform(0, boneMat, nil)
		boneMat:Invert()
		boneMat:Transform(w3)
	end
	local outPt = LM.Vector2:new_local()
	outPt:Set(w3.x + (tonumber(ref.offsetX) or 0), w3.y + (tonumber(ref.offsetY) or 0))
	return outPt, nil
end

local function serializeBone(skel, b, idx, frame)
	local pos = b.fAnimPos:GetValue(frame)
	local ang = b.fAnimAngle:GetValue(frame)
	local scl = b.fAnimScale:GetValue(frame)
	local worldHead = LM.Vector2:new_local()
	local worldTail = LM.Vector2:new_local()
	worldHead:Set(0, 0)
	worldTail:Set(b.fLength, 0)
	local m = (frame == 0) and b.fRestMatrix or b.fMovedMatrix
	if m then
		m:Transform(worldHead)
		m:Transform(worldTail)
	end
	local posScale = b.fPosControlScale
	local angleWeight = b.AngleWeight and b:AngleWeight() or 1
	local posWeight = b.PosWeight and b:PosWeight() or 1
	local scaleWeight = b.ScaleWeight and b:ScaleWeight() or 1
	return {
		id = idx,
		name = b:Name(),
		parent = b.fParent,
		length = b.fLength,
		isPinBone = (b.fLength == 0),
		strength = b.fStrength,
		localPos = { x = pos.x, y = pos.y },
		offset = b.fOffset and { x = b.fOffset.x, y = b.fOffset.y } or { x = 0, y = 0 },
		worldHead = { x = worldHead.x, y = worldHead.y },
		worldTail = { x = worldTail.x, y = worldTail.y },
		angleDeg = math.deg(ang),
		scale = scl,
		selected = b.fSelected,
		shy = b.fShy or false,
		flipH = b.fFlipH and b.fFlipH:GetValue(frame) or false,
		flipV = b.fFlipV and b.fFlipV:GetValue(frame) or false,
		showLabel = b.IsLabelShowing and b:IsLabelShowing() or false,
		tags = b.Tags and b:Tags() or 0,
		constraints = b.fConstraints,
		minConstraintDeg = math.deg(b.fMinConstraint or 0),
		maxConstraintDeg = math.deg(b.fMaxConstraint or 0),
		scalingMode = b.fScalingMode or 0,
		squashStretch = (b.fScalingMode == 2),
		squashStretchScaling = b.fSquashStretchScaling or 1,
		maxAutoScaling = b.fMaxAutoScaling or 1,
		arcSolver = b.IsArcSolverEnabled and b:IsArcSolverEnabled() or false,
		targetBone = b.fTargetBone and b.fTargetBone:GetValue(frame) or -1,
		ignoredByIK = b.fIgnoredByIK or false,
		fixedAngle = b.fFixedAngle or false,
		controlConstraints = {
			angleParent = b.fAngleControlParent or -1,
			angleScale = b.fAngleControlScale or 1,
			angleDelay = b.fAngleControlDelay or 0,
			posParent = b.fPosControlParent or -1,
			posScale = posScale and { x = posScale.x, y = posScale.y } or { x = 1, y = 1 },
			posDelay = b.fPosControlDelay or 0,
			scaleParent = b.fScaleControlParent or -1,
			scaleScale = b.fScaleControlScale or 1,
			scaleDelay = b.fScaleControlDelay or 0,
		},
		dynamics = {
			enabled = b.fBoneDynamics and b.fBoneDynamics:GetValue(frame) or false,
			angle = b.fAngleDynamics or false,
			pos = b.fPosDynamics or false,
			scale = b.fScaleDynamics or false,
			wind = b.fWindDynamics or false,
			angleTorque = b.fAngleTorqueForce or 0,
			angleSpring = b.fAngleSpringForce or 0,
			angleDamping = b.fAngleDampingForce or 0,
			angleWeight = angleWeight,
			posTorque = b.fPosTorqueForce or 0,
			posSpring = b.fPosSpringForce or 0,
			posDamping = b.fPosDampingForce or 0,
			posWeight = posWeight,
			scaleTorque = b.fScaleTorqueForce or 0,
			scaleSpring = b.fScaleSpringForce or 0,
			scaleDamping = b.fScaleDampingForce or 0,
			scaleWeight = scaleWeight,
		},
	}
end

function bones.list(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local list = {}
	for i = 0, skel:CountBones() - 1 do
		list[#list + 1] = serializeBone(skel, skel:Bone(i), i, frame)
	end
	return {
		layerId = lid,
		layerName = layer:Name(),
		frame = frame,
		count = #list,
		bones = json.array(list),
	}
end

--- Create a bone using world coordinates (headX/Y, tailX/Y), geometry refs (headRef, tailRef), or local (x/y, angleDeg, length).
function bones.create(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local parentId = -1
	if params.parentBoneId ~= nil or params.parentBoneName ~= nil then
		local pid, perr = resolveOptionalBoneId(skel, params.parentBoneId, params.parentBoneName)
		if perr then
			return nil, perr
		end
		if pid ~= nil then
			parentId = pid
		end
	end

	local headRefPt, tailRefPt = nil, nil
	if type(params.headRef) == "table" then
		local rerr
		headRefPt, rerr = resolveGeometryRef(moho, layer, params.headRef)
		if not headRefPt then return nil, rerr end
	end
	if type(params.tailRef) == "table" then
		local rerr
		tailRefPt, rerr = resolveGeometryRef(moho, layer, params.tailRef)
		if not tailRefPt then return nil, rerr end
	end

	local hx = headRefPt and headRefPt.x or (params.headX ~= nil and tonumber(params.headX) or nil)
	local hy = headRefPt and headRefPt.y or (params.headY ~= nil and tonumber(params.headY) or nil)
	local tx = tailRefPt and tailRefPt.x or (params.tailX ~= nil and tonumber(params.tailX) or nil)
	local ty = tailRefPt and tailRefPt.y or (params.tailY ~= nil and tonumber(params.tailY) or nil)

	helpers.prepUndo(moho, layer, true)
	local bone = skel:AddBone(0)
	local newId = skel:CountBones() - 1
	bone.fParent = parentId
	bone.fAnimParent:SetValue(0, parentId)

	if params.name then
		bone:SetName(tostring(params.name))
	end

	local isPin = (params.pinBone == true)

	if hx ~= nil and hy ~= nil and tx ~= nil and ty ~= nil then
		local headW = LM.Vector2:new_local()
		local tailW = LM.Vector2:new_local()
		headW:Set(hx, hy)
		tailW:Set(tx, ty)
		if parentId >= 0 then
			local inv = LM.Matrix:new_local()
			inv:Set(skel:Bone(parentId).fRestMatrix)
			inv:Invert()
			inv:Transform(headW)
			inv:Transform(tailW)
		end
		local dx = tailW.x - headW.x
		local dy = tailW.y - headW.y
		local dist = math.sqrt(dx * dx + dy * dy)
		bone.fAnimPos:SetValue(0, headW)
		if isPin or dist < 1e-6 then
			isPin = true
			bone.fAnimAngle:SetValue(0, math.rad(tonumber(params.angleDeg) or 0))
			bone.fLength = 0
		else
			bone.fAnimAngle:SetValue(0, math.atan(dy, dx))
			bone.fLength = dist
		end
	elseif hx ~= nil and hy ~= nil then
		local headW = LM.Vector2:new_local()
		headW:Set(hx, hy)
		if parentId >= 0 then
			local inv = LM.Matrix:new_local()
			inv:Set(skel:Bone(parentId).fRestMatrix)
			inv:Invert()
			inv:Transform(headW)
		end
		bone.fAnimPos:SetValue(0, headW)
		bone.fAnimAngle:SetValue(0, math.rad(tonumber(params.angleDeg) or 0))
		if isPin then
			bone.fLength = 0
		elseif params.length ~= nil then
			local lenVal = math.max(0.0, tonumber(params.length) or 0)
			bone.fLength = lenVal
			if lenVal == 0 then isPin = true end
		else
			bone.fLength = 0.25
		end
	else
		local pos = LM.Vector2:new_local()
		pos:Set(tonumber(params.x) or 0, tonumber(params.y) or 0)
		bone.fAnimPos:SetValue(0, pos)
		bone.fAnimAngle:SetValue(0, math.rad(tonumber(params.angleDeg) or 0))
		if isPin then
			bone.fLength = 0
		elseif params.length ~= nil then
			local lenVal = math.max(0.0, tonumber(params.length) or 0)
			bone.fLength = lenVal
			if lenVal == 0 then
				isPin = true
			end
		else
			bone.fLength = 0.25
		end
	end

	if params.scale ~= nil then
		bone.fAnimScale:SetValue(0, tonumber(params.scale) or 1)
	end
	bone.fStrength = (params.strength ~= nil) and math.max(0.0, tonumber(params.strength) or 0) or (isPin and 0.0 or 0.35)
	if params.tags ~= nil and bone.SetTags then
		bone:SetTags(math.floor(tonumber(params.tags)))
	end

	skel:UpdateBoneMatrix(newId)
	helpers.updateUI(moho)
	return serializeBone(skel, bone, newId, 0)
end

function bones.deleteBone(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local bone, idx, berr = resolveBoneIndex(skel, params)
	if not bone then
		return nil, berr
	end
	helpers.prepUndo(moho, layer, true)
	local name = bone:Name()
	skel:DeleteBone(idx)
	helpers.updateUI(moho)
	return { deleted = true, layerId = lid, boneId = idx, name = name }
end

function bones.setTransform(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local bone, idx, berr = resolveBoneIndex(skel, params)
	if not bone then
		return nil, berr
	end
	local pid, perr = resolveOptionalBoneId(skel, params.parentBoneId, params.parentBoneName)
	if perr then return nil, perr end
	local tid, terr = resolveOptionalBoneId(skel, params.targetBone, params.targetBoneName)
	if terr then return nil, terr end

	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	helpers.prepUndo(moho, layer, false)

	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)
	if params.x ~= nil or params.y ~= nil then
		local cur = bone.fAnimPos:GetValue(frame)
		local v = LM.Vector2:new_local()
		v:Set(
			params.x ~= nil and tonumber(params.x) or cur.x,
			params.y ~= nil and tonumber(params.y) or cur.y
		)
		bone.fAnimPos:SetValue(frame, v)
		helpers.applyKeyInterp(bone.fAnimPos, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.angleDeg ~= nil then
		bone.fAnimAngle:SetValue(frame, math.rad(tonumber(params.angleDeg)))
		helpers.applyKeyInterp(bone.fAnimAngle, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.scale ~= nil then
		bone.fAnimScale:SetValue(frame, tonumber(params.scale))
		helpers.applyKeyInterp(bone.fAnimScale, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.flipH ~= nil and bone.fFlipH then
		bone.fFlipH:SetValue(frame, params.flipH == true)
		helpers.applyKeyInterp(bone.fFlipH, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.flipV ~= nil and bone.fFlipV then
		bone.fFlipV:SetValue(frame, params.flipV == true)
		helpers.applyKeyInterp(bone.fFlipV, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if pid ~= nil then
		if frame == 0 then
			bone.fParent = pid
		end
		if bone.fAnimParent then
			bone.fAnimParent:SetValue(frame, pid)
			helpers.applyKeyInterp(bone.fAnimParent, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
		end
	end
	if tid ~= nil and bone.fTargetBone then
		bone.fTargetBone:SetValue(frame, tid)
		helpers.applyKeyInterp(bone.fTargetBone, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end

	skel:UpdateBoneMatrix(idx)
	helpers.updateUI(moho)
	return serializeBone(skel, bone, idx, frame)
end

function bones.setProperties(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local bone, idx, berr = resolveBoneIndex(skel, params)
	if not bone then
		return nil, berr
	end
	local pid, perr = resolveOptionalBoneId(skel, params.parentBoneId, params.parentBoneName)
	if perr then return nil, perr end
	local tid, terr = resolveOptionalBoneId(skel, params.targetBone, params.targetBoneName)
	if terr then return nil, terr end

	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or 0
	helpers.prepUndo(moho, layer, false)
	if params.name ~= nil then bone:SetName(tostring(params.name)) end
	if params.length ~= nil then bone.fLength = math.max(0.0, tonumber(params.length) or 0) end
	if params.strength ~= nil then bone.fStrength = math.max(0.0, tonumber(params.strength)) end
	if params.ignoredByIK ~= nil then bone.fIgnoredByIK = (params.ignoredByIK == true) end
	if params.fixedAngle ~= nil then bone.fFixedAngle = (params.fixedAngle == true) end
	if params.shy ~= nil then
		bone.fShy = (params.shy == true)
		bone.fHidden = bone.fShy
	end
	if params.showLabel ~= nil and bone.ShowLabel then
		bone:ShowLabel(params.showLabel == true)
	end
	if params.flipH ~= nil and bone.fFlipH then
		bone.fFlipH:SetValue(frame, params.flipH == true)
	end
	if params.flipV ~= nil and bone.fFlipV then
		bone.fFlipV:SetValue(frame, params.flipV == true)
	end
	if type(params.offset) == "table" and bone.fOffset then
		bone.fOffset:Set(
			params.offset.x ~= nil and tonumber(params.offset.x) or bone.fOffset.x,
			params.offset.y ~= nil and tonumber(params.offset.y) or bone.fOffset.y
		)
	end
	if tid ~= nil and bone.fTargetBone then
		bone.fTargetBone:SetValue(frame, tid)
	end
	if pid ~= nil then
		if frame == 0 then
			bone.fParent = pid
		end
		if bone.fAnimParent then
			bone.fAnimParent:SetValue(frame, pid)
		end
	end
	if params.tags ~= nil and bone.SetTags then
		bone:SetTags(math.floor(tonumber(params.tags)))
	end
	skel:UpdateBoneMatrix(idx)
	helpers.updateUI(moho)
	return serializeBone(skel, bone, idx, params.frame ~= nil and frame or moho.frame)
end

function bones.setConstraints(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end

	-- Delayed-constraint chain mode for hair, tails, and secondary motion
	if type(params.chainBoneIds) == "table" or type(params.chainBoneNames) == "table" then
		local chainIds = {}
		if type(params.chainBoneIds) == "table" then
			for i = 1, #params.chainBoneIds do
				local bi = math.floor(tonumber(params.chainBoneIds[i]))
				if bi < 0 or bi >= skel:CountBones() then
					return nil, "chainBoneIds entry out of range: " .. tostring(bi)
				end
				chainIds[#chainIds + 1] = bi
			end
		else
			for i = 1, #params.chainBoneNames do
				local _, bi, berr = resolveBoneIndex(skel, { boneName = params.chainBoneNames[i] })
				if not bi or berr then return nil, berr end
				chainIds[#chainIds + 1] = bi
			end
		end
		if #chainIds == 0 then
			return nil, "Provide non-empty chainBoneIds or chainBoneNames"
		end
		local ctrlOverride, cerr = resolveOptionalBoneId(skel, params.controlParentId, params.controlParentName)
		if cerr then return nil, cerr end

		local cMode = string.lower(tostring(params.chainMode or "angle"))
		local aScale = tonumber(params.chainScale or params.angleControlScale) or 1.0
		local aDelay = math.floor(tonumber(params.chainDelay or params.angleControlDelay) or 2)
		local pScaleX, pScaleY
		if type(params.posControlScale) == "table" then
			pScaleX = tonumber(params.posControlScale.x) or 1.0
			pScaleY = tonumber(params.posControlScale.y) or 1.0
		else
			local ps = tonumber(params.posControlScale or params.chainScale) or 1.0
			pScaleX, pScaleY = ps, ps
		end
		local pDelay = math.floor(tonumber(params.posControlDelay or params.chainDelay) or aDelay)
		local sScale = tonumber(params.scaleControlScale or params.chainScale) or 1.0
		local sDelay = math.floor(tonumber(params.scaleControlDelay or params.chainDelay) or aDelay)

		helpers.prepUndo(moho, layer, true)
		local updated = {}
		for i = 1, #chainIds do
			local bi = chainIds[i]
			local b = skel:Bone(bi)
			local cp = (ctrlOverride ~= nil) and ctrlOverride or b.fParent
			if cp >= 0 and cp ~= bi then
				if cMode == "angle" or cMode == "all" then
					b.fAngleControlParent = cp
					b.fAngleControlScale = aScale
					b.fAngleControlDelay = aDelay
				end
				if cMode == "pos" or cMode == "all" then
					b.fPosControlParent = cp
					if b.fPosControlScale then b.fPosControlScale:Set(pScaleX, pScaleY) end
					b.fPosControlDelay = pDelay
				end
				if cMode == "scale" or cMode == "all" then
					b.fScaleControlParent = cp
					b.fScaleControlScale = sScale
					b.fScaleControlDelay = sDelay
				end
				skel:UpdateBoneMatrix(bi)
				updated[#updated + 1] = serializeBone(skel, b, bi, moho.frame)
			end
		end
		helpers.updateUI(moho)
		return {
			layerId = lid,
			layerName = layer:Name(),
			chainMode = cMode,
			updatedCount = #updated,
			bones = json.array(updated),
		}
	end

	local bone, idx, berr = resolveBoneIndex(skel, params)
	if not bone then
		return nil, berr
	end
	local acp, acErr = resolveOptionalBoneId(skel, params.angleControlParent, params.angleControlParentName)
	if acErr then return nil, acErr end
	local pcp, pcErr = resolveOptionalBoneId(skel, params.posControlParent, params.posControlParentName)
	if pcErr then return nil, pcErr end
	local scp, scErr = resolveOptionalBoneId(skel, params.scaleControlParent, params.scaleControlParentName)
	if scErr then return nil, scErr end

	helpers.prepUndo(moho, layer, false)
	if params.enabled ~= nil then bone.fConstraints = (params.enabled == true) end
	if params.minDeg ~= nil then bone.fMinConstraint = math.rad(tonumber(params.minDeg)) end
	if params.maxDeg ~= nil then bone.fMaxConstraint = math.rad(tonumber(params.maxDeg)) end
	if acp ~= nil then bone.fAngleControlParent = acp end
	if params.angleControlScale ~= nil then bone.fAngleControlScale = tonumber(params.angleControlScale) end
	if params.angleControlDelay ~= nil then bone.fAngleControlDelay = math.floor(tonumber(params.angleControlDelay)) end
	if pcp ~= nil then bone.fPosControlParent = pcp end
	if params.posControlScale ~= nil and bone.fPosControlScale then
		if type(params.posControlScale) == "table" then
			bone.fPosControlScale:Set(
				params.posControlScale.x ~= nil and tonumber(params.posControlScale.x) or bone.fPosControlScale.x,
				params.posControlScale.y ~= nil and tonumber(params.posControlScale.y) or bone.fPosControlScale.y
			)
		else
			local ps = tonumber(params.posControlScale) or 1.0
			bone.fPosControlScale:Set(ps, ps)
		end
	end
	if params.posControlDelay ~= nil then bone.fPosControlDelay = math.floor(tonumber(params.posControlDelay)) end
	if scp ~= nil then bone.fScaleControlParent = scp end
	if params.scaleControlScale ~= nil then bone.fScaleControlScale = tonumber(params.scaleControlScale) end
	if params.scaleControlDelay ~= nil then bone.fScaleControlDelay = math.floor(tonumber(params.scaleControlDelay)) end
	if params.squashStretch ~= nil then
		bone.fScalingMode = (params.squashStretch == true) and 2 or 0
	end
	if params.squashStretchScaling ~= nil then
		bone.fSquashStretchScaling = tonumber(params.squashStretchScaling)
	end
	local ikStretch = (params.maxIKStretching ~= nil) and params.maxIKStretching or params.maxAutoScaling
	if ikStretch ~= nil then
		bone.fMaxAutoScaling = tonumber(ikStretch)
	end
	if params.arcSolver ~= nil and bone.EnableArcSolver then
		bone:EnableArcSolver(params.arcSolver == true)
	end
	skel:UpdateBoneMatrix(idx)
	helpers.updateUI(moho)
	return serializeBone(skel, bone, idx, moho.frame)
end

function bones.setDynamics(moho, params)
	if params.enableBoneDynamics ~= nil and MOHO and MOHO.MohoGlobals then
		MOHO.MohoGlobals.EnableBoneDynamics = (params.enableBoneDynamics == true)
	end
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		if params.enableBoneDynamics ~= nil and params.layerId == nil and params.layerName == nil then
			helpers.updateUI(moho)
			return {
				globalBoneDynamicsEnabled = MOHO and MOHO.MohoGlobals and (MOHO.MohoGlobals.EnableBoneDynamics == true) or true,
			}
		end
		return nil, err
	end
	if params.boneId == nil and params.boneName == nil and params.enableBoneDynamics ~= nil then
		helpers.updateUI(moho)
		return {
			layerId = lid,
			layerName = layer:Name(),
			globalBoneDynamicsEnabled = MOHO and MOHO.MohoGlobals and (MOHO.MohoGlobals.EnableBoneDynamics == true) or true,
		}
	end
	local bone, idx, berr = resolveBoneIndex(skel, params)
	if not bone then
		return nil, berr
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or 0
	helpers.prepUndo(moho, layer, false)
	if params.enabled ~= nil and bone.fBoneDynamics then
		bone.fBoneDynamics:SetValue(frame, params.enabled == true)
	end
	if params.angle ~= nil then bone.fAngleDynamics = (params.angle == true) end
	if params.pos ~= nil then bone.fPosDynamics = (params.pos == true) end
	if params.scale ~= nil then bone.fScaleDynamics = (params.scale == true) end
	if params.wind ~= nil then bone.fWindDynamics = (params.wind == true) end
	if params.torque ~= nil then bone.fAngleTorqueForce = tonumber(params.torque) end
	if params.spring ~= nil then bone.fAngleSpringForce = tonumber(params.spring) end
	if params.damping ~= nil then bone.fAngleDampingForce = tonumber(params.damping) end
	if params.angleWeight ~= nil and bone.SetAngleWeight then bone:SetAngleWeight(tonumber(params.angleWeight)) end
	if params.posTorque ~= nil then bone.fPosTorqueForce = tonumber(params.posTorque) end
	if params.posSpring ~= nil then bone.fPosSpringForce = tonumber(params.posSpring) end
	if params.posDamping ~= nil then bone.fPosDampingForce = tonumber(params.posDamping) end
	if params.posWeight ~= nil and bone.SetPosWeight then bone:SetPosWeight(tonumber(params.posWeight)) end
	if params.scaleTorque ~= nil then bone.fScaleTorqueForce = tonumber(params.scaleTorque) end
	if params.scaleSpring ~= nil then bone.fScaleSpringForce = tonumber(params.scaleSpring) end
	if params.scaleDamping ~= nil then bone.fScaleDampingForce = tonumber(params.scaleDamping) end
	if params.scaleWeight ~= nil and bone.SetScaleWeight then bone:SetScaleWeight(tonumber(params.scaleWeight)) end
	skel:UpdateBoneMatrix(idx)
	helpers.updateUI(moho)
	local out = serializeBone(skel, bone, idx, frame)
	out.globalBoneDynamicsEnabled = MOHO and MOHO.MohoGlobals and (MOHO.MohoGlobals.EnableBoneDynamics == true) or true
	return out
end

-- --- Vitruvian Bones (M_BoneGroup) ---

local function serializeBoneGroup(skel, grp, grpIdx, frame)
	-- Moho 14.4 tolua++ quirk: accessing grp.fActiveBone invalidates further method
	-- lookups on the same Lua grp handle. Always call all grp methods FIRST, read
	-- grp.fActiveBone ONCE into a local variable LAST, and re-fetch skel:Group(idx)
	-- after mutating fActiveBone.
	local gname = grp:Name()
	local enabled = (grp.fEnabled == true)
	local count = grp:CountBones()
	local memberIds = {}
	local memberNames = {}
	for i = 0, count - 1 do
		local b = grp:Bone(i)
		if b then
			memberIds[#memberIds + 1] = skel:BoneID(b)
			memberNames[#memberNames + 1] = b:Name()
		end
	end
	local activeBone = grp:ActiveBone()
	local activeBoneName = activeBone and activeBone:Name() or ""
	local activeBoneId = activeBone and skel:BoneID(activeBone) or -1
	local activeLocalIdx = 0
	local ch = grp.fActiveBone
	if ch and ch.GetValue then
		activeLocalIdx = ch:GetValue(frame)
	end
	return {
		groupIndex = grpIdx,
		name = gname,
		enabled = enabled,
		activeLocalIndex = activeLocalIdx,
		activeBoneName = activeBoneName,
		activeBoneId = activeBoneId,
		boneCount = count,
		boneIds = json.array(memberIds),
		boneNames = json.array(memberNames),
	}
end

function bones.listGroups(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	local groups = {}
	for i = 0, skel:CountGroups() - 1 do
		groups[#groups + 1] = serializeBoneGroup(skel, skel:Group(i), i, frame)
	end
	return {
		layerId = lid,
		layerName = layer:Name(),
		frame = frame,
		count = #groups,
		groups = json.array(groups),
	}
end

function bones.manageGroup(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local op = string.lower(tostring(params.operation or "create"))
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	local function resolveGroup()
		if params.groupIndex ~= nil then
			local gi = math.floor(tonumber(params.groupIndex))
			if gi < 0 or gi >= skel:CountGroups() then
				return nil, -1, "groupIndex out of range"
			end
			return skel:Group(gi), gi, nil
		end
		if params.groupName ~= nil then
			local target = tostring(params.groupName)
			for i = 0, skel:CountGroups() - 1 do
				local g = skel:Group(i)
				if g:Name() == target then
					return g, i, nil
				end
			end
			return nil, -1, "Bone group not found: " .. target
		end
		return nil, -1, "groupIndex or groupName is required"
	end

	helpers.prepUndo(moho, layer, true)
	skel:MarkGroupVisibilityUnknown()

	if op == "create" then
		local boneIds = params.boneIds
		if type(boneIds) ~= "table" or #boneIds < 2 then
			return nil, "boneIds array with at least 2 bone indices is required to create a Vitruvian Bone group"
		end
		local grp = skel:AddGroup(frame)
		local grpIdx = skel:CountGroups() - 1
		grp:SetName(tostring(params.groupName or ("Group " .. tostring(skel:CountGroups()))))
		for i = 1, #boneIds do
			local bid = math.floor(tonumber(boneIds[i]))
			if bid >= 0 and bid < skel:CountBones() then
				grp:AddBone(bid)
			end
		end
		if params.enabled ~= nil then
			grp.fEnabled = (params.enabled == true)
		end
		local activeLocal = math.max(0, math.floor(tonumber(params.activeLocalIndex) or 0))
		local ch = grp.fActiveBone
		if ch and ch.SetValue then
			ch:SetValue(frame, activeLocal)
		end
		skel:MarkGroupVisibilityUnknown()
		helpers.updateUI(moho)
		-- Re-fetch fresh handle after touching grp.fActiveBone (Moho 14.4 tolua++ quirk)
		return serializeBoneGroup(skel, skel:Group(grpIdx), grpIdx, frame)
	elseif op == "set_active" then
		local grp, gi, gerr = resolveGroup()
		if not grp then return nil, gerr end
		local localIdx = params.activeLocalIndex
		if localIdx == nil and params.boneId ~= nil then
			local wantId = math.floor(tonumber(params.boneId))
			for i = 0, grp:CountBones() - 1 do
				if skel:BoneID(grp:Bone(i)) == wantId then
					localIdx = i
					break
				end
			end
		elseif localIdx == nil and params.boneName ~= nil then
			local wantName = tostring(params.boneName)
			for i = 0, grp:CountBones() - 1 do
				if grp:Bone(i):Name() == wantName then
					localIdx = i
					break
				end
			end
		end
		if localIdx == nil then
			return nil, "Provide activeLocalIndex, boneId, or boneName belonging to the group"
		end
		if params.enabled ~= nil then
			grp.fEnabled = (params.enabled == true)
		end
		local ch = grp.fActiveBone
		if ch and ch.SetValue then
			ch:SetValue(frame, math.floor(tonumber(localIdx)))
		end
		skel:MarkGroupVisibilityUnknown()
		moho:SetCurFrame(moho.frame)
		helpers.updateUI(moho)
		return serializeBoneGroup(skel, skel:Group(gi), gi, frame)
	elseif op == "add_bones" then
		local grp, gi, gerr = resolveGroup()
		if not grp then return nil, gerr end
		for i = 1, #(params.boneIds or {}) do
			local bid = math.floor(tonumber(params.boneIds[i]))
			if bid >= 0 and bid < skel:CountBones() then
				grp:AddBone(bid)
			end
		end
		skel:MarkGroupVisibilityUnknown()
		helpers.updateUI(moho)
		return serializeBoneGroup(skel, skel:Group(gi), gi, frame)
	elseif op == "remove_bones" then
		local grp, gi, gerr = resolveGroup()
		if not grp then return nil, gerr end
		for i = 1, #(params.boneIds or {}) do
			local bid = math.floor(tonumber(params.boneIds[i]))
			grp:RemoveBone(bid)
		end
		skel:MarkGroupVisibilityUnknown()
		helpers.updateUI(moho)
		return serializeBoneGroup(skel, skel:Group(gi), gi, frame)
	elseif op == "delete" then
		local grp, gi, gerr = resolveGroup()
		if not grp then return nil, gerr end
		local name = grp:Name()
		skel:DeleteGroup(grp)
		skel:MarkGroupVisibilityUnknown()
		helpers.updateUI(moho)
		return { deleted = true, groupIndex = gi, name = name }
	end

	return nil, "Unsupported Vitruvian Bone operation: " .. op
end

-- --- Wind & Gravity Dynamics on BoneLayer ---

function bones.setWind(moho, params)
	local skel, boneLayer, lid, err = resolveSkeleton(moho, params)
	if not boneLayer then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	helpers.prepUndo(moho, boneLayer, false)

	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)

	if params.windDirectionDeg ~= nil and boneLayer.fWindDirection then
		boneLayer.fWindDirection:SetValue(frame, math.rad(tonumber(params.windDirectionDeg)))
		helpers.applyKeyInterp(boneLayer.fWindDirection, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if (params.windStrengthPercent ~= nil or params.windStrength ~= nil) and boneLayer.fWindStrength then
		local rawWind = (params.windStrengthPercent ~= nil)
			and ((tonumber(params.windStrengthPercent) / 100.0) * 500.0)
			or tonumber(params.windStrength)
		boneLayer.fWindStrength:SetValue(frame, rawWind)
		helpers.applyKeyInterp(boneLayer.fWindStrength, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if (params.turbulentAmplitudePercent ~= nil or params.turbulentAmplitude ~= nil) and boneLayer.fWindTurbulentAmplitude then
		local rawAmp = (params.turbulentAmplitudePercent ~= nil)
			and ((tonumber(params.turbulentAmplitudePercent) / 100.0) * 2.0)
			or tonumber(params.turbulentAmplitude)
		boneLayer.fWindTurbulentAmplitude:SetValue(frame, rawAmp)
		helpers.applyKeyInterp(boneLayer.fWindTurbulentAmplitude, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if (params.turbulentFrequencyPercent ~= nil or params.turbulentFrequency ~= nil) and boneLayer.fWindTurbulentFrequency then
		local rawFreq = (params.turbulentFrequencyPercent ~= nil)
			and ((tonumber(params.turbulentFrequencyPercent) / 100.0) * 10.0)
			or tonumber(params.turbulentFrequency)
		boneLayer.fWindTurbulentFrequency:SetValue(frame, rawFreq)
		helpers.applyKeyInterp(boneLayer.fWindTurbulentFrequency, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if params.gravityDirectionDeg ~= nil and boneLayer.fGravityDirection then
		boneLayer.fGravityDirection:SetValue(frame, math.rad(tonumber(params.gravityDirectionDeg)))
		helpers.applyKeyInterp(boneLayer.fGravityDirection, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end
	if (params.gravityStrengthPercent ~= nil or params.gravityStrength ~= nil) and boneLayer.fGravityStrength then
		local rawGrav = (params.gravityStrengthPercent ~= nil)
			and ((tonumber(params.gravityStrengthPercent) / 100.0) * 10.0)
			or tonumber(params.gravityStrength)
		boneLayer.fGravityStrength:SetValue(frame, rawGrav)
		helpers.applyKeyInterp(boneLayer.fGravityStrength, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
	end

	boneLayer:UpdateCurFrame()
	helpers.updateUI(moho)
	local ws = boneLayer.fWindStrength and boneLayer.fWindStrength:GetValue(frame) or 0
	local ta = boneLayer.fWindTurbulentAmplitude and boneLayer.fWindTurbulentAmplitude:GetValue(frame) or 0
	local tf = boneLayer.fWindTurbulentFrequency and boneLayer.fWindTurbulentFrequency:GetValue(frame) or 0
	local gs = boneLayer.fGravityStrength and boneLayer.fGravityStrength:GetValue(frame) or 0
	return {
		layerId = lid,
		layerName = boneLayer:Name(),
		frame = frame,
		windDirectionDeg = boneLayer.fWindDirection and math.deg(boneLayer.fWindDirection:GetValue(frame)) or 0,
		windStrength = ws,
		windStrengthPercent = (ws / 500.0) * 100.0,
		turbulentAmplitude = ta,
		turbulentAmplitudePercent = (ta / 2.0) * 100.0,
		turbulentFrequency = tf,
		turbulentFrequencyPercent = (tf / 10.0) * 100.0,
		gravityDirectionDeg = boneLayer.fGravityDirection and math.deg(boneLayer.fGravityDirection:GetValue(frame)) or 0,
		gravityStrength = gs,
		gravityStrengthPercent = (gs / 10.0) * 100.0,
	}
end

local function mirrorBoneName(name, findSub, repSub)
	local s = tostring(name or "")
	if findSub and repSub and #findSub > 0 then
		local out = s:gsub(findSub:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"), repSub)
		if out ~= s then
			return out
		end
	end
	local pairsList = {
		{ "_L$", "_R" }, { "_R$", "_L" },
		{ "%.L$", ".R" }, { "%.R$", ".L" },
		{ " L$", " R" }, { " R$", " L" },
		{ "^L_", "R_" }, { "^R_", "L_" },
		{ "Left", "Right" }, { "Right", "Left" },
		{ "left", "right" }, { "right", "left" },
	}
	for i = 1, #pairsList do
		local pat, rep = pairsList[i][1], pairsList[i][2]
		if s:find(pat) then
			local out = s:gsub(pat, rep, 1)
			if out ~= s then
				return out
			end
		end
	end
	return (#s > 0 and (s .. "_Mirror") or "MirrorBone")
end

function bones.mirror(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local rootIds = {}
	local rootSeen = {}
	local function addRoot(bid)
		if bid ~= nil and bid >= 0 and bid < skel:CountBones() and not rootSeen[bid] then
			rootSeen[bid] = true
			rootIds[#rootIds + 1] = bid
		end
	end
	if type(params.boneIds) == "table" then
		for i = 1, #params.boneIds do
			local bi = math.floor(tonumber(params.boneIds[i]))
			if bi < 0 or bi >= skel:CountBones() then return nil, "boneId out of range: " .. tostring(bi) end
			addRoot(bi)
		end
	elseif type(params.boneNames) == "table" then
		for i = 1, #params.boneNames do
			local _, bi, berr = resolveBoneIndex(skel, { boneName = params.boneNames[i] })
			if berr then return nil, berr end
			addRoot(bi)
		end
	else
		local _, bi, berr = resolveBoneIndex(skel, params)
		if berr then return nil, berr end
		addRoot(bi)
	end
	if #rootIds == 0 then
		return nil, "Provide boneId/boneName or boneIds/boneNames"
	end

	local includeChildren = (params.includeChildren ~= false)
	local ordered = {}
	local visited = {}
	local function collectSubtree(bid)
		if visited[bid] then return end
		visited[bid] = true
		ordered[#ordered + 1] = bid
		if includeChildren then
			for ci = 0, skel:CountBones() - 1 do
				if skel:Bone(ci).fParent == bid then
					collectSubtree(ci)
				end
			end
		end
	end
	for i = 1, #rootIds do
		collectSubtree(rootIds[i])
	end

	local axis = string.lower(tostring(params.axis or "x"))
	if axis ~= "x" and axis ~= "y" then
		return nil, "axis must be 'x' or 'y'"
	end
	local axisValue = tonumber(params.axisValue) or 0
	local mirrorParent = (params.mirrorParent ~= false)
	local mirrorConstraints = (params.mirrorConstraints ~= false)
	local mirrorTargets = (params.mirrorTargets ~= false)
	local keepExternalTargets = (params.keepExternalTargets == true)
	local findSub = params.findSubstring and tostring(params.findSubstring) or nil
	local repSub = params.replaceSubstring and tostring(params.replaceSubstring) or nil

	local function mirrorPt(pt)
		if axis == "x" then
			return 2 * axisValue - pt.x, pt.y
		end
		return pt.x, 2 * axisValue - pt.y
	end

	helpers.prepUndo(moho, layer, true)
	local idMap = {}
	local createdBones = {}
	local mapping = {}

	for i = 1, #ordered do
		local srcId = ordered[i]
		local sb = skel:Bone(srcId)
		local headLocal = LM.Vector2:new_local()
		local tailLocal = LM.Vector2:new_local()
		headLocal:Set(0, 0)
		tailLocal:Set(sb.fLength > 0 and sb.fLength or 1.0, 0)
		if sb.fRestMatrix then
			sb.fRestMatrix:Transform(headLocal)
			sb.fRestMatrix:Transform(tailLocal)
		end
		local mhX, mhY = mirrorPt(headLocal)
		local mtX, mtY = mirrorPt(tailLocal)

		local newParent = -1
		if idMap[sb.fParent] ~= nil then
			newParent = idMap[sb.fParent]
		elseif mirrorParent and sb.fParent >= 0 then
			newParent = sb.fParent
		end

		local nb = skel:AddBone(0)
		local nid = skel:CountBones() - 1
		idMap[srcId] = nid

		nb.fParent = newParent
		nb.fAnimParent:SetValue(0, newParent)
		local newName = mirrorBoneName(sb:Name(), findSub, repSub)
		nb:SetName(newName)

		local headW = LM.Vector2:new_local()
		local tailW = LM.Vector2:new_local()
		headW:Set(mhX, mhY)
		tailW:Set(mtX, mtY)
		if newParent >= 0 then
			local inv = LM.Matrix:new_local()
			inv:Set(skel:Bone(newParent).fRestMatrix)
			inv:Invert()
			inv:Transform(headW)
			inv:Transform(tailW)
		end
		local dx = tailW.x - headW.x
		local dy = tailW.y - headW.y
		nb.fAnimPos:SetValue(0, headW)
		if sb.fLength == 0 then
			nb.fLength = 0
			nb.fAnimAngle:SetValue(0, math.atan(dy, dx))
		else
			nb.fLength = math.sqrt(dx * dx + dy * dy)
			nb.fAnimAngle:SetValue(0, math.atan(dy, dx))
		end

		nb.fStrength = sb.fStrength
		nb.fAnimScale:SetValue(0, sb.fAnimScale:GetValue(0))
		nb.fShy = sb.fShy
		nb.fHidden = sb.fHidden
		nb.fFixedAngle = sb.fFixedAngle
		nb.fIgnoredByIK = sb.fIgnoredByIK
		nb.fScalingMode = sb.fScalingMode
		nb.fSquashStretchScaling = sb.fSquashStretchScaling
		nb.fMaxAutoScaling = sb.fMaxAutoScaling
		if nb.EnableArcSolver and sb.IsArcSolverEnabled then
			nb:EnableArcSolver(sb:IsArcSolverEnabled())
		end
		if nb.SetTags and sb.Tags then nb:SetTags(sb:Tags()) end
		if nb.ShowLabel and sb.IsLabelShowing then nb:ShowLabel(sb:IsLabelShowing()) end
		if sb.fOffset and nb.fOffset then
			local ox, oy = sb.fOffset.x, sb.fOffset.y
			if axis == "x" then ox = -ox else oy = -oy end
			nb.fOffset:Set(ox, oy)
		end

		if mirrorConstraints then
			nb.fConstraints = sb.fConstraints
			nb.fMinConstraint = -(sb.fMaxConstraint or 0)
			nb.fMaxConstraint = -(sb.fMinConstraint or 0)
			local acp = sb.fAngleControlParent
			nb.fAngleControlParent = (acp >= 0 and idMap[acp] ~= nil) and idMap[acp] or acp
			nb.fAngleControlScale = sb.fAngleControlScale
			nb.fAngleControlDelay = sb.fAngleControlDelay
			local pcp = sb.fPosControlParent
			nb.fPosControlParent = (pcp >= 0 and idMap[pcp] ~= nil) and idMap[pcp] or pcp
			if sb.fPosControlScale and nb.fPosControlScale then
				nb.fPosControlScale:Set(sb.fPosControlScale.x, sb.fPosControlScale.y)
			end
			nb.fPosControlDelay = sb.fPosControlDelay
			local scp = sb.fScaleControlParent
			nb.fScaleControlParent = (scp >= 0 and idMap[scp] ~= nil) and idMap[scp] or scp
			nb.fScaleControlScale = sb.fScaleControlScale
			nb.fScaleControlDelay = sb.fScaleControlDelay
		end

		if sb.fBoneDynamics and nb.fBoneDynamics then
			nb.fBoneDynamics:SetValue(0, sb.fBoneDynamics:GetValue(0))
		end
		nb.fAngleDynamics = sb.fAngleDynamics
		nb.fPosDynamics = sb.fPosDynamics
		nb.fScaleDynamics = sb.fScaleDynamics
		nb.fWindDynamics = sb.fWindDynamics
		nb.fAngleTorqueForce = sb.fAngleTorqueForce
		nb.fAngleSpringForce = sb.fAngleSpringForce
		nb.fAngleDampingForce = sb.fAngleDampingForce
		nb.fPosTorqueForce = sb.fPosTorqueForce
		nb.fPosSpringForce = sb.fPosSpringForce
		nb.fPosDampingForce = sb.fPosDampingForce
		nb.fScaleTorqueForce = sb.fScaleTorqueForce
		nb.fScaleSpringForce = sb.fScaleSpringForce
		nb.fScaleDampingForce = sb.fScaleDampingForce
		if nb.SetAngleWeight and sb.AngleWeight then nb:SetAngleWeight(sb:AngleWeight()) end
		if nb.SetPosWeight and sb.PosWeight then nb:SetPosWeight(sb:PosWeight()) end
		if nb.SetScaleWeight and sb.ScaleWeight then nb:SetScaleWeight(sb:ScaleWeight()) end

		skel:UpdateBoneMatrix(nid)
		mapping[#mapping + 1] = { sourceId = srcId, sourceName = sb:Name(), mirroredId = nid, mirroredName = newName }
	end

	if mirrorTargets then
		for i = 1, #ordered do
			local srcId = ordered[i]
			local nid = idMap[srcId]
			local sb = skel:Bone(srcId)
			local nb = skel:Bone(nid)
			if sb.fTargetBone and nb.fTargetBone then
				local tid = sb.fTargetBone:GetValue(0)
				if tid >= 0 then
					if idMap[tid] ~= nil then
						nb.fTargetBone:SetValue(0, idMap[tid])
					elseif keepExternalTargets then
						nb.fTargetBone:SetValue(0, tid)
					end
				end
			end
			skel:UpdateBoneMatrix(nid)
		end
	end

	for i = 1, #ordered do
		local nid = idMap[ordered[i]]
		createdBones[#createdBones + 1] = serializeBone(skel, skel:Bone(nid), nid, 0)
	end

	helpers.updateUI(moho)
	return {
		mirrored = true,
		layerId = lid,
		layerName = layer:Name(),
		axis = axis,
		axisValue = axisValue,
		count = #createdBones,
		mapping = json.array(mapping),
		bones = json.array(createdBones),
	}
end

function bones.freezePose(moho, params)
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local mode = string.lower(tostring(params.mode or "freeze"))
	if mode ~= "freeze" and mode ~= "reset" then
		return nil, "mode must be 'freeze' or 'reset'"
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame
	if mode == "freeze" and frame == 0 and params.allowFrame0 ~= true then
		return nil, "Refusing to freeze pose at frame 0 unless allowFrame0=true"
	end

	local targetIds = {}
	local targetSeen = {}
	local function addTarget(bi)
		if bi >= 0 and bi < skel:CountBones() and not targetSeen[bi] then
			targetSeen[bi] = true
			targetIds[#targetIds + 1] = bi
		end
	end
	if type(params.boneIds) == "table" then
		for i = 1, #params.boneIds do
			local bi = math.floor(tonumber(params.boneIds[i]))
			if bi < 0 or bi >= skel:CountBones() then return nil, "boneId out of range: " .. tostring(bi) end
			addTarget(bi)
		end
	elseif type(params.boneNames) == "table" then
		for i = 1, #params.boneNames do
			local _, bi, berr = resolveBoneIndex(skel, { boneName = params.boneNames[i] })
			if berr then return nil, berr end
			addTarget(bi)
		end
	else
		local scope = string.lower(tostring(params.scope or "all"))
		for i = 0, skel:CountBones() - 1 do
			local b = skel:Bone(i)
			if scope == "selected" then
				if b.fSelected then addTarget(i) end
			elseif scope == "non_shy" then
				if not b.fShy then addTarget(i) end
			else
				addTarget(i)
			end
		end
	end

	local chList = type(params.channels) == "table" and params.channels or { "angle", "pos", "scale" }
	local wantCh = {}
	for i = 1, #chList do
		wantCh[string.lower(tostring(chList[i]))] = true
	end
	local deleteKeys = (params.deleteKeys == true)
	local iName, iCycle, iV1, iV2, iInterval, iOpts = helpers.extractInterpArgs(params)

	helpers.prepUndo(moho, layer, false)
	for i = 1, #targetIds do
		local bi = targetIds[i]
		local b = skel:Bone(bi)
		local function handleCh(ch, zeroVal)
			if not ch then return end
			if mode == "reset" then
				if deleteKeys and frame > 0 then
					ch:DeleteKey(frame)
				else
					ch:SetValue(frame, zeroVal)
					helpers.applyKeyInterp(ch, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
				end
			else
				local curVal = ch:GetValue(frame)
				ch:SetValue(frame, curVal)
				helpers.applyKeyInterp(ch, frame, iName, iCycle, iV1, iV2, iInterval, iOpts)
			end
		end
		if wantCh["angle"] then
			handleCh(b.fAnimAngle, b.fAnimAngle:GetValue(0))
		end
		if wantCh["pos"] then
			local p0 = LM.Vector2:new_local()
			p0:Set(b.fAnimPos:GetValue(0))
			handleCh(b.fAnimPos, p0)
		end
		if wantCh["scale"] then
			handleCh(b.fAnimScale, b.fAnimScale:GetValue(0))
		end
		if wantCh["flip"] then
			handleCh(b.fFlipH, b.fFlipH and b.fFlipH:GetValue(0) or false)
			handleCh(b.fFlipV, b.fFlipV and b.fFlipV:GetValue(0) or false)
		end
		if wantCh["target"] then
			handleCh(b.fTargetBone, b.fTargetBone and b.fTargetBone:GetValue(0) or -1)
		end
		skel:UpdateBoneMatrix(bi)
	end

	layer:UpdateCurFrame()
	helpers.updateUI(moho)
	return {
		mode = mode,
		layerId = lid,
		layerName = layer:Name(),
		frame = frame,
		affectedBones = #targetIds,
		channels = json.array(chList),
	}
end

local function hasAxisDynamicsEnabled(ch)
	if ch == nil then return false end
	if type(ch) == "boolean" then return ch end
	if ch.GetValue then
		local ok, v = pcall(function() return ch:GetValue(0) end)
		return ok and (v == true)
	end
	return false
end

local function isBoneDynamicsActive(b)
	if not b or not b.fBoneDynamics then
		return false
	end
	if b.fBoneDynamics:GetValue(0) ~= true then
		return false
	end
	return hasAxisDynamicsEnabled(b.fAngleDynamics)
		or hasAxisDynamicsEnabled(b.fPosDynamics)
		or hasAxisDynamicsEnabled(b.fScaleDynamics)
		or hasAxisDynamicsEnabled(b.fWindDynamics)
end

--- Read-only Moho Pro 14.4 Rig Health Linter covering control bone strength, rigid-group traps,
--- Animated Layer Order Smart Bone collisions, active action leaks, unbound artwork, and dynamics pre-roll.
function bones.auditRig(moho, params)
	params = params or {}
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end

	local scopeLayerId = nil
	if params.layerId ~= nil or params.layerName ~= nil or params.layerUuid ~= nil then
		local scopeLayer, slid, serr = helpers.resolveLayer(moho, params)
		if not scopeLayer then
			return nil, serr
		end
		if scopeLayer:LayerType() ~= MOHO.LT_BONE then
			return nil, "Target layer '" .. scopeLayer:Name() .. "' is not a BoneLayer"
		end
		scopeLayerId = slid
	end

	local checkUnbound = (params.checkUnboundArtwork ~= false)
	local checkPreRoll = (params.checkDynamicsPreRoll ~= false)
	local strengthEps = tonumber(params.strengthEpsilon) or 0.001

	local allLayers = {}
	local childrenByParent = {}
	helpers.walkLayers(moho, function(layer, lid, parentId, depth)
		allLayers[lid] = {
			layer = layer,
			id = lid,
			parentId = parentId,
			depth = depth,
		}
		childrenByParent[parentId] = childrenByParent[parentId] or {}
		childrenByParent[parentId][#childrenByParent[parentId] + 1] = lid
	end)

	local function collectDescendants(rootId, out)
		local kids = childrenByParent[rootId]
		if not kids then return end
		for i = 1, #kids do
			local cid = kids[i]
			out[#out + 1] = cid
			collectDescendants(cid, out)
		end
	end

	local function hasExplicitPointBinding(layer)
		if layer:LayerType() ~= MOHO.LT_VECTOR then
			return false
		end
		local vl = moho:LayerAsVector(layer)
		local mesh = vl and vl:Mesh() or nil
		if not mesh then return false end
		for pi = 0, mesh:CountPoints() - 1 do
			local pt = mesh:Point(pi)
			if pt and pt.fParent ~= nil and pt.fParent >= 0 then
				return true
			end
		end
		return false
	end

	local issues = {}
	local stats = {
		boneLayers = 0,
		totalBones = 0,
		smartBoneActions = 0,
		bonesWithDynamics = 0,
		particleLayers = 0,
	}

	local targetBoneLayerIds = {}
	if scopeLayerId ~= nil then
		targetBoneLayerIds[1] = scopeLayerId
	else
		for lid = 0, #allLayers do
			local rec = allLayers[lid]
			if rec and rec.layer:LayerType() == MOHO.LT_BONE then
				targetBoneLayerIds[#targetBoneLayerIds + 1] = lid
			end
		end
	end

	-- Count ParticleLayers in scope (or document) for pre-roll check
	if scopeLayerId ~= nil then
		local desc = {}
		collectDescendants(scopeLayerId, desc)
		for i = 1, #desc do
			if allLayers[desc[i]].layer:LayerType() == MOHO.LT_PARTICLE then
				stats.particleLayers = stats.particleLayers + 1
			end
		end
	else
		for lid = 0, #allLayers do
			local rec = allLayers[lid]
			if rec and rec.layer:LayerType() == MOHO.LT_PARTICLE then
				stats.particleLayers = stats.particleLayers + 1
			end
		end
	end

	for idx = 1, #targetBoneLayerIds do
		local blId = targetBoneLayerIds[idx]
		local blLayer = allLayers[blId].layer
		local bl = moho:LayerAsBone(blLayer)
		local skel = bl and bl:Skeleton() or nil
		if bl and skel then
			stats.boneLayers = stats.boneLayers + 1
			local boneCount = skel:CountBones()
			stats.totalBones = stats.totalBones + boneCount

			-- 1. Check active action leak on BoneLayer
			local curAct = blLayer.CurrentAction and blLayer:CurrentAction() or ""
			if curAct ~= "" then
				issues[#issues + 1] = {
					severity = "warning",
					code = "active_action_not_mainline",
					layerId = blId,
					layerName = blLayer:Name(),
					actionName = curAct,
					message = "BoneLayer '" .. blLayer:Name() .. "' is currently editing Action '" .. curAct
						.. "' instead of Mainline; switch back via action_activate with actionName='' before rigging or animating.",
				}
			end

			-- Collect Smart Bone Actions and IK targets on this skeleton
			local smartActions = {}
			local smartBoneNames = {}
			if blLayer.CountActions then
				for ai = 0, blLayer:CountActions() - 1 do
					local aname = blLayer:ActionName(ai)
					if aname ~= "" and blLayer.IsSmartBoneAction and blLayer:IsSmartBoneAction(aname) then
						smartActions[#smartActions + 1] = aname
						smartBoneNames[aname] = true
						local baseName = aname:match("^(.-)%s+2$")
						if baseName then
							smartBoneNames[baseName] = true
						end
					end
				end
			end
			stats.smartBoneActions = stats.smartBoneActions + #smartActions

			local ikTargets = {}
			for bi = 0, boneCount - 1 do
				local b = skel:Bone(bi)
				if b and b.fTargetBone then
					local tid = b.fTargetBone:GetValue(0)
					if tid >= 0 and tid < boneCount then
						ikTargets[tid] = true
					end
				end
			end

			local strengthBearingBones = 0
			for bi = 0, boneCount - 1 do
				local b = skel:Bone(bi)
				if b then
					local bName = b:Name()
					local strength = b.fStrength or 0
					if strength > strengthEps then
						strengthBearingBones = strengthBearingBones + 1
					end
					if isBoneDynamicsActive(b) then
						stats.bonesWithDynamics = stats.bonesWithDynamics + 1
					end

					-- 2. Check non-zero strength on Pin Bones, IK Targets, and Smart Bone dials
					local roles = {}
					if (b.fLength or 0) <= 0.0001 then
						roles[#roles + 1] = "pin_bone"
					end
					if ikTargets[bi] then
						roles[#roles + 1] = "ik_target"
					end
					if smartBoneNames[bName] then
						roles[#roles + 1] = "smart_bone_dial"
					end
					if #roles > 0 and strength > strengthEps then
						issues[#issues + 1] = {
							severity = "error",
							code = "control_bone_nonzero_strength",
							layerId = blId,
							layerName = blLayer:Name(),
							boneId = bi,
							boneName = bName,
							strength = strength,
							roles = json.array(roles),
							message = "Control bone '" .. bName .. "' (" .. table.concat(roles, ", ")
								.. ") has bone strength " .. string.format("%.3f", strength)
								.. "; set strength=0 via bone_setProperties so it does not warp nearby artwork.",
						}
					end
					if smartBoneNames[bName] and b.fConstraints ~= true then
						issues[#issues + 1] = {
							severity = "info",
							code = "smart_dial_unconstrained",
							layerId = blId,
							layerName = blLayer:Name(),
							boneId = bi,
							boneName = bName,
							message = "Smart Bone dial '" .. bName .. "' has angle constraints disabled; consider enabling constraints matching its authored action angles.",
						}
					end
				end
			end

			-- Walk descendants of this BoneLayer
			local descendants = {}
			collectDescendants(blId, descendants)
			local rigidTrappedAncestor = {}

			-- Include the BoneLayer itself for Animated Layer Order collision check
			local groupCandidates = { blId }
			for i = 1, #descendants do
				groupCandidates[#groupCandidates + 1] = descendants[i]
			end

			for i = 1, #groupCandidates do
				local gid = groupCandidates[i]
				local glayer = allLayers[gid].layer
				if glayer:IsGroupType() then
					local grp = moho:LayerAsGroup(glayer)
					-- 3. Animated Layer Order collision across >= 2 Smart Bone Actions
					if grp and grp.GetLayerOrdering and #smartActions >= 2 then
						local orderCh = grp:GetLayerOrdering()
						if orderCh and orderCh.ActionByName then
							local colliding = {}
							for si = 1, #smartActions do
								local aname = smartActions[si]
								local actCh = orderCh:ActionByName(aname)
								if actCh and actCh.CountKeys and actCh:CountKeys() > 1 then
									colliding[#colliding + 1] = aname
								end
							end
							if #colliding >= 2 then
								issues[#issues + 1] = {
									severity = "warning",
									code = "animated_layer_order_collision",
									layerId = gid,
									layerName = glayer:Name(),
									boneLayerId = blId,
									actions = json.array(colliding),
									message = "Group '" .. glayer:Name() .. "' keyframes Animated Layer Order in "
										.. tostring(#colliding) .. " Smart Bone Actions (" .. table.concat(colliding, ", ")
										.. "); Moho layer order overrides do not blend across multiple Smart Bones.",
								}
							end
						end
					end

					-- 4. Rigid-bound GroupLayer trapping bone-bound descendants
					if gid ~= blId then
						local grpParentBone = glayer.LayerParentBone and glayer:LayerParentBone() or -1
						if grpParentBone >= 0 then
							local subDesc = {}
							collectDescendants(gid, subDesc)
							local trapped = {}
							for di = 1, #subDesc do
								local subId = subDesc[di]
								rigidTrappedAncestor[subId] = gid
								local subL = allLayers[subId].layer
								local subPb = subL.LayerParentBone and subL:LayerParentBone() or -1
								local subFlexi = helpers.getFlexiBoneIds(subL)
								local hasChildBind = (subPb >= 0) or (#subFlexi > 0) or (subL:LayerType() == MOHO.LT_BONE) or hasExplicitPointBinding(subL)
								if hasChildBind then
									trapped[#trapped + 1] = subL:Name()
								end
							end
							if #trapped > 0 then
								issues[#issues + 1] = {
									severity = "warning",
									code = "rigid_group_traps_children",
									layerId = gid,
									layerName = glayer:Name(),
									parentBone = grpParentBone,
									trappedChildren = json.array(trapped),
									message = "Group '" .. glayer:Name() .. "' is rigid-bound to boneId " .. tostring(grpParentBone)
										.. ", which locks " .. tostring(#trapped) .. " bone-bound child layer(s) ("
										.. table.concat(trapped, ", ") .. ") rigidly to that bone; unbind the group (boneId=-1) and bind children directly.",
								}
							end
						end
					end
				end
			end

			-- 5. Unbound / implicit-flexi artwork directly controlled by this BoneLayer
			if checkUnbound and boneCount > 0 then
				for i = 1, #descendants do
					local cid = descendants[i]
					local clayer = allLayers[cid].layer
					local clt = clayer:LayerType()
					if (clt == MOHO.LT_VECTOR or clt == MOHO.LT_IMAGE) and not rigidTrappedAncestor[cid] then
						local isEditOnly = clayer.IsEditOnly and (clayer:IsEditOnly() == true) or false
						local isWarpSelf = false
						if clt == MOHO.LT_VECTOR then
							local vl = moho:LayerAsVector(clayer)
							if vl and vl.IsWarpLayer and vl:IsWarpLayer() then
								isWarpSelf = true
							end
						end
						local hasWarp = clayer.GetWarpLayer and (clayer:GetWarpLayer() ~= nil) or false
						local ctrlSkel = clayer.ControllingSkeleton and clayer:ControllingSkeleton() or nil
						if (not isEditOnly) and (not isWarpSelf) and (not hasWarp) and ctrlSkel == skel then
							local pb = clayer.LayerParentBone and clayer:LayerParentBone() or -1
							local flexi = helpers.getFlexiBoneIds(clayer)
							local ptBound = hasExplicitPointBinding(clayer)
							if pb < 0 and #flexi == 0 and not ptBound then
								if strengthBearingBones == 0 then
									issues[#issues + 1] = {
										severity = "warning",
										code = "unbound_artwork_zero_strength_rig",
										layerId = cid,
										layerName = clayer:Name(),
										boneLayerId = blId,
										boneLayerName = blLayer:Name(),
										message = "Artwork layer '" .. clayer:Name() .. "' has no rigid, flexi-subset, or point binding and skeleton '"
											.. blLayer:Name() .. "' has zero strength-bearing bones; bind it via layer_bindToBone or point binding.",
									}
								else
									issues[#issues + 1] = {
										severity = "info",
										code = "implicit_global_flexi_bind",
										layerId = cid,
										layerName = clayer:Name(),
										boneLayerId = blId,
										boneLayerName = blLayer:Name(),
										message = "Artwork layer '" .. clayer:Name() .. "' uses global Flexi-Bind from all "
											.. tostring(strengthBearingBones) .. " strength-bearing bone(s); consider explicit flexiBoneIds, rigid boneId, or point binding.",
									}
								end
							end
						end
					end
				end
			end
		end
	end

	-- 6. Pre-roll check for active Bone Dynamics or ParticleLayers
	if checkPreRoll and (stats.bonesWithDynamics > 0 or stats.particleLayers > 0) then
		local startFrame = doc:StartFrame()
		if startFrame <= 1 then
			issues[#issues + 1] = {
				severity = "info",
				code = "dynamics_missing_preroll",
				startFrame = startFrame,
				bonesWithDynamics = stats.bonesWithDynamics,
				particleLayers = stats.particleLayers,
				message = "Scene has active simulation (" .. tostring(stats.bonesWithDynamics) .. " dynamic bone(s), "
					.. tostring(stats.particleLayers) .. " particle layer(s)) with startFrame=" .. tostring(startFrame)
					.. "; add settling pre-roll frames before shot start or render startFrame > 1 so dynamics settle naturally.",
			}
		end
	end

	local errCount, warnCount, infoCount = 0, 0, 0
	for i = 1, #issues do
		local sev = issues[i].severity
		if sev == "error" then errCount = errCount + 1
		elseif sev == "warning" then warnCount = warnCount + 1
		else infoCount = infoCount + 1 end
	end

	return {
		healthy = (errCount == 0 and warnCount == 0),
		documentName = doc:Name(),
		scopeLayerId = scopeLayerId,
		summary = {
			errors = errCount,
			warnings = warnCount,
			infos = infoCount,
			boneLayers = stats.boneLayers,
			totalBones = stats.totalBones,
			smartBoneActions = stats.smartBoneActions,
			bonesWithDynamics = stats.bonesWithDynamics,
			particleLayers = stats.particleLayers,
		},
		issues = json.array(issues),
	}
end

local function inferControlRole(name)
	local s = string.lower(tostring(name or ""))
	if s:find("blink") or s:find("eyelid") or s:find("wink") then return "blink" end
	if s:find("mouth") or s:find("jaw") or s:find("smile") or s:find("frown") or s:find("lip") or s:find("talk") then return "mouth" end
	if s:find("brow") then return "eyebrows" end
	if s:find("eye") or s:find("pupil") or s:find("gaze") or s:find("look") then return "eyes" end
	if s:find("head") then return "head_turn" end
	if s:find("body") or s:find("torso") or s:find("turn") then return "body_turn" end
	if s:find("hand") or s:find("finger") or s:find("fist") or s:find("grip") then return "hand" end
	if s:find("walk") or s:find("run") or s:find("stride") or s:find("step") then return "walk" end
	if s:find("arm") or s:find("elbow") or s:find("wrist") or s:find("shoulder") then return "arm" end
	if s:find("leg") or s:find("foot") or s:find("feet") or s:find("ankle") or s:find("knee") then return "leg" end
	return "custom"
end

--- Read-only Puppet Control Surface inspector for any Moho character rig.
--- Returns Smart Bone Dials (with exact action sweep angles and limits), IK Targets,
--- Pin Bones, SwitchLayer controls, Vitruvian Bone groups, and Regular Actions.
function bones.getControls(moho, params)
	params = params or {}
	local doc = moho.document
	if not doc then
		return nil, "No document open"
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or moho.frame

	local scopeLayerId = nil
	if params.layerId ~= nil or params.layerName ~= nil or params.layerUuid ~= nil then
		local scopeLayer, slid, serr = helpers.resolveLayer(moho, params)
		if not scopeLayer then
			return nil, serr
		end
		if scopeLayer:LayerType() ~= MOHO.LT_BONE then
			return nil, "Target layer '" .. scopeLayer:Name() .. "' is not a BoneLayer"
		end
		scopeLayerId = slid
	end

	local allLayers = {}
	local childrenByParent = {}
	helpers.walkLayers(moho, function(layer, lid, parentId, depth)
		allLayers[lid] = { layer = layer, id = lid, parentId = parentId, depth = depth }
		childrenByParent[parentId] = childrenByParent[parentId] or {}
		childrenByParent[parentId][#childrenByParent[parentId] + 1] = lid
	end)

	local function collectDescendants(rootId, out)
		local kids = childrenByParent[rootId]
		if not kids then return end
		for i = 1, #kids do
			local cid = kids[i]
			out[#out + 1] = cid
			collectDescendants(cid, out)
		end
	end

	local targetBoneIds = {}
	if scopeLayerId ~= nil then
		targetBoneIds[1] = scopeLayerId
	else
		for lid = 0, #allLayers do
			local rec = allLayers[lid]
			if rec and rec.layer:LayerType() == MOHO.LT_BONE then
				targetBoneIds[#targetBoneIds + 1] = lid
			end
		end
	end

	local smartBoneDials = {}
	local ikTargets = {}
	local pinBones = {}
	local switchControls = {}
	local vitruvianGroups = {}
	local regularActions = {}
	local seenSwitch = {}
	local seenActionLayer = {}

	local function recordRegularActions(layer, lid)
		if seenActionLayer[lid] or not layer.CountActions then return end
		seenActionLayer[lid] = true
		for ai = 0, layer:CountActions() - 1 do
			local aname = layer:ActionName(ai)
			if aname ~= "" then
				local isSmart = layer.IsSmartBoneAction and (layer:IsSmartBoneAction(aname) == true) or false
				if not isSmart then
					local dur = layer.ActionDuration and layer:ActionDuration(aname) or 0
					regularActions[#regularActions + 1] = {
						layerId = lid,
						layerName = layer:Name(),
						actionName = aname,
						duration = dur,
						inferredRole = inferControlRole(aname),
					}
				end
			end
		end
	end

	for idx = 1, #targetBoneIds do
		local blId = targetBoneIds[idx]
		local blLayer = allLayers[blId].layer
		local bl = moho:LayerAsBone(blLayer)
		local skel = bl and bl:Skeleton() or nil
		if bl and skel then
			recordRegularActions(blLayer, blId)
			local boneCount = skel:CountBones()

			-- Map Smart Bone Action names to their base bone name
			local smartActionsByBone = {}
			if blLayer.CountActions then
				for ai = 0, blLayer:CountActions() - 1 do
					local aname = blLayer:ActionName(ai)
					if aname ~= "" and blLayer.IsSmartBoneAction and blLayer:IsSmartBoneAction(aname) then
						local baseName = aname:match("^(.-)%s+2$") or aname
						local dir = (aname:match("%s+2$") ~= nil) and "second" or "first"
						smartActionsByBone[baseName] = smartActionsByBone[baseName] or {}
						smartActionsByBone[baseName][#smartActionsByBone[baseName] + 1] = {
							name = aname,
							direction = dir,
							duration = blLayer.ActionDuration and blLayer:ActionDuration(aname) or 0,
						}
					end
				end
			end

			-- Map IK targets -> list of bones targeting them
			local drivenByTarget = {}
			for bi = 0, boneCount - 1 do
				local b = skel:Bone(bi)
				if b and b.fTargetBone then
					local tid = b.fTargetBone:GetValue(0)
					if tid >= 0 and tid < boneCount then
						drivenByTarget[tid] = drivenByTarget[tid] or {}
						drivenByTarget[tid][#drivenByTarget[tid] + 1] = {
							boneId = bi,
							boneName = b:Name(),
						}
					end
				end
			end

			for bi = 0, boneCount - 1 do
				local b = skel:Bone(bi)
				if b then
					local bName = b:Name()
					local restAng = math.deg(b.fAnimAngle:GetValue(0))
					local curAng = math.deg(b.fAnimAngle:GetValue(frame))
					local p0 = b.fAnimPos:GetValue(0)
					local pf = b.fAnimPos:GetValue(frame)
					local sbActs = smartActionsByBone[bName]

					if sbActs and #sbActs > 0 then
						local actDetails = {}
						for ai = 1, #sbActs do
							local spec = sbActs[ai]
							local startDeg = restAng
							local endDeg = restAng
							local sweepDeg = 0
							if b.fAnimAngle and b.fAnimAngle.ActionByName then
								local rawCh = b.fAnimAngle:ActionByName(spec.name)
								local typedCh = (rawCh and moho.ChannelAsAnimVal) and moho:ChannelAsAnimVal(rawCh) or rawCh
								if typedCh and typedCh.GetValue and spec.duration > 0 then
									local okS, vS = pcall(function() return typedCh:GetValue(1) end)
									local okE, vE = pcall(function() return typedCh:GetValue(spec.duration) end)
									if okS and okE and type(vS) == "number" and type(vE) == "number" then
										startDeg = math.deg(vS)
										endDeg = math.deg(vE)
										sweepDeg = math.deg(vE - vS)
									end
								end
							end
							actDetails[#actDetails + 1] = {
								name = spec.name,
								direction = spec.direction,
								duration = spec.duration,
								startAngleDeg = startDeg,
								endAngleDeg = endDeg,
								deltaAngleDeg = sweepDeg,
								is360 = (math.abs(sweepDeg) >= 359.5),
							}
						end
						smartBoneDials[#smartBoneDials + 1] = {
							layerId = blId,
							layerName = blLayer:Name(),
							boneId = bi,
							boneName = bName,
							inferredRole = inferControlRole(bName),
							restAngleDeg = restAng,
							currentAngleDeg = curAng,
							strength = b.fStrength or 0,
							length = b.fLength or 0,
							parentBone = b.fParent,
							constraints = {
								enabled = (b.fConstraints == true),
								minDeg = math.deg(b.fMinConstraint or 0),
								maxDeg = math.deg(b.fMaxConstraint or 0),
							},
							bidirectional = (#actDetails >= 2),
							actions = json.array(actDetails),
						}
					end

					if drivenByTarget[bi] then
						ikTargets[#ikTargets + 1] = {
							layerId = blId,
							layerName = blLayer:Name(),
							boneId = bi,
							boneName = bName,
							inferredRole = inferControlRole(bName),
							parentBone = b.fParent,
							strength = b.fStrength or 0,
							restPos = { x = p0.x, y = p0.y },
							currentPos = { x = pf.x, y = pf.y },
							drivenBones = json.array(drivenByTarget[bi]),
						}
					elseif (b.fLength or 0) <= 0.0001 and not (sbActs and #sbActs > 0) then
						pinBones[#pinBones + 1] = {
							layerId = blId,
							layerName = blLayer:Name(),
							boneId = bi,
							boneName = bName,
							inferredRole = inferControlRole(bName),
							parentBone = b.fParent,
							strength = b.fStrength or 0,
							restPos = { x = p0.x, y = p0.y },
							currentPos = { x = pf.x, y = pf.y },
						}
					end
				end
			end

			-- Vitruvian Bone Groups (avoid touching grp.fActiveBone to respect Gotcha #5)
			if skel.CountGroups and skel.Group then
				for gi = 0, skel:CountGroups() - 1 do
					local grp = skel:Group(gi)
					if grp then
						local gName = grp.Name and grp:Name() or ("Group " .. tostring(gi + 1))
						local enabled = (grp.fEnabled ~= false)
						local activeId = grp.ActiveBone and grp:ActiveBone() or -1
						local activeName = (activeId >= 0 and activeId < boneCount) and skel:Bone(activeId):Name() or ""
						local gBones = {}
						if grp.CountBones and grp.Bone then
							for gb = 0, grp:CountBones() - 1 do
								local mb = grp:Bone(gb)
								if mb then
									local mbName = mb:Name()
									local mbId = -1
									for bi = 0, boneCount - 1 do
										if skel:Bone(bi) == mb or skel:Bone(bi):Name() == mbName then
											mbId = bi
											break
										end
									end
									gBones[#gBones + 1] = { boneId = mbId, boneName = mbName }
								end
							end
						end
						vitruvianGroups[#vitruvianGroups + 1] = {
							layerId = blId,
							layerName = blLayer:Name(),
							groupIndex = gi,
							groupName = gName,
							enabled = enabled,
							activeBoneId = activeId,
							activeBoneName = activeName,
							bones = json.array(gBones),
						}
					end
				end
			end

			-- Descendant SwitchLayers and child Regular Actions
			local desc = {}
			collectDescendants(blId, desc)
			for i = 1, #desc do
				local cid = desc[i]
				local clayer = allLayers[cid].layer
				recordRegularActions(clayer, cid)
				if clayer:LayerType() == MOHO.LT_SWITCH and not seenSwitch[cid] then
					seenSwitch[cid] = true
					local sw = moho:LayerAsSwitch(clayer)
					if sw then
						local kids = {}
						for ki = sw:CountLayers() - 1, 0, -1 do
							kids[#kids + 1] = sw:Layer(ki):Name()
						end
						local activeVal = ""
						if sw.GetValue then
							local okV, v = pcall(function() return sw:GetValue(frame) end)
							if okV and v ~= nil then
								activeVal = (type(v) == "userdata" and v.Buffer) and v:Buffer() or tostring(v)
							end
						end
						switchControls[#switchControls + 1] = {
							layerId = cid,
							layerName = clayer:Name(),
							boneLayerId = blId,
							inferredRole = inferControlRole(clayer:Name()),
							activeChild = activeVal,
							frameByFrame = sw.IsFBFLayer and (sw:IsFBFLayer() == true) or false,
							interpMode = sw.InterpMode and (sw:InterpMode() == true) or false,
							children = json.array(kids),
						}
					end
				end
			end
		end
	end

	-- When auditing whole document, also include standalone SwitchLayers outside BoneLayers
	if scopeLayerId == nil then
		for lid = 0, #allLayers do
			local rec = allLayers[lid]
			if rec and rec.layer:LayerType() == MOHO.LT_SWITCH and not seenSwitch[lid] then
				seenSwitch[lid] = true
				local sw = moho:LayerAsSwitch(rec.layer)
				if sw then
					local kids = {}
					for ki = sw:CountLayers() - 1, 0, -1 do
						kids[#kids + 1] = sw:Layer(ki):Name()
					end
					local activeVal = ""
					if sw.GetValue then
						local okV, v = pcall(function() return sw:GetValue(frame) end)
						if okV and v ~= nil then
							activeVal = (type(v) == "userdata" and v.Buffer) and v:Buffer() or tostring(v)
						end
					end
					switchControls[#switchControls + 1] = {
						layerId = lid,
						layerName = rec.layer:Name(),
						boneLayerId = -1,
						inferredRole = inferControlRole(rec.layer:Name()),
						activeChild = activeVal,
						frameByFrame = sw.IsFBFLayer and (sw:IsFBFLayer() == true) or false,
						interpMode = sw.InterpMode and (sw:InterpMode() == true) or false,
						children = json.array(kids),
					}
				end
			end
		end
	end

	return {
		documentName = doc:Name(),
		frame = frame,
		scopeLayerId = scopeLayerId,
		summary = {
			boneLayers = #targetBoneIds,
			smartBoneDials = #smartBoneDials,
			ikTargets = #ikTargets,
			pinBones = #pinBones,
			switchControls = #switchControls,
			vitruvianGroups = #vitruvianGroups,
			regularActions = #regularActions,
		},
		smartBoneDials = json.array(smartBoneDials),
		ikTargets = json.array(ikTargets),
		pinBones = json.array(pinBones),
		switchControls = json.array(switchControls),
		vitruvianGroups = json.array(vitruvianGroups),
		regularActions = json.array(regularActions),
	}
end

--- One-shot Moho Pro studio Smart Bone Dial builder (mirrors Bone > Make Smart Bone Dial):
--- creates a zero-strength, labeled, color-tagged, IK-ignored dial bone with angle constraints
--- and its Smart Bone Action(s) (<name>, plus optional <name> 2 for bidirectional controls).
function bones.createSmartDial(moho, params)
	params = params or {}
	local skel, layer, lid, err = resolveSkeleton(moho, params)
	if not skel then
		return nil, err
	end
	local dialName = tostring(params.name or "")
	if #dialName == 0 then
		return nil, "name is required for bone_createSmartDial"
	end

	local parentId = -1
	if params.parentBoneId ~= nil or params.parentBoneName ~= nil then
		local pid, perr = resolveOptionalBoneId(skel, params.parentBoneId, params.parentBoneName)
		if perr then return nil, perr end
		if pid ~= nil then parentId = pid end
	end

	local mode = string.lower(tostring(params.mode or "standard"))
	local is360 = (mode == "360")
	local bidirectional = (params.bidirectional == true) and (not is360)
	local restAngleDeg = (params.restAngleDeg ~= nil) and tonumber(params.restAngleDeg) or 90
	local length = (params.length ~= nil) and math.max(0.02, tonumber(params.length)) or 0.22
	local duration = math.max(2, math.floor(tonumber(params.duration) or 96))
	local colorTag = (params.colorTag ~= nil) and math.floor(tonumber(params.colorTag)) or 1
	local showLabel = (params.showLabel ~= false)
	local interpolation = tostring(params.interpolation or "linear")

	local delta1, delta2, minDeg, maxDeg
	if is360 then
		delta1 = (params.deltaAngleDeg ~= nil) and tonumber(params.deltaAngleDeg) or ((params.clockwise == true) and -360 or 360)
		minDeg = nil
		maxDeg = nil
	elseif bidirectional then
		delta1 = (params.deltaAngleDeg ~= nil) and tonumber(params.deltaAngleDeg) or ((params.maxDeg ~= nil) and tonumber(params.maxDeg) or 90)
		delta2 = (params.secondDeltaAngleDeg ~= nil) and tonumber(params.secondDeltaAngleDeg) or ((params.minDeg ~= nil) and tonumber(params.minDeg) or -90)
		minDeg = (params.minDeg ~= nil) and tonumber(params.minDeg) or math.min(0, delta1, delta2)
		maxDeg = (params.maxDeg ~= nil) and tonumber(params.maxDeg) or math.max(0, delta1, delta2)
	else
		delta1 = (params.deltaAngleDeg ~= nil) and tonumber(params.deltaAngleDeg) or 90
		minDeg = (params.minDeg ~= nil) and tonumber(params.minDeg) or math.min(0, delta1)
		maxDeg = (params.maxDeg ~= nil) and tonumber(params.maxDeg) or math.max(0, delta1)
	end

	-- Compute dial placement (explicit x/y or auto-laid-out side control column beside character)
	local px, py
	if params.x ~= nil or params.y ~= nil then
		px = tonumber(params.x) or 0
		py = tonumber(params.y) or 0
	else
		local side = string.lower(tostring(params.side or "right"))
		local minX, maxX, minY, maxY = -0.35, 0.35, -0.35, 0.45
		local foundExtent = false
		local bbox = layer.Bounds and layer:Bounds(0) or nil
		if bbox and bbox.fMin and bbox.fMax and (bbox.fMax.x > bbox.fMin.x or bbox.fMax.y > bbox.fMin.y) then
			minX, maxX = bbox.fMin.x, bbox.fMax.x
			minY, maxY = bbox.fMin.y, bbox.fMax.y
			foundExtent = true
		end
		-- Count existing side control dials so new dials stack neatly without overlap
		local existingDials = 0
		local baseRightX = maxX + 0.35
		local baseLeftX = minX - 0.35
		for bi = 0, skel:CountBones() - 1 do
			local eb = skel:Bone(bi)
			if eb and (eb.fStrength or 0) <= 0.001 and eb.fIgnoredByIK == true and eb.IsLabelShowing and eb:IsLabelShowing() then
				existingDials = existingDials + 1
			elseif (not foundExtent) and eb then
				local ep = eb.fAnimPos:GetValue(0)
				if ep.x > maxX then maxX = ep.x end
				if ep.x < minX then minX = ep.x end
				if ep.y > maxY then maxY = ep.y end
				if ep.y < minY then minY = ep.y end
			end
		end
		local colIdx = math.floor(existingDials / 5)
		local rowIdx = existingDials % 5
		if side == "left" then
			px = (baseLeftX - colIdx * 0.42)
		else
			px = (baseRightX + colIdx * 0.42)
		end
		py = (maxY - 0.15) - rowIdx * 0.34
	end

	helpers.prepUndo(moho, layer, true)

	local b = skel:AddBone(0)
	local bid = skel:CountBones() - 1
	b:SetName(dialName)
	b.fParent = parentId
	b.fAnimParent:SetValue(0, parentId)

	local posVec = LM.Vector2:new_local()
	posVec:Set(px, py)
	if parentId >= 0 then
		local inv = LM.Matrix:new_local()
		inv:Set(skel:Bone(parentId).fRestMatrix)
		inv:Invert()
		inv:Transform(posVec)
	end
	b.fAnimPos:SetValue(0, posVec)
	b.fAnimAngle:SetValue(0, math.rad(restAngleDeg))
	b.fAnimScale:SetValue(0, 1.0)
	b.fLength = length
	b.fStrength = 0
	b.fIgnoredByIK = true
	if b.ShowLabel then b:ShowLabel(showLabel) end
	if b.SetTags then b:SetTags(colorTag) end

	local useConstraints = (params.enableConstraints ~= false) and (not is360)
	if useConstraints and minDeg ~= nil and maxDeg ~= nil then
		b.fConstraints = true
		b.fMinConstraint = math.rad(minDeg)
		b.fMaxConstraint = math.rad(maxDeg)
	end

	skel:UpdateBoneMatrix(bid)

	local animTools = require("moho_studio.tools.animation")
	local leaveActive = string.lower(tostring(params.leaveActive or "none"))
	local createdActions = {}

	local act1, err1 = animTools.actionCreateSmartBone(moho, {
		layerId = lid,
		boneId = bid,
		mode = is360 and "360" or "standard",
		direction = "first",
		duration = duration,
		deltaAngleDeg = delta1,
		interpolation = interpolation,
		addMidpointKey = is360 and (params.addMidpointKey ~= false) or false,
		mirrorFrame0ToEnd = (params.mirrorFrame0ToEnd ~= nil) and (params.mirrorFrame0ToEnd == true) or is360,
		leaveActive = (leaveActive == "first" or leaveActive == "true"),
	})
	if not act1 then
		return nil, "Created dial bone '" .. dialName .. "' but failed creating primary Smart Bone Action: " .. tostring(err1)
	end
	createdActions[#createdActions + 1] = act1

	if bidirectional then
		local act2, err2 = animTools.actionCreateSmartBone(moho, {
			layerId = lid,
			boneId = bid,
			mode = "standard",
			direction = "second",
			duration = duration,
			deltaAngleDeg = delta2,
			interpolation = interpolation,
			leaveActive = (leaveActive == "second"),
		})
		if not act2 then
			return nil, "Created dial bone '" .. dialName .. "' but failed creating secondary Smart Bone Action: " .. tostring(err2)
		end
		createdActions[#createdActions + 1] = act2
		if leaveActive == "first" then
			animTools.actionActivate(moho, { layerId = lid, actionName = act1.actionName })
		end
	end

	helpers.updateUI(moho)
	return {
		created = true,
		layerId = lid,
		layerName = layer:Name(),
		boneId = bid,
		boneName = dialName,
		position = { x = px, y = py },
		restAngleDeg = restAngleDeg,
		length = length,
		strength = 0,
		ignoredByIK = true,
		showLabel = showLabel,
		colorTag = colorTag,
		bidirectional = bidirectional,
		constraints = useConstraints and { enabled = true, minDeg = minDeg, maxDeg = maxDeg } or { enabled = false },
		actions = json.array(createdActions),
		activeAction = layer:CurrentAction(),
	}
end

return bones
