local M = {}

local config = require("nvim-buffergator.config")
local view   = require("nvim-buffergator.view")

-- Debounce timer for autocommand-triggered refreshes
local refresh_timer = nil
local DEBOUNCE_MS   = 50

local function debounced_refresh()
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
  end
  refresh_timer = vim.uv.new_timer()
  refresh_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if view.is_open() then
      view.refresh()
    end
    refresh_timer = nil
  end))
end

function M.setup(user_opts)
  config.setup(user_opts)

  -- Global keymaps
  local gk = config.options.global_keymaps
  if gk.toggle then
    vim.keymap.set("n", gk.toggle, view.toggle, { noremap = true, silent = true, desc = "Toggle buffergator" })
  end
  if gk.close then
    vim.keymap.set("n", gk.close, view.close, { noremap = true, silent = true, desc = "Close buffergator" })
  end

  -- Autocommands
  local grp = vim.api.nvim_create_augroup("NvimBuffergator", { clear = true })

  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWritePost", "BufEnter" }, {
    group    = grp,
    callback = debounced_refresh,
  })

  -- Close sidebar if it becomes the last window
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = grp,
    callback = function()
      if view.is_open() and #vim.api.nvim_list_wins() == 1 then
        -- Only the sidebar is open; close it to avoid being stranded
        view.close()
        vim.cmd("enew")
      end
    end,
  })
end

-- Public API
M.open   = view.open
M.close  = view.close
M.toggle = view.toggle
M.is_open = view.is_open

return M
