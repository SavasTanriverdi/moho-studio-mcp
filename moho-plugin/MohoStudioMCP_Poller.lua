-- **************************************************
-- Moho Studio MCP - Dedicated Poller Tool
-- **************************************************

ScriptName = "MohoStudioMCP_Poller"

MohoStudioMCP_Poller = {}
MohoStudioMCP_Poller.MSG_POLL = MOHO.MSG_BASE + 1

function MohoStudioMCP_Poller:Name()
	return "MohoStudioMCP Poller"
end

function MohoStudioMCP_Poller:Version()
	return "3.1.0"
end

function MohoStudioMCP_Poller:Description()
	return "Safe neutral polling tool for Moho Studio MCP (keeps live IPC responsive)"
end

function MohoStudioMCP_Poller:Creator()
	return "Moho Studio MCP"
end

function MohoStudioMCP_Poller:UILabel()
	return "MohoStudioMCP Poller"
end

function MohoStudioMCP_Poller:ColorizeIcon()
	return false
end

function MohoStudioMCP_Poller:NonDragMouseMove()
	return true
end

function MohoStudioMCP_Poller:IsEnabled(moho)
	-- CRITICAL: Never call server.poll() inside IsEnabled (Moho C++ +0x209f99 faults
	-- with 0xc000041d if FileNew switches documents during toolbar IsEnabled sweeps).
	return true
end

function MohoStudioMCP_Poller:IsRelevant(moho)
	return true
end

function MohoStudioMCP_Poller:DoLayout(moho, layout)
	-- Dedicated UI button right beside the active tool icon so background PostMessage
	-- can unconditionally invoke HandleMessage(MSG_POLL) on a clean UI command stack.
	if LM and LM.GUI and LM.GUI.Button then
		self.syncBtn = LM.GUI.Button("MCP Sync", self.MSG_POLL)
		layout:AddChild(self.syncBtn)
	end
end

function MohoStudioMCP_Poller:UpdateWidgets(moho)
	-- Intentionally no-op: only HandleMessage(MSG_POLL) and DrawMe dispatch server.poll.
end

function MohoStudioMCP_Poller:HandleMessage(moho, view, msg)
	if msg == self.MSG_POLL then
		if MohoStudioMCP_Server and MohoStudioMCP_Server.pollActive and MohoStudioMCP_Server.server then
			local ok, err = pcall(MohoStudioMCP_Server.server.poll, moho, "command")
			if not ok then
				print("[MohoStudioMCP] Poller HandleMessage error: " .. tostring(err))
			end
		end
	end
end

function MohoStudioMCP_Poller:DrawMe(moho, view)
	if MohoStudioMCP_Server and (not MohoStudioMCP_Server._inMouseMove) and MohoStudioMCP_Server.pollActive and MohoStudioMCP_Server.server then
		local ok, err = pcall(MohoStudioMCP_Server.server.poll, moho, "draw")
		if not ok then
			print("[MohoStudioMCP] Poller error: " .. tostring(err))
		end
		local now = os.clock()
		if not MohoStudioMCP_Server._lastNudge or (now - MohoStudioMCP_Server._lastNudge) > 0.22 then
			MohoStudioMCP_Server._lastNudge = now
			pcall(function() moho:UpdateUI() end)
		end
	end
end

function MohoStudioMCP_Poller:OnMouseDown(moho, mouseEvent) end

function MohoStudioMCP_Poller:OnMouseMoved(moho, mouseEvent)
	if MohoStudioMCP_Server and MohoStudioMCP_Server.pollActive and MohoStudioMCP_Server.server then
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
end

function MohoStudioMCP_Poller:OnMouseUp(moho, mouseEvent)
	if MohoStudioMCP_Server and MohoStudioMCP_Server.pollActive and MohoStudioMCP_Server.server then
		if MOHO and MOHO.Redraw then
			pcall(MOHO.Redraw)
		end
	end
end
