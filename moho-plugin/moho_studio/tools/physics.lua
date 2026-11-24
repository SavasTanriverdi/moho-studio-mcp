-- Moho Pro 14.4 2D Physics configuration tool (Group/Bone physics + per-layer MohoPhysicsOptions).
-- Verified Moho Pro 14.4 signatures:
--   GroupLayer:EnablePhysics(frame, enabled)
--   GroupLayer:SetPhysicsGravity(LM.Vector2)
--   GroupLayer:UseBakedPhysics(bool)

local helpers = require("moho_studio.helpers")

local physics = {}

function physics.configure(moho, params)
	params = params or {}
	local layer, id, err = helpers.resolveLayer(moho, params)
	if not layer then
		return nil, err
	end
	local frame = (params.frame ~= nil) and math.floor(tonumber(params.frame)) or 0

	local mutateKeys = {
		"groupEnabled", "gravity", "useBakedPhysics", "bake",
		"enabled", "staticBody", "sleeping", "pivotOnOrigin",
		"density", "friction", "restitution", "respawnInterval", "lifetime",
		"enableMotor", "motorSpeed", "motorTorque", "forceObject",
		"initialVelocity", "forceVector",
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
	end

	local result = {
		layerId = id,
		layerName = layer:Name(),
		frame = frame,
		mutated = mutated,
	}

	-- Group-level physics simulation settings
	if layer:IsGroupType() then
		local grp = moho:LayerAsGroup(layer)
		if grp then
			if params.groupEnabled ~= nil then
				-- Verified: GroupLayer:EnablePhysics(frame, bool)
				grp:EnablePhysics(frame, params.groupEnabled == true)
			end
			if type(params.gravity) == "table" then
				local gv = LM.Vector2:new_local()
				gv:Set(tonumber(params.gravity.x) or 0, tonumber(params.gravity.y) or -9.8)
				grp:SetPhysicsGravity(gv)
			end
			if params.bake == true then
				local doc = moho.document
				local origFrame = moho.frame
				local startF = params.startFrame ~= nil and math.floor(tonumber(params.startFrame)) or (doc and doc:StartFrame() or 1)
				local endF = params.endFrame ~= nil and math.floor(tonumber(params.endFrame)) or (doc and doc:EndFrame() or 48)
				if not grp:IsPhysicsEnabled() then
					grp:EnablePhysics(0, true)
				end
				grp:UseBakedPhysics(false)
				for f = startF, endF do
					moho:SetCurFrame(f)
					layer:UpdateCurFrame()
				end
				grp:UseBakedPhysics(true)
				moho:SetCurFrame(origFrame)
				result.baked = true
				result.bakedRange = { startFrame = startF, endFrame = endF }
			elseif params.useBakedPhysics ~= nil then
				grp:UseBakedPhysics(params.useBakedPhysics == true)
			end
			local curG = grp:PhysicsGravity()
			result.groupPhysics = {
				enabled = grp:IsPhysicsEnabled(),
				usingBakedPhysics = grp:UsingBakedPhysics(),
				gravity = curG and { x = curG.x, y = curG.y } or nil,
			}
		end
	end

	-- Per-layer rigid body physics options (MohoPhysicsOptions)
	-- Note: in Moho 14.4, fMotorSpeed is AnimVal and fForceVector is AnimVec2.
	-- Moho's Lua binding exposes fRespawnInterval (aliased here as lifetime).
	local po = layer.PhysicsOptions and layer:PhysicsOptions() or nil
	if po then
		if params.enabled ~= nil then po.fPhysicsEnabled = (params.enabled == true) end
		if params.staticBody ~= nil then po.fStaticBody = (params.staticBody == true) end
		if params.sleeping ~= nil then po.fSleeping = (params.sleeping == true) end
		if params.pivotOnOrigin ~= nil then po.fPivotOnOrigin = (params.pivotOnOrigin == true) end
		if params.density ~= nil then po.fDensity = tonumber(params.density) end
		if params.friction ~= nil then po.fFriction = tonumber(params.friction) end
		if params.restitution ~= nil then po.fRestitution = tonumber(params.restitution) end
		local respawnVal = params.respawnInterval ~= nil and params.respawnInterval or params.lifetime
		if respawnVal ~= nil then
			po.fRespawnInterval = math.max(0, math.floor(tonumber(respawnVal)))
		end
		if params.enableMotor ~= nil then po.fEnableMotor = (params.enableMotor == true) end
		if params.motorSpeed ~= nil then
			local ms = tonumber(params.motorSpeed)
			if type(po.fMotorSpeed) == "number" then
				po.fMotorSpeed = ms
			elseif po.fMotorSpeed and po.fMotorSpeed.SetValue then
				po.fMotorSpeed:SetValue(frame, ms)
			end
		end
		if params.motorTorque ~= nil then po.fMotorTorque = tonumber(params.motorTorque) end
		if params.forceObject ~= nil then po.fForceObject = (params.forceObject == true) end
		if type(params.initialVelocity) == "table" and po.fInitialVelocity then
			local ivx = tonumber(params.initialVelocity.x) or 0
			local ivy = tonumber(params.initialVelocity.y) or 0
			if po.fInitialVelocity.SetValue then
				local iv = LM.Vector2:new_local()
				iv:Set(ivx, ivy)
				po.fInitialVelocity:SetValue(frame, iv)
			elseif po.fInitialVelocity.Set then
				po.fInitialVelocity:Set(ivx, ivy)
			end
		end
		if type(params.forceVector) == "table" and po.fForceVector then
			local fvx = tonumber(params.forceVector.x) or 0
			local fvy = tonumber(params.forceVector.y) or 0
			if po.fForceVector.SetValue then
				local fv = LM.Vector2:new_local()
				fv:Set(fvx, fvy)
				po.fForceVector:SetValue(frame, fv)
			elseif po.fForceVector.Set then
				po.fForceVector:Set(fvx, fvy)
			end
		end

		local readMotorSpeed = 0
		if type(po.fMotorSpeed) == "number" then
			readMotorSpeed = po.fMotorSpeed
		elseif po.fMotorSpeed and po.fMotorSpeed.GetValue then
			readMotorSpeed = po.fMotorSpeed:GetValue(frame)
		end

		local readForceVec = nil
		if po.fForceVector then
			if po.fForceVector.GetValue then
				local cf = po.fForceVector:GetValue(frame)
				if cf then readForceVec = { x = cf.x, y = cf.y } end
			elseif po.fForceVector.x ~= nil then
				readForceVec = { x = po.fForceVector.x, y = po.fForceVector.y }
			end
		end

		local readInitVel = nil
		if po.fInitialVelocity then
			if po.fInitialVelocity.GetValue then
				local ci = po.fInitialVelocity:GetValue(frame)
				if ci then readInitVel = { x = ci.x, y = ci.y } end
			elseif po.fInitialVelocity.x ~= nil then
				readInitVel = { x = po.fInitialVelocity.x, y = po.fInitialVelocity.y }
			end
		end

		result.bodyOptions = {
			enabled = po.fPhysicsEnabled == true,
			staticBody = po.fStaticBody == true,
			sleeping = po.fSleeping == true,
			pivotOnOrigin = po.fPivotOnOrigin == true,
			density = po.fDensity,
			friction = po.fFriction,
			restitution = po.fRestitution,
			respawnInterval = po.fRespawnInterval,
			lifetime = po.fRespawnInterval,
			enableMotor = po.fEnableMotor == true,
			motorSpeed = readMotorSpeed,
			motorTorque = po.fMotorTorque,
			forceObject = po.fForceObject == true,
			initialVelocity = readInitVel,
			forceVector = readForceVec,
		}
	end

	if mutated then
		helpers.updateUI(moho)
	end
	return result
end

return physics
