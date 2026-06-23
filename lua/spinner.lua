local M = {}

local frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local timers = {}
local notif_ids = {}
local active_opts = {} -- New: Store options to preserve titles during M.stop

function M.start(text, opts)
	opts = opts or {}
	local id = opts.id or "default"
	M.stop(id)

	-- Save the original options (like title, icon) for this specific spinner
	active_opts[id] = opts

	notif_ids[id] =
		vim.notify(frames[1] .. " " .. text, vim.log.levels.INFO, vim.tbl_extend("force", opts, { replace = nil }))
	timers[id] = vim.loop.new_timer()
	local idx = 1

	-- Changed initial delay from 0 to 80 to prevent a race condition on initialization
	timers[id]:start(
		80,
		80,
		vim.schedule_wrap(function()
			idx = idx % #frames + 1
			if notif_ids[id] then
				local next_id = vim.notify(
					frames[idx] .. " " .. text,
					vim.log.levels.INFO,
					vim.tbl_extend("force", active_opts[id], { replace = notif_ids[id] })
				)
				notif_ids[id] = next_id or notif_ids[id]
			end
		end)
	)
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
			-- Inject the original active_opts so the notification manager recognizes the window
			local stop_opts = vim.tbl_extend("force", active_opts[id] or {}, { replace = notif_ids[id] })
			vim.notify(msg, lvl, stop_opts)

			-- Cleanup
			notif_ids[id] = nil
			active_opts[id] = nil
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
			local stop_opts = vim.tbl_extend("force", active_opts[k] or {}, { replace = notif_ids[k] })
			vim.notify(msg, lvl, stop_opts)
		end
		notif_ids = {}
		active_opts = {}
	end
end

return M
