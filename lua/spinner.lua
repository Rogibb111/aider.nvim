local M = {}

local frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local timer = nil
local notif_id = nil
local idx = 1

function M.start(text, opts)
	M.stop()
	opts = opts or {}
	notif_id = vim.notify(frames[idx] .. " " .. text, vim.log.levels.INFO, vim.tbl_extend("force", opts, { replace = nil }))
	timer = vim.loop.new_timer()
	timer:start(0, 80, vim.schedule_wrap(function()
		idx = idx % #frames + 1
		if notif_id then
			vim.notify(frames[idx] .. " " .. text, vim.log.levels.INFO, vim.tbl_extend("force", opts, { replace = notif_id }))
		end
	end))
end

function M.stop(final_text, level)
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	if notif_id then
		local msg = final_text or ""
		local lvl = level or vim.log.levels.INFO
		vim.notify(msg, lvl, { replace = notif_id })
		notif_id = nil
	end
end

return M
