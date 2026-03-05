local M = {}

local config   = require("nvim-buffergator.config")
local renderer = require("nvim-buffergator.renderer")

local state = {
  win      = nil,
  bufnr    = nil,
  prev_win = nil,
}

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

function M.get_win()   return state.win   end
function M.get_bufnr() return state.bufnr end

function M.get_prev_win()
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    return state.prev_win
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= state.win then return win end
  end
  return nil
end

local function apply_resize(win, max_width)
  if config.options.auto_resize then
    local opts  = config.options
    local width = math.max(opts.min_width, math.min(opts.max_width, max_width + 2))
    vim.api.nvim_win_set_width(win, width)
  end
end

function M.refresh()
  if not M.is_open() then return end
  local max_width = renderer.render(state.bufnr)
  apply_resize(state.win, max_width)
end

function M.open()
  if M.is_open() then
    -- Already open: just focus it and refresh
    vim.api.nvim_set_current_win(state.win)
    M.refresh()
    return
  end

  -- Record the window we're leaving so keymaps can navigate back to it
  state.prev_win = vim.api.nvim_get_current_win()

  local bufnr = get_or_create_buf()

  vim.cmd("topleft " .. config.options.width .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  state.win = win

  local wo = vim.wo[win]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = "no"
  wo.foldcolumn     = "0"
  wo.wrap           = false
  wo.winfixwidth    = true
  wo.cursorline     = true
  wo.spell          = false

  if not vim.b[bufnr]._buffergator_keymaps_set then
    require("nvim-buffergator.keymaps").setup(bufnr)
    vim.b[bufnr]._buffergator_keymaps_set = true
  end

  -- Render and resize
  local max_width = renderer.render(bufnr)
  apply_resize(win, max_width)

  -- Position cursor on the active buffer's entry (fall back to first entry)
  local prev_buf  = vim.api.nvim_win_get_buf(state.prev_win)
  local entries   = require("nvim-buffergator.catalog").get_buffers()
  local target    = renderer.HEADER_LINES + 1
  for i, e in ipairs(entries) do
    if e.bufnr == prev_buf then
      target = renderer.HEADER_LINES + i
      break
    end
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if target <= line_count then
    vim.api.nvim_win_set_cursor(win, { target, 0 })
  end

  -- Focus stays in the sidebar so the user can navigate immediately
end

function M.close()
  if not M.is_open() then return end
  local win = state.win
  state.win = nil
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

function M.toggle()
  if M.is_open() then M.close() else M.open() end
end

return M
