-- **************************************************
-- Moho Studio MCP v3.0.0 - Menu Server Script (Moho Pro 14.4 / Lua 5.4)
-- **************************************************

ScriptName = "MohoStudioMCP_Server"

MohoStudioMCP_Server = MohoStudioMCP_Server or {}

if MohoStudioMCP_Server.server == nil then
	MohoStudioMCP_Server.server = nil
	MohoStudioMCP_Server.isLoaded = false
	MohoStudioMCP_Server.BASE_DIR = ""
	MohoStudioMCP_Server.pollActive = false
	MohoStudioMCP_Server._hookedTools = {}
end

function MohoStudioMCP_Server:Name()
	return "MohoStudioMCP Server"
end

function MohoStudioMCP_Server:Version()
	return "3.0.0"
end

function MohoStudioMCP_Server:Description()
	return "Start/Stop Moho Studio MCP v3.0.0 server for full live MCP client control"
end

function MohoStudioMCP_Server:Creator()
	return "Moho Studio MCP"
end

function MohoStudioMCP_Server:UILabel()
	return "Start/Stop MohoStudioMCP Server"
end

local function getScriptDir()
	local info = debug.getinfo(1, "S")
	local path = info.source
	if path:sub(1, 1) == "@" then
		path = path:sub(2)
	end
	path = path:gsub("\\", "/")
	return path:match("^(.*/)") or "./"
end

local function setupPackagePath(baseDir)
	local sep = package.config:sub(1, 1)
	local pattern = baseDir .. "?.lua;" .. baseDir .. "?" .. sep .. "init.lua"
	if not package.path:find(baseDir, 1, true) then
		package.path = pattern .. ";" .. package.path
	end
end

local function loadModules(baseDir)
	if MohoStudioMCP_Server.isLoaded then
		return true
	end
	setupPackagePath(baseDir)

	local okJson, jsonMod = pcall(require, "moho_studio.json")
	if not okJson then
		print("[MohoStudioMCP] ERROR loading json: " .. tostring(jsonMod))
		return false
	end

	local okProto, protoMod = pcall(require, "moho_studio.protocol")
	if not okProto then
		print("[MohoStudioMCP] ERROR loading protocol: " .. tostring(protoMod))
		return false
	end
	protoMod.init(jsonMod)

	local okSrv, srv = pcall(require, "moho_studio.server")
	if not okSrv then
		print("[MohoStudioMCP] ERROR loading server: " .. tostring(srv))
		return false
	end
	srv.init({ protocol = protoMod, json = jsonMod })

	local okSys, sysTools = pcall(require, "moho_studio.tools.system")
	local okDoc, docTools = pcall(require, "moho_studio.tools.document")
	local okLay, layTools = pcall(require, "moho_studio.tools.layers")
	local okBone, boneTools = pcall(require, "moho_studio.tools.bones")
	local okAnim, animTools = pcall(require, "moho_studio.tools.animation")
	local okMesh, meshTools = pcall(require, "moho_studio.tools.mesh")
	local okStyle, styleTools = pcall(require, "moho_studio.tools.styles")
	local okSpec, specTools = pcall(require, "moho_studio.tools.special")
	local okPhys, physTools = pcall(require, "moho_studio.tools.physics")
	local okGltf, gltfTools = pcall(require, "moho_studio.tools.gltf")
	local okBatch, batchTools = pcall(require, "moho_studio.tools.batch")

	local modules = {
		{ okSys, "system", sysTools },
		{ okDoc, "document", docTools },
		{ okLay, "layers", layTools },
		{ okBone, "bones", boneTools },
		{ okAnim, "animation", animTools },
		{ okMesh, "mesh", meshTools },
		{ okStyle, "styles", styleTools },
		{ okSpec, "special", specTools },
		{ okPhys, "physics", physTools },
		{ okGltf, "gltf", gltfTools },
		{ okBatch, "batch", batchTools },
	}
	for i = 1, #modules do
		if not modules[i][1] then
			print("[MohoStudioMCP] ERROR loading " .. modules[i][2] .. ": " .. tostring(modules[i][3]))
			return false
		end
	end

	local regs = {
		{ "moho.status", sysTools.status },
		{ "moho.apiInspect", sysTools.apiInspect },
		{ "lua.execute", sysTools.executeLua },

		{ "document.getInfo", docTools.getInfo },
		{ "document.new", docTools.newDoc },
		{ "document.open", docTools.open },
		{ "document.save", docTools.save },
		{ "document.saveAs", docTools.saveAs },
		{ "document.close", docTools.closeDoc },
		{ "document.undo", docTools.undoRedo },
		{ "document.setSettings", docTools.setSettings },
		{ "document.import", docTools.importFile },
		{ "document.setFrame", docTools.setFrame },
		{ "document.renderFrame", docTools.renderFrame },
		{ "document.renderRange", docTools.renderRange },
		{ "document.exportGltf", gltfTools.exportGltf },
		{ "rig.auditGltf", gltfTools.auditGltf },
		{ "layercomp.list", docTools.layerCompList },
		{ "layercomp.manage", docTools.layerCompManage },

		{ "layer.list", layTools.list },
		{ "layer.getProperties", layTools.getProperties },
		{ "layer.create", layTools.create },
		{ "layer.delete", layTools.deleteLayer },
		{ "layer.duplicate", layTools.duplicateLayer },
		{ "layer.reparent", layTools.reparent },
		{ "layer.select", layTools.selectLayer },
		{ "layer.setProperties", layTools.setProperties },
		{ "layer.bindToBone", layTools.bindToBone },
		{ "layer.setWarpLayer", layTools.setWarpLayer },
		{ "layer.setMasking", layTools.setMasking },
		{ "layer.setLayerOrder", layTools.setLayerOrder },
		{ "layer.convertType", layTools.convertType },
		{ "layer.groupSelection", layTools.groupSelection },
		{ "layer.followPath", layTools.followPath },
		{ "layer.referenceManage", layTools.referenceManage },
		{ "layer.renderImage", layTools.renderImage },
		{ "switch.setActive", specTools.switchSetActive },
		{ "fbf.manage", specTools.fbfManage },
		{ "particle.configure", specTools.particleConfigure },

		{ "bone.list", boneTools.list },
		{ "bone.create", boneTools.create },
		{ "bone.delete", boneTools.deleteBone },
		{ "bone.setTransform", boneTools.setTransform },
		{ "bone.setProperties", boneTools.setProperties },
		{ "bone.setConstraints", boneTools.setConstraints },
		{ "bone.setDynamics", boneTools.setDynamics },
		{ "bone.mirror", boneTools.mirror },
		{ "bone.freezePose", boneTools.freezePose },
		{ "bone.listGroups", boneTools.listGroups },
		{ "bone.manageGroup", boneTools.manageGroup },
		{ "bone.setWind", boneTools.setWind },
		{ "physics.configure", physTools.configure },

		{ "animation.getKeyframes", animTools.getKeyframes },
		{ "animation.setKeyframes", animTools.setKeyframes },
		{ "animation.deleteKeyframe", animTools.deleteKeyframe },
		{ "animation.createCycle", animTools.createCycle },
		{ "animation.retime", animTools.retime },
		{ "animation.tween", animTools.tween },
		{ "timeline.markers", animTools.timelineMarkers },
		{ "action.list", animTools.actionList },
		{ "action.activate", animTools.actionActivate },
		{ "action.createSmartBone", animTools.actionCreateSmartBone },
		{ "action.manage", animTools.actionManage },
		{ "camera.get", animTools.cameraGet },
		{ "camera.setKeyframe", animTools.cameraSetKeyframe },

		{ "mesh.getData", meshTools.getData },
		{ "mesh.createShape", meshTools.createShape },
		{ "mesh.editShape", meshTools.editShape },
		{ "mesh.editPoints", meshTools.editPoints },
		{ "mesh.editTopology", meshTools.editTopology },
		{ "mesh.createSmartWarp", meshTools.createSmartWarp },
		{ "mesh.setCurveProfile", meshTools.setCurveProfile },
		{ "mesh.liquidShapes", meshTools.liquidShapes },
		{ "style.manage", styleTools.manage },

		{ "batch.execute", batchTools.makeHandler(srv) },
	}

	for i = 1, #regs do
		srv.registerHandler(regs[i][1], regs[i][2])
	end
	print("[MohoStudioMCP] Registered " .. tostring(#regs) .. " live v3.0.0 handlers")

	MohoStudioMCP_Server.server = srv
	MohoStudioMCP_Server.isLoaded = true
	return true
end

local function hookSingleTool(name, t)
	if type(t) ~= "table" then
		return false
	end
	MohoStudioMCP_Server._hookedTools = MohoStudioMCP_Server._hookedTools or {}
	if MohoStudioMCP_Server._hookedTools[name] then
		return false
	end
	if name == "MohoStudioMCP_Server" or name == "MohoStudioMCP_Poller" then
		return false
	end
	-- Only hook Moho tool scripts (tables that expose mouse/draw callbacks and UILabel/Name)
	local looksLikeTool = (type(t.OnMouseMoved) == "function" or type(t.DrawMe) == "function")
		and (type(t.UILabel) == "function" or type(t.Name) == "function")
	if not looksLikeTool then
		return false
	end

	MohoStudioMCP_Server._hookedTools[name] = true

	-- 1. Enable NonDragMouseMove + drag-safe OnMouseMoved wrapper so background
	--    WM_MOUSEMOVE wakes Moho regardless of which tool or empty tab is active,
	--    without altering non-drag behavior for tools that did not opt in.
	local origMove = t.OnMouseMoved
	local origDown = t.OnMouseDown
	local origUp = t.OnMouseUp
	local origNonDrag = t.NonDragMouseMove
	local hadNonDrag = (type(origNonDrag) == "function")
	t.NonDragMouseMove = function(self)
		return true
	end
	if type(origDown) == "function" then
		t.OnMouseDown = function(self, moho, mouseEvent)
			self._mcpDragging = true
			return origDown(self, moho, mouseEvent)
		end
	end
	if type(origUp) == "function" then
		t.OnMouseUp = function(self, moho, mouseEvent)
			self._mcpDragging = false
			return origUp(self, moho, mouseEvent)
		end
	end
	t.OnMouseMoved = function(self, moho, mouseEvent)
		local isDragging = (self._mcpDragging == true)
		if not isDragging and mouseEvent and mouseEvent.view and mouseEvent.view.IsMouseDragging then
			local okD, resD = pcall(function() return mouseEvent.view:IsMouseDragging() end)
			if okD then
				isDragging = (resD == true)
			end
		end
		-- Two-stage crash-safe wakeup: NEVER execute server.poll / FileNew inside OnMouseMoved
		-- (Moho's C++ WM_MOUSEMOVE handler holds pointers to the active view/doc and faults if
		-- FileNew switches tabs mid-event). Instead, mark viewport dirty via MOHO.Redraw()
		-- under _inMouseMove guard so DrawMe executes server.poll on the next clean WM_PAINT stack.
		if (not isDragging) and MohoStudioMCP_Server.pollActive and MohoStudioMCP_Server.server then
			local srv = MohoStudioMCP_Server.server
			if srv.hasPending and srv.hasPending(moho, "draw") then
				MohoStudioMCP_Server._inMouseMove = true
				if MOHO and MOHO.Redraw then
					pcall(MOHO.Redraw)
				elseif mouseEvent and mouseEvent.view and mouseEvent.view.RefreshView then
					pcall(function() mouseEvent.view:RefreshView() end)
				end
				MohoStudioMCP_Server._inMouseMove = false
			end
		end
		if type(origMove) == "function" then
			if isDragging or (hadNonDrag and origNonDrag(self)) then
				return origMove(self, moho, mouseEvent)
			end
		end
	end

	-- 2. DrawMe hook: the single proven crash-safe dispatch point (runs on clean WM_PAINT stack).
	--    Installed on every hooked tool even if it did not previously define DrawMe.
	local origDraw = t.DrawMe
	t.DrawMe = function(self, moho, view)
		local docBefore = moho and moho.document or nil
		if (not MohoStudioMCP_Server._inMouseMove) and MohoStudioMCP_Server.pollActive and MohoStudioMCP_Server.server then
			local ok, res = pcall(MohoStudioMCP_Server.server.poll, moho, "draw")
			if not ok then
				print("[MohoStudioMCP] DrawMe poll error: " .. tostring(res))
			end
		end
		if moho and moho.document ~= docBefore then
			return
		end
		if type(origDraw) == "function" then
			return origDraw(self, moho, view)
		end
	end

	return true
end

local function installToolHooks(verbose)
	local newlyHooked = 0
	for k, v in pairs(_G) do
		if type(k) == "string" and type(v) == "table" then
			if hookSingleTool(k, v) then
				newlyHooked = newlyHooked + 1
			end
		end
	end
	if verbose or newlyHooked > 0 then
		local total = 0
		for _ in pairs(MohoStudioMCP_Server._hookedTools or {}) do
			total = total + 1
		end
		print("[MohoStudioMCP] Active zero-click hooks on " .. tostring(total) .. " Moho tools (+" .. tostring(newlyHooked) .. " new)")
	end
end

-- Install tool hooks as early as possible (before Moho caches NonDragMouseMove)
pcall(installToolHooks, false)

function MohoStudioMCP_Server:IsEnabled(moho)
	pcall(installToolHooks, false)
	return true
end

function MohoStudioMCP_Server:Run(moho)
	if MohoStudioMCP_Server.BASE_DIR == "" then
		MohoStudioMCP_Server.BASE_DIR = getScriptDir()
	end
	if not MohoStudioMCP_Server.isLoaded then
		if not loadModules(MohoStudioMCP_Server.BASE_DIR) then
			LM.GUI.Alert(
				LM.GUI.ALERT_WARNING,
				"MohoStudioMCP failed to load.",
				"Open Window > Lua Console for error details.",
				nil,
				MOHO.Localize("/Scripts/OK=OK"),
				nil,
				nil
			)
			return
		end
	end

	local srv = MohoStudioMCP_Server.server
	if srv.isRunning() then
		srv.stop()
		MohoStudioMCP_Server.pollActive = false
		LM.GUI.Alert(
			LM.GUI.ALERT_INFO,
			"MohoStudioMCP Server stopped.",
			nil, nil,
			MOHO.Localize("/Scripts/OK=OK"),
			nil, nil
		)
	else
		local ok, err = srv.start(moho)
		if ok then
			MohoStudioMCP_Server.pollActive = true
			installToolHooks(true)
			srv.poll(moho, "command")
			LM.GUI.Alert(
				LM.GUI.ALERT_INFO,
				"MohoStudioMCP Server v3.0.0 started!",
				"IPC directory: " .. srv.getInfo().ipcDir,
				"78 tools ready (crash-safe HandleMessage MCP Sync + DrawMe).",
				MOHO.Localize("/Scripts/OK=OK"),
				nil, nil
			)
		else
			LM.GUI.Alert(
				LM.GUI.ALERT_WARNING,
				"MohoStudioMCP Server failed to start.",
				tostring(err),
				nil,
				MOHO.Localize("/Scripts/OK=OK"),
				nil, nil
			)
		end
	end
end
