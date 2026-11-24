-- Atomic batch execution handler (single Undo step + coalesced UpdateUI).

local json = require("moho_studio.json")
local helpers = require("moho_studio.helpers")

local batch = {}

function batch.makeHandler(serverMod)
	return function(moho, params)
		local ops = params.operations
		if type(ops) ~= "table" or #ops == 0 then
			return nil, "operations must be a non-empty array"
		end
		if #ops > 100 then
			return nil, "batch_execute supports up to 100 operations per call"
		end
		local stopOnError = (params.stopOnError ~= false)
		if moho.document then
			moho.document:PrepMultiUndo(true)
			moho.document:SetDirty()
		end

		local results = {}
		local succeeded = 0
		local failed = 0

		helpers.batchDepth = helpers.batchDepth + 1
		local loopOk, loopErr = pcall(function()
			for i = 1, #ops do
				local op = ops[i]
				local method = op and op.method
				local opParams = (op and type(op.params) == "table") and op.params or {}
				local handler = method and serverMod.getHandler(method) or nil
				if not handler then
					failed = failed + 1
					results[#results + 1] = { index = i, method = method, ok = false, error = "Unknown method: " .. tostring(method) }
					if stopOnError then break end
				else
					local ok, res, herr = pcall(handler, moho, opParams)
					if not ok then
						failed = failed + 1
						results[#results + 1] = { index = i, method = method, ok = false, error = tostring(res) }
						if stopOnError then break end
					elseif res == nil and herr ~= nil then
						failed = failed + 1
						results[#results + 1] = { index = i, method = method, ok = false, error = tostring(herr) }
						if stopOnError then break end
					else
						succeeded = succeeded + 1
						results[#results + 1] = { index = i, method = method, ok = true, result = res }
					end
				end
			end
		end)
		helpers.batchDepth = math.max(0, helpers.batchDepth - 1)

		if moho.UpdateUI then
			pcall(function() moho:UpdateUI() end)
		end

		if not loopOk then
			return nil, "Batch execution error: " .. tostring(loopErr)
		end

		return {
			total = #ops,
			succeeded = succeeded,
			failed = failed,
			results = json.array(results),
		}
	end
end

return batch
