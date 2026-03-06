local M = {}

local config   = require("nvim-buffergator.config")
local renderer = require("nvim-buffergator.renderer")

local sel_ns = vim.api.nvim_create_namespace("nvim-buffergator-sel")

-- Reversed fg/bg gives guaranteed contrast in any colorscheme.
-- Define once; ColorScheme autocmd keeps it in sync after theme changes.
local function def_sel_hl()
  local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "NvimBuffergatorSel", {
    bg   = visual.bg,
    fg   = normal.fg,
    bold = true,
  })
end
def_sel_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = def_sel_hl })

-- Highlight [NNN] on the cursor line so the selected entry is obvious.
-- Uses a separate namespace so it doesn't interfere with render highlights.
local function update_sel_hl(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, sel_ns, 0, -1)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1  -- 0-indexed
  if row >= renderer.HEADER_LINES then
    -- Use set_extmark with explicit priority so this wins over the render's
    -- Comment highlight that covers the same [NNN] columns (0-4).
    vim.api.nvim_buf_set_extmark(bufnr, sel_ns, row, 0, {
      end_col  = 5,
      hl_group = "NvimBuffergatorSel",
      priority = 200,
    })
  end
end

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
  -- Suppress matchparen: clearing matchpairs means there are no pairs to match
  vim.bo[bufnr].matchpairs = ""
  -- Update [NNN] selection highlight whenever the cursor moves
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer   = bufnr,
    callback = function() update_sel_hl(bufnr) end,
  })
  -- Blank the statusline whenever any plugin (lualine etc.) changes it for
  -- this buffer's window. OptionSet fires synchronously on the option write,
  -- so we always win regardless of scheduling. v:option_new guard stops the loop.
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern  = "statusline",
    callback = function()
      if vim.api.nvim_get_current_buf() == bufnr and vim.v.option_new ~= " " then
        vim.opt_local.statusline = " "
      end
    end,
  })
  state.bufnr = bufnr
  return bufnr
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.get_win()   return state.win   end
function M.get_bufnr() return state.bufnr end

function M.set_prev_win(win)
  state.prev_win = win
end

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
    local width = math.max(opts.min_width, math.min(opts.max_width, max_width))
    vim.api.nvim_win_set_width(win, width)
  end
end

function M.refresh()
  if not M.is_open() then return end
  -- When triggered while inside the sidebar (e.g. BufEnter on the nofile
  -- buffer itself), fall back to prev_win so current/alternate resolve correctly.
  local context_win = vim.api.nvim_get_current_win()
  if context_win == state.win then context_win = state.prev_win end
  local max_width = renderer.render(state.bufnr, context_win)
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
  wo.statusline     = " "

  if not vim.b[bufnr]._buffergator_keymaps_set then
    require("nvim-buffergator.keymaps").setup(bufnr)
    vim.b[bufnr]._buffergator_keymaps_set = true
  end

  -- Render with correct context so current/alternate flags resolve against
  -- the window the user was in (not the sidebar nofile buffer).
  local max_width, entries = renderer.render(bufnr, state.prev_win)
  apply_resize(win, max_width)

  -- Position cursor on the active buffer's entry (fall back to first entry)
  local prev_buf = vim.api.nvim_win_get_buf(state.prev_win)
  local target   = renderer.HEADER_LINES + 1
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
  -- nvim_win_set_cursor doesn't fire CursorMoved, so paint the initial highlight
  update_sel_hl(bufnr)

  -- Kick off async git refresh. When it completes, re-render to add git
  -- status/branch data. The sidebar is already usable before this arrives.
  require("nvim-buffergator.catalog").refresh_git_async(function()
    if M.is_open() then M.refresh() end
  end)
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
