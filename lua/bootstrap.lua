local M = {}

-- Detect the OS platform
local is_windows = vim.loop.os_uname().sysname:find("Windows") ~= nil

-- System-safe path joiner helper
local function join_paths(...)
	local separator = is_windows and "\\" or "/"
	return table.concat({ ... }, separator)
end

function M.ensure_dependencies()
	-- 1. Establish the paths relative to the plugin installation
	local plugin_dir = vim.fn.stdpath("data") .. join_paths("", "lazy", "aider.nvim")
	local venv_dir = join_paths(plugin_dir, ".venv")

	-- Windows venv uses \Scripts\, Unix uses /bin/
	local bin_subfolder = is_windows and "Scripts" or "bin"
	local exe_extension = is_windows and ".exe" or ""

	local litellm_bin = join_paths(venv_dir, bin_subfolder, "litellm" .. exe_extension)
	local pip_bin = join_paths(venv_dir, bin_subfolder, "pip" .. exe_extension)

	-- 2. If LiteLLM already exists in the venv, return its absolute path
	if vim.fn.filereadable(litellm_bin) == 1 then
		return litellm_bin
	end

	vim.notify("Aider.nvim: Bootstrapping cross-platform LiteLLM environment...", vim.log.levels.INFO)

	-- 3. Resolve the host system's base python command
	-- Windows usually registers 'python', Unix usually registers 'python3'
	local host_python = is_windows and "python" or "python3"
	if vim.fn.executable(host_python) == 0 then
		-- Fallback check if python3 isn't explicitly linked on some linux systems
		host_python = "python"
	end

	if vim.fn.executable(host_python) == 0 then
		vim.notify("Aider.nvim: Error - Python was not found on your system PATH.", vim.log.levels.ERROR)
		return nil
	end

	-- 4. Construct the sequential execution command string
	-- Windows uses '&&' just like Unix in modern cmd/powershell contexts for chaining
	local cmd =
		string.format("%s -m venv %s && %s install litellm", host_python, shell_escape(venv_dir), shell_escape(pip_bin))

	-- 5. Run the installation asynchronously
	vim.fn.jobstart(cmd, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.notify("Aider.nvim: LiteLLM sidecar environment ready!", vim.log.levels.INFO)
				-- You can trigger a callback here to start LiteLLM automatically
			else
				vim.notify("Aider.nvim: Failed to initialize cross-platform Python venv.", vim.log.levels.ERROR)
			end
		end,
	})

	return nil
end

-- Helper to safely escape paths with spaces for the system shell
function shell_escape(path)
	if is_windows then
		return '"' .. path .. '"'
	else
		return vim.fn.shellescape(path)
	end
end

return M
