--- nvim-buffergator configuration
-- Holds plugin defaults and the merged user options table.
-- Call setup(user_opts) once from init.lua; all other modules read from
-- M.options at runtime so changes via :BuffergatorPath / cycle_sort take
-- effect immediately without re-requiring.

local M = {}

--- Default configuration values.
-- Users pass a subset of this table to setup(); any missing keys fall back
-- to these defaults via vim.tbl_deep_extend.
M.defaults = {
  -- Initial sidebar width (columns).  auto_resize adjusts this after render.
  width = 30,
  -- Minimum width auto-resize will shrink to.
  min_width = 20,
  -- Maximum width auto-resize will grow to.
  max_width = 60,

  -- Sort order for the buffer list.
  -- "filepath"  — alphabetical by full path (default)
  -- "bufnum"    — Neovim buffer number (order of creation)
  -- "basename"  — filename only, path as tiebreaker
  -- "mru"       — most-recently-used (BufEnter timestamp)
  sort = "filepath",

  -- When true, auto-resize the sidebar width to fit the longest filename.
  auto_resize = true,

  -- Close the sidebar automatically after opening a buffer (true) or keep
  -- it open (false).
  close_on_select = true,

  -- Filename display mode (mirrors lualine's path option).
  --   0  filename only — parent directory shown off-screen to the right
  --   1  relative path — no separate parent column  (default recommended)
  --   2  absolute path — no separate parent column
  --   3  tilde-relative — no separate parent column
  path = 0,

  -- Buffer-local keymaps active while the sidebar has focus.
  -- Set any key to false to disable it.  Lists mean multiple bindings.
  keymaps = {
    open        = { "<CR>", "o" },   -- open in previous window
    open_vsplit = { "s", "<C-v>" },  -- open in vertical split
    open_split  = { "i", "<C-s>" },  -- open in horizontal split
    open_tab    = { "t", "<C-t>" },  -- open in new tab
    delete      = "d",               -- :bdelete
    wipe        = "D",               -- :bwipeout
    close       = { "q", "<Esc>" },  -- close sidebar
    next        = "<C-n>",           -- move cursor down
    prev        = "<C-p>",           -- move cursor up
    refresh     = "R",               -- force refresh
    cycle_sort  = "S",               -- rotate through sort modes
    help        = "g?",              -- show keymap reference
    mouse_open  = "<2-LeftMouse>",   -- double-click to open; false to disable
  },

  -- Global (non-sidebar) keymaps set during setup().
  global_keymaps = {
    toggle = "<Leader>b",  -- toggle sidebar open/closed
    close  = "<Leader>B",  -- close sidebar
  },
}

--- Merged options table populated by setup().
M.options = {}

--- Merge user_opts over M.defaults and store in M.options.
-- @param user_opts table|nil  Partial options table from the user's config.
function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
