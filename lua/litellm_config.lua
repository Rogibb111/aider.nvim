local M = {}

---Generates the YAML configuration string for LiteLLM.
---@param config table The free_tier_router configuration table.
---@return string|nil yaml_content The generated YAML content, or nil on error.
---@return string|nil error The error message, if any.
function M.generate_yaml(config)
  if not config or not config.providers or #config.providers == 0 then
    return nil, "No providers configured for free_tier_router"
  end

  local lines = {}
  table.insert(lines, "model_list:")
  for _, provider in ipairs(config.providers) do
    if not provider.model or not provider.api_key then
      return nil, "Invalid provider configuration: missing model or api_key"
    end
    table.insert(lines, "  - model_name: free-aider-agent")
    table.insert(lines, "    litellm_params:")
    table.insert(lines, "      model: " .. provider.model)
    table.insert(lines, "      api_key: " .. provider.api_key)
    if provider.rpm then
      table.insert(lines, "      rpm: " .. tonumber(provider.rpm))
    end
  end

  table.insert(lines, "")
  table.insert(lines, "router_settings:")
  table.insert(lines, "  routing_strategy: simple-shuffle")
  -- Retries within the same model group (free-aider-agent) on failure (e.g. 429)
  table.insert(lines, "  enable_weighted_failover: true")
  local num_providers = #config.providers
  local retries = math.max(3, num_providers * 2)
  table.insert(lines, "  num_retries: " .. tostring(retries))

  table.insert(lines, "")
  table.insert(lines, "litellm_settings:")
  table.insert(lines, "  num_retries: " .. tostring(retries))

  return table.concat(lines, "\n")
end

---Writes the YAML configuration to standard data directory.
---@param config table The free_tier_router configuration table.
---@return string|nil file_path The path to the written file, or nil on error.
---@return string|nil error The error message, if any.
function M.write_config(config)
  local yaml_content, err = M.generate_yaml(config)
  if not yaml_content then
    return nil, err
  end

  local data_dir = vim.fn.stdpath("data")
  local config_path = data_dir .. "/litellm_config.yaml"

  local file = io.open(config_path, "w")
  if not file then
    return nil, "Failed to open " .. config_path .. " for writing"
  end

  file:write(yaml_content)
  file:close()

  return config_path
end

return M
