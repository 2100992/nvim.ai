local api = vim.api

local Utils = require("ai.utils")
local Config = require("ai.config")
local P = require("ai.providers")

local curl = require("plenary.curl")

local M = {}

M.CANCEL_PATTERN = "NVIMAIHTTPEscape"

local group = api.nvim_create_augroup("NVIMAIHTTP", { clear = true })
local active_job = nil

M.stream = function(system_prompt, messages, on_chunk, on_complete)
  local provider = Config.config.provider
  local request = {
    messages = messages,
    system_prompt = system_prompt,
  }

  ---@type string
  local current_event_state = nil

  local Provider = P[provider]

  local spec = Provider.parse_curl_args(Config.get_provider(provider), request)

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  active_job = curl.post(spec.url, {
    headers = spec.headers,
    proxy = spec.proxy,
    insecure = spec.insecure,
    body = vim.json.encode(spec.body),
    stream = function(err, data, _)
      if err then
        on_complete(err)
        return
      end
      if not data then return end
      vim.schedule(function()
        if Config.config[provider] ~= nil and Provider.parse_response ~= nil then
          Provider.parse_response(data, current_event_state, on_chunk)
        end
      end)
    end,
    on_error = function(err)
      print("http error", vim.inspect(err))
      on_complete(err)
    end,
    callback = function(resp)
      if Config.get("debug") then print("resp:", vim.inspect(resp)) end

      active_job = nil
      on_complete(nil)
    end,
  })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = M.CANCEL_PATTERN,
    callback = function()
      if active_job then
        active_job:shutdown()
        Utils.debug("LLM request cancelled", { title = "NVIM.AI" })
        active_job = nil
      end
    end,
  })

  return active_job


end

return M
