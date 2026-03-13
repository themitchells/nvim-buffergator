--- nvim-buffergator view
-- Manages the sidebar window and scratch buffer lifecycle.
--
-- State machine:
--   closed  →  open()  →  open (sidebar focused)
--   open    →  close() →  closed
--   open    →  open()  →  open (refocused and refreshed)
--   open    →  toggle()→  closed
--   closed  →  toggle()→  open
--
-- The sidebar uses a nofile scratch buffer that is wiped when its window
-- closes (bufhidden=wipe), so a fresh buffer is created on each open().
-- All rendering goes through renderer.render(); this module only handles
-- window creation, sizing, and cursor management.

local M = {}

local config   = require("nvim-buffergator.config")
local renderer = require("nvim-buffergator.renderer")

-- ── Highlight groups ──────────────────────────────────────────────────────────

local sel_ns = vim.api.nvim_create_namespace("nvim-buffergator-sel")

--- Define NvimBuffergatorSel: Visual background with Normal foreground + bold.
-- This gives guaranteed contrast regardless of colorscheme — the fg is
-- the theme's default readable text colour, and the bg is the selection
-- colour the user is already familiar with from Visual mode.
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

-- ── Selection highlight ───────────────────────────────────────────────────────

--- Apply NvimBuffergatorSel to the [NNN] field on the cursor's current line.
-- Uses a dedicated namespace (sel_ns) so it sits above the render highlights
-- without interfering with them.  Priority 200 > default 100 ensures the
-- selection colour wins over the Comment highlight on the same columns.
-- @param bufnr integer  The sidebar buffer handle.
local function update_sel_hl(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, sel_ns, 0, -1)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1  -- 0-indexed
  if row >= renderer.HEADER_LINES then
    vim.api.nvim_buf_set_extmark(bufnr, sel_ns, row, 0, {
      end_col  = 5,
      hl_group = "NvimBuffergatorSel",
      priority = 200,
    })
  end
end

-- ── Module state ──────────────────────────────────────────────────────────────

--- Sidebar state.  win and bufnr are nil when the sidebar is closed.
-- prev_win is the last user-focused editing window, updated by the
-- WinEnter autocmd in init.lua; used by keymaps to know where to open buffers.
local state = {
  win      = nil,  -- sidebar window handle
  bufnr    = nil,  -- sidebar scratch buffer handle
  prev_win = nil,  -- last non-sidebar window the user was in
}

-- ── Buffer creation ───────────────────────────────────────────────────────────

--- Create the sidebar scratch buffer and attach its buffer-local autocmds.
-- Called once per open() since the buffer is wiped on close (bufhidden=wipe).
-- @return integer  The new buffer handle.
local function create_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype    = "nofile"
  vim.bo[bufnr].bufhidden  = "wipe"
  vim.bo[bufnr].swapfile   = false
  vim.bo[bufnr].filetype   = "nvim-buffergator"
  vim.bo[bufnr].modifiable = false
  -- Suppress matchparen: with no matchpairs defined, there are no pairs
  -- to highlight, so the [NNN] brackets are never highlighted.
  vim.bo[bufnr].matchpairs = ""

  -- Update the [NNN] selection indicator whenever the cursor moves.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer   = bufnr,
    callback = function() update_sel_hl(bufnr) end,
  })

  -- Keep statusline and winbar blank even if lualine or another plugin
  -- tries to set them.  OptionSet fires synchronously on each write to
  -- the option, so this always wins regardless of plugin scheduling order.
  -- The v:option_new guard prevents the re-entrant loop.
  for _, opt in ipairs({ "statusline", "winbar" }) do
    vim.api.nvim_create_autocmd("OptionSet", {
      pattern  = opt,
      callback = function()
        if vim.api.nvim_get_current_buf() == bufnr and vim.v.option_new ~= " " then
          vim.opt_local[opt] = " "
        end
      end,
    })
  end

  state.bufnr = bufnr
  return bufnr
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Return true if the sidebar window is currently open and valid.
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Return the sidebar window handle, or nil if closed.
function M.get_win()   return state.win   end

--- Return the sidebar buffer handle, or nil if it has been wiped.
function M.get_bufnr() return state.bufnr end

--- Update the remembered previous window (called from WinEnter autocmd).
-- @param win integer  The window that just gained focus.
function M.set_prev_win(win)
  state.prev_win = win
end

--- Return the most recent non-sidebar window, used by keymaps to decide
-- where to open a buffer.  Falls back to any non-sidebar window if
-- prev_win is no longer valid.
-- @return integer|nil
function M.get_prev_win()
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    return state.prev_win
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= state.win then return win end
  end
  return nil
end

--- Resize the sidebar window to max_width, clamped to [min_width, max_width].
-- @param win       integer
-- @param max_width integer  Preferred width returned by renderer.render().
local function apply_resize(win, max_width)
  if config.options.auto_resize then
    local opts  = config.options
    local width = math.max(opts.min_width, math.min(opts.max_width, max_width))
    vim.api.nvim_win_set_width(win, width)
  end
end

--- Re-render the sidebar from the current cache (no git I/O) and resize.
-- Safe to call when the sidebar is closed (returns immediately).
function M.refresh()
  if not M.is_open() then return end
  -- If the current window is the sidebar itself (e.g. triggered by BufEnter
  -- on the nofile buffer), resolve current/alternate flags from prev_win.
  local context_win = vim.api.nvim_get_current_win()
  if context_win == state.win then context_win = state.prev_win end
  local max_width = renderer.render(state.bufnr, context_win)
  apply_resize(state.win, max_width)
end

--- Open the sidebar.
-- If already open, refocuses it and refreshes the content.
-- If closed, creates the window on the left, renders immediately from the
-- current git cache, then fires an async git refresh in the background.
function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
    M.refresh()
    return
  end

  -- Record the window we're leaving so keymaps know where to open buffers.
  state.prev_win = vim.api.nvim_get_current_win()

  local bufnr = create_buf()

  vim.cmd("topleft " .. config.options.width .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  state.win = win

  -- Window-local display options for the sidebar.
  local wo = vim.wo[win]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = "no"
  wo.foldcolumn     = "0"
  wo.wrap           = false
  wo.winfixwidth    = true  -- prevents other windows from stealing this width
  wo.cursorline     = true
  wo.spell          = false
  wo.statusline     = " "   -- blank (OptionSet autocmd keeps it this way)
  wo.winbar         = " "

  -- Attach buffer-local keymaps.
  require("nvim-buffergator.keymaps").setup(bufnr)

  -- Render immediately from cache so the sidebar is usable at once, even
  -- before git data arrives.
  local max_width, entries = renderer.render(bufnr, state.prev_win)
  apply_resize(win, max_width)

  -- Position cursor on the currently active buffer's entry.
  local prev_buf = vim.api.nvim_win_get_buf(state.prev_win)
  local target   = renderer.HEADER_LINES + 1  -- default: first entry
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
  -- nvim_win_set_cursor does not fire CursorMoved, so paint the initial
  -- selection highlight manually.
  update_sel_hl(bufnr)

  -- Async git refresh: runs in the background and re-renders when done,
  -- adding branch name and per-file status without blocking the open.
  require("nvim-buffergator.catalog").refresh_git_async(function()
    if M.is_open() then M.refresh() end
  end)
end

--- Close the sidebar if it is open.
-- Restores focus to the window that was active before the sidebar was opened.
function M.close()
  if not M.is_open() then return end
  local win      = state.win
  local prev_win = M.get_prev_win()
  state.win = nil
  -- state.bufnr is intentionally not cleared: the buffer will be auto-wiped
  -- by bufhidden=wipe when its last window closes.
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  -- Return focus to whichever editing window was active before the sidebar
  -- was opened.  Without this, Neovim defaults to the first split after the
  -- leftmost (sidebar) window is removed, ignoring which split the user was in.
  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

--- Toggle the sidebar open/closed.
function M.toggle()
  if M.is_open() then M.close() else M.open() end
end

return M
