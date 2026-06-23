local M = {}

-- Detect the OS platform
local is_windows = vim.loop.os_uname().sysname:find("Windows") ~= nil

-- System-safe path joiner helper
local function join_paths(...)
	local separator = is_windows and "\\" or "/"
	return table.concat({ ... }, separator)
end

-- Helper to safely escape paths with spaces for the system shell
local function shell_escape(path)
	if is_windows then
		return '"' .. path .. '"'
	else
		return vim.fn.shellescape(path)
	end
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

	-- Ensure the plugin data directory exists before running file/venv tasks
	if vim.fn.isdirectory(plugin_dir) == 0 then
		vim.fn.mkdir(plugin_dir, "p")
	end

	-- 3. Resolve the host system's base python command
	local candidates = is_windows and { "python" } or { "python3", "python" }
	local host_python = ""
	local last_error = "No Python executable found in PATH."

	for _, cmd in ipairs(candidates) do
		if vim.fn.executable(cmd) == 1 then
			local full_path = vim.fn.exepath(cmd)
			local res = vim.fn.system({ full_path, "--version" })
			if vim.v.shell_error == 0 then
				host_python = full_path
				break
			else
				last_error = string.format("Candidate '%s' failed validation: %s", full_path, vim.trim(res))
			end
		end
	end

	-- LiteLLM requires Python >=3.10 and <3.14. Target 3.11.10 as a stable baseline.
	local target_python_version = "3.11.10"
	local cmd = ""

	-- Fallback installation block if system Python is missing or invalid
	if host_python == "" then
		if vim.fn.executable("mise") == 1 then
			vim.notify(
				"Aider.nvim: Python missing. Installing Python " .. target_python_version .. " via mise...",
				vim.log.levels.INFO
			)
			cmd = string.format(
				"mise install python@%s && mise exec python@%s -- python -m venv %s && %s install litellm",
				target_python_version,
				target_python_version,
				shell_escape(venv_dir),
				shell_escape(pip_bin)
			)
		elseif vim.fn.executable("asdf") == 1 then
			vim.notify(
				"Aider.nvim: Python missing. Installing Python " .. target_python_version .. " via asdf...",
				vim.log.levels.INFO
			)
			cmd = string.format(
				"(asdf plugin add python || true) && asdf install python %s && ASDF_PYTHON_VERSION=%s asdf exec python -m venv %s && %s install litellm",
				target_python_version,
				target_python_version,
				shell_escape(venv_dir),
				shell_escape(pip_bin)
			)
		elseif vim.fn.executable("pyenv") == 1 then
			vim.notify(
				"Aider.nvim: Python missing. Installing Python " .. target_python_version .. " via pyenv...",
				vim.log.levels.INFO
			)
			cmd = string.format(
				"pyenv install %s -s && PYENV_VERSION=%s pyenv exec python -m venv %s && %s install litellm",
				target_python_version,
				target_python_version,
				shell_escape(venv_dir),
				shell_escape(pip_bin)
			)
		else
			error(
				"Aider.nvim: No usable Python found, and no supported version manager (asdf, pyenv, mise) detected. "
					.. last_error
			)
		end
	else
		cmd = string.format(
			"%s -m venv %s && %s install litellm",
			shell_escape(host_python),
			shell_escape(venv_dir),
			shell_escape(pip_bin)
		)
	end

	local output = {}
	local function append_output(_, data)
		if data then
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
				end
			end
		end
	end

	-- 5. Run the installation asynchronously
	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = append_output,
		on_stderr = append_output,
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.notify("Aider.nvim: LiteLLM sidecar environment ready!", vim.log.levels.INFO)
			else
				local err_msg = "Aider.nvim: Failed to initialize cross-platform Python venv."
				if #output > 0 then
					err_msg = err_msg .. "\nConsole output:\n" .. table.concat(output, "\n")
				end
				vim.notify(err_msg, vim.log.levels.ERROR)
			end
		end,
	})

	return nil
end

return M
