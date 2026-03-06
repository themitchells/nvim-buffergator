--- nvim-buffergator public API and autocommand setup
-- This is the module users interact with directly:
--   require("nvim-buffergator").setup(opts)
--   require("nvim-buffergator").open()
--   require("nvim-buffergator").close()
--   require("nvim-buffergator").toggle()
--   require("nvim-buffergator").is_open()
--
-- setup() wires together:
--   • Global keymaps (<Leader>b / <Leader>B)
--   • Autocommands for refresh (BufEnter, BufAdd, …)
--   • lualine compatibility (disabled_filetypes injection)

local M = {}

local config = require("nvim-buffergator.config")
local view   = require("nvim-buffergator.view")

-- ── Debounced refresh timers ──────────────────────────────────────────────────

local display_timer = nil  -- re-render from cache (no git I/O)
local git_timer     = nil  -- async git refresh + re-render
local DEBOUNCE_MS   = 80

--- Re-render the sidebar from cache.
-- Used for BufEnter — the buffer list may have changed focus but git
-- status has not changed, so no git I/O is needed.
local function debounced_display_refresh()
  if display_timer then display_timer:stop(); display_timer:close() end
  display_timer = vim.uv.new_timer()
  display_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if view.is_open() then view.refresh() end
    display_timer = nil
  end))
end

--- Trigger an async git refresh followed by a re-render.
-- Used for BufAdd / BufDelete / BufWritePost / BufFilePost — events where
-- the git status or buffer list may have genuinely changed on disk.
local function debounced_git_refresh()
  if git_timer then git_timer:stop(); git_timer:close() end
  git_timer = vim.uv.new_timer()
  git_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if view.is_open() then
      require("nvim-buffergator.catalog").refresh_git_async(function()
        if view.is_open() then view.refresh() end
      end)
    end
    git_timer = nil
  end))
end

-- ── lualine compatibility ─────────────────────────────────────────────────────

--- Inject "nvim-buffergator" into lualine's disabled_filetypes.statusline.
-- lualine.config.get_config() returns the live internal table by reference,
-- so mutating it here takes effect immediately without re-calling lualine.setup().
-- Called at setup() time and again at VimEnter in case lualine loads lazily.
local function register_lualine_compat()
  local ok, lc = pcall(require, "lualine.config")
  if not ok then return end
  local cfg = lc.get_config()
  if not (cfg and cfg.options and cfg.options.disabled_filetypes) then return end
  local df = cfg.options.disabled_filetypes
  df.statusline = df.statusline or {}
  for _, ft in ipairs(df.statusline) do
    if ft == "nvim-buffergator" then return end  -- already present
  end
  table.insert(df.statusline, "nvim-buffergator")
end

-- ── Public setup ──────────────────────────────────────────────────────────────

--- Initialise the plugin.  Must be called before any other function.
-- @param user_opts table|nil  Partial config table; see config.lua for options.
function M.setup(user_opts)
  config.setup(user_opts)

  -- lualine compat: try now (if lualine is already loaded) and at VimEnter
  -- as a safety net for lazy-loaded lualine.
  register_lualine_compat()
  vim.api.nvim_create_autocmd("VimEnter", {
    once     = true,
    callback = register_lualine_compat,
  })

  -- Global keymaps
  local gk = config.options.global_keymaps
  if gk.toggle then
    vim.keymap.set("n", gk.toggle, view.toggle,
      { noremap = true, silent = true, desc = "Toggle nvim-buffergator" })
  end
  if gk.close then
    vim.keymap.set("n", gk.close, view.close,
      { noremap = true, silent = true, desc = "Close nvim-buffergator" })
  end

  local grp = vim.api.nvim_create_augroup("NvimBuffergator", { clear = true })

  -- File-change events: git status may have changed, so run a full refresh.
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWritePost", "BufFilePost" }, {
    group    = grp,
    callback = debounced_git_refresh,
  })

  -- BufEnter: record MRU timestamp and re-render from cache.
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = grp,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      require("nvim-buffergator.catalog").record_mru(bufnr)
      debounced_display_refresh()
    end,
  })

  -- WinEnter: update prev_win so <CR> always targets the last focused editing
  -- window; also close the sidebar if it becomes the last window.
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = grp,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if view.is_open() then
        if win ~= view.get_win() then
          -- User focused an editing window; remember it for keymap use.
          view.set_prev_win(win)
        elseif #vim.api.nvim_list_wins() == 1 then
          -- Sidebar is the only window left; close it to avoid being stranded.
          view.close()
          vim.cmd("enew")
        end
      end
    end,
  })
end

-- ── Public API ────────────────────────────────────────────────────────────────

M.open    = view.open
M.close   = view.close
M.toggle  = view.toggle
M.is_open = view.is_open

return M
