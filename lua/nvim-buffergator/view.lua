local M = {}

local config   = require("nvim-buffergator.config")
local renderer = require("nvim-buffergator.renderer")

-- State
local state = {
  win    = nil,   -- sidebar window handle
  bufnr  = nil,   -- sidebar buffer handle
  prev_win = nil, -- window that was active before opening
}

-- Create (or reuse) the sidebar scratch buffer
local function get_or_create_buf()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    return state.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype    = "nofile"
  vim.bo[bufnr].bufhidden  = "wipe"
  vim.bo[bufnr].swapfile   = false
  vim.bo[bufnr].filetype   = "nvim-buffergator"
  vim.bo[bufnr].modifiable = false
  state.bufnr = bufnr
  return bufnr
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.get_win()
  return state.win
end

function M.get_bufnr()
  return state.bufnr
end

function M.get_prev_win()
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    return state.prev_win
  end
  -- Fallback: any non-sidebar window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= state.win then
      return win
    end
  end
  return nil
end

function M.refresh()
  if not M.is_open() then return end
  local bufnr = state.bufnr
  local max_width, _ = renderer.render(bufnr)

  if config.options.auto_resize then
    local opts  = config.options
    local width = math.max(opts.min_width, math.min(opts.max_width, max_width + 2))
    vim.api.nvim_win_set_width(state.win, width)
  end
end

function M.open()
  if M.is_open() then
    M.refresh()
    return
  end

  -- Remember the current window so we can return focus there
  state.prev_win = vim.api.nvim_get_current_win()

  local bufnr = get_or_create_buf()

  -- Open leftmost vertical split
  vim.cmd("topleft " .. config.options.width .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  state.win = win

  -- Window-local options
  local wo = vim.wo[win]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = "no"
  wo.foldcolumn     = "0"
  wo.wrap           = false
  wo.winfixwidth    = true
  wo.cursorline     = true
  wo.spell          = false

  -- Attach keymaps (only once per buffer)
  if not vim.b[bufnr]._buffergator_keymaps_set then
    require("nvim-buffergator.keymaps").setup(bufnr)
    vim.b[bufnr]._buffergator_keymaps_set = true
  end

  -- Render + auto-resize
  local max_width = renderer.render(bufnr)
  if config.options.auto_resize then
    local opts = config.options
    local width = math.max(opts.min_width, math.min(opts.max_width, max_width + 2))
    vim.api.nvim_win_set_width(win, width)
  end

  -- Return focus to previous window
  vim.api.nvim_set_current_win(state.prev_win)
end

function M.close()
  if not M.is_open() then return end
  local win = state.win
  state.win  = nil
  -- bufnr intentionally kept so we can reuse; it's nofile/wipe so it'll gc on its own
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

return M
