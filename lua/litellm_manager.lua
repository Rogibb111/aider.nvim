local M = {}
local spinner = require("spinner")
local config_module = require("litellm_config")
local uv = vim.uv or vim.loop

local job_id = nil
local is_starting = false

-- Rolling log buffer to capture startup errors without leaking memory
local process_logs = {}
local MAX_LOG_LINES = 50

local function append_to_logs(data)
	if not data then
		return
	end
	for _, line in ipairs(data) do
		if line and line ~= "" then
			table.insert(process_logs, line)
			if #process_logs > MAX_LOG_LINES then
				table.remove(process_logs, 1)
			end
		end
	end
end

-- Helper to check if a TCP port is open using libuv
local function check_port_open(port, host, timeout_ms, callback)
	local timer = uv.new_timer()
	local start_time = uv.now()

	local check_connect
	check_connect = function()
		local client = uv.new_tcp()
		client:connect(host, port, function(err)
			client:close()
			if not err then
				timer:stop()
				timer:close()
				callback(true)
			else
				if uv.now() - start_time > timeout_ms then
					timer:stop()
					timer:close()
					callback(false)
				else
					timer:start(100, 0, check_connect)
				end
			end
		end)
	end

	timer:start(0, 0, check_connect)
end

function M.ensure_started(router_config, litellm_path, callback)
	if type(litellm_path) == "function" then
		callback = litellm_path
		litellm_path = nil
	end

	if not router_config or not router_config.enabled then
		callback()
		return
	end

	-- Already started and running
	if job_id then
		callback()
		return
	end

	if is_starting then
		-- Wait for the active startup to complete
		check_port_open(8080, "127.0.0.1", 5000, function(ok)
			vim.schedule(function()
				callback()
			end)
		end)
		return
	end

	is_starting = true
	process_logs = {} -- Reset logs for the new startup attempt

	-- 1. Write the YAML configuration
	local config_path, err = config_module.write_config(router_config)
	if not config_path then
		is_starting = false
		vim.notify("Failed to write LiteLLM config: " .. tostring(err), vim.log.levels.ERROR)
		callback()
		return
	end

	-- 2. Spawn the process
	local cmd = {
		litellm_path or "litellm",
		"--config",
		config_path,
		"--port",
		"8080",
		"--host",
		"127.0.0.1",
	}

	local ok, res = pcall(vim.fn.jobstart, cmd, {
		on_stdout = function(_, data)
			append_to_logs(data)
		end,
		on_stderr = function(_, data)
			append_to_logs(data)
		end,
		on_exit = function(_, exit_code)
			job_id = nil
			is_starting = false
			if exit_code ~= 0 and exit_code ~= 143 and exit_code ~= 9 then
				local error_msg = "LiteLLM background process exited with code: " .. exit_code
				if #process_logs > 0 then
					error_msg = error_msg .. "\n\nRecent Output:\n" .. table.concat(process_logs, "\n")
				end
				vim.notify(error_msg, vim.log.levels.ERROR)
			end
		end,
	})

	if not ok or res <= 0 then
		job_id = nil
		is_starting = false
		vim.notify("Failed to start LiteLLM process. Is 'litellm' CLI installed?", vim.log.levels.ERROR)
		callback()
		return
	end

	job_id = res

	-- 3. Wait for the server port to open
	check_port_open(8080, "127.0.0.1", 5000, function(ready)
		vim.schedule(function()
			is_starting = false
			if not ready then
				local error_msg = "Timed out waiting for LiteLLM to start on port 8080."
				if #process_logs > 0 then
					error_msg = error_msg .. "\n\nRecent Output:\n" .. table.concat(process_logs, "\n")
				end
				spinner.stop("aider_loading", error_msg, vim.log.levels.WARN)
			else
				spinner.stop("aider_loading", "Aider.nvim ready", vim.log.levels.INFO)
			end
			callback()
		end)
	end)
end

function M.stop()
	if job_id then
		vim.fn.jobstop(job_id)
		job_id = nil
	end
end

-- Register autocmd for cleanup when Neovim exits
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		M.stop()
	end,
})

return M
