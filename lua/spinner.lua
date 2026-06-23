local M = {}

local frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local timers = {}
local notif_ids = {}

function M.start(text, opts)
	opts = opts or {}
	local id = opts.id or "default"
	M.stop(id)

	notif_ids[id] = vim.notify(frames[1] .. " " .. text, vim.log.levels.INFO, vim.tbl_extend("force", opts, { replace = nil }))
	timers[id] = vim.loop.new_timer()
	local idx = 1
	timers[id]:start(0, 80, vim.schedule_wrap(function()
		idx = idx % #frames + 1
		if notif_ids[id] then
			vim.notify(frames[idx] .. " " .. text, vim.log.levels.INFO, vim.tbl_extend("force", opts, { replace = notif_ids[id] }))
		end
	end))
end

function M.stop(id, final_text, level)
	if type(id) == "string" then
		-- Called with id parameter
		if timers[id] then
			timers[id]:stop()
			timers[id]:close()
			timers[id] = nil
		end
		if notif_ids[id] then
			local msg = final_text or ""
			local lvl = level or vim.log.levels.INFO
			vim.notify(msg, lvl, { replace = notif_ids[id] })
			notif_ids[id] = nil
		end
	else
		-- Called with (final_text, level) for backward compatibility
		for k, _ in pairs(timers) do
			timers[k]:stop()
			timers[k]:close()
		end
		timers = {}
		for k, _ in pairs(notif_ids) do
			local msg = id or ""
			local lvl = final_text or vim.log.levels.INFO
			vim.notify(msg, lvl, { replace = notif_ids[k] })
		end
		notif_ids = {}
	end
	vim.defer_fn(function()
		if type(id) == "string" then
			-- Called with id parameter
			if timers[id] then
				timers[id]:stop()
				timers[id]:close()
				timers[id] = nil
			end
			if notif_ids[id] then
				local msg = final_text or ""
				local lvl = level or vim.log.levels.INFO
				vim.notify(msg, lvl, { replace = notif_ids[id] })
				notif_ids[id] = nil
			end
		else
			-- Called with (final_text, level) for backward compatibility
			for k, _ in pairs(timers) do
				timers[k]:stop()
				timers[k]:close()
			end
			timers = {}
			for k, _ in pairs(notif_ids) do
				local msg = id or ""
				local lvl = final_text or vim.log.levels.INFO
				vim.notify(msg, lvl, { replace = notif_ids[k] })
			end
			notif_ids = {}
		end
	end, 100)
end

return M
