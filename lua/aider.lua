local helpers = require("helpers")
local M = {}

M.aider_buf = nil
M.debug = false

local function is_valid_buffer(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

	-- Ignore special buffers and directories
	if
		buftype ~= ""
		or filetype == "NvimTree"
		or filetype == "neo-tree"
		or filetype == "AiderConsole"
		or not vim.fn.filereadable(bufname)
		or vim.fn.isdirectory(bufname) == 1
	then
		return false
	end

	for _, ignore_buf in ipairs(M.config.ignore_buffers or {}) do
		if bufname:match(ignore_buf) then
			return false
		end
	end

	return true
end

local function log(message)
	if M.debug then
		print(string.format("[Aider Log] %s", message))
	end
end

local function OnExit(job_id, exit_code, event_type)
	vim.schedule(function()
		if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
			vim.api.nvim_buf_set_option(M.aider_buf, "modifiable", true)
			local message
			if exit_code == 0 then
				message = "Aider process completed successfully."
			else
				message = "Aider process exited with code: " .. exit_code
			end
			vim.api.nvim_buf_set_lines(M.aider_buf, -1, -1, false, { "", message })
			vim.api.nvim_buf_set_option(M.aider_buf, "modifiable", false)
		end
		log("Aider process exited with code: " .. exit_code)
	end)
end

function M.AiderOpen(args, window_type)
	log("AiderOpen called with args: " .. (args or "nil") .. ", window_type: " .. (window_type or "nil"))
	window_type = window_type or "vsplit"

	local litellm_path = nil
	if M.config.free_tier_router and M.config.free_tier_router.enabled then
		local bootstrap = require("bootstrap")
		litellm_path = bootstrap.ensure_dependencies()
		if not litellm_path then
			vim.notify("[Aider] LiteLLM environment is setting up. Please wait a moment...", vim.log.levels.WARN)
			return
		end
	end

	if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
		log("Existing aider buffer found, opening in new window")
		helpers.open_buffer_in_new_window(window_type, M.aider_buf)
	else
		log("No existing aider buffer, creating new one")

		local function spawn_aider()
			local command = "aider "
			if M.config.free_tier_router and M.config.free_tier_router.enabled then
				if not (args and args:match("%-%-model")) then
					command = command .. "--model free-aider-agent "
				end
			end
			command = command .. (args or "")
			log("Opening window with type: " .. window_type)
			helpers.open_window(window_type)
			log("Adding buffers to command")
			command = helpers.add_buffers_to_command(command, is_valid_buffer)
			log("Final command: " .. command)
			log("Opening terminal with command")
			M.aider_buf = vim.api.nvim_get_current_buf()

			local term_opts = { on_exit = OnExit }
			local old_api_base, old_api_key
			if M.config.free_tier_router and M.config.free_tier_router.enabled then
				old_api_base = vim.env.OPENAI_API_BASE
				old_api_key = vim.env.OPENAI_API_KEY
				vim.env.OPENAI_API_BASE = "http://127.0.0.1:8080/v1"
				vim.env.OPENAI_API_KEY = "sk-mock-key"
			end

			-- Capture the window that will host the terminal so we can close it later
			M.aider_win = vim.api.nvim_get_current_win()
			-- Capture the window that will host the terminal so we can close it later
			M.aider_win = vim.api.nvim_get_current_win()
			M.aider_job_id = vim.fn.termopen(command, term_opts)

			-- Set a terminal-mode mapping for <CR> to handle custom commands like /quit
			-- This replaces the default <CR> behaviour with our own handler.
			vim.api.nvim_buf_set_keymap(
				M.aider_buf,
				't',
				'<CR>',
				[[<Cmd>lua require('aider').handle_terminal_enter()<CR>]],
				{ noremap = true, silent = true }
			)

			-- Set a terminal-mode mapping for <CR> to handle custom commands like /quit
			-- This replaces the default <CR> behaviour with our own handler.
			vim.api.nvim_buf_set_keymap(
				M.aider_buf,
				't',
				'<CR>',
				[[<Cmd>lua require('aider').handle_terminal_enter()<CR>]],
				{ noremap = true, silent = true }
			)

			if M.config.free_tier_router and M.config.free_tier_router.enabled then
				vim.env.OPENAI_API_BASE = old_api_base
				vim.env.OPENAI_API_KEY = old_api_key
			end

			log("Terminal opened with job ID: " .. M.aider_job_id)
			log("Set aider_buf to: " .. M.aider_buf)
			vim.bo[M.aider_buf].bufhidden = "hide"
			vim.bo[M.aider_buf].filetype = "AiderConsole"
			log("AiderOpen completed")
			log("Final aider_buf: " .. (M.aider_buf or "nil"))
		end

		if M.config.free_tier_router and M.config.free_tier_router.enabled then
			require("litellm_manager").ensure_started(M.config.free_tier_router, litellm_path, spawn_aider)
		else
			spawn_aider()
		end
	end
end

function M.AiderOnBufferOpen(bufnr)
	if not vim.g.aider_buffer_sync or vim.g.aider_buffer_sync == 0 then
		return
	end
	bufnr = tonumber(bufnr)
	if not is_valid_buffer(bufnr) then
		return
	end
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local relative_filename = vim.fn.fnamemodify(bufname, ":~:.")
	if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
		local line_to_add = "/add " .. relative_filename
		vim.fn.chansend(M.aider_job_id, line_to_add .. "\n")
	end
end

function M.AiderOnBufferClose(bufnr)
	if not vim.g.aider_buffer_sync or vim.g.aider_buffer_sync == 0 then
		return
	end
	bufnr = tonumber(bufnr)
	if not is_valid_buffer(bufnr) then
		return
	end
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local relative_filename = vim.fn.fnamemodify(bufname, ":~:.")
	if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
		local line_to_drop = "/drop " .. relative_filename
		vim.fn.chansend(M.aider_job_id, line_to_drop .. "\n")
	end
end

local function create_commands()
	log("Creating user commands")
	vim.api.nvim_create_user_command("AiderOpen", function(opts)
		log("AiderOpen command called with args: " .. (opts.args or "nil"))
		M.AiderOpen(opts.args)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("AiderAddModifiedFiles", function()
		log("AiderAddModifiedFiles command called")
		M.AiderAddModifiedFiles()
	end, {})
	log("User commands created")
end

function M.AiderAddModifiedFiles()
	log("AiderAddModifiedFiles called")
	if not M.aider_buf or not vim.api.nvim_buf_is_valid(M.aider_buf) then
		log("Aider chat not open, opening it first")
		M.AiderOpen()
		-- Wait a bit for the Aider chat to initialize
		vim.defer_fn(function()
			M.AiderAddModifiedFiles()
		end, 1000)
		return
	end

	local modified_files = helpers.get_git_modified_files()
	for _, file in ipairs(modified_files) do
		local line_to_add = "/add " .. file
		vim.fn.chansend(M.aider_job_id, line_to_add .. "\n")
	end
	vim.notify("Added " .. #modified_files .. " modified files to Aider chat")
end

function M.setup(config)
	M.config = {
		auto_manage_context = true,
		default_bindings = true,
		debug = false,
		ignore_buffers = { "^term://", "NeogitConsole", "NvimTree_", "neo-tree filesystem" },
		border = nil,
		free_tier_router = {
			enabled = false,
			providers = {},
		},
	}
	M.config = vim.tbl_deep_extend("force", M.config, config or {})

	helpers.set_config(M.config)

	vim.g.aider_buffer_sync = M.config.auto_manage_context

	if M.config.auto_manage_context then
		vim.api.nvim_create_autocmd("BufReadPost", {
			callback = function(ev)
				M.AiderOnBufferOpen(ev.buf)
			end,
		})
		vim.api.nvim_create_autocmd("BufDelete", {
			callback = function(ev)
				M.AiderOnBufferClose(ev.buf)
			end,
		})
	end

	create_commands()

	if M.config.default_bindings then
		require("keybindings")
	end

	-- create (or reuse) the augroup named "aider_console"
	local aider_grp = vim.api.nvim_create_augroup("aider_console", { clear = false })

	-- attach your autocmds to that group
	vim.api.nvim_create_autocmd({ "TermOpen", "TermClose" }, {
		group = aider_grp,
		pattern = "term://*aider*",
		callback = function(ev)
			if ev.event == "TermOpen" then
				vim.opt_local.number = false
				vim.opt_local.signcolumn = "no"
				-- drop into insert mode immediately
				vim.api.nvim_feedkeys("i", "n", false)
			else -- TermClose
				local enter = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
				vim.api.nvim_feedkeys(enter, "n", false)
			end
		end,
	})

	log("Aider setup completed with debug mode: " .. tostring(M.debug))
end

-- ----------------------------------------------------------------------
-- Handle <CR> in the Aider terminal buffer.
-- If the user typed "/quit", close the terminal window and buffer,
-- stop the associated job, and notify the user.
-- Otherwise forward the line to the Aider process.
-- ----------------------------------------------------------------------
function M.handle_terminal_enter()
	-- Get the current line the user typed
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""

	-- Trim surrounding whitespace
	line = line:gsub("^%s+", ""):gsub("%s+$", "")

	if line:match("^/quit") then
		-- Close the terminal window and buffer
		if M.aider_win and vim.api.nvim_win_is_valid(M.aider_win) then
			vim.api.nvim_win_close(M.aider_win, true)
		end
		if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
			vim.api.nvim_buf_delete(M.aider_buf, { force = true })
		end
		-- Stop the background job if it is still running
		if M.aider_job_id then
			vim.fn.jobstop(M.aider_job_id)
		end
		-- Reset module state
		M.aider_buf = nil
		M.aider_win = nil
		M.aider_job_id = nil
		vim.notify("Aider session closed via /quit", vim.log.levels.INFO)
	else
		-- Forward the line to the Aider process
		if M.aider_job_id then
			vim.fn.chansend(M.aider_job_id, line .. "\n")
		end
	end
end

return M
